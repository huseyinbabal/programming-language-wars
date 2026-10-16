#!/usr/bin/env bash
# Runs on the benchmark machine next to the stack. Every INTERVAL seconds it fetches main; when main moved,
# it rebuilds only the implementations whose folder changed and writes one Grafana annotation per new commit,
# so every line on the dashboard can be matched to the code that produced it.
# Only merged code on main is ever built; pull requests are not run here.
#   REPO_DIR=/opt/plw bash deploy/deployer.sh          (normally started by plw-deployer.service)
set -euo pipefail
REPO_DIR=${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
INTERVAL=${INTERVAL:-60}
GRAFANA=${GRAFANA:-http://127.0.0.1:3000/grafana}
cd "$REPO_DIR"
set -a; . stack/.env; set +a
REPO_URL=${REPO_URL:-$(git remote get-url origin 2>/dev/null | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##')}

compose() { docker compose -f stack/compose.yml --env-file stack/.env "$@"; }

annotate() { # text, tags as a JSON array
  local body
  body=$(python3 -c 'import json,sys,time; print(json.dumps({"time": int(time.time()*1000), "tags": json.loads(sys.argv[2]), "text": sys.argv[1]}))' "$1" "$2")
  curl -fsS -u "admin:$GF_ADMIN_PASSWORD" -H 'Content-Type: application/json' -X POST "$GRAFANA/api/annotations" -d "$body" >/dev/null \
    || echo "annotation failed: $1" >&2
}

deploy() { # old new
  local old=$1 new=$2 files impls=() tags rest
  files=$(git diff --name-only "$old" "$new")
  for dir in impls/*/; do
    name=$(basename "$dir")
    grep -q "^impls/$name/" <<<"$files" && impls+=("$name")
  done
  if [ ${#impls[@]} -gt 0 ]; then compose up -d --build "${impls[@]}"; fi
  rest=$(grep -v '^impls/' <<<"$files" || true)
  if grep -qE '^(stack|load)/' <<<"$rest"; then compose up -d --build; fi

  tags=$(printf '"%s",' deploy "${impls[@]}"); tags="[${tags%,}]"
  # one annotation per commit on main since the last deploy, oldest first
  git log --reverse --first-parent --format='%H%x09%s' "$old..$new" | while IFS=$'\t' read -r sha subject; do
    annotate "$subject · ${sha:0:7} · $REPO_URL/commit/$sha" "$tags"
  done
}

current=$(git rev-parse HEAD)
annotate "deployer started at ${current:0:7}" '["deploy"]'
while true; do
  if git fetch -q origin main; then
    target=$(git rev-parse origin/main)
    if [ "$target" != "$current" ]; then
      git merge -q --ff-only origin/main
      deploy "$current" "$target" && current=$target
    fi
  fi
  sleep "$INTERVAL"
done
