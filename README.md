# Release Watcher

Release Watcher is a lightweight macOS menu bar app that keeps an eye on GitHub repositories and lets you know when a new release appears.

If you find it useful, please consider **starring the project on GitHub** — it helps a lot and makes the project easier for other people to discover.

**GitHub:** https://github.com/alvarosanchez/release-watcher

## What it does

- Watch one or more GitHub repositories
- See the latest release directly from the menu bar
- Jump to the release page with one click
- Get macOS notifications when a new release is published
- Configure how often the app checks GitHub
- Optionally launch the app automatically at login

## Install

The easiest way to install Release Watcher is from the GitHub Releases page.

1. Open the releases page:
   https://github.com/alvarosanchez/release-watcher/releases
2. Download the latest `ReleaseWatcher.zip`
3. Unzip it
4. Move `ReleaseWatcher.app` to your **Applications** folder
5. Open the app

Depending on your macOS security settings, you may need to confirm that you want to open the app the first time.

## How to use it

1. Launch **Release Watcher**
2. Click the menu bar icon
3. Open the repository management window
4. Add a GitHub repository using either:
   - `owner/repo`
   - `https://github.com/owner/repo`
5. Choose how often Release Watcher should check GitHub
6. Optionally enable **Open Release Watcher at login**

Once repositories are configured, the app lives quietly in the menu bar.

### Menu bar popover

The popover shows:
- your watched repositories
- the latest known release tag
- how long ago it was released

Click any repository in the popover to open its latest release page in your browser.

### Status bar icon actions

- **Left click**: open the popover
- **Right click**: open the quick action menu

## Notifications

Release Watcher can ask for permission to send macOS notifications when it detects a new release.

If notifications are unavailable on your system, the management window will show the current status.

## Build from source

If you want to build it yourself:

```bash
swift build
```

To create a local app bundle:

```bash
Scripts/package-app.sh
```

This generates:
- `dist/ReleaseWatcher.app`
- `dist/ReleaseWatcher.zip`

## Contributing, feedback, and issues

Bug reports, ideas, and contributions are very welcome.

- Report issues here: https://github.com/alvarosanchez/release-watcher/issues
- Project page: https://github.com/alvarosanchez/release-watcher

And if you like the app, please **star the repository** — it’s a small gesture that helps a lot.

---

Made with care, curiosity, and a little sparkle by **Álvaro Sánchez-Mariscal**.
