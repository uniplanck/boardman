# Board-Man Release and Update Spec

## Correct Update Architecture

Board-Man updates should follow this path:

```text
GitHub Releases -> prebuilt Board-Man.app.zip or dmg -> appcast.xml -> Sparkle -> Check for Updates
```

The app should check a published Sparkle appcast and let Sparkle handle update discovery, download, verification, and installation prompts.

## Explicitly Rejected Architecture

Board-Man must not update itself by running app-internal `git pull` plus local build.

Reasons:

- End users may not have Git, Xcode, dependencies, or signing context.
- Local builds are not equivalent to signed release artifacts.
- It bypasses Sparkle's release verification path.
- It creates security, support, and reproducibility problems.

## Current State

- App-side update route exists.
- Feed may be unpublished.
- Manual check may show a feed-not-published alert.
- This is acceptable for 0.0.1 internal / pre-release baseline.

## Out of Scope for This PR

Production release steps are intentionally out of scope for this PR.

Do not:

- Generate Sparkle private keys
- Create GitHub Releases
- Upload release assets
- Publish `appcast.xml`
- Notarize artifacts
- Change production distribution settings

## Production Release Direction

A future production release should build signed artifacts outside the app, attach the prebuilt artifact to GitHub Releases, publish a verified appcast, and confirm Sparkle can discover the release through Check for Updates.
