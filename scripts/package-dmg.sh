#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
BUILD_DIR="$ROOT_DIR/.build/dmg"
APP_DIR="$BUILD_DIR/Perch.app"
DMG_STAGE="$BUILD_DIR/dmg-root"
VERSION="${PERCH_VERSION:-0.0.0}"
ARCHS="${PERCH_ARCHS:-arm64 x86_64}"

# Apple version fields allow only dot-separated numbers. Keep a readable version
# in the DMG filename while normalizing tag suffixes for Info.plist.
PLIST_VERSION="$(printf '%s' "$VERSION" | sed -E 's/^[vV]//; s/[^0-9.].*$//')"
if [[ ! "$PLIST_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  PLIST_VERSION="0.0.0"
fi
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-0}"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DMG_STAGE" "$OUTPUT_DIR"

binaries=()
for arch in $ARCHS; do
  triple="${arch}-apple-macosx13.0"
  scratch="$BUILD_DIR/build-$arch"
  swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$scratch" \
    --configuration release \
    --triple "$triple" \
    --jobs 2 \
    --product Perch
  bin_dir="$(swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$scratch" \
    --configuration release \
    --triple "$triple" \
    --show-bin-path)"
  binaries+=("$bin_dir/Perch")
done

if [[ ${#binaries[@]} -eq 1 ]]; then
  cp "${binaries[0]}" "$APP_DIR/Contents/MacOS/Perch"
else
  lipo -create "${binaries[@]}" -output "$APP_DIR/Contents/MacOS/Perch"
fi

cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLIST_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

# Export the native vector-drawn icon from Perch itself, then build an .icns.
icon_png="$BUILD_DIR/icon-1024.png"
PERCH_ICON_PNG="$icon_png" "$APP_DIR/Contents/MacOS/Perch"
iconset="$BUILD_DIR/Perch.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$icon_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$APP_DIR/Contents/Resources/Perch.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Perch.icns" "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/Perch"
codesign --force --sign - --identifier com.perch.twitter "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

cp -R "$APP_DIR" "$DMG_STAGE/Perch.app"
ln -s /Applications "$DMG_STAGE/Applications"

safe_version="$(printf '%s' "$VERSION" | sed -E 's/^[vV]//; s/[^A-Za-z0-9._-]/-/g')"
dmg_path="$OUTPUT_DIR/Perch-$safe_version-universal.dmg"
rm -f "$dmg_path"
hdiutil create \
  -volname "Perch $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -format UDZO \
  -ov \
  "$dmg_path"

echo "Created $dmg_path"
