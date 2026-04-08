# ReleaseWatcher

ReleaseWatcher is a tiny native macOS menu bar app for watching GitHub repositories and surfacing new releases.

## What is scaffolded

- Native SwiftUI app targeting macOS 14+
- `MenuBarExtra` status item that shows watched repositories and latest versions
- Main window for adding and removing repositories
- GitHub release polling service scaffold using the GitHub REST API
- Local persistence with a JSON-backed repository store
- GitHub Actions workflow that builds the app, packages a `.app` bundle, zips it, and drafts a GitHub Release on tag pushes

## Local development

```bash
swift run
```

## Building locally

```bash
swift build
```

## Packaging locally

```bash
Scripts/package-app.sh
```

This generates:

- `dist/ReleaseWatcher.app`
- `dist/ReleaseWatcher.zip`

## Publishing a release with GitHub Actions

Push a semantic version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow in `.github/workflows/release.yml` will:

1. build the app on macOS
2. assemble a minimal `.app` bundle
3. zip the app for distribution
4. create a draft GitHub Release with the zip attached

## Notes

This initial scaffold intentionally ships an unsigned build so GitHub Actions works without Apple signing secrets. For public distribution, the next step is to add Developer ID signing and notarization before uploading the release asset.
