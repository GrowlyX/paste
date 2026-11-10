# Install

Paste runs on **macOS 14 Sonoma or later**, on Apple silicon and Intel.

## Download

Grab `Paste-<version>.zip` from
[Releases](https://github.com/GrowlyX/paste/releases/latest), unzip it and move
**Paste.app** to `/Applications`.

Builds that aren't signed with a Developer ID yet are blocked by Gatekeeper on
first launch. Right-click Paste.app › **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Paste.app
```

## Build from source

Needs the Swift command-line tools and **Xcode.app**. Xcode supplies the SwiftUI
macro plugin; you don't have to accept its license or select it with
`xcode-select`. If Xcode lives somewhere other than `/Applications/Xcode.app`,
set `XCODE_PATH`.

```sh
git clone https://github.com/GrowlyX/paste && cd paste
make install   # same as scripts/build.sh --install
```

`make build` only builds `build/Paste.app`. See [Development](development.md)
for the rest.

## First launch

Paste lives in the menu bar and has no Dock icon. Press **⇧⌘V** to open the
shelf. The first time you paste into another app, Paste asks for
**Accessibility** access (System Settings › Privacy & Security ›
Accessibility). It needs this to type ⌘V for you. Without it, Paste puts the
item on the clipboard and you press ⌘V yourself.

Locally built apps are signed ad hoc. macOS ties the Accessibility grant to the
signature, so after a rebuild you may need to switch Paste off and on again in
that list.

## Uninstall

Quit Paste from the menu bar icon, then:

```sh
rm -rf /Applications/Paste.app
rm -rf ~/Library/Application\ Support/app.paste.clipboard
defaults delete app.paste.clipboard
```

If you used iCloud sync, also delete `iCloud Drive/Paste`.
