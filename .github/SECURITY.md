# Security Policy

Board-Man processes clipboard contents, local templates, image previews, global shortcuts, and signed update metadata. Security reports deserve a private path before public disclosure.

## Supported versions

Security fixes are targeted at the latest tagged release and the current `main` branch. Older releases may not receive backports.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** / private security advisory feature for this repository when available. Include:

- affected version or commit
- macOS version and hardware architecture
- impact and realistic attack path
- minimal reproduction steps
- relevant logs with secrets and clipboard contents removed
- whether the issue affects a clean profile or only migrated data

Do **not** open a public issue for suspected vulnerabilities involving:

- clipboard or template disclosure
- local Realm or archived clipboard data exposure
- update-signature or Sparkle verification
- owner/license token verification
- Accessibility, Input Monitoring, or TCC bypass
- arbitrary code execution or unsafe paste behavior

If private reporting is unavailable, open a public issue containing only a request for a secure contact channel. Do not include exploit details.

## Scope notes

Board-Man is local-first, but clipboard managers inherently handle sensitive data. Users should avoid copying secrets they do not want stored in local history and should use the masking and retention controls appropriately.

The project will not treat social engineering, access to an already-unlocked user session, or behavior requiring prior full control of the Mac as equivalent to a remote vulnerability unless an additional trust boundary is crossed.

## Disclosure

Please allow time to reproduce, fix, verify, and publish an update before public disclosure. Credit will be provided when requested and appropriate.
