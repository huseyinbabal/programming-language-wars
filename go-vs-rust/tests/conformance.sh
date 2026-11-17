#!/usr/bin/env bash
# Checks an implementation against SPEC.md. Start it with CAPACITY=128 first.
#   bash tests/conformance.sh http://127.0.0.1:8000
set -uo pipefail
BASE=${1:-http://127.0.0.1:8000}
fail=0
check() { # name expected actual
  if [ "$2" == "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: expected $2, got $3"; fail=1; fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "health" 200 "$(code "$BASE/health")"
check "health body" ok "$(curl -s "$BASE/health")"
check "missing key is 404" 404 "$(code "$BASE/kv/nope")"
check "put is 204" 204 "$(code -X PUT --data-binary 'hello' "$BASE/kv/a1")"
check "get returns the value" hello "$(curl -s "$BASE/kv/a1")"
check "get content type" application/octet-stream "$(curl -s -o /dev/null -w '%{content_type}' "$BASE/kv/a1")"
check "put replaces" 204 "$(code -X PUT --data-binary 'world' "$BASE/kv/a1")"
check "replaced value" world "$(curl -s "$BASE/kv/a1")"
check "1024 bytes accepted" 204 "$(head -c 1024 /dev/zero | tr '\0' x | code -X PUT --data-binary @- "$BASE/kv/big")"
check "1025 bytes is 413" 413 "$(head -c 1025 /dev/zero | tr '\0' x | code -X PUT --data-binary @- "$BASE/kv/big2")"
check "empty body is 400" 400 "$(code -X PUT --data-binary '' "$BASE/kv/empty")"
check "bad key is 400" 400 "$(code "$BASE/kv/bad.key")"
check "65 char key is 400" 400 "$(code "$BASE/kv/$(head -c 65 /dev/zero | tr '\0' k)")"

# Fill far past CAPACITY=128 and check the entry count never goes above it.
# Sequential on purpose, so k1 is the oldest key and k1000 the newest.
for i in $(seq 1 1000); do printf 'url = "%s/kv/k%d"\nrequest = "PUT"\ndata = "v"\noutput = "/dev/null"\nnext\n' "$BASE" "$i"; done | sed '$d' > /tmp/plw-fill.cfg
curl -s -K /tmp/plw-fill.cfg
m=$(curl -s "$BASE/metrics")
entries=$(echo "$m" | awk '$1=="cache_entries"{print $2}')
evictions=$(echo "$m" | awk '$1=="cache_evictions_total"{print $2}')
check "entries capped at 128" 1 "$([ "${entries:-999}" -le 128 ] && echo 1 || echo 0)"
check "evictions counted" 1 "$([ "${evictions:-0}" -gt 0 ] && echo 1 || echo 0)"
check "recent key kept" v "$(curl -s "$BASE/kv/k1000")"
check "oldest key evicted" 404 "$(code "$BASE/kv/k1")"
for s in cache_entries cache_hits_total cache_misses_total cache_evictions_total; do
  check "metric $s" 1 "$(echo "$m" | grep -c "^$s ")"
done
exit $fail
