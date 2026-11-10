# Settings and privacy

Open Settings with ⌘, in the shelf, or from the menu bar icon.

## General

| Setting | What it does |
| --- | --- |
| Open at login | start Paste when you log in |
| iCloud sync | see [Sync](sync.md) |
| Sound effects | a soft paper brush on copy, a soft tap on paste |
| Show in menu bar | hide the menu bar icon (⇧⌘V still works) |
| Paste Items | **To active app** types ⌘V for you (needs Accessibility); **To clipboard** only copies |
| Always paste as Plain Text | drop formatting every time |
| Keep History | Day, Week, Month, Year or Forever. Pinned items are always kept |
| Erase History… | delete everything except pinboards and their items |

## Privacy

| Setting | What it does |
| --- | --- |
| Show during screen sharing | off by default: the shelf is invisible to screen sharing and recording |
| Generate link previews | fetch the title and image of copied links |
| Ignore confidential content | skip passwords and anything an app marks as concealed |
| Ignore transient content | skip data apps put on the clipboard automatically |
| Ignore Applications | nothing copied in these apps is saved |

Paste makes no network requests except link previews (when on) and whatever
iCloud Drive does for sync. There is no analytics or telemetry.

## Shortcuts

| Shortcut | Default |
| --- | --- |
| Activate Paste | ⇧⌘V |
| Activate Paste Stack | ⇧⌘C |
| Show next / previous pinboard | ⌘→ / ⌘← (in the shelf) |
| Quick Paste modifier | ⌘ + 1…9 |
| Plain Text mode modifier | ⇧ + ↩ |

If another app already owns a shortcut, Settings says so; pick another one.

## Where data lives

| What | Where |
| --- | --- |
| History and pinboards | `~/Library/Application Support/app.paste.clipboard/library.json` |
| Images, rich text, previews | `~/Library/Application Support/app.paste.clipboard/data/` |
| Settings | `defaults read app.paste.clipboard` |
| Sync | `iCloud Drive/Paste/` |
