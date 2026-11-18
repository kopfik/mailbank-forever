-- Mail Bank - written entirely by AI (Claude), designed and tested in the game by the maintainer.
-- A window next to the mailbox that shows every item attached to the mails in the inbox,
-- like one big bag. It opens together with the mailbox; the "Mail Bank" tab under the
-- mailbox shows / hides it (remembered).
--   Left click    take that stack
--   Right click   take every stack of that item, one after another
--   Shift click   link it in chat (like in bags)
-- Items from C.O.D. (cash on delivery) and GM mails are shown grey and cannot be taken here,
-- so a click never pays anything.
-- The window grows with the number of items: 8 wide and up to 12 rows, then wider (up to 16),
-- then it scrolls.
-- While the window is open the items keep their places: a taken item leaves an empty place.
-- They are put in order again the next time the window opens.
-- OTHER CHARACTERS. Every time a character looks into its mailbox, the items are remembered.
-- The drop-down in the window's header shows the remembered inbox of another character
-- (view only - as it was when that character last opened its mailbox).
-- AWAY FROM A MAILBOX. /mailbank (or the Mail Bank button in Baganator's bag window) opens the window
-- anywhere; it then shows your inbox as it was when you last opened a mailbox (view only).
-- There the window can be dragged (the place is remembered) and Escape closes it.
-- /mailbank forget    forgets the remembered inbox of the character chosen in the drop-down
-- /mailbank size 42   sets the icon size (default 42, same as Baganator here)
--
-- The expiry marks, the sender in the tooltip, the money total and the grey C.O.D. / GM items
-- follow the Bankbox addon by Siz.

local COLS_MIN, COLS_MAX = 8, 16   -- items per row: starts at 8, widens up to 16 when 12 rows are not enough
local ROWS_MIN, ROWS_MAX = 4, 12   -- rows shown: at least 4, at most 12 (more = scrolling)
local DEFAULT_SIZE = 42            -- item button size; /mailbank size N changes it
local SIZE, GAP = DEFAULT_SIZE, 4
local EXPIRY_FRAME_DAYS = 10       -- red frame around items of mails that expire sooner than this
local EXPIRY_TEXT_DAYS = 3         -- ... and a countdown on the item when sooner than this
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16

local slots = {}     -- every item in the inbox, see Scan()
local cells = {}     -- what each place of the grid shows: an entry of "slots", or false = empty place
local cellCount = 0  -- how many places were filled when the grid was last put in order
local gridCols, gridRows = COLS_MIN, ROWS_MIN
local totalMoney = 0 -- money in the inbox (C.O.D. mails not counted)
local buttons = {}
local filter = ""
local busy = 0       -- > 0: a take was sent to the server, waiting for the inbox to update
local takeAll        -- itemID being taken stack after stack (right click), nil = none
local charKey        -- "Name Surname-Realm" of the character you are on (Forever: first names are not unique)
local viewing        -- nil = your own inbox; "Name-Realm" = the remembered inbox of another character (view only)
local atMailbox = false   -- the mailbox is open (only then can items be taken)
local inboxLoaded = false -- the game has sent the inbox since the mailbox was opened (before that it may be empty)

local function DaysText(days)
	if days >= 1 then return math.floor(days) .. "d" end
	return math.max(1, math.floor(days * 24)) .. "h"
end

local function AgeText(seconds)
	if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. " min" end
	if seconds < 86400 then return math.floor(seconds / 3600) .. " h" end
	return math.floor(seconds / 86400) .. " d"
end

-- race, sex, class, faction and ruleset of the character you are on (remembered with its inbox, for the drop-down)
local function MyDetails()
	local ruleset
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule then -- same as Baganator / Syndicator show it
		local pvp = Enum.GameRule.PvPRuleset and C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset)
		local rp = Enum.GameRule.RPRuleset and C_GameRules.IsGameRuleActive(Enum.GameRule.RPRuleset)
		local hc = Enum.GameRule.HardcoreRuleset and C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset)
		ruleset = (pvp and rp and "RPPvP") or (pvp and "PvP") or (rp and "RP") or (hc and "HC") or "PvE"
	end
	return { race = select(2, UnitRace("player")), sex = UnitSex("player"), class = select(2, UnitClass("player")),
		faction = UnitFactionGroup("player"), ruleset = ruleset }
end

-- how a character is written in the drop-down: race icon and name in its class colour, without the realm.
-- long = also the ruleset and the faction emblem (in the list)
local RACE_ATLAS = { scourge = "undead", zandalaritroll = "zandalari", highmountaintauren = "highmountain",
	lightforgeddraenei = "lightforged", earthendwarf = "earthen", harronir = "haranir" }
local function CharLabel(name, long)
	local d = (name == charKey) and MyDetails() or MailBankDB.chars[name] or {}
	local text = name:match("^[^-]+") or name
	local color = d.class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[d.class]
	if color and color.colorStr then text = "|c" .. color.colorStr .. text .. "|r" end
	if d.race then
		local race = d.race:lower()
		local sex = (d.sex == 3 and "female") or (d.sex == 2 and "male") or "unknown"
		text = "|A:raceicon-" .. (RACE_ATLAS[race] or race) .. "-" .. sex .. ":13:13|a " .. text
	end
	if long then
		if d.ruleset then text = text .. "  |cffbfbfbf" .. d.ruleset .. "|r" end
		if d.faction == "Horde" then
			text = text .. " |A:charcreatetest-logo-horde:16:14|a"
		elseif d.faction == "Alliance" then
			text = text .. " |A:charcreatetest-logo-alliance:16:14|a"
		end
	end
	return text
end

local function MoneyText(copper)
	if GetMoneyString then return GetMoneyString(copper, true) end
	return GetCoinTextureString(copper)
end

---------------------------------------------------------------------------
-- WINDOW
---------------------------------------------------------------------------
local window = CreateFrame("Frame", "MailBankWindow", UIParent, "ButtonFrameTemplate")
window:Hide()
window:SetToplevel(true)
window:EnableMouse(true)
if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(window) end
if window.SetTitle then
	window:SetTitle("Mail Bank")
elseif MailBankWindowTitleText then
	MailBankWindowTitleText:SetText("Mail Bank")
end
local portrait = (window.PortraitContainer and window.PortraitContainer.portrait) or window.portrait
if window.SetPortraitToAsset then
	window:SetPortraitToAsset("Interface\\MailFrame\\Mail-Icon") -- same icon as the Inbox window
elseif portrait and SetPortraitToTexture then
	SetPortraitToTexture(portrait, "Interface\\MailFrame\\Mail-Icon")
end
if window.Inset then
	window.Inset:ClearAllPoints()
	window.Inset:SetPoint("TOPLEFT", 4, -60)
	window.Inset:SetPoint("BOTTOMRIGHT", -6, 26)
end

-- header: whose inbox is shown (left) and the search box (right)
local charDropDown = CreateFrame("Frame", "MailBankCharDropDown", window, "UIDropDownMenuTemplate")
charDropDown:SetPoint("TOPLEFT", 48, -28)
UIDropDownMenu_SetWidth(charDropDown, 130)

local search = CreateFrame("EditBox", "MailBankSearch", window, "SearchBoxTemplate")
search:SetSize(150, 20)
search:SetPoint("TOPRIGHT", -14, -34)
search:SetAutoFocus(false)

-- bottom line: number of items and what is going on (left), the money in the inbox (right)
local moneyText = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
moneyText:SetPoint("BOTTOMRIGHT", -14, 8)
local countText = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
countText:SetPoint("BOTTOMLEFT", 14, 8)
local statusText = window:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
statusText:SetPoint("LEFT", countText, "RIGHT", 10, 0)

local scroll = CreateFrame("ScrollFrame", "MailBankScroll", window, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
scroll:SetScrollChild(content)

-- Sizes the window for a grid of cols x rows; only rowsShown rows are visible (the rest scrolls).
local function Layout(cols, rows, rowsShown)
	local scrolling = rows > rowsShown
	local gridW, gridH = cols * (SIZE + GAP) - GAP, rowsShown * (SIZE + GAP) - GAP
	local right = scrolling and 32 or 14 -- room for the scroll bar
	-- at least wide enough for the character drop-down and the search box in the header
	window:SetSize(math.max(392, 14 + gridW + right), 68 + gridH + 34)
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", 14, -68)
	scroll:SetPoint("BOTTOMRIGHT", -right, 34)
	content:SetSize(gridW, rows * (SIZE + GAP) - GAP)
	local scrollBar = scroll.ScrollBar or MailBankScrollScrollBar
	if scrollBar then scrollBar:SetShown(scrolling) end
	if not scrolling then scroll:SetVerticalScroll(0) end
end

-- sits right of the mailbox, or right of the opened letter when one is open.
-- Away from a mailbox it floats: it can be dragged, the place is remembered, Escape closes it.
local function Anchor()
	window:ClearAllPoints()
	tDeleteItem(UISpecialFrames, "MailBankWindow") -- at the mailbox Escape closes the mailbox, and this window with it
	if not atMailbox then
		table.insert(UISpecialFrames, "MailBankWindow")
		local pos = MailBankDB.pos
		if pos then
			window:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		else
			window:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
		end
		return
	end
	local left = (OpenMailFrame and OpenMailFrame:IsShown()) and OpenMailFrame or MailFrame
	window:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
end

window:SetMovable(true)
window:SetClampedToScreen(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", function(self)
	if not atMailbox then self:StartMoving() end
end)
window:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false) -- the place is kept here, not by the game (so it still snaps to the mailbox)
	if atMailbox then return end
	local point, _, relPoint, x, y = self:GetPoint()
	MailBankDB.pos = { point, relPoint, x, y }
end)

---------------------------------------------------------------------------
-- READING THE INBOX
---------------------------------------------------------------------------
-- slots[n] = { mail, attach, itemID, name, link, texture, count, quality,
--              sender, daysLeft, wasReturned, cod (copper, nil = none), isGM }
-- While another character is chosen in the drop-down, its remembered items are put there instead.
local function Scan()
	wipe(slots)
	totalMoney = 0
	if viewing or not atMailbox then
		local saved = MailBankDB.chars[viewing or charKey]
		local age = saved and (time() - saved.time) / 86400 or 0 -- days since it was remembered
		for i, item in ipairs(saved and saved.items or {}) do
			local slot = {}
			for k, v in pairs(item) do slot[k] = v end
			slot.saved = true -- cannot be taken
			slot.daysLeft = math.max(0, (item.daysLeft or 0) - age)
			slots[i] = slot
		end
		totalMoney = saved and saved.money or 0
		return
	end
	for mail = 1, GetInboxNumItems() do
		local _, _, sender, _, money, cod, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mail)
		local isCOD = cod and cod > 0
		if money and money > 0 and not isCOD then totalMoney = totalMoney + money end
		if itemCount and itemCount > 0 then
			for attach = 1, MAX_ATTACH do
				local name, itemID, texture, count, quality = GetInboxItem(mail, attach)
				if texture then
					slots[#slots + 1] = { mail = mail, attach = attach, itemID = itemID, name = name or "",
						link = GetInboxItemLink(mail, attach), texture = texture, count = count, quality = quality,
						sender = sender, daysLeft = daysLeft or 0, wasReturned = wasReturned,
						cod = isCOD and cod or nil, isGM = isGM }
					-- what tells this stack from the others (its place in the inbox changes when mails above are deleted)
					local slot = slots[#slots]
					slot.sig = table.concat({ slot.link or slot.name, count or 0, sender or "", slot.cod or 0,
						wasReturned and 1 or 0, isGM and 1 or 0 }, "|")
				end
			end
		end
	end
	-- remember it, so that other characters can look at it
	if inboxLoaded and charKey and MailBankDB then
		local items = {}
		for i, slot in ipairs(slots) do
			items[i] = { itemID = slot.itemID, name = slot.name, link = slot.link, texture = slot.texture,
				count = slot.count, quality = slot.quality, sender = slot.sender, daysLeft = slot.daysLeft,
				wasReturned = slot.wasReturned, cod = slot.cod, isGM = slot.isGM, sig = slot.sig }
		end
		local saved = MyDetails()
		saved.time, saved.money, saved.items = time(), totalMoney, items
		MailBankDB.chars[charKey] = saved
	end
end

local Refresh -- defined below

-- SEARCH. Everything that can be searched about an item, in lower case: its name, its type
-- (Trade Goods, Cloth, Head...) and the whole text of its tooltip ("Crafting Reagent", "Use: ...").
-- Remembered per item, so the tooltip is read only once.
local searchText = {}
local function SearchText(slot)
	local key = slot.link or slot.name
	if searchText[key] then return searchText[key] end
	local parts, complete = { slot.name }, true
	if slot.link and C_Item and C_Item.GetItemInfo then
		local _, _, _, _, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(slot.link)
		if itemType then
			parts[#parts + 1] = itemType
			parts[#parts + 1] = itemSubType or ""
			local where = equipLoc and equipLoc ~= "" and _G[equipLoc] -- "Head", "Two-Hand"...
			if type(where) == "string" then parts[#parts + 1] = where end
		else
			complete = false -- the game has not loaded this item yet; try again next time
		end
	end
	if slot.link and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, slot.link)
		if ok and data and data.lines then
			for _, line in ipairs(data.lines) do
				if type(line.leftText) == "string" then parts[#parts + 1] = line.leftText end
				if type(line.rightText) == "string" then parts[#parts + 1] = line.rightText end
			end
		else
			complete = false
		end
	end
	-- without colour codes
	local text = table.concat(parts, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
	if complete then searchText[key] = text end
	return text
end

-- every word typed in the search box must be somewhere in the item's text
local filterWords = {}
local function Matches(slot)
	if filter == "" then return true end
	local text = SearchText(slot)
	for _, word in ipairs(filterWords) do
		if not text:find(word, 1, true) then return false end
	end
	return true
end

-- Puts the grid in order from scratch: the items one after another, no empty places between them.
-- Done when the window opens (and when the inbox changed in a way Sync below cannot follow).
local function Arrange()
	wipe(cells)
	for i, slot in ipairs(slots) do cells[i] = slot end
	local n = #slots
	cellCount = n
	-- 8 wide while 12 rows are enough, then wider (up to 16), then more rows that scroll
	gridCols = COLS_MIN
	if n > COLS_MIN * ROWS_MAX then gridCols = math.min(COLS_MAX, math.ceil(n / ROWS_MAX)) end
	gridRows = math.max(ROWS_MIN, math.ceil(n / gridCols))
end

-- After the inbox changed while the window is open: every item stays in its place and
-- an item that is gone leaves its place empty. (Run after Scan.)
local function Sync()
	local used, from, waiting = {}, 1, {}
	for i = 1, cellCount do
		local old = cells[i]
		if old and old.taking then
			waiting[#waiting + 1] = i -- being taken right now: decided below
		elseif old then
			-- the inbox keeps its order, so the same item is further on in the new list
			local found
			for j = from, #slots do
				if slots[j].sig == old.sig then found = j break end
			end
			if found then
				cells[i] = slots[found]
				used[found] = true
				from = found + 1
			else
				cells[i] = false
			end
		end
	end
	for j, slot in ipairs(slots) do
		if not used[j] then
			-- still in the inbox: it is an item whose take has not gone through yet ...
			local placed = false
			for k, i in ipairs(waiting) do
				if i and cells[i].sig == slot.sig then
					slot.taking = true
					cells[i] = slot
					waiting[k] = false
					placed = true
					break
				end
			end
			-- ... or something new (a mail arrived): put everything in order again
			if not placed then
				Arrange()
				return
			end
		end
	end
	for _, i in ipairs(waiting) do
		if i then cells[i] = false end -- taken
	end
end

-- reads the inbox again and redraws; stopTaking = a take failed or timed out, nothing is on its way
local function Reread(stopTaking)
	if stopTaking then
		for i = 1, cellCount do
			if cells[i] then cells[i].taking = nil end
		end
	end
	Scan()
	Sync()
	Refresh()
end

-- a take is on its way; if the inbox does not update in 3 s, stop waiting
local function Take(slot)
	-- mails move up when one above is emptied and deleted: make sure this place still holds this item
	if GetInboxItemLink(slot.mail, slot.attach) ~= slot.link then
		takeAll = nil
		Reread(true)
		return
	end
	busy = busy + 1
	local mine = busy
	slot.taking = true
	TakeInboxItem(slot.mail, slot.attach)
	C_Timer.After(3, function()
		if busy == mine then
			busy, takeAll = 0, nil
			Reread(true)
		end
	end)
end

-- right click: take the next stack of the same item, until there is none
local function ContinueTakeAll()
	if not takeAll or busy > 0 or not window:IsShown() then return end
	if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
		C_Timer.After(0.2, ContinueTakeAll)
		return
	end
	Scan()
	Sync()
	-- take from the LAST mail first: a mail that is emptied gets deleted and the mails below it
	-- move up, which would make the next take point at the wrong mail
	local best
	for i = 1, cellCount do
		local slot = cells[i]
		if slot and slot.itemID == takeAll and not slot.cod and not slot.isGM and not slot.taking then
			if not best or slot.mail > best.mail or (slot.mail == best.mail and slot.attach > best.attach) then
				best = slot
			end
		end
	end
	if best then
		Refresh()
		Take(best)
		return
	end
	takeAll = nil
	Refresh()
end

---------------------------------------------------------------------------
-- ITEM BUTTONS
---------------------------------------------------------------------------
local function OnClick(self, mouseButton)
	local slot = self.slot
	if not slot then return end
	if IsModifiedClick() then
		HandleModifiedItemClick(slot.link)
		return
	end
	if slot.saved then
		if viewing then
			UIErrorsFrame:AddMessage("This is the remembered inbox of " .. viewing .. ": log in with it to take this.", 1, 0.5, 0.25)
		else
			UIErrorsFrame:AddMessage("Open a mailbox to take this.", 1, 0.5, 0.25)
		end
		return
	end
	if slot.isGM then
		UIErrorsFrame:AddMessage("GM mail: open it in the inbox to take this.", 1, 0.5, 0.25)
		return
	end
	if slot.cod then
		UIErrorsFrame:AddMessage("Cash on delivery: open the mail in the inbox to pay and take it.", 1, 0.5, 0.25)
		return
	end
	if busy > 0 or takeAll then return end
	if mouseButton == "RightButton" then takeAll = slot.itemID end
	Take(slot)
end

local function OnEnter(self)
	local slot = self.slot
	if not slot then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if not slot.saved then
		GameTooltip:SetInboxItem(slot.mail, slot.attach)
	elseif slot.link then
		GameTooltip:SetHyperlink(slot.link)
	else
		GameTooltip:SetText(slot.name)
	end
	GameTooltip:AddLine(" ")
	if slot.sender then GameTooltip:AddDoubleLine("From", slot.sender, 0.6, 0.6, 0.6, 1, 1, 1) end
	local r, g, b = 1, 1, 1
	if slot.daysLeft < EXPIRY_FRAME_DAYS then r, g, b = 1, 0.25, 0.25 end
	GameTooltip:AddDoubleLine(slot.wasReturned and "Deleted in" or "Expires in", DaysText(slot.daysLeft), 0.6, 0.6, 0.6, r, g, b)
	if slot.isGM then
		GameTooltip:AddLine("GM mail: open it in the inbox to take this.", 1, 0.5, 0.25, true)
	elseif slot.cod then
		GameTooltip:AddLine("Cash on delivery: " .. MoneyText(slot.cod), 1, 0.5, 0.25)
		GameTooltip:AddLine("Open the mail in the inbox to pay and take it.", 1, 0.5, 0.25, true)
	elseif slot.saved then
		GameTooltip:AddLine("Remembered inbox: log in with this character to take it.", 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine("Left click: take   Right click: take all of these", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function GetButton(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("ItemButton", "MailBankItem" .. i, content) -- the game's bag item button
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", OnClick)
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- red frame: the mail expires soon
	b.expiryFrame = b:CreateTexture(nil, "OVERLAY", nil, 3)
	b.expiryFrame:SetTexture("Interface\\Common\\WhiteIconFrame")
	b.expiryFrame:SetAllPoints()
	b.expiryFrame:SetVertexColor(1, 0.1, 0.1)
	b.expiryFrame:Hide()
	-- countdown: it expires very soon
	b.expiry = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.expiry:SetPoint("TOPLEFT", 2, -2)
	b.expiry:SetTextColor(1, 0.25, 0.25)
	-- dark cover for items that do not match the search (the bag buttons have one; else make it)
	if not b.searchOverlay then
		b.searchOverlay = b:CreateTexture(nil, "OVERLAY", nil, 4)
		b.searchOverlay:SetAllPoints()
		b.searchOverlay:SetColorTexture(0, 0, 0, 0.8)
	end
	b.searchOverlay:Hide()
	buttons[i] = b
	return b
end

function Refresh()
	if not window:IsShown() then return end

	-- the grid as it was last put in order (see Arrange)
	local n = #slots
	local cols, rows = gridCols, gridRows
	Layout(cols, rows, math.min(rows, ROWS_MAX))

	local matching = 0
	for i = 1, rows * cols do
		local b = GetButton(i)
		local slot = cells[i] or nil
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		b:SetSize(SIZE, SIZE)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", col * (SIZE + GAP), -row * (SIZE + GAP))
		b.slot = slot
		if slot then
			local matches = Matches(slot)
			if matches then matching = matching + 1 end
			SetItemButtonTexture(b, slot.texture)
			SetItemButtonCount(b, slot.count)
			SetItemButtonQuality(b, slot.quality, slot.link or slot.itemID)
			SetItemButtonDesaturated(b, slot.cod ~= nil or slot.isGM) -- cannot be taken here
			b.expiry:SetText(slot.daysLeft < EXPIRY_TEXT_DAYS and DaysText(slot.daysLeft) or "")
			b.expiryFrame:SetShown(slot.daysLeft < EXPIRY_FRAME_DAYS)
			b.searchOverlay:SetShown(not matches) -- stays in place, only dimmed
		else
			-- empty slot: the game's bag slot background (as in Baganator)
			if not (b.icon and b.icon:SetAtlas("bags-item-slot64")) then
				SetItemButtonTexture(b, "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
			end
			SetItemButtonCount(b, 0)
			SetItemButtonQuality(b, nil)
			SetItemButtonDesaturated(b, false)
			b.expiry:SetText("")
			b.expiryFrame:Hide()
			b.searchOverlay:Hide()
		end
		b:Show()
	end
	for i = rows * cols + 1, #buttons do
		buttons[i].slot = nil
		buttons[i]:Hide()
	end

	countText:SetText((filter == "") and (n .. " items") or (matching .. " / " .. n .. " items"))
	local saved = (viewing or not atMailbox) and MailBankDB.chars[viewing or charKey]
	if saved then
		statusText:SetText("as of " .. AgeText(time() - saved.time) .. " ago, view only")
	elseif viewing then
		statusText:SetText("not remembered yet - open a mailbox with this character")
	else
		statusText:SetText(takeAll and "Taking..." or "")
	end
	moneyText:SetText(totalMoney > 0 and MoneyText(totalMoney) or "")

	if GameTooltip:IsShown() then
		local owner = GameTooltip:GetOwner()
		if owner and owner.slot and owner:IsMouseOver() then OnEnter(owner) end
	end
end

search:HookScript("OnTextChanged", function(self)
	filter = strtrim(self:GetText() or ""):lower()
	wipe(filterWords)
	for word in filter:gmatch("%S+") do filterWords[#filterWords + 1] = word end
	Refresh()
end)

-- shows the inbox of the chosen character: your own (live) or a remembered one
local function View(name)
	viewing = (name ~= charKey) and name or nil
	takeAll = nil
	UIDropDownMenu_SetText(charDropDown, CharLabel(name))
	Scan()
	Arrange()
	Refresh()
end

UIDropDownMenu_Initialize(charDropDown, function()
	if not MailBankDB or not charKey then return end -- the game calls this once right away, before our settings are loaded
	local names = {}
	for name in pairs(MailBankDB.chars) do
		if name ~= charKey then names[#names + 1] = name end
	end
	table.sort(names)
	table.insert(names, 1, charKey)
	for _, name in ipairs(names) do
		local info = UIDropDownMenu_CreateInfo()
		local saved = MailBankDB.chars[name]
		info.text = CharLabel(name, true) .. (name == charKey and "  (this one)" or ("  |cff808080" .. #saved.items .. " items|r"))
		info.checked = (name == (viewing or charKey))
		info.func = function() View(name) end
		UIDropDownMenu_AddButton(info)
	end
end)

window:SetScript("OnShow", function()
	Anchor()
	viewing = nil -- always starts on your own inbox
	UIDropDownMenu_SetText(charDropDown, charKey and CharLabel(charKey) or "")
	Scan()
	Arrange() -- opening the window puts the items in order
	Refresh()
end)
window:SetScript("OnHide", function()
	takeAll = nil
end)

-- shows / hides the window (the tab, the Baganator button and /mailbank)
local function Toggle()
	local open = not window:IsShown()
	if atMailbox then MailBankDB.closed = not open end -- remembered only at the mailbox
	window:SetShown(open)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end

---------------------------------------------------------------------------
-- BUTTON IN BAGANATOR'S BAG WINDOW (only when Baganator is installed)
---------------------------------------------------------------------------
local bagButton
local function MakeBaganatorButton()
	if bagButton or not (Baganator and Baganator.API and Baganator.API.RegisterRegion) then return end
	-- same template as Baganator's own buttons at the top of the bag window
	bagButton = CreateFrame("Button", "MailBankBaganatorButton", UIParent, "BaganatorTooltipIconButtonTemplate")
	bagButton.tooltipHeader = "Mail Bank"
	bagButton.tooltipText = "Items in your mailbox"
	bagButton.Icon = bagButton:CreateTexture(nil, "ARTWORK")
	bagButton.Icon:SetSize(18, 18)
	bagButton.Icon:SetPoint("CENTER")
	bagButton.Icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox") -- the envelope of the minimap's mailbox tracking
	bagButton:SetScript("OnClick", Toggle)
	-- Baganator moves the button into its window; keep it above the window's border like its own buttons
	hooksecurefunc(bagButton, "SetParent", function(self) self:SetFrameLevel(700) end)
	if Baganator.Skins and Baganator.Skins.AddFrame then
		Baganator.Skins.AddFrame("IconButton", bagButton, { "mailBank" }) -- follows Baganator's skin
	end
	-- "top_left" = right after Baganator's buttons at the top left
	Baganator.API.RegisterRegion("Mail Bank", "MailBank", "backpack", "top_left", bagButton)
	-- choosing a character in Baganator's "All Characters" list shows that character's inbox here too (only while open)
	if Baganator.CallbackRegistry then
		Baganator.CallbackRegistry:RegisterCallback("CharacterSelect", function(_, character)
			if not window:IsShown() or type(character) ~= "string" then return end
			local who = character:match("^[^-]+") -- "Name Surname", without the realm (Baganator writes it differently)
			if who == charKey:match("^[^-]+") then View(charKey) return end
			for name in pairs(MailBankDB.chars) do
				if name:match("^[^-]+") == who then View(name) return end
			end
			View(who .. "-" .. GetRealmName()) -- not remembered: shows an empty inbox with a note
		end, window)
	end
	if Baganator.API.RequestLayoutUpdate then Baganator.API.RequestLayoutUpdate() end
end

---------------------------------------------------------------------------
-- TAB UNDER THE MAILBOX (shows / hides the window)
---------------------------------------------------------------------------
local tab
local function MakeTab()
	if tab or not MailFrame or not MailFrameTab2 then return end
	tab = CreateFrame("Button", "MailBankTab", MailFrame, "FriendsFrameTabTemplate")
	tab:SetPoint("LEFT", MailFrameTab2, "RIGHT", 4, 0) -- same gap as between Inbox and Send Mail
	-- the template adds the tab to MailFrame.Tabs; take it out so the mailbox's own tab code leaves it alone
	if MailFrame.Tabs then tDeleteItem(MailFrame.Tabs, tab) end
	tab:SetText("Mail Bank")
	if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
	if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end -- normal (not selected) look
	tab:SetScript("OnClick", Toggle)
	MailFrame:HookScript("OnHide", function()
		atMailbox = false -- the game does not always send MAIL_CLOSED when the mailbox closes
		window:Hide()
	end)
	if OpenMailFrame then
		OpenMailFrame:HookScript("OnShow", Anchor)
		OpenMailFrame:HookScript("OnHide", Anchor)
	end
end

---------------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "MailBank" then
			MailBankDB = MailBankDB or {}
			MailBankDB.chars = MailBankDB.chars or {} -- "Name-Realm" -> { time, money, items } as last seen in its mailbox
			local name, surname = UnitName("player")
			local sep = Constants and Constants.CharacterNameSeparatorConsts and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
			charKey = ((surname and surname ~= "") and (name .. sep .. surname) or name) .. "-" .. GetRealmName()
			-- older versions remembered the inbox under the first name only; drop that (saved again at the next mailbox)
			local old = name .. "-" .. GetRealmName()
			if old ~= charKey then MailBankDB.chars[old] = nil end
			SIZE = MailBankDB.size or DEFAULT_SIZE
			MakeBaganatorButton() -- Baganator is loaded before this addon (OptionalDeps in the .toc)
		end
		MakeTab() -- the mailbox may load before or after this addon
		return
	end
	if event == "MAIL_SHOW" then
		MakeTab()
		busy, takeAll = 0, nil
		inboxLoaded = false
		atMailbox = true
		window:Hide() -- if it was open away from the mailbox: open it again next to the mailbox
		if not MailBankDB.closed then window:Show() end
	elseif event == "MAIL_CLOSED" then
		atMailbox = false
		window:Hide()
	elseif event == "MAIL_INBOX_UPDATE" then
		busy = 0
		inboxLoaded = true
		-- read your own inbox (this also remembers it), even when the window is closed or shows another character
		local other = viewing
		viewing = nil
		Scan()
		viewing = other
		if not window:IsShown() or not atMailbox then return end
		if viewing then Scan() end
		Sync()
		Refresh()
		if takeAll then C_Timer.After(0.2, ContinueTakeAll) end
	elseif event == "MAIL_FAILED" or event == "UI_ERROR_MESSAGE" then
		-- bags full, item unique, ... : stop taking
		if takeAll or busy > 0 then
			busy, takeAll = 0, nil
			Reread(true)
		end
	end
end)

SLASH_MAILBANK1 = "/mailbank"
SlashCmdList.MAILBANK = function(msg)
	if (msg or ""):match("^%s*text") then
		-- for finding out why the search does not find something: what is searched in for each item
		print("Mail Bank: tooltip reading " .. ((C_TooltipInfo and C_TooltipInfo.GetHyperlink) and "available" or "NOT available in this client"))
		for i = 1, math.min(#slots, 3) do
			print(i .. ": " .. SearchText(slots[i]):gsub("\n", " / "))
		end
		return
	end
	if (msg or ""):match("^%s*bag") then
		-- for finding out why the button in Baganator's bag window cannot be seen
		if not bagButton then
			print("Mail Bank: no Baganator button (Baganator " .. ((Baganator and Baganator.API and Baganator.API.RegisterRegion) and "found" or "NOT found") .. ")")
		else
			local parent = bagButton:GetParent()
			print("Mail Bank: Baganator button - in " .. tostring(parent and parent:GetName()) .. ", shown " .. tostring(bagButton:IsVisible())
				.. ", level " .. bagButton:GetFrameLevel() .. ", width " .. math.floor(bagButton:GetWidth()) .. ", placed " .. tostring(bagButton:GetNumPoints() > 0))
		end
		return
	end
	if (msg or ""):match("^%s*forget") then
		if viewing then
			local name = viewing
			MailBankDB.chars[name] = nil
			View(charKey)
			print("Mail Bank: forgot the remembered inbox of " .. name)
		else
			print("Mail Bank: first choose another character in the window's drop-down.")
		end
		return
	end
	if strtrim(msg or "") == "" then
		Toggle()
		return
	end
	local size = tonumber((msg or ""):match("^%s*size%s+(%d+)"))
	if size and size >= 24 and size <= 80 then
		SIZE = size
		MailBankDB.size = size
		if window:IsShown() then Anchor() Refresh() end
		print("Mail Bank: icon size " .. size)
	else
		print("Mail Bank: /mailbank   opens / closes the window (away from a mailbox: view only)")
		print("Mail Bank: /mailbank size N   (24-80, now " .. SIZE .. ", default " .. DEFAULT_SIZE .. ")")
		print("Mail Bank: /mailbank forget   forgets the remembered inbox of the character chosen in the drop-down")
	end
end
