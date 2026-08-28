#!/bin/sh
# On-device verification that a compile and a unit suite cannot perform.
#
# Runs three things a stub can never prove:
#   1. The macOS app actually launches on this Mac and does not crash.
#   2. Its live accessibility tree — the one VoiceOver reads — has no unlabelled
#      control and no hit target below 44pt.
#   3. The iOS bundle installs on a Simulator. This is what catches an Info.plist
#      that installd rejects; the scaffold shipped exactly such a defect
#      (NSExtensionPrincipalClass on a WidgetKit extension) and it compiled cleanly.
#
# Prints DEVICE_CHECK_OK only when all three pass.
#
# Requires: Accessibility permission for the calling terminal
# (System Settings > Privacy & Security > Accessibility), and one booted or
# bootable iOS Simulator.

set -eu

cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/WakaBoard-device-check"
ENTITLEMENTS="${TMPDIR:-/tmp}/wakaboard-localrun.entitlements"

# The shipping App Group entitlement is a restricted entitlement on macOS and needs a
# provisioning profile. This local-run build drops it so the app can launch unsigned
# on this machine. That means this script verifies launch, layout, and accessibility
# — NOT the entitlement grant, which stays open in GATES.md.
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST

cleanup() {
    pkill -f "WakaBoardApp_macOS" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Regenerating project"
xcodegen generate --quiet

echo "==> Building a runnable macOS app"
xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  -quiet

APP="$DERIVED/Build/Products/Debug/WakaBoardApp_macOS.app"
[ -d "$APP" ] || { echo "macOS app was not produced at $APP"; exit 1; }

echo "==> Launching on this Mac"
pkill -f "WakaBoardApp_macOS" 2>/dev/null || true
sleep 1
open "$APP"
sleep 6

PID=$(pgrep -f "WakaBoardApp_macOS" | head -1 || true)
[ -n "$PID" ] || { echo "the app did not stay running"; exit 1; }
echo "    running as pid $PID"

echo "==> Auditing the live accessibility tree"
swift scripts/ax-audit.swift "$PID"

echo "==> Installing on an iOS Simulator"
SIM=$(xcrun simctl list devices available 2>/dev/null \
      | grep -oE '\(([0-9A-F-]{36})\) \(Booted\)' \
      | grep -oE '[0-9A-F-]{36}' | head -1 || true)
if [ -z "$SIM" ]; then
    SIM=$(xcrun simctl list devices available 2>/dev/null \
          | grep -A100 -- '-- iOS' \
          | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1 || true)
    [ -n "$SIM" ] || { echo "no iOS Simulator available"; exit 1; }
    xcrun simctl boot "$SIM" >/dev/null 2>&1 || true
    sleep 8
fi
echo "    simulator $SIM"

xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_iOS \
  -destination "id=$SIM" \
  -derivedDataPath "$DERIVED-ios" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="" \
  DEVELOPMENT_TEAM="" \
  -quiet

IOS_APP="$DERIVED-ios/Build/Products/Debug-iphonesimulator/WakaBoardApp_iOS.app"
[ -d "$IOS_APP" ] || { echo "iOS app was not produced at $IOS_APP"; exit 1; }

xcrun simctl uninstall "$SIM" org.wakaboard.app >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$IOS_APP"
echo "    installed"

xcrun simctl launch "$SIM" org.wakaboard.app >/dev/null
sleep 4
xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -q "org.wakaboard.app" \
  || { echo "the iOS app did not stay running"; exit 1; }
echo "    launched and still running"

echo "DEVICE_CHECK_OK"
