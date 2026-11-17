# Mail Bank (WoW Forever)

**All items from your mailbox in one window, like one big bag.**

Mail Bank is a World of Warcraft addon for the Forever client. It opens a window next to the mailbox that shows every item attached to the mails in your inbox. A click takes the item, without opening the mails one by one.

---

**Project status:** Early version, before 0.1. It is used daily by the author and a few guild mates.

**Transparency:** Mail Bank is written entirely by AI. All of the code and this documentation were produced by an AI coding assistant (Claude); the maintainer is not a programmer and did not write any of it by hand. His part was deciding what the addon should do, testing every change in the game and reporting what was wrong. The code is one Lua file, kept readable and commented so that it can be inspected directly.

**Credits:** The expiry marks, the sender in the tooltip, the money total and the grey C.O.D. / GM items follow the Bankbox addon by Siz.

**License:** [MIT](LICENSE)

---

## What it does

- Shows every item from all mails in the inbox in one grid, next to the mailbox.
- Takes one stack with a left click, and every stack of the same item with a right click.
- Keeps the items in their places while you take them: a taken item leaves an empty place. The items are put in order again the next time the window opens.
- Has a search box that looks in the item's name, its type and the whole text of its tooltip (for example `crafting reagent`, `cloth` or `use:`). Every word typed must be found. Items that do not match are dimmed and stay where they are.
- Marks items from mails that expire soon: a red frame under 10 days, a countdown under 3 days.
- Shows the sender and the time left in the tooltip.
- Shows the total of the money in the inbox.
- Remembers the inbox of every character that opens its mailbox. A drop-down in the window shows the remembered inbox of your other characters (view only, as it was when that character last looked).
- Grows with the number of items: 8 wide and up to 12 rows, then wider (up to 16), then it scrolls.
- Links an item in chat with Shift + click, like in bags.

## What it is not

- Not a mail collector. It does not take money and it does not open or delete mails.
- It never pays for anything. Items from cash on delivery (C.O.D.) and GM mails are shown grey and cannot be taken from this window; open the mail in the inbox for those.

## Install

1. Download this repository.
2. Copy the folder `MailBank` into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Start the game.

## Use

Open a mailbox. The Mail Bank window opens next to it. The **Mail Bank** tab under the mailbox shows and hides the window; the choice is remembered.

- **Left click:** take that stack.
- **Right click:** take every stack of that item, one after another. It stops when the bags are full.
- **Shift + click:** link the item in chat.
- `/mailbank` opens the window anywhere. Away from a mailbox it shows your inbox as it was when you last opened a mailbox (view only); there the window can be dragged and Escape closes it. With [Baganator](https://www.curseforge.com/wow/addons/baganator) there is also a Mail Bank button at the top of the bag window. Choosing a character in Baganator's All Characters list also switches the open Mail Bank window to that character.
- `/mailbank size 42` sets the icon size (24 - 80, default 42).
- `/mailbank forget` forgets the remembered inbox of the character chosen in the drop-down.

## Requirements

- World of Warcraft, Forever client (interface 16001).
- No other addons or libraries.
