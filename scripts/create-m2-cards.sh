#!/usr/bin/env bash

set -u

source .envrc
[[ -n "${ORG}" ]] || { echo -e "\033[31mUnable to source '.enrvc'!\033[m"; exit 1; }

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M2_STATUS:-Todo}"
MILESTONE="${HSH_M2_MILESTONE:-}"
ASSIGNEE="${HSH_M2_ASSIGNEE:-}"
PRIORITY="${HSH_M2_PRIORITY:-}"
TYPE="${HSH_M2_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m2-cards.sh [--dry-run]

Create all M2 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M2_STATUS        Initial Project Status. Default: Todo
  HSH_M2_MILESTONE     Optional GitHub milestone.
  HSH_M2_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M2_PRIORITY      Optional Project Priority value.
  HSH_M2_TYPE          Optional Project Type value.

Project/repository configuration is inherited by cards.sh/create-card.sh:
  GH_CARD_REPO
  GH_CARD_PROJECT
  GH_CARD_PROJECT_OWNER
EOF
}

resolve_cards_bin() {
  local script_dir

  if [ -n "$CARDS_BIN" ]; then
    if [ -x "$CARDS_BIN" ]; then
      return 0
    fi

    printf '[ERROR] CARDS_BIN is not executable: %s\n' "$CARDS_BIN" >&2
    exit 3
  fi

  script_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

  if [ -x "$script_dir/cards.sh" ]; then
    CARDS_BIN="$script_dir/cards.sh"
    return 0
  fi

  if command -v cards.sh >/dev/null 2>&1; then
    CARDS_BIN="$(command -v cards.sh)"
    return 0
  fi

  printf '[ERROR] cards.sh was not found.\n' >&2
  exit 3
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
      printf '[ERROR] Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

resolve_cards_bin

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

  printf '\rM2 card creation: [%s] %3d%% (%d/%d)' \
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
    create
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

  "$CARDS_BIN" "${args[@]}"
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
      printf '[ERROR] Failed (%d): %s\n' "$rc" "$title" >&2
      ;;
  esac

  PROCESSED=$((PROCESSED + 1))
  progress "$PROCESSED"
}

progress 0

create_card \
  "[M2] Define typed mutation step semantics" \
  "$(cat <<'EOF'
## Goal

Introduce typed state-changing plan operations without falling back to unrestricted shell text.

## Scope

Define and implement semantics for:

- FileOperationStep
- ProcessOperationStep
- PrivilegeStep
- NetworkStep where needed by the schema

Requirements:

- No free-form selection expression.
- No `eval`.
- No unrestricted `bash -c`.
- No raw shell-script step.
- Every target must be explicit or resolved into a deterministic typed target set before authorization.
- Future schema types may exist, but unsupported types remain default-deny.

## Dependencies

- M1 ExecutionPlan v1
- M1 strict plan parser
- M1 Policy Engine v1

## Done when

- Write/delete/process-control/privilege operations have typed schemas.
- Unsupported mutation semantics are rejected before authorization.
- Mutation does not require reconstructing arbitrary shell source.

## Acceptance criteria

Supports M2-AC-01 through M2-AC-05.
EOF
)"

create_card \
  "[M2] Expand capability derivation for mutation, cwd, env, targets, and host profile" \
  "$(cat <<'EOF'
## Goal

Ensure effective capabilities are recomputed locally from the full meaning of a mutating plan.

## Scope

Derive capabilities from:

- typed step kind;
- program and arguments;
- canonical targets;
- cwd;
- env_delta;
- redirections;
- host profile;
- filesystem profile;
- network effects;
- privilege requirements.

Rules:

- Provider capability/risk labels remain hints only.
- `cwd` and `env_delta` may increase risk/capabilities.
- Dangerous environment changes must not bypass policy.
- Special filesystems and privileged paths must be recognizable by policy.

## Dependencies

- M1 local capability derivation
- M2 typed mutation steps
- OS/path abstraction

## Done when

- Equivalent dangerous effects derive equivalent capabilities regardless of provider labels.
- Environment or cwd manipulation cannot hide state-changing behavior.

## Acceptance criteria

- M2-AC-02
- Supports M2-AC-04
EOF
)"

create_card \
  "[M2] Implement multi-phase IPC for plan, confirm, authorize, execute, and cancel" \
  "$(cat <<'EOF'
## Goal

Replace single-shot plan/execution behavior with an explicit authorization state machine.

## Scope

Implement versioned IPC messages for:

- Plan response
- ConfirmationChallenge
- ConfirmRequest
- CancelRequest
- AuthorizationArtifact
- ExecuteRequest
- streamed/bounded output
- final ExecutionResult

Rules:

- Planning and execution are separate phases.
- Cancel must terminate the pending authorization flow.
- Unsupported message ordering fails closed.
- Agent restart/session epoch invalidates pending authorization state.

## Dependencies

- M1 IPC v1
- M2 typed mutation steps
- M2 policy evaluation

## Done when

- Mutating plans cannot proceed from planning directly to execution.
- Confirm/cancel behavior is represented explicitly in the protocol.

## Acceptance criteria

- M2-AC-03
- Supports M2-AC-01
EOF
)"

create_card \
  "[M2] Implement TTY confirmation UX with safe defaults" \
  "$(cat <<'EOF'
## Goal

Provide a deterministic user confirmation contract for state-changing AI-mediated actions.

## Scope

- Render confirmation in the C frontend/TTY.
- Show the exact action/targets being authorized.
- Use `[y/N]`.
- Pressing Enter cancels.
- Default timeout: 60 seconds.
- Timeout cancels.
- Non-interactive AI mutation is denied unless a future explicit policy mode is designed.
- Confirmation is not implemented as terminal I/O inside the Rust policy engine.

## Dependencies

- M2 multi-phase IPC
- M2 typed target model

## Done when

- The user can approve or cancel from the shell frontend.
- Enter and timeout both cancel safely.
- Non-interactive mutation fails closed.

## Acceptance criteria

- M2-AC-03
EOF
)"

create_card \
  "[M2] Implement AuthorizationArtifact bound to plan, session, policy, config, and expiry" \
  "$(cat <<'EOF'
## Goal

Make execution authorization cryptographically/structurally bound to the exact approved operation.

## Scope

AuthorizationArtifact must bind at least:

- plan_hash;
- session identifier;
- restart/session epoch;
- immutable policy snapshot identity;
- immutable config snapshot identity;
- uid/gid where applicable;
- cwd;
- derived capabilities;
- authorized target identity/set;
- issued-at time;
- expiry.

Rules:

- Any plan mutation invalidates authorization.
- Any relevant cwd/env/risk-input mutation invalidates authorization.
- Policy/config reload applies to subsequent planning/authorization only.
- Artifact from another session/epoch is invalid.
- Read-only and mutating execution paths use the same canonical verification model.

## Dependencies

- M1 plan hashing
- M2 multi-phase IPC
- M2 capability derivation

## Done when

- Bash/C refuses execution without a valid artifact for the exact approved plan.
- Changed snapshots or execution context invalidate prior approval.

## Acceptance criteria

- M2-AC-01
- M2-AC-02
EOF
)"

create_card \
  "[M2] Implement pre-execution target canonicalization and mutation revalidation" \
  "$(cat <<'EOF'
## Goal

Prevent TOCTOU, symlink, path-scope, and stale-target errors between approval and mutation.

## Scope

- Canonicalize filesystem targets according to policy.
- Detect/reject unsafe symlink ambiguity.
- Revalidate target identity immediately before mutation.
- Re-check scope boundaries after canonicalization.
- Revalidate process targets before process-control operations.
- Recognize special filesystems where supported (`/proc`, mounts, bind mounts, NFS, etc.).
- Deny when safe identity/scope cannot be established.

## Dependencies

- M2 typed target model
- M2 AuthorizationArtifact
- OS/path abstraction

## Done when

- Approval cannot be silently redirected to a different target.
- Ambiguous target identity fails closed.

## Acceptance criteria

- M2-AC-01
- M2-AC-02
EOF
)"

create_card \
  "[M2] Enforce mutation execution limits, audit decisions, and canonical Bash executor path" \
  "$(cat <<'EOF'
## Goal

Ensure state-changing plans remain bounded, auditable, and executable only through the canonical Bash/C core.

## Scope

- Bash Compatibility Core remains the sole OS executor.
- Rust cannot spawn an alternate execution path for AI plans.
- Apply timeout limits.
- Apply stdout/stderr bounds.
- Apply subprocess/process-count limits.
- Record local policy decision and authorization metadata.
- Audit must never itself grant authority.
- Keep network and privilege capabilities default-deny unless explicitly implemented and policy-enabled.

## Dependencies

- M2 AuthorizationArtifact
- M2 Policy Engine expansion
- M1 canonical Bash executor

## Done when

- Every state-changing operation reaches OS execution only after artifact verification.
- Limits are applied consistently to mutation paths.
- Network/privilege remain denied unless intentionally enabled.

## Acceptance criteria

- M2-AC-04
- M2-AC-05
EOF
)"

create_card \
  "[M2] Add mutation authorization, cancellation, TOCTOU, and bypass adversarial tests" \
  "$(cat <<'EOF'
## Goal

Prove that M2 state-changing execution cannot bypass policy, confirmation, artifact binding, or target validation.

## Scope

Add tests for:

- mutation without AuthorizationArtifact;
- wrong plan_hash;
- expired artifact;
- wrong session/restart epoch;
- policy/config snapshot change;
- cwd/env change after approval;
- altered target set;
- confirmation cancel;
- confirmation timeout;
- Enter default-cancel;
- non-interactive mutation rejection;
- symlink retargeting;
- file replacement between approval and execution;
- process identity change;
- unsupported network/privilege operation;
- Rust direct-exec bypass attempt;
- output/process/time limit enforcement.

## Dependencies

- All M2 implementation cards

## Done when

- Security/adversarial tests fail closed.
- No tested mutation path can bypass confirmation, policy, artifact verification, or the canonical executor.

## Acceptance criteria

Regression coverage for M2-AC-01 through M2-AC-05.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
