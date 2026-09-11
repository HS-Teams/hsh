#!/usr/bin/env bash

set -u

source .envrc
[[ -n "${ORG}" ]] || { echo -e "\033[31mUnable to source '.enrvc'!\033[m"; exit 1; }

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M3_STATUS:-Todo}"
MILESTONE="${HSH_M3_MILESTONE:-}"
ASSIGNEE="${HSH_M3_ASSIGNEE:-}"
PRIORITY="${HSH_M3_PRIORITY:-}"
TYPE="${HSH_M3_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m3-cards.sh [--dry-run]

Create all M3 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M3_STATUS        Initial Project Status. Default: Todo
  HSH_M3_MILESTONE     Optional GitHub milestone.
  HSH_M3_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M3_PRIORITY      Optional Project Priority value.
  HSH_M3_TYPE          Optional Project Type value.

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

  printf '\rM3 card creation: [%s] %3d%% (%d/%d)' \
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
  "[M3] Implement typed ContextResult model with bounded retention" \
  "$(cat <<'EOF'
## Goal

Introduce the typed context model used for safe conversational follow-up without treating prior stdout or file content as instructions.

## Scope

- Define `ContextResult` schema and Rust types.
- Store typed target identities rather than raw conversational references.
- Include originating `job_id`.
- Include source `plan_hash` and result hash/reference.
- Add creation timestamp and TTL.
- Add hard size/count bounds.
- Default context TTL to 15 minutes unless configuration explicitly changes it.
- Keep context session-local in M3.

## Dependencies

- M2 authorization and execution-result model
- Versioned IPC/schema infrastructure

## Done when

- Context is represented by typed bounded records.
- Raw stdout/file bodies are not required to resolve ordinary references.
- Expired context cannot be used to authorize follow-up operations.

## Acceptance criteria

- Context records are typed, bounded, session-local and TTL-constrained.
- Each record can be traced to its originating job and plan/result identity.
EOF
)"

create_card \
  "[M3] Implement same-job reference resolver for conversational follow-ups" \
  "$(cat <<'EOF'
## Goal

Resolve references such as `them`, `it`, or `the third one` only inside a well-defined originating job scope.

## Scope

- Resolve references against typed `ContextResult` entries.
- Require an unambiguous originating `job_id`.
- Support deterministic ordinal references such as `the third one`.
- Do not implicitly bind pronouns across jobs.
- Reject ambiguous, missing or expired references.
- Never use free-form model text as the authoritative target set.
- Return typed resolved targets to the planning/policy flow.

## Dependencies

- Typed ContextResult model
- M2 policy/authorization path

## Done when

- Same-job references resolve deterministically.
- Cross-job pronouns fail closed unless the user explicitly identifies the other job/target.
- Ambiguous resolution never reaches execution.

## Acceptance criteria

- Destructive follow-up cannot infer a target set from unrelated jobs.
- Reference resolution is deterministic and auditable.
EOF
)"

create_card \
  "[M3] Revalidate process identities and prevent PID-reuse targeting" \
  "$(cat <<'EOF'
## Goal

Prevent conversational process follow-ups from acting on a different process that reused the same PID.

## Scope

- Store process identity beyond PID alone.
- Capture stable identity attributes available on the platform, including process start time where supported.
- Revalidate identity immediately before a destructive process action.
- Treat exited processes as stale.
- Treat PID reuse as a different target.
- Require fresh resolution when identity cannot be proven.

## Dependencies

- Typed ContextResult
- M2 ProcessOperationStep and process-control policy
- OS abstraction

## Done when

- A context reference to a terminated process cannot target a newly created process with the same PID.
- Stale process targets fail closed before authorization/execution.

## Acceptance criteria

- PID reuse cannot redirect an approved follow-up to a new process.
EOF
)"

create_card \
  "[M3] Revalidate filesystem targets and reject stale or replaced identities" \
  "$(cat <<'EOF'
## Goal

Prevent file-oriented follow-ups from operating on paths whose underlying object changed after the original result.

## Scope

- Store canonical target identity metadata appropriate to supported filesystems.
- Revalidate target existence and identity before destructive follow-up.
- Detect deleted/recreated targets where possible.
- Apply existing symlink and canonical-path policy rules.
- Treat ambiguous identity changes as stale.
- Require fresh resolution/confirmation after target change.

## Dependencies

- Typed ContextResult
- M2 FileOperationStep
- M2 filesystem/canonical-path policy

## Done when

- A deleted/recreated file cannot silently inherit approval from the prior object.
- Changed or ambiguous targets become stale and cannot execute under old context.

## Acceptance criteria

- Filesystem identity is revalidated immediately before context-derived mutation.
EOF
)"

create_card \
  "[M3] Implement context Data-Egress allowlist and prompt-injection boundary" \
  "$(cat <<'EOF'
## Goal

Ensure previous command output and file content remain data and cannot become trusted instructions in later provider prompts.

## Scope

- Export only allowlisted typed context metadata to AI providers.
- Deny raw stdout by default.
- Deny raw file body/content by default.
- Allow safe metadata such as canonical display path, size, type, exit status and bounded identifiers where policy permits.
- Mark external/output-derived text as untrusted data in prompt construction.
- Prevent prior output from altering system/policy instructions.
- Prevent provider requests to disable or bypass local policy.
- Keep egress decisions local and provider-independent.

## Dependencies

- Typed ContextResult
- Existing Data-Egress Gate
- Provider prompt builder

## Done when

- Context-enabled prompts do not automatically include raw prior stdout/file bodies.
- Output containing instruction-like text cannot change local policy or authorization behavior.
- Egress decisions are testable independently from the provider.

## Acceptance criteria

- Prior OS/file output is always treated as untrusted data.
- Provider context export is allowlist-based and deny-by-default.
EOF
)"

create_card \
  "[M3] Route every context-derived mutation through fresh policy and confirmation" \
  "$(cat <<'EOF'
## Goal

Guarantee that conversational follow-up never reuses an old authorization decision.

## Scope

For every context-derived state-changing action:

- resolve typed targets;
- revalidate target identity;
- build a fresh typed ExecutionPlan;
- recompute effective capabilities;
- evaluate current immutable policy/config snapshot;
- render a fresh confirmation challenge;
- issue a new AuthorizationArtifact;
- execute only through the canonical Bash/C executor.

Rules:

- Prior confirmation is not reusable.
- Prior AuthorizationArtifact is not reusable.
- Context cannot broaden the original target set implicitly.
- Changed plan/target/policy/config/session invalidates authorization.

## Dependencies

- M2 confirmation and AuthorizationArtifact
- Typed context resolver
- Target revalidation

## Done when

- `kill them`, delete-follow-up, and equivalent state-changing requests require a fresh authorization lifecycle.
- Context cannot bypass M2 safety gates.

## Acceptance criteria

- Every context-derived mutation is independently authorized for the exact current target set.
EOF
)"

create_card \
  "[M3] Implement stale-context, ambiguity, and context-lifecycle UX" \
  "$(cat <<'EOF'
## Goal

Make context failure states explicit to the user instead of silently guessing.

## Scope

Provide clear local diagnostics for:

- expired context;
- missing originating job;
- ambiguous pronoun/reference;
- stale PID;
- stale/replaced file;
- target count changed;
- cross-job reference attempt;
- target no longer exists.

Behavior:

- Fail closed.
- Explain why the reference cannot safely be resolved.
- Do not silently fall back to a broader target search.
- Allow the user to issue a fresh explicit query to rebuild context.

## Dependencies

- Reference resolver
- Target revalidation
- Context TTL/lifecycle

## Done when

- Every unsafe/ambiguous context state has deterministic user-facing behavior.
- No stale-context failure results in implicit execution against replacement targets.

## Acceptance criteria

- Ambiguous or stale conversational references never execute silently.
EOF
)"

create_card \
  "[M3] Add context security, stale-target, and prompt-injection adversarial tests" \
  "$(cat <<'EOF'
## Goal

Prove that bounded context does not weaken the M1/M2 execution and policy boundaries.

## Scope

Add automated tests for:

- TTL expiry;
- same-job resolution;
- cross-job pronoun rejection;
- ordinal references;
- missing target;
- changed target count;
- process exit;
- PID reuse;
- deleted/recreated files;
- symlink/path identity change;
- stale target immediately before mutation;
- raw stdout containing fake system instructions;
- filenames containing prompt-injection text;
- output asking the provider to disable policy;
- attempts to reuse an old AuthorizationArtifact;
- plan/target mutation after confirmation;
- provider context egress allowlist.

## Dependencies

- All M3 implementation cards

## Done when

- Adversarial tests fail closed.
- Regression tests demonstrate that context cannot bypass capability derivation, policy, confirmation or the canonical executor.
- Test fixtures run in CI or the canonical security/regression command.

## Acceptance criteria

- M3 is blocked if stale-target or prompt-injection tests fail.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
