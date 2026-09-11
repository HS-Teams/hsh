#!/usr/bin/env bash

set -e
set -u
set -o pipefail

[[ -f .envrc ]] && source .envrc
[[ -n "${REPO:-}" ]] || { echo -e "\033[31mUnable to source '.envrc'!\033[m"; exit 1; }

assign_milestone() {
  local milestone="$1"

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
}

create_milestone() {
  local title="$1"
  local description="$2"

  if gh api "repos/$REPO/milestones?state=all&per_page=100" \
    --jq ".[] | select(.title == \"$title\") | .title" \
    | grep -qx "$title"; then
    printf '\033[033mMilestone %s already exists!\n\033[m' "$title"
    return 0
  fi

  gh api \
    --method POST \
    "repos/$REPO/milestones" \
    -f title="$title" \
    -f state="open" \
    -f description="$description"
  
  assign_milestone "$title"
}

create_milestone \
  "M0" \
  "MVP - Foundation & Provenance"

create_milestone \
  "M1" \
  "MVP - Explicit AI / Read-only execution with Policy Engine v1"

create_milestone \
  "M2" \
  "Controlled Mutation - Typed mutation, confirmation and authorization artifacts"

create_milestone \
  "M3" \
  "Bounded Context - Typed conversational context, target revalidation and stale-target protection"

create_milestone \
  "M4" \
  "Provider & Configuration Maturity - Multi-provider support, configuration and data-egress controls"

create_milestone \
  "M5" \
  "Opt-in Automatic Natural-Language Routing - Bash-first multilingual routing"

create_milestone \
  "M6" \
  "Hardening & 1.0 - Security, platform matrix, packaging, compatibility and release"

echo ''

gh api "repos/$REPO/milestones" \
  --jq '.[] | "\u001b[34m\(.number)\u001b[0m\t\u001b[34m\(.title)\u001b[0m\t\(.description)"'
