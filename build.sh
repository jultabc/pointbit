#!/bin/sh
# Build "Pointbit.app" (arm64 + x86_64) into ./build with Swift Package Manager. Runs the tests first.
set -e
cd "$(dirname "$0")"
swift test
# README "Size" table must match the Swift files (it was out of date three times in review).
# find, not git ls-files: also works in a downloaded ZIP (no .git).
S=$(find Sources -name '*.swift' -exec cat {} + | wc -l | tr -d ' ')
T=$( (find Tests -name '*.swift' -exec cat {} +; cat Package.swift) | wc -l | tr -d ' ')
grep -q "| $S |" README.md && grep -q "| $T |" README.md && grep -q "| Total | $((S + T)) |" README.md \
  || { echo "README Size table is out of date: Sources $S, Tests + Package.swift $T, Total $((S + T))"; exit 1; }
NAME=$(sed -n 's/^public let appName = "\(.*\)"$/\1/p' Sources/PointbitKit/ClickStyle.swift)
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Info.plist)" = "$NAME" ] || { echo "Info.plist CFBundleName != appName ($NAME)"; exit 1; }
swift build -c release --arch arm64 --arch x86_64 --product Pointbit
swift build -c release --product MakeIcon
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
APP="build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Pointbit" "$APP/Contents/MacOS/Pointbit"
cp Info.plist "$APP/Contents/Info.plist"
rm -rf build/AppIcon.iconset; "$(swift build -c release --show-bin-path)/MakeIcon" build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Sign with a local identity when one exists (macOS then keeps Accessibility / Screen Recording grants across
# rebuilds); otherwise ad hoc. Override with SIGN_ID=<name>.
SIGN_ID=${SIGN_ID:-"Do I Click Local Signing"}
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then codesign --force --sign "$SIGN_ID" "$APP"
else codesign --force --sign - "$APP"; fi
echo "built $APP"
