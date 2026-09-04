#!/bin/sh
# Builds every shipping target on every platform, warnings treated as errors.
#
# `swift test` only covers the two library targets. This is what proves the app
# shells and widget extensions still compile — the part that actually ships and the
# part a package-only CI job silently skips.
#
# macOS and iOS build for a destination, because both have one available here. The
# other three build against their device SDK with signing off: their simulator
# runtimes are multi-gigabyte downloads that are not installed, so `-destination`
# cannot resolve and `xcodebuild -target -sdk` is used instead. An SDK build proves
# the source, the Info.plist, the entitlements, and framework availability for that
# platform. It proves nothing about running.
#
# One honest exception, printed on every run rather than buried here: on watchOS,
# `actool` refuses to compile an asset catalog without a watchsimulator runtime
# ("No available simulator runtimes for platform watchsimulator"), so the watchOS
# build excludes the catalog. Everything else about that target — the app code, the
# shared libraries, the complication extension, the Info.plist, the entitlements —
# is built exactly as it ships. The app icon for watchOS is wired in the catalog and
# is unverified here; `TODO.md` carries it.
#
# Prints BUILD_ALL_OK on success and nothing decisive otherwise, so the gate cannot
# pass on a partial run.

set -eu

cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/WakaBoard-build-all"
BUILDROOT="${TMPDIR:-/tmp}/WakaBoard-build-all-sdk"
COMMON="SWIFT_TREAT_WARNINGS_AS_ERRORS=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="

echo "==> Regenerating the Xcode project"
xcodegen generate --quiet

echo "==> Building macOS app and widget extension"
# shellcheck disable=SC2086
xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  $COMMON \
  -quiet

echo "==> Building iOS app and widget extension"
# shellcheck disable=SC2086
xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_iOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  $COMMON \
  -quiet

# Each entry is target:sdk:extra-settings:label. The extra-settings field is empty
# for everything except watchOS, which carries the asset-catalog exclusion.
for entry in \
  "WakaBoardApp_watchOS:watchos:EXCLUDED_SOURCE_FILE_NAMES=*.xcassets:watchOS app and complications (asset catalog excluded)" \
  "WakaBoardApp_tvOS:appletvos::tvOS app" \
  "WakaBoardApp_visionOS:xros::visionOS app and widget extension"
do
  target=$(echo "$entry" | cut -d: -f1)
  sdk=$(echo "$entry" | cut -d: -f2)
  extra=$(echo "$entry" | cut -d: -f3)
  label=$(echo "$entry" | cut -d: -f4)
  echo "==> Building $label"
  # shellcheck disable=SC2086
  xcodebuild build \
    -project WakaBoard.xcodeproj \
    -target "$target" \
    -sdk "$sdk" \
    ONLY_ACTIVE_ARCH=NO \
    CONFIGURATION_BUILD_DIR="$BUILDROOT/$target" \
    OBJROOT="$BUILDROOT/$target-obj" \
    SYMROOT="$BUILDROOT/$target-sym" \
    $extra \
    $COMMON \
    -quiet
done

echo "NOTE: watchOS was built without its asset catalog; actool needs a watchsimulator runtime that is not installed."
echo "BUILD_ALL_OK"
