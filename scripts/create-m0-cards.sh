#!/usr/bin/env bash

set -u

[[ -f .envrc ]] && source .envrc

CREATE_CARD_BIN="${CREATE_CARD_BIN:-}"
STATUS="${HSH_M0_STATUS:-Backlog}"
MILESTONE="${HSH_M0_MILESTONE:-}"
ASSIGNEE="${HSH_M0_ASSIGNEE:-}"
PRIORITY="${HSH_M0_PRIORITY:-}"
TYPE="${HSH_M0_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m0-cards.sh [--dry-run]

Environment:
  CREATE_CARD_BIN       Optional path to create-card.sh.
  HSH_M0_STATUS         Project status. Default: Backlog
  HSH_M0_MILESTONE      Optional GitHub milestone name.
  HSH_M0_ASSIGNEE       Optional assignee, e.g. @me.
  HSH_M0_PRIORITY       Optional Project Priority value.
  HSH_M0_TYPE           Optional Project Type value.

Repository/project selection is inherited by create-card.sh through:
  GH_CARD_REPO
  GH_CARD_PROJECT
  GH_CARD_PROJECT_OWNER
  GH_CARD_DEFAULT_STATUS
  GH_CARD_DEFAULT_PRIORITY
  GH_CARD_DEFAULT_TYPE
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$CREATE_CARD_BIN" ]; then
  script_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

  if [ -x "$script_dir/create-card.sh" ]; then
    CREATE_CARD_BIN="$script_dir/create-card.sh"
  fi
fi

if [ ! -x "$CREATE_CARD_BIN" ]; then
  if command -v create-card.sh >/dev/null 2>&1; then
    CREATE_CARD_BIN="$(command -v create-card.sh)"
  else
    printf 'create-card.sh not found or not executable: %s\n' "$CREATE_CARD_BIN" >&2
    exit 3
  fi
fi

TOTAL=8
PROCESSED=0
CREATED=0
EXISTING=0
FAILED=0
BAR_WIDTH=32

progress() {
  local processed="$1"
  local percent filled empty bar i

  percent=$((processed * 100 / TOTAL))
  filled=$((percent * BAR_WIDTH / 100))
  empty=$((BAR_WIDTH - filled))
  bar=""

  i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}#"
    i=$((i + 1))
  done

  i=0
  while [ "$i" -lt "$empty" ]; do
    bar="${bar}-"
    i=$((i + 1))
  done

  printf '\rM0 card creation: [%s] %3d%% (%d/%d)' \
    "$bar" "$percent" "$processed" "$TOTAL"

  if [ "$processed" -eq "$TOTAL" ]; then
    printf '\n'
  fi
}

create_card() {
  local title="$1"
  local body="$2"
  local rc
  local args

  args=(
    --title "$title"
    --body "$body"
    --status "$STATUS"
  )

  if [ -n "$MILESTONE" ]; then
    args+=(--milestone "$MILESTONE")
  fi

  if [ -n "$ASSIGNEE" ]; then
    args+=(--assignee "$ASSIGNEE")
  fi

  if [ -n "$PRIORITY" ]; then
    args+=(--priority "$PRIORITY")
  fi

  if [ -n "$TYPE" ]; then
    args+=(--type "$TYPE")
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    args+=(--dry-run)
  fi

  printf '\nCreating: %s\n' "$title"

  "$CREATE_CARD_BIN" "${args[@]}"
  rc=$?

  case "$rc" in
    0)
      CREATED=$((CREATED + 1))
      ;;
    12)
      EXISTING=$((EXISTING + 1))
      printf 'Already exists: %s\n' "$title" >&2
      ;;
    *)
      FAILED=$((FAILED + 1))
      printf 'Failed (%d): %s\n' "$rc" "$title" >&2
      ;;
  esac

  PROCESSED=$((PROCESSED + 1))
  progress "$PROCESSED"
}

progress 0

create_card \
  "[M0] Pin GNU Bash 5.3.x baseline and upstream provenance" \
  "$(cat <<'EOF'
## Goal

Establish the exact GNU Bash baseline from which hsh is derived.

## Scope

- Select an exact GNU Bash 5.3.x upstream tag/commit.
- Record the immutable commit SHA.
- Record the canonical GNU upstream repository.
- Define the upstream remote/fetch/merge policy for future Bash updates.
- Document build prerequisites for a clean checkout.
- Preserve required GNU/GPL provenance and notices.

## Done when

- A clean clone of the pinned baseline builds using documented prerequisites.
- The exact upstream tag/commit and SHA are committed to project documentation.
- The upstream remote policy is documented and reproducible.

## Acceptance criteria

- M0-AC-01

## References

Roadmap M0: Bash baseline / Foundation & Provenance.
EOF
)"

create_card \
  "[M0] Select primary M1 platform and secondary smoke platform" \
  "$(cat <<'EOF'
## Goal

Freeze the platform support order for M1 so build acceptance is objective.

## Scope

- Select exactly one blocking M1 platform: Linux or macOS.
- Mark the other platform as smoke/non-blocking until M6.
- Record supported compiler/toolchain assumptions for both.
- Record WSL as a secondary target, not an M1 blocking target.

## Done when

- The primary M1 platform is explicitly recorded.
- The secondary smoke platform is explicitly recorded.
- CI/release documentation uses the same platform roles.

## Acceptance criteria

- M0-AC-02

## References

Roadmap M0: Primary M1 platform.
EOF
)"

create_card \
  "[M0] Freeze Bash compatibility smoke suite" \
  "$(cat <<'EOF'
## Goal

Create the objective compatibility gate used by M1 and later milestones.

## Scope

- Select and name a stable subset of upstream Bash tests.
- Add hsh-specific direct-command fixtures.
- Include shell startup, `hsh -c`, quoting, pipes, redirections, environment, traps and job-control smoke coverage where applicable.
- Provide one documented command to run the suite.
- Version-control the suite definition and expected results.

## Done when

- The frozen suite is committed and runnable.
- A clean pinned Bash baseline passes the selected upstream subset.
- The suite can later be run against hsh without changing its definition.

## Acceptance criteria

- M0-AC-03

## References

Roadmap M0: Bash smoke suite.
EOF
)"

create_card \
  "[M0] Define hsh-agent lifecycle and direct-Bash fallback" \
  "$(cat <<'EOF'
## Goal

Freeze the process ownership model before implementing the C-to-Rust bridge.

## Scope

- One hsh-agent child per interactive hsh session.
- The Bash/C parent owns agent start, stop and restart.
- Define a restart/session epoch.
- No shared user daemon in M1-M5.
- Agent/provider failure must leave the direct Bash path usable.
- Define behavior for shell exit, agent crash and agent restart.
- Define ownership boundaries for foreground/background shell jobs.

## Done when

- The lifecycle is documented as a normative M0 decision.
- There is exactly one owner for agent process creation and teardown.
- Direct Bash operation is explicitly independent from agent availability.

## Acceptance criteria

Supports the M1 agent/fallback acceptance criteria and the canonical execution boundary.

## References

Roadmap M0: Agent lifecycle.
EOF
)"

create_card \
  "[M0] Select initial AI provider and deterministic CI mock" \
  "$(cat <<'EOF'
## Goal

Choose the single provider integration used by the M1 vertical slice without coupling CI to an external service.

## Scope

- Select one M1 AIProvider adapter.
- Record model/provider assumptions required for structured plan generation.
- Define a deterministic mock provider for CI.
- Keep live-provider integration tests opt-in.
- Define credential/configuration requirements without committing secrets.
- Provider output must remain untrusted input to local validation/policy.

## Done when

- The M1 provider is explicitly selected.
- The deterministic CI mock contract is documented.
- CI can exercise provider-facing code without network access or credentials.

## Acceptance criteria

Supports M1 provider and deterministic-test acceptance criteria.

## References

Roadmap M0: Initial provider.
EOF
)"

create_card \
  "[M0] Freeze IPC v1 and ExecutionPlan v1 contracts" \
  "$(cat <<'EOF'
## Goal

Freeze the versioned C-to-Rust protocol before executable AI functionality lands.

## Scope

- Set IPC protocol_version to `1.0`.
- Set ExecutionPlan schema_version to `1.0`.
- Define request/response envelope kinds.
- Define plan/result/error envelopes required by M1.
- Define error taxonomy.
- Define version-negotiation behavior.
- Define the canonical plan hash algorithm.
- Define malformed/unknown-version rejection behavior.
- Reserve confirm/cancel/authorization message evolution without creating an alternate execution path.

## Done when

- Versioned protocol/schema definitions are committed.
- Both sides reject unsupported versions deterministically.
- The plan hash algorithm is documented and testable.
- Executable AI code does not land before these contracts exist.

## Acceptance criteria

- M0-AC-04

## References

Roadmap M0: Protocol v1.
EOF
)"

create_card \
  "[M0] Establish canonical repository layout and ownership boundaries" \
  "$(cat <<'EOF'
## Goal

Make the repository structure match the SRS/UML component ownership model before M1 implementation.

## Scope

Establish one canonical tree for:

- Bash/C compatibility core and builtins.
- C-to-Rust bridge.
- hsh-agent and Rust crates.
- Protocol/schema definitions.
- Policy, provider, privacy/egress, context, authorization and audit components as applicable.
- Tests, including adversarial/protocol tests.

Architecture constraints:

- Bash Compatibility Core is the only OS process/pipeline/job-control executor.
- No Rust crate may become a parallel OS executor for AI plans.
- Rust may plan, validate, derive capabilities, apply policy and issue authorization artifacts.
- Repository names/paths must match the canonical SRS/UML baseline.

## Done when

- The canonical tree is documented and committed.
- Component ownership is unambiguous.
- No Rust OS-executor crate/module exists.

## Acceptance criteria

- M0-AC-05

## References

SRS/UML repository ownership baseline.
EOF
)"

create_card \
  "[M0] Complete GPL/provenance and distribution checklist" \
  "$(cat <<'EOF'
## Goal

Establish the licensing/provenance gate before any public hsh binary is distributed.

## Scope

- Record Bash/GNU source provenance.
- Preserve applicable GPL notices and copyright information.
- Document corresponding-source obligations for distributed binaries.
- Document third-party dependencies and their licenses.
- Define the pre-distribution license/provenance checklist.
- Record that process separation is not assumed to magically resolve derivative-work questions.
- Require legal review before commercial/public binary distribution where appropriate.

## Done when

- A version-controlled license/provenance checklist exists.
- Required notices/source obligations are documented.
- Public binary distribution is blocked until the checklist is satisfied.

## Acceptance criteria

- M0-AC-06

## References

Roadmap M0: GPL/distribution.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
