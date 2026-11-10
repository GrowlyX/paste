# Sync

Paste syncs your history and pinboards between your Macs through
**iCloud Drive**. There's no account and no server: turn on iCloud Drive in
System Settings › Apple Account › iCloud, then Settings › General ›
**iCloud sync** in Paste.

## How it works

```text
iCloud Drive/Paste/
  devices/<device-id>.json   one snapshot per Mac
  data/                      images, rich text, link previews
```

- Each Mac writes only its own snapshot, so iCloud never sees two Macs
  writing the same file and never makes conflict copies.
- Each Mac reads the others' snapshots every ten seconds, and whenever the
  shelf opens.
- Items and pinboards merge **last writer wins** by modification time.
- Deletions travel as **tombstones**, kept for 90 days so a Mac that was
  offline still learns about them.
- Payload files are copied into `data/` once and fetched on demand.

The status line under the toggle shows **Synced**, **Syncing**, an error, or
that iCloud Drive is unavailable.

## Limits

- The data is visible in iCloud Drive like any other file. Apple encrypts
  it under your iCloud account; turn on Advanced Data Protection for
  end-to-end encryption.
- Items you never let leave your Mac (concealed content, ignored apps) are
  never captured, so they are never synced either.
- A future signed build can move to CloudKit, which adds push updates and
  invite-link sharing.
