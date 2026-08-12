#!/bin/bash
# fixtures.sh must be deterministic: two runs produce identical trees and
# identical commit SHAs. Without pinned dates, diff screenshots churn every sweep.
set -uo pipefail
cd "$(dirname "$0")"

root=$(./fixtures.sh) || { echo "FAIL: fixtures.sh exited nonzero"; exit 1; }
[ -d "$root/field-notes" ] || { echo "FAIL: no field-notes"; exit 1; }
[ -d "$root/field-guide/.git" ] || { echo "FAIL: no git repo"; exit 1; }

sum1=$(find "$root/field-notes" -type f -exec shasum {} \; | sed "s|$root||" | sort | shasum)
sha1=$(git -C "$root/field-guide" log --format=%H | shasum)
status1=$(git -C "$root/field-guide" status --porcelain | sort | shasum)

root=$(./fixtures.sh)
sum2=$(find "$root/field-notes" -type f -exec shasum {} \; | sed "s|$root||" | sort | shasum)
sha2=$(git -C "$root/field-guide" log --format=%H | shasum)
status2=$(git -C "$root/field-guide" status --porcelain | sort | shasum)

[ "$sum1" = "$sum2" ] || { echo "FAIL: file content not deterministic"; exit 1; }
[ "$sha1" = "$sha2" ] || { echo "FAIL: commit SHAs not deterministic — pin GIT_*_DATE"; exit 1; }
[ "$status1" = "$status2" ] || { echo "FAIL: dirty state not deterministic"; exit 1; }

git -C "$root/field-guide" status --porcelain | grep -q '^ M' || { echo "FAIL: no modified file"; exit 1; }
git -C "$root/field-guide" status --porcelain | grep -q '^A ' || { echo "FAIL: no staged add"; exit 1; }
git -C "$root/field-guide" status --porcelain | grep -q '^??' || { echo "FAIL: no untracked file"; exit 1; }

echo "PASS"
