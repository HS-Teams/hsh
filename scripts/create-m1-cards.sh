#!/usr/bin/env bash

set -u

[[ -f .envrc ]] && source .envrc

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M1_STATUS:-Todo}"
MILESTONE="${HSH_M1_MILESTONE:-}"
ASSIGNEE="${HSH_M1_ASSIGNEE:-}"
PRIORITY="${HSH_M1_PRIORITY:-}"
TYPE="${HSH_M1_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m1-cards.sh [--dry-run]

Create all M1 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M1_STATUS        Initial Project Status. Default: Todo
  HSH_M1_MILESTONE     Optional GitHub milestone.
  HSH_M1_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M1_PRIORITY      Optional Project Priority value.
  HSH_M1_TYPE          Optional Project Type value.

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

TOTAL=9
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

  printf '\rM1 card creation: [%s] %3d%% (%d/%d)' \
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
  "[M1] Fork and rebrand Bash as hsh with reproducible primary-platform build" \
  "$(cat <<'EOF'
## Goal

Produce the first reproducible hsh build from the pinned M0 GNU Bash baseline while preserving ordinary Bash behavior.

## Scope

- Apply the hsh product/branding changes required for the executable and version output.
- Keep ordinary Bash input on the direct Bash path.
- Preserve the pinned upstream provenance and remote strategy.
- Document the exact primary-platform build procedure.
- Do not add automatic natural-language routing.

## Dependencies

- M0 Bash baseline
- M0 primary platform decision
- M0 repository layout

## Done when

- A clean clone builds hsh reproducibly on the selected primary platform.
- The secondary platform status is recorded as smoke/non-blocking.
- Direct shell startup and normal Bash execution still work.

## Acceptance criteria

- M1-AC-01
- Supports M1-AC-02
- Supports M1-AC-03
EOF
)"

create_card \
  "[M1] Implement frozen Bash compatibility smoke and direct-path regression harness" \
  "$(cat <<'EOF'
## Goal

Turn the M0 compatibility definition into an executable regression gate for hsh.

## Scope

- Run the frozen M0 Bash smoke suite against hsh.
- Add direct-command regression fixtures around hsh-specific startup/branding changes.
- Include `hsh -c "echo ok"` in the blocking primary-platform gate.
- Verify ordinary Bash commands do not contact or start the AI provider path.
- Produce clear failure output suitable for CI.

## Dependencies

- M0 frozen Bash smoke suite
- M1 hsh build/rebrand

## Done when

- The frozen suite runs unchanged against hsh.
- `hsh -c "echo ok"` succeeds.
- Direct Bash commands demonstrate zero AI-provider dependency.

## Acceptance criteria

- M1-AC-02
- M1-AC-03
EOF
)"

create_card \
  "[M1] Implement IPC v1 C bridge and per-session hsh-agent lifecycle" \
  "$(cat <<'EOF'
## Goal

Implement the versioned C-to-Rust bridge and the M1 per-interactive-session agent lifecycle.

## Scope

- Implement IPC v1 codecs in the C/Bash side.
- Start one hsh-agent child per interactive hsh session.
- Bind the child to a session/restart epoch.
- Implement clean shutdown and bounded restart behavior.
- Preserve direct Bash usability when the agent crashes or is unavailable.
- Reject malformed or unsupported protocol versions before execution.
- No shared user daemon.

## Dependencies

- M0 Protocol v1
- M0 agent lifecycle decision
- M1 hsh build

## Done when

- C and Rust exchange versioned request/response envelopes.
- Unsupported versions fail closed.
- Agent failure cannot make the direct Bash path unusable.

## Acceptance criteria

- M1-AC-05
- M1-AC-11
- Supports M1-AC-04
EOF
)"

create_card \
  "[M1] Implement hsh-agent skeleton and strict ExecutionPlan v1 parser" \
  "$(cat <<'EOF'
## Goal

Create the Rust agent core that accepts only schema-valid, versioned plans.

## Scope

- Implement the hsh-agent process skeleton.
- Implement strict ExecutionPlan v1 parsing.
- Reject unknown `schema_version`.
- Reject malformed JSON.
- Reject unknown step types.
- Enforce field size/count bounds.
- Do not execute processes from Rust.
- Do not support raw shell-script, `eval`, or `bash -c` plan semantics.

## Dependencies

- M0 ExecutionPlan v1 contract
- M1 IPC bridge

## Done when

- Valid v1 plans parse into typed internal structures.
- Invalid/unknown plans are rejected before authorization or process creation.
- The Rust agent contains no alternate OS execution path for AI plans.

## Acceptance criteria

- M1-AC-05
- M1-AC-08
- M1-AC-09
- Supports M1-AC-12
EOF
)"

create_card \
  "[M1] Implement AIProvider contract, initial provider adapter, and deterministic mock" \
  "$(cat <<'EOF'
## Goal

Connect the M1 explicit AI path to one real provider while keeping tests deterministic and provider-independent.

## Scope

- Implement the common AIProvider interface.
- Implement the provider selected in M0.
- Implement a deterministic mock provider for CI.
- Request structured ExecutionPlan v1 output.
- Treat provider risk/capability labels as untrusted hints.
- Keep live-provider tests opt-in.
- Keep credentials outside source control.
- Provider failure must not crash the shell.

## Dependencies

- M0 initial provider decision
- M1 hsh-agent skeleton
- M1 ExecutionPlan v1 parser

## Done when

- `ai "..."` can obtain a versioned typed plan from the configured provider.
- CI can exercise the same flow with no network or provider credentials.
- Provider outages/errors leave direct Bash usable.

## Acceptance criteria

- M1-AC-04
- M1-AC-11
- Supports M1-AC-06
EOF
)"

create_card \
  "[M1] Implement read-only ExecutionPlan v1 step subset" \
  "$(cat <<'EOF'
## Goal

Define and implement the M1 typed plan subset required for useful read-only system inspection.

## Scope

Implement the M1-safe subset of:

- ProcessStep
- PipelineStep
- Glob
- Redirection
- InputRef

Rules:

- No unrestricted shell text.
- No `eval`.
- No `bash -c`.
- No shell-script step.
- Schema may know future mutation-oriented step types, but M1 must reject/deny them as unsupported.
- Plan semantics must preserve argument boundaries and avoid command-string reconstruction.

## Dependencies

- M0 ExecutionPlan v1
- M1 strict plan parser

## Done when

- Representative read-only plans can express inspection commands and pipelines without shell-string evaluation.
- Mutation/network/privilege-oriented steps cannot become executable in M1.

## Acceptance criteria

- M1-AC-04
- M1-AC-07
- M1-AC-09
EOF
)"

create_card \
  "[M1] Implement Policy Engine v1 with local capability derivation and default-deny" \
  "$(cat <<'EOF'
## Goal

Ship a real, versioned M1 policy boundary rather than an executor-side allowlist hack.

## Scope

- Implement Policy Engine v1 as a named Rust component.
- Recompute effective capabilities locally from typed steps.
- Include program, args, cwd, env and targets in derivation as applicable to the M1 subset.
- Ignore provider capability/risk labels for authorization.
- Default-deny unsupported capability combinations.
- Allow only the explicitly defined M1 read-only capability set.
- Deny write/delete/process-control mutation/network mutation/privilege operations.
- Keep policy decisions auditable/inspectable without granting the audit layer authority.

## Dependencies

- M1 typed plan subset
- M1 strict plan parser

## Done when

- Provider hints cannot authorize a plan.
- Read-only supported plans may be allowed.
- Unsupported or state-changing plans are denied before process creation.

## Acceptance criteria

- M1-AC-06
- M1-AC-07
EOF
)"

create_card \
  "[M1] Implement canonical Bash executor adapter and bounded result capture" \
  "$(cat <<'EOF'
## Goal

Execute authorized M1 plans only through the Bash Compatibility Core and return bounded typed results.

## Scope

- Define the C-side adapter from approved typed plan semantics to Bash process/pipeline/redirection machinery.
- Bash Compatibility Core remains the sole OS executor.
- Rust must never call an alternate direct execution path for AI plans.
- Enforce output, time and subprocess bounds.
- Capture exit status plus bounded stdout/stderr.
- Return typed execution results over IPC.
- Produce local presentation from approved metadata.
- Do not resend raw stdout/file bodies to the provider by default.

## Dependencies

- M1 IPC bridge
- M1 typed plan subset
- M1 Policy Engine v1

## Done when

- An approved read-only plan executes through the canonical Bash/C path.
- Rust cannot bypass the policy/executor boundary.
- Bounded local results are available without a second provider call over raw output.

## Acceptance criteria

- M1-AC-08
- M1-AC-10
- Supports M1-AC-07
EOF
)"

create_card \
  "[M1] Add adversarial, fuzz, failure-path tests and MVP engineering documentation" \
  "$(cat <<'EOF'
## Goal

Make protocol/parser/policy failure behavior a blocking M1 property instead of postponing it to public hardening.

## Scope

Add automated coverage for:

- malformed JSON;
- unsupported schema/protocol versions;
- oversized fields;
- unknown step types;
- command-smuggling strings;
- attempts to inject `eval`, `bash -c`, or unrestricted shell text;
- fake provider capability/risk labels;
- attempts to bypass Policy Engine v1;
- agent crash/restart;
- provider timeout/failure;
- bounded stdout/stderr behavior;
- direct Bash fallback.

Add/update engineering documentation for:

- M1 build/run flow;
- explicit `ai` usage;
- provider/mock configuration;
- known M1 limitations;
- security boundary and out-of-scope capabilities.

## Dependencies

- All M1 implementation work packages

## Done when

- Adversarial/parser tests execute in CI or the primary regression command.
- Known malformed/bypass inputs fail closed.
- A contributor can build and exercise the M1 vertical slice from documentation.

## Acceptance criteria

- M1-AC-11
- M1-AC-12
- Regression coverage for M1-AC-05 through M1-AC-10
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
