# Canonical Board-Man Install

Board-Man has one canonical dogfooding and production identity:

- App path: `/Applications/Board-Man.app`
- Bundle identifier: `com.uniplanck.BoardMan`
- Bundle name: `Board-Man`
- Display name: `Board-Man`

Do not install or dogfood as `Board-Man-beta.app`, `Dogfood.app`, `Board-Man 2.app`, or backup `.app` bundles. Those copies can pollute Spotlight, LaunchServices, and macOS TCC permissions, which makes Accessibility and Input Monitoring prompts harder to reason about.

Use `scripts/install-canonical-boardman.sh` only when intentionally replacing the canonical app. It builds Release, installs only to `/Applications/Board-Man.app`, verifies the final Info.plist identity, and ad-hoc signs only that installed app. The script does not launch, quit, or kill Board-Man; if the app is running, it stops and asks you to quit it manually.

Backups must be `.tar.gz` archives, not `.app` directories. A backup app bundle is still an app bundle and can be indexed or registered by macOS. The canonical install script stores backups and build output under a timestamped `_copy/canonical-install-runs/` run directory with `.metadata_never_index`, then removes transient DerivedData app products after installation.

The install script never runs `tccutil reset`. TCC grants are user-controlled macOS privacy state, and resetting them during install makes permission behavior less predictable. If permissions need attention, adjust them manually in System Settings > Privacy & Security > Accessibility and Input Monitoring, keeping only `/Applications/Board-Man.app` enabled.

For a non-mutating check, run:

```bash
scripts/check-boardman-identity.sh
```
