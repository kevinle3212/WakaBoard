#!/bin/sh
# Renders every screen across widths, Dynamic Type sizes, and appearances, and fails
# if one overflows its width or comes back blank.
#
# The blank check is not paranoia. `ImageRenderer` lays a `ScrollView` out at full
# height and draws none of its content, so the first version of this check produced
# fifty blank white images and passed every geometric assertion in the suite.
#
# macOS only, and it does not replace looking at the result: it replaces the part of
# looking that a person was never actually going to do fifty times. The contact
# sheets it writes are what a person looks at.
#
# Prints SNAPSHOTS_OK on success and nothing decisive otherwise.

set -eu

cd "$(dirname "$0")/.."

OUT="docs/screenshots"
LOG="${TMPDIR:-/tmp}/wakaboard-snapshots.log"

# Delete first, so a stale render from a previous run cannot satisfy the counts below.
# The first version of this script did exactly that: its filter matched no tests, the
# suite reported "0 tests in 0 suites passed", and the check went green on images left
# behind by an earlier run.
rm -f "$OUT"/*.png

echo "==> Rendering every screen"
swift test --filter Snapshot 2>&1 | tee "$LOG"

if ! command grep -qE "Test run with [1-9][0-9]* tests? in [1-9][0-9]* suites? passed" "$LOG"; then
  echo "FAIL: the snapshot suite did not run, or did not pass" >&2
  exit 1
fi

# The suite asserts its own output, but a rendering step that silently wrote nothing
# would otherwise pass this script.
count=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
if [ "$count" -lt 40 ]; then
  echo "FAIL: expected at least 40 renders in $OUT, found $count" >&2
  exit 1
fi

sheets=$(find "$OUT" -name 'contact-*.png' | wc -l | tr -d ' ')
if [ "$sheets" -lt 4 ]; then
  echo "FAIL: expected a contact sheet per screen, found $sheets" >&2
  exit 1
fi

echo "==> $count renders and $sheets contact sheets in $OUT"
echo "SNAPSHOTS_OK"
