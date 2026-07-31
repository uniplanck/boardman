# Board-Man Support

## Before opening an issue

1. Confirm the problem still occurs on the latest published release.
2. Restart Board-Man from `/Applications/Board-Man.app`.
3. Check **System Settings → Privacy & Security** for Accessibility and Input Monitoring permissions.
4. Reproduce with a non-sensitive clipboard value.
5. Search existing issues.

## Bug reports

Use the bug report form and include:

- Board-Man version or commit
- macOS version
- Apple Silicon or Intel
- exact steps and expected/actual behavior
- whether the issue occurs at normal and narrow panel widths
- screenshots using non-sensitive content
- relevant logs with private data removed

Never attach Realm databases, archived clipboard files, license tokens, passwords, API keys, customer data, or complete system logs.

## Feature requests

Describe the workflow problem before prescribing an implementation. Explain what you repeatedly copy, paste, organize, or search, and why existing History, Templates, Pin, or settings behavior does not solve it.

## Installation and permissions

Board-Man uses macOS Accessibility and Input Monitoring for global shortcuts and reliable pasting. The project cannot silently grant or bypass these permissions. If macOS keeps showing stale permissions, remove old development copies, keep one canonical app in `/Applications`, then grant permissions to that copy.

## Security issues

Follow [`SECURITY.md`](SECURITY.md). Do not disclose vulnerability details in a public issue.
