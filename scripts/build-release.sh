#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SQLiteo"
SCHEME_NAME="SQLiteo"

# -- Setup --
VERSION=${1:-""}
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
fi

echo "Building ${APP_NAME} version ${VERSION}..."

# 1. Generate Xcode Project
echo "Generating Xcode project with XcodeGen..."
xcodegen generate

# 2. Archive the project
echo "Archiving project..."
rm -rf .build-archive
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath ".build-archive/${APP_NAME}.xcarchive" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${VERSION}"

# 3. Extract .app from archive
echo "Extracting .app from archive..."
rm -rf .build-export
mkdir -p .build-export
cp -R ".build-archive/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" ".build-export/"

APP_PATH=".build-export/${APP_NAME}.app"

# 4. Ad-hoc signing (without --deep to preserve entitlements)
echo "Ad-hoc signing nested bundles..."
find "${APP_PATH}/Contents" \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) -print0 2>/dev/null | \
xargs -0 -I {} codesign --force -s - {} || true
echo "Ad-hoc signing main app with entitlements..."
codesign --force -s - --entitlements Sources/SQLiteo/SQLiteo.entitlements "${APP_PATH}"

# 5. Create distribution DMG
echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "${APP_NAME}-macOS.dmg"

echo "Success! Created ${APP_NAME}-macOS.dmg"
