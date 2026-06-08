# Board-Man Sparkle Update Foundation

Board-Man uses Sparkle for manual update checks from the Updates preferences pane.

Production auto-update distribution is not enabled yet. The current app-side feed URL is:

```text
https://github.com/uniplanck/boardman/releases/latest/download/appcast.xml
```

Until that release asset exists, the app should show a non-fatal message that the update feed is not published yet.

## Intended Release Assets

Each published update release should include:

- `Board-Man.app.zip` or `Board-Man.dmg`
- `appcast.xml`
- a Sparkle EdDSA signature for the downloadable archive

Expected GitHub Release asset URL shape:

```text
https://github.com/uniplanck/boardman/releases/download/vX.Y.Z/Board-Man.app.zip
https://github.com/uniplanck/boardman/releases/download/vX.Y.Z/appcast.xml
https://github.com/uniplanck/boardman/releases/latest/download/appcast.xml
```

## Sparkle Signature Requirements

Sparkle 2 requires signed update items. Generate update signatures with Sparkle's official signing tooling and keep the private signing key outside the repository.

Do not commit:

- private Sparkle signing keys
- release-only credentials
- GitHub tokens
- notarization credentials

The public EdDSA key belongs in the app bundle Info.plist as `SUPublicEDKey`.

## Appcast Template

This template is illustrative only. Replace every version, URL, length, and signature value before publishing.

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Board-Man Updates</title>
    <item>
      <title>Version X.Y.Z</title>
      <sparkle:version>X.Y.Z</sparkle:version>
      <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
      <pubDate>Mon, 08 Jun 2026 00:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/uniplanck/boardman/releases/download/vX.Y.Z/Board-Man.app.zip"
        sparkle:edSignature="REPLACE_WITH_SPARKLE_SIGNATURE"
        length="REPLACE_WITH_BYTE_LENGTH"
        type="application/zip" />
    </item>
  </channel>
</rss>
```

## Not Enabled Yet

This foundation does not:

- create a GitHub Release
- upload release assets
- generate or print private signing keys
- enable aggressive background update checks by default
- install or mutate the installed app bundle
