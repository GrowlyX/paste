# Development

```sh
make build      # build/Paste.app (ad-hoc signed)
make install    # build, copy to /Applications, relaunch
make run        # build and run from build/ with debug logging
```

Paste is a single SwiftPM executable target (`Sources/Paste`) that
`scripts/build.sh` wraps into an app bundle. There's no Xcode project. You need
the Swift command-line tools plus Xcode.app for the SwiftUI macro plugin
(`XCODE_PATH` overrides where it's looked up).

## Layout

| File | What's in it |
| --- | --- |
| `main.swift` | app delegate, menu bar item, hotkeys, About |
| `ClipboardMonitor.swift` | pasteboard polling, classification, ignore rules, sounds |
| `Store.swift` | the library: items, pinboards, tombstones, merging, persistence |
| `PanelController.swift` | the non-activating shelf panel, focus, keyboard |
| `ShelfView.swift`, `CardView.swift` | the shelf UI and cards |
| `CardDragger.swift` | multi-card drag sessions and the deck drag image |
| `PasteService.swift` | writing to the pasteboard and typing ⌘V |
| `PasteStack.swift` | the Paste Stack panel and its ⌘V event tap |
| `SyncEngine.swift` | iCloud Drive sync |
| `SharedPinboards.swift` | shared-folder pinboards |
| `SettingsView.swift`, `Settings.swift` | preferences |
| `HotKey.swift` | Carbon global hotkeys, debug logging |
| `Media.swift` | app icons and tints, thumbnails, link previews |

## Environment variables

| Variable | Effect |
| --- | --- |
| `PASTE_DEBUG=1` | log hotkeys, drags and paste events to the unified log (`log stream --predicate 'process == "Paste"'`) |
| `PASTE_HOME=/some/dir` | use another library folder instead of Application Support. iCloud sync stays off. Handy for screenshots and testing |

`open -n --env PASTE_HOME=/tmp/demo build/Paste.app` launches a second copy
against a scratch library. Quit the installed Paste first so they don't fight
over ⇧⌘V.

## Artwork and sounds

| Output | Made by |
| --- | --- |
| `Resources/AppIcon.icns`, `assets/AppIcon-1024.png` | `make icon` (`scripts/make_icon.swift`) |
| `Resources/Copy.wav`, `Resources/Paste.wav` | `make sounds` (`scripts/make_sounds.py`, synthesized, no samples) |
| `docs/banner.svg` | `make banner` (`scripts/banner.py`) |

The icon and banner need
[Macintosh Skeletal Filled](https://github.com/npwitk/Macintosh-Skeletal-Filled).
Its license is personal and non-commercial, so it isn't in this repo: download
`MacintoshSkeletalFilled.otf` into `assets/` (it's git-ignored). The banner
converts all text, including SF Pro from `/System/Library/Fonts/SFNS.ttf`, to
outlines, so the SVG carries no font. `docs/shelf.png` is a capture of the shelf
running against a `PASTE_HOME` demo library.

## What CI checks

On every push and pull request, on macOS:

- the release build compiles and `scripts/build.sh` produces a valid bundle;
- the bundle's signature verifies and its Info.plist has the expected keys;
- the app launches against an empty `PASTE_HOME` and stays up.

## Releasing

Push a `v*` tag. The release workflow builds `Paste-<version>.zip` and
attaches it to a GitHub release.

Signing and notarization switch on when these repository secrets exist:

| Secret | What |
| --- | --- |
| `DEVELOPER_ID_P12` | base64 of the exported "Developer ID Application" certificate and key |
| `DEVELOPER_ID_P12_PASSWORD` | its export password |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `NOTARY_KEY_P8` | base64 of the App Store Connect API key (`.p8`) |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | that key's ID and issuer |

Without them the release is ad-hoc signed and users have to approve it in
Gatekeeper (see [Install](install.md)).
