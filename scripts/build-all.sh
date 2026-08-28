#!/bin/sh
# Builds every shipping target on both platforms, warnings treated as errors.
#
# `swift test` only covers the two library targets. This is what proves the app
# shells and widget extensions still compile — the part that actually ships and the
# part a package-only CI job silently skips.
#
# Prints BUILD_ALL_OK on success and nothing decisive otherwise, so the gate cannot
# pass on a partial run.

set -eu

cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/WakaBoard-build-all"
COMMON="SWIFT_TREAT_WARNINGS_AS_ERRORS=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -derivedDataPath $DERIVED"

echo "==> Regenerating the Xcode project"
xcodegen generate --quiet

echo "==> Building macOS app and widget extension"
# shellcheck disable=SC2086
xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_macOS \
  -destination 'platform=macOS' \
  $COMMON \
  -quiet

echo "==> Building iOS app and widget extension"
# shellcheck disable=SC2086
xcodebuild build \
  -project WakaBoard.xcodeproj \
  -scheme WakaBoardApp_iOS \
  -destination 'generic/platform=iOS Simulator' \
  $COMMON \
  -quiet

echo "BUILD_ALL_OK"
