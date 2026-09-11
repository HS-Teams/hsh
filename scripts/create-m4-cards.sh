#!/usr/bin/env bash

set -u

source .envrc
[[ -n "${ORG}" ]] || { echo -e "\033[31mUnable to source '.enrvc'!\033[m"; exit 1; }

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M4_STATUS:-Todo}"
MILESTONE="${HSH_M4_MILESTONE:-}"
ASSIGNEE="${HSH_M4_ASSIGNEE:-}"
PRIORITY="${HSH_M4_PRIORITY:-}"
TYPE="${HSH_M4_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m4-cards.sh [--dry-run]

Create all M4 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M4_STATUS        Initial Project Status. Default: Todo
  HSH_M4_MILESTONE     Optional GitHub milestone.
  HSH_M4_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M4_PRIORITY      Optional Project Priority value.
  HSH_M4_TYPE          Optional Project Type value.

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

  printf '\rM4 card creation: [%s] %3d%% (%d/%d)' \
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
  "[M4] Stabilize AIProvider contract and provider conformance rules" \
  "$(cat <<'EOF'
## Goal

Freeze a provider-neutral contract so hsh can integrate different LLM backends without leaking provider-specific behavior into policy or execution.

## Scope

- Stabilize the `AIProvider` interface.
- Define provider request/response normalization.
- Define structured-output requirements.
- Define provider error taxonomy.
- Define timeout/cancellation semantics.
- Define unsupported-model behavior.
- Keep provider-specific SDK/types behind adapters.
- Ensure providers cannot authorize or execute plans.

## Dependencies

- M1 AIProvider contract
- M1/M2 protocol and plan schemas

## Done when

- All provider adapters implement the same normalized contract.
- Policy/execution code contains no provider-specific branches.
- Provider output remains untrusted input.

## Acceptance criteria

- Provider adapters are interchangeable at the hsh-agent boundary.
EOF
)"

create_card \
  "[M4] Implement production-ready remote AI provider adapter" \
  "$(cat <<'EOF'
## Goal

Provide at least one production-ready remote LLM provider behind the stable AIProvider contract.

## Scope

- Implement one supported remote provider.
- Support configured model selection.
- Support structured ExecutionPlan generation.
- Apply request timeout/cancellation.
- Normalize provider errors.
- Keep credentials out of logs and source control.
- Route all outbound data through the Data-Egress Gate.
- Do not let provider metadata influence local authorization.

## Dependencies

- Stable AIProvider contract
- Data-Egress Gate
- Config/credential model

## Done when

- A remote model can complete the supported planning flow.
- Provider outage or timeout does not crash hsh.
- No execution authority exists in the adapter.

## Acceptance criteria

- At least one remote provider passes the provider conformance suite.
EOF
)"

create_card \
  "[M4] Implement production-ready local AI provider adapter" \
  "$(cat <<'EOF'
## Goal

Provide at least one local-model integration using the same AIProvider contract as remote providers.

## Scope

- Implement one local provider adapter, e.g. Ollama-compatible.
- Support configurable endpoint/model.
- Normalize structured plan output.
- Apply timeout/cancellation.
- Handle unavailable local service cleanly.
- Preserve the same validation, capability derivation, policy and authorization path as remote providers.
- Do not create a special local-provider execution bypass.

## Dependencies

- Stable AIProvider contract
- Config model
- Existing plan validation/policy pipeline

## Done when

- A local provider can generate supported typed plans.
- Local and remote providers use the same downstream security path.
- Local provider failure leaves direct Bash usable.

## Acceptance criteria

- At least one local provider passes the provider conformance suite.
EOF
)"

create_card \
  "[M4] Implement canonical TOML configuration precedence and credential separation" \
  "$(cat <<'EOF'
## Goal

Define one predictable configuration model for shell, agent, policy and providers.

## Scope

Define precedence for:

- built-in defaults;
- system configuration;
- user configuration;
- project/repository configuration;
- environment variables;
- explicit CLI/session overrides where supported.

Requirements:

- Use TOML for hsh configuration.
- Separate provider credentials from normal configuration where practical.
- Never print secrets in diagnostics.
- Validate unknown/invalid keys deterministically.
- Keep configuration loading provider-neutral.
- Document which settings are security-sensitive.

## Dependencies

- M0/M1 config baseline
- Provider contract
- Policy Engine

## Done when

- Effective configuration is deterministic and inspectable.
- Credentials are not persisted in ordinary project config by default.
- Config precedence is documented and tested.

## Acceptance criteria

- All supported providers and policy components consume the same resolved configuration model.
EOF
)"

create_card \
  "[M4] Apply Data-Egress Gate uniformly across all providers" \
  "$(cat <<'EOF'
## Goal

Guarantee that adding providers cannot weaken hsh privacy and prompt-injection boundaries.

## Scope

- Apply the same Data-Egress Gate before every provider request.
- Keep raw stdout denied by default.
- Keep file bodies denied by default.
- Keep environment/secrets denied by default.
- Permit only explicitly classified/allowlisted metadata.
- Redact known credential patterns where applicable.
- Mark external/output-derived text as untrusted data.
- Prevent provider adapters from bypassing egress policy.

## Dependencies

- M1/M3 Data-Egress Gate
- Stable provider contract
- Config/credential classification

## Done when

- Remote and local adapters receive only approved payloads.
- Provider-specific code cannot silently add raw local context.
- Egress decisions are independently testable.

## Acceptance criteria

- All providers pass identical privacy/egress policy tests.
EOF
)"

create_card \
  "[M4] Implement immutable config/policy snapshots and safe reload semantics" \
  "$(cat <<'EOF'
## Goal

Prevent runtime configuration reloads from changing the meaning of an already approved plan.

## Scope

- Resolve config/policy into immutable snapshots.
- Bind authorization to snapshot identity/hash.
- Reload applies only to subsequent planning/authorization.
- Existing approved execution uses the exact snapshot referenced by its AuthorizationArtifact.
- Reject execution if required snapshot identity cannot be verified.
- Define behavior for provider/config reload while requests are in flight.

## Dependencies

- M2 AuthorizationArtifact
- Canonical config model
- Policy Engine

## Done when

- Reload cannot turn a prior deny into an allow for an already authorized plan.
- Snapshot identity participates in authorization validation.
- Concurrent reload behavior is deterministic.

## Acceptance criteria

- Policy/config reload cannot mutate authorization semantics mid-plan.
EOF
)"

create_card \
  "[M4] Isolate provider failures, timeouts, retries, and cancellation" \
  "$(cat <<'EOF'
## Goal

Make provider instability non-fatal to the shell and predictable to users.

## Scope

- Add bounded request timeouts.
- Support cancellation where provider APIs permit.
- Define retry policy for safe/idempotent planning requests.
- Do not retry mutating execution; providers only plan.
- Normalize rate-limit, auth, timeout, network and model errors.
- Ensure provider crash/error cannot corrupt shell job control.
- Keep direct Bash usable when every provider is unavailable.
- Avoid infinite retry loops.

## Dependencies

- Provider contract
- Per-session agent lifecycle
- Config model

## Done when

- Provider failures produce bounded local errors.
- hsh remains usable as Bash after provider failure.
- Retry/cancel behavior is documented and tested.

## Acceptance criteria

- Provider failure isolation passes automated tests.
EOF
)"

create_card \
  "[M4] Add provider conformance, configuration, egress, and failure-isolation tests" \
  "$(cat <<'EOF'
## Goal

Make multi-provider behavior a tested contract rather than adapter-specific convention.

## Scope

Add automated coverage for:

- remote provider conformance;
- local provider conformance;
- deterministic mock provider;
- structured-output normalization;
- unsupported model;
- invalid credentials;
- timeout;
- cancellation;
- rate limiting;
- provider unavailable;
- malformed provider output;
- configuration precedence;
- unknown/invalid config keys;
- credential redaction;
- Data-Egress Gate parity;
- policy/config snapshot reload;
- provider failure with direct Bash fallback.

## Dependencies

- All M4 implementation cards

## Done when

- Every supported provider passes the same conformance suite.
- Security/privacy tests are provider-independent.
- Config and reload semantics are covered by regression tests.

## Acceptance criteria

- M4 is blocked if any provider bypasses normalized planning, egress, policy, or failure-isolation rules.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
