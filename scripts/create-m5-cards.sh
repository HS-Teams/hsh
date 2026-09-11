#!/usr/bin/env bash

set -u

source .envrc
[[ -n "${ORG}" ]] || { echo -e "\033[31mUnable to source '.enrvc'!\033[m"; exit 1; }

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M5_STATUS:-Todo}"
MILESTONE="${HSH_M5_MILESTONE:-}"
ASSIGNEE="${HSH_M5_ASSIGNEE:-}"
PRIORITY="${HSH_M5_PRIORITY:-}"
TYPE="${HSH_M5_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m5-cards.sh [--dry-run]

Create all M5 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M5_STATUS        Initial Project Status. Default: Todo
  HSH_M5_MILESTONE     Optional GitHub milestone.
  HSH_M5_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M5_PRIORITY      Optional Project Priority value.
  HSH_M5_TYPE          Optional Project Type value.

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

  printf '\rM5 card creation: [%s] %3d%% (%d/%d)' \
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
  "[M5] Implement opt-in automatic natural-language input routing" \
  "$(cat <<'EOF'
## Goal

Allow prefixless natural-language requests only when automatic routing is explicitly enabled.

## Scope

- Add an opt-in automatic NL routing mode.
- Keep routing disabled by default.
- Route ordinary valid Bash input directly to Bash.
- Route clear natural-language input to the existing AI planning path.
- Preserve the explicit `ai` command regardless of auto-routing state.
- Do not broaden capabilities, context scope, or provider privileges.

## Dependencies

- M1 explicit AI path
- M2 policy/authorization
- M3 bounded context
- M4 provider/config maturity

## Done when

- Prefixless natural-language input works only when enabled.
- Disabling auto-routing restores explicit-AI-only behavior.
- Routing decisions do not alter downstream security semantics.

## Acceptance criteria

- Automatic NL routing is opt-in.
- Bash remains the default execution language.
EOF
)"

create_card \
  "[M5] Implement Bash-first precedence and ambiguity-safe classifier" \
  "$(cat <<'EOF'
## Goal

Ensure valid Bash syntax always wins over automatic natural-language interpretation.

## Scope

- Classify input before invoking the provider path.
- Valid Bash syntax/direct commands take precedence.
- Treat ambiguous input conservatively.
- Never reinterpret a valid destructive shell command as natural language.
- Never execute ambiguous high-risk input automatically.
- Unknown-command fallback may route to AI only when enabled and visibly indicated.
- Keep classification local where practical.

## Dependencies

- Automatic NL routing
- Bash parser/direct-command path
- Existing policy gates

## Done when

- Valid Bash commands are not diverted to AI.
- Ambiguous high-risk input fails closed or requires explicit user intent.
- Routing is deterministic enough to test.

## Acceptance criteria

- Bash precedence is preserved.
- Ambiguous high-risk input never auto-executes.
EOF
)"

create_card \
  "[M5] Add explicit force modes for AI and direct-shell execution" \
  "$(cat <<'EOF'
## Goal

Give users deterministic escape hatches from automatic routing.

## Scope

Provide explicit modes for:

- force AI routing;
- force direct Bash routing.

Requirements:

- Existing `ai` remains an explicit AI entry point.
- Add/retain a direct-shell force mode that bypasses auto-routing classification.
- Force modes must not bypass policy, capability derivation, confirmation, or authorization.
- Help/documentation must clearly describe precedence.

## Dependencies

- Automatic NL routing
- Existing `ai` command

## Done when

- Users can explicitly choose AI or direct shell behavior for ambiguous input.
- Force modes are independent from automatic classifier heuristics.

## Acceptance criteria

- Explicit routing controls always override automatic classification.
EOF
)"

create_card \
  "[M5] Implement multilingual natural-language routing without language-specific execution semantics" \
  "$(cat <<'EOF'
## Goal

Support natural-language requests in multiple human languages while preserving one execution/security model.

## Scope

- Accept multilingual natural-language input.
- Keep language detection/routing separate from execution semantics.
- Do not create language-specific command executors.
- Normalize requests into the same provider/plan pipeline.
- Preserve typed plans, capability derivation, policy, context, confirmation and authorization unchanged.
- Add fixtures for at least English and Portuguese, plus representative additional languages.

## Dependencies

- Automatic NL routing
- Provider/config maturity

## Done when

- Equivalent intents in different languages reach the same typed planning path.
- Language choice cannot broaden capabilities or bypass safety gates.

## Acceptance criteria

- Multilingual routing changes interpretation only, not authorization semantics.
EOF
)"

create_card \
  "[M5] Implement routing diagnostics and visible unknown-command fallback" \
  "$(cat <<'EOF'
## Goal

Make automatic routing observable so users can understand why input went to Bash, AI, or rejection.

## Scope

Expose local diagnostics for classifications such as:

- direct Bash;
- explicit AI;
- automatic NL;
- unknown-command fallback;
- forced direct shell;
- rejected ambiguity.

Requirements:

- Unknown-command fallback must visibly indicate rerouting before planning.
- Diagnostics must not expose secrets/provider credentials.
- Provide an optional verbose/debug mode for classifier reasoning signals.
- Keep normal output concise.

## Dependencies

- Automatic routing classifier
- Force modes

## Done when

- Users can tell which route was selected.
- Unknown commands are not silently transformed into AI actions.

## Acceptance criteria

- Every automatic reroute is observable.
EOF
)"

create_card \
  "[M5] Enforce context and policy boundaries during automatic routing" \
  "$(cat <<'EOF'
## Goal

Ensure prefixless NL routing cannot weaken M2/M3 safety guarantees.

## Scope

- Automatic routing cannot broaden ContextResult job scope.
- Pronouns/follow-ups still use M3 same-job resolution rules.
- Destructive context-derived actions still require fresh target revalidation.
- Effective capabilities are recomputed after routing.
- State-changing actions still require confirmation and AuthorizationArtifact.
- Provider choice/routing cannot bypass Data-Egress Gate.
- Auto-routing must never reuse prior authorization.

## Dependencies

- M2 controlled mutation
- M3 bounded context
- M4 providers/egress
- Automatic NL routing

## Done when

- Prefixless input follows exactly the same downstream authorization path as explicit `ai`.
- Routing cannot implicitly widen context or target sets.

## Acceptance criteria

- Automatic routing introduces no alternate security path.
EOF
)"

create_card \
  "[M5] Implement compatibility mode and auto-routing configuration UX" \
  "$(cat <<'EOF'
## Goal

Allow users and scripts to disable hsh automatic interpretation and behave predictably like Bash.

## Scope

- Add a compatibility mode that disables automatic NL routing.
- Keep direct Bash semantics as close to pinned Bash behavior as intended.
- Define TOML configuration for auto-routing enable/disable.
- Support session-level override where appropriate.
- Document startup behavior and precedence.
- Ensure non-interactive/script mode does not unexpectedly auto-route unknown input.

## Dependencies

- M4 configuration model
- Automatic NL routing

## Done when

- Compatibility mode reliably disables ambiguous hsh extensions.
- Scripts do not become AI-routed accidentally.
- Configuration precedence is deterministic.

## Acceptance criteria

- Users can opt out completely without uninstalling provider support.
EOF
)"

create_card \
  "[M5] Add routing ambiguity, multilingual, precedence, and security regression tests" \
  "$(cat <<'EOF'
## Goal

Prove automatic routing does not regress Bash compatibility or bypass established safety boundaries.

## Scope

Add automated tests for:

- valid Bash precedence;
- explicit `ai`;
- force-direct mode;
- force-AI mode;
- unknown command fallback;
- auto-routing disabled;
- compatibility mode;
- ambiguous shell-like natural language;
- destructive Bash commands;
- ambiguous high-risk input;
- multilingual equivalents;
- context pronouns under auto-routing;
- cross-job context rejection;
- state-changing confirmation/authorization;
- provider outage during routing;
- Data-Egress Gate parity;
- non-interactive/script behavior.

## Dependencies

- All M5 implementation cards

## Done when

- Routing regression/adversarial tests run in CI.
- No prefixless route can bypass M1-M4 policy/context/authorization invariants.
- Bash compatibility fixtures remain green.

## Acceptance criteria

- M5 is blocked if routing changes execution authority or safety semantics.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
