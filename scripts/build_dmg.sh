#!/bin/bash
# Builds Crumble as a universal (arm64 + x86_64) Release app, ad-hoc signs it,
# and packages it into a distributable .dmg.
#
# The Xcode project/scheme is still named MyWorkTracker (bundle id kept for data
# preservation); the product is Crumble.app.
#
# This produces an UNSIGNED-for-distribution build (ad-hoc only). Users install
# via scripts/install.sh (curl → no quarantine) or bypass Gatekeeper once.
#
# Usage: ./scripts/build_dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
PROJECT="MyWorkTracker"
SCHEME="MyWorkTracker"
APP_NAME="Crumble"
DMG_NAME="Crumble.dmg"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building universal Release"
rm -rf "$BUILD_DIR"
"$XCODEBUILD" \
  -project "$PROJECT.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Build failed: $APP_PATH not found"; exit 1; }

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose "$APP_PATH" || true

echo "==> Staging DMG contents"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG_NAME"
mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/$DMG_NAME"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$ROOT/dist/$DMG_NAME" >/dev/null

echo "==> Done: $ROOT/dist/$DMG_NAME"
ls -lh "$ROOT/dist/$DMG_NAME"
lipo -info "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
