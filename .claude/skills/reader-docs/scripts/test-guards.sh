#!/bin/bash
# The guards must fail loudly. A harness that silently captures the wrong thing
# is worse than one that stops.
set -uo pipefail
cd "$(dirname "$0")"

cat > /tmp/bad-domain.json <<'EOF'
{ "page": "t", "domain": "com.nahian.reader-md", "shots": [] }
EOF
out=$(./capture.sh /tmp/bad-domain.json 2>&1)
[ $? -ne 0 ] || { echo "FAIL: ran against the real preference domain"; exit 1; }
echo "$out" | grep -q "refusing" || { echo "FAIL: no explanation, got: $out"; exit 1; }

out=$(./capture.sh /tmp/does-not-exist.json 2>&1)
[ $? -ne 0 ] || { echo "FAIL: accepted a missing manifest"; exit 1; }

cat > /tmp/geom.json <<'EOF'
{ "page": "_test", "window": { "width": 1400, "height": 900 }, "shots": [] }
EOF
./capture.sh /tmp/geom.json >/dev/null 2>&1 || { echo "FAIL: empty manifest should succeed"; exit 1; }

echo "PASS"
