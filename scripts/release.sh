#!/usr/bin/env bash
# Build a release DMG of GameBridge into ./dist/.
#
# Signing: defaults to the local self-signed "GameBridge Dev" identity so this
# works with no Apple Developer Program membership. Override via env for
# notarised distribution once a Developer ID is available:
#
#   GAMEBRIDGE_RELEASE_IDENTITY="Developer ID Application: Argie Suboc (TEAMID)" \
#   GAMEBRIDGE_DEVELOPMENT_TEAM="TEAMID" \
#   GAMEBRIDGE_NOTARIZE=1 \
#   scripts/release.sh
#
# Notarisation additionally reads GAMEBRIDGE_NOTARIZE_PROFILE (a
# `xcrun notarytool store-credentials` profile name).
#
# Steps: xcodegen -> tests -> archive -> export -> DMG. Fails fast on any
# error. Existing dist/ contents are overwritten.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="GameBridge"
SCHEME="GameBridge"
VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
[ -n "$VERSION" ] || { echo "ERROR: could not read MARKETING_VERSION from project.yml"; exit 1; }
BUILD_DIR="$(pwd)/build/release"
DIST_DIR="$(pwd)/dist"
ARCHIVE="$BUILD_DIR/$PROJECT.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_NAME="$PROJECT-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

RELEASE_IDENTITY="${GAMEBRIDGE_RELEASE_IDENTITY:-GameBridge Dev}"
DEVELOPMENT_TEAM="${GAMEBRIDGE_DEVELOPMENT_TEAM:-}"

echo "GameBridge release pipeline"
echo "  version:   $VERSION"
echo "  identity:  $RELEASE_IDENTITY"
echo "  dist dir:  $DIST_DIR"
echo

echo "[1/6] xcodegen generate"
xcodegen generate

echo "[2/6] xcodebuild test (Debug)"
xcodebuild -scheme "$SCHEME" -configuration Debug \
    -derivedDataPath "$BUILD_DIR/dd" \
    test | tail -20

echo "[3/6] xcodebuild archive (Release)"
rm -rf "$ARCHIVE"
xcodebuild -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd" \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="$RELEASE_IDENTITY" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    archive | tail -10

echo "[4/6] xcodebuild -exportArchive"
rm -rf "$EXPORT_DIR"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$RELEASE_IDENTITY</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" 2>&1 | tail -6 || {
    # exportArchive with `developer-id` sometimes rejects self-signed identities.
    # Fall back to copying the .app out of the archive directly — the archive's
    # copy is already signed with the identity we asked for.
    echo "  (exportArchive failed; copying .app from archive as fallback)"
    mkdir -p "$EXPORT_DIR"
    cp -R "$ARCHIVE/Products/Applications/$PROJECT.app" "$EXPORT_DIR/"
}

APP_PATH="$EXPORT_DIR/$PROJECT.app"
[ -d "$APP_PATH" ] || { echo "ERROR: exported app not found at $APP_PATH"; exit 1; }
echo "  exported: $APP_PATH"

if [ "${GAMEBRIDGE_NOTARIZE:-0}" = "1" ]; then
    PROFILE="${GAMEBRIDGE_NOTARIZE_PROFILE:-}"
    [ -n "$PROFILE" ] || { echo "ERROR: GAMEBRIDGE_NOTARIZE=1 requires GAMEBRIDGE_NOTARIZE_PROFILE"; exit 1; }
    echo "[5/6] Notarising via profile '$PROFILE'"
    NOTARY_ZIP="$BUILD_DIR/$PROJECT.zip"
    (cd "$EXPORT_DIR" && ditto -c -k --keepParent "$PROJECT.app" "$NOTARY_ZIP")
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
else
    echo "[5/6] Skipping notarisation (set GAMEBRIDGE_NOTARIZE=1 to enable)."
fi

echo "[6/6] Packaging DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
    -volname "$PROJECT $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" | tail -3

echo
echo "==============================================="
echo " Release DMG:   $DMG_PATH"
echo " Signed with:   $RELEASE_IDENTITY"
if [ "${GAMEBRIDGE_NOTARIZE:-0}" = "1" ]; then
    echo " Notarised:     YES"
else
    echo " Notarised:     NO — recipients will see Gatekeeper warning."
    echo "                First-launch instructions: right-click GameBridge.app → Open."
fi
echo "==============================================="
