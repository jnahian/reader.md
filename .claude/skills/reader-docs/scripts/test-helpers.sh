#!/bin/bash
# Helper contract tests. Run with Reader.md NOT running.
set -uo pipefail
cd "$(dirname "$0")"

swift winid.swift NoSuchAppXYZ >/dev/null 2>&1
[ $? -eq 1 ] || { echo "FAIL: winid should exit 1 when no window matches"; exit 1; }

open -a "$(git rev-parse --show-toplevel)/build/Reader.md.app"
sleep 4
id=$(swift winid.swift Reader) || { echo "FAIL: winid exited nonzero with app running"; exit 1; }
[[ "$id" =~ ^[0-9]+$ ]] || { echo "FAIL: winid printed non-numeric: $id"; exit 1; }

swift cursor.swift 10 10 || { echo "FAIL: cursor exited nonzero"; exit 1; }

osascript -e 'tell application "Reader.md" to quit'
echo "PASS"
