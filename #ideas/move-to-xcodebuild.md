# Idea: Move to `xcodebuild`

Currently, SQLiteo uses `swift build` via the command line and a custom `build-release.sh` script to package the app. This requires a manual `sed` patch to fix `Bundle.module` resource lookups.

Moving to `xcodebuild` would provide a more standard macOS build experience while keeping the project as a pure Swift Package.

## Why move?
- **Native Resource Handling**: `xcodebuild` correctly manages resource bundles for App targets, so `Bundle.module` works without `sed` hacks.
- **Improved Signing**: Handles provisioning profiles and "official" codesigning more robustly than ad-hoc `codesign` commands.
- **Future Proofing**: Essential if we ever need to add CloudKit, Sandboxing (App Store), or custom Plist keys via standard Xcode build settings.

## Proposed Strategy
Instead of maintaining an `.xcodeproj` file, we can continue using `Package.swift` and use the built-in Swift Package support in `xcodebuild`.

### Local Development Command
```bash
xcodebuild -scheme SQLiteo -configuration Release -destination 'platform=macOS' -derivedDataPath .build
```

### GitHub Actions Integration
The `macos-latest` runner already has `xcodebuild` installed. The workflow step would look like this:

```yaml
- name: Build App
  run: |
    xcodebuild -scheme SQLiteo \
               -configuration Release \
               -destination 'platform=macOS' \
               -derivedDataPath .build
```

## Considerations
- **Build Speed**: `xcodebuild` can be slightly slower to start than `swift build`.
- **Log Verbosity**: Output is much more verbose; might need `xcbeautify` or `xcpretty` for cleaner CI logs.
- **Cross-Platform**: While the app is macOS-only, using `xcodebuild` tightly couples the build process to Apple hardware (which is true for the app anyway).
