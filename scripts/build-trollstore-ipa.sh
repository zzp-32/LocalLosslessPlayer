#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build"
APP_PATH="$BUILD_ROOT/Build/Products/Release-iphoneos/LocalLosslessPlayer.app"
PACKAGE_ROOT="$BUILD_ROOT/package"
IPA_PATH="$PROJECT_ROOT/LocalLosslessPlayer-TrollStore.ipa"

rm -rf "$BUILD_ROOT" "$IPA_PATH"

xcodebuild \
  -project "$PROJECT_ROOT/LocalLosslessPlayer.xcodeproj" \
  -scheme LocalLosslessPlayer \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  build

test -d "$APP_PATH"
test -x "$APP_PATH/LocalLosslessPlayer"

mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "$APP_PATH" "$PACKAGE_ROOT/Payload/"
cd "$PACKAGE_ROOT"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload "$IPA_PATH"

echo "Created: $IPA_PATH"
/usr/bin/file "$APP_PATH/LocalLosslessPlayer"
