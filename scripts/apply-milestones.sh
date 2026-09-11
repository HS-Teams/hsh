#!/usr/bin/env bash

set -u

[[ -f .envrc ]] && source .envrc

for milestone in M0 M1 M2 M3 M4 M5 M6; do
  gh issue list \
    --repo "$REPO" \
    --state all \
    --limit 500 \
    --json number,title \
    --jq ".[] | select(.title | startswith(\"[$milestone]\")) | .number" |
  while read -r issue; do
    [ -z "$issue" ] && continue

    echo "Assigning $milestone to issue #$issue"

    gh issue edit "$issue" \
      --repo "$REPO" \
      --milestone "$milestone"
  done
done
