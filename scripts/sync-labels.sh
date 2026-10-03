#!/usr/bin/env bash
# Create/update the workflow labels from labels.txt in the given repos.
# Usage: scripts/sync-labels.sh byfae-dev/project-fae byfae-dev/brain
# ponytail: create/update only, never deletes extra labels; add pruning if label drift becomes a problem.
set -euo pipefail
labels="$(dirname "$0")/../labels.txt"
for repo in "$@"; do
  grep -v '^#' "$labels" | while IFS='|' read -r name color desc; do
    gh label create "$name" -R "$repo" -c "$color" -d "$desc" --force >/dev/null
    echo "$repo: $name"
  done
done
