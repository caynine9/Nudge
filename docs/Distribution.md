# Nudge distribution

## Install a personal build

On a Mac with Xcode installed, run:

```bash
./scripts/package-dmg.sh
```

The script builds a universal `Nudge.app`, then creates `dist/Nudge-<version>-macOS.dmg`. Open the DMG and drag `Nudge.app` onto the `Applications` shortcut. Nudge is an accessory app, so its window is in the menu bar and notch rather than the Dock. Launch it from Applications.

This build uses an ad-hoc signature and is intended for your own Mac. A copy downloaded from GitHub can trigger macOS Gatekeeper because it has not been signed with Developer ID or notarized. In Finder, Control-click `Nudge.app`, choose **Open**, and confirm the one-time prompt. For a release that installs without this step, Nudge needs Developer ID signing and notarization.

## Publish a GitHub Release

The `Personal macOS release` workflow builds an arm64/x86_64 universal app and attaches the ad-hoc-signed DMG to a GitHub Release when a `v*` tag is pushed. It requires no Apple signing secrets. GitHub currently lists `xcode-27` as a public-preview macOS runner image.

This release path is for personal use. Anyone downloading the app will need the one-time Gatekeeper confirmation above. For broad public distribution, add Developer ID signing and notarization credentials before publishing.

To publish version `0.1.0`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

When the workflow succeeds, GitHub creates a release named `Nudge 0.1.0` with a `Nudge-0.1.0-macOS.dmg` attachment.
