# Pinboards

Pinboards keep items for good. Pinned items survive **Erase History** and
history retention.

- **Create** one with the **+** next to the tabs.
- **Pin** a card by dragging it onto a tab, or right-click › Pin.
- **Rename** with a double-click on the tab, or right-click › Rename.
- **Recolor** and **delete** from the tab's right-click menu.
- **Switch** between Clipboard and pinboards with ⇥ or ⌘← ⌘→ (change these
  in Settings › Shortcuts).

## Shared pinboards

A pinboard can be shared with other people through any folder you all can
reach: a shared iCloud Drive folder, Dropbox, Google Drive, a network share.

1. Right-click the pinboard › **Share Pinboard…** and pick the shared folder.
   Paste creates `<Name>.pastepinboard` in it and shows it in Finder.
2. Everyone else uses the shelf's ⋯ menu › **Join Shared Pinboard…** and picks
   that `.pastepinboard` folder.

Once joined, the tab shows a people badge. Changes from everyone show up within
about ten seconds.

Inside the folder:

```text
Snippets.pastepinboard/
  pinboard.json            name, color, id
  participants/<device>.json
  data/                    images, rich text, link previews
```

Each person's Mac writes only its own `participants/<device>.json` and reads
everyone else's. Because no two Macs write the same file, the sync service
never has to resolve a conflict. Items merge last-writer-wins, and deletions
travel as tombstones.

From the tab's menu, **Show Shared Folder** reveals the folder in Finder.
**Stop Sharing on This Mac** leaves the pinboard: the folder and everyone else's
copy stay as they are.
