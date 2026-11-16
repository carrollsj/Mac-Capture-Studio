#!/bin/zsh
# Builds "Mac Capture Studio.app" into build/. Pass --install to copy it to /Applications and open it.
set -euo pipefail
ROOT="${0:A:h}"
NAME="Mac Capture Studio"
APP="$ROOT/build/$NAME.app"
TMP=$(mktemp -d /private/tmp/mcs-build.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "Drawing icon…"
swiftc -module-cache-path "$TMP/cache-icon" "$ROOT/Tools/MakeIcon.swift" -o "$TMP/makeicon" -framework Cocoa
"$TMP/makeicon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

for ARCH in arm64 x86_64; do
  echo "Compiling $ARCH…"
  swiftc -O -swift-version 5 -module-cache-path "$TMP/cache-$ARCH" -target "$ARCH-apple-macosx13.0" \
    "$ROOT"/Source/*.swift -o "$TMP/bin-$ARCH" \
    -framework Cocoa -framework Carbon -framework CoreImage -framework ServiceManagement -framework UniformTypeIdentifiers
done
lipo -create "$TMP/bin-arm64" "$TMP/bin-x86_64" -output "$APP/Contents/MacOS/MacCaptureStudio"

xattr -cr "$APP"
codesign --force --sign - --identifier com.carrollsj.MacCaptureStudio "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MacCaptureStudio 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$NAME.app"
  ditto "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed to /Applications and opened"
fi
