# Security Policy

## Supported versions

Only the latest release gets security fixes.

## Reporting a vulnerability

Please don't open a public issue for security problems.

Report it privately through GitHub instead:
[**Report a vulnerability**](https://github.com/GrowlyX/paste/security/advisories/new)
(the Security tab, then "Report a vulnerability").

Include what you can:

- Paste version (Settings › About), macOS version, and whether you built it yourself
- steps to reproduce, or a proof of concept
- what an attacker gains

### What to expect

- **Acknowledgement** within 3 business days.
- **Assessment** within 10 business days: we confirm the issue, or explain why
  we don't consider it a vulnerability.
- **Fix and disclosure**: we ship a patched release, publish a GitHub security
  advisory, and credit you unless you'd rather we didn't.

## Scope

In scope:

- Clipboard capture: content Paste saves even though it should be skipped
  (concealed or transient types, ignored apps, while paused)
- The library on disk, iCloud Drive sync and shared pinboards: anything that
  lets another person or app read or inject items they shouldn't
- Pasting: anything that makes Paste type into or paste into an app the user
  didn't choose
- The Accessibility-based ⌘V event tap used by the Paste Stack
- Link previews: requests Paste makes on its own

Out of scope:

- Other apps reading the system clipboard, which macOS allows by design
- Attacks that already require the same user account
- Contents of a shared pinboard folder that you shared with someone yourself

Thanks for helping keep Paste and its users safe.
