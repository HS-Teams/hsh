#!/usr/bin/env bash

set -u

source .envrc
[[ -n "${ORG}" ]] || { echo -e "\033[31mUnable to source '.enrvc'!\033[m"; exit 1; }

CARDS_BIN="${CARDS_BIN:-}"
STATUS="${HSH_M6_STATUS:-Todo}"
MILESTONE="${HSH_M6_MILESTONE:-}"
ASSIGNEE="${HSH_M6_ASSIGNEE:-}"
PRIORITY="${HSH_M6_PRIORITY:-}"
TYPE="${HSH_M6_TYPE:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  create-m6-cards.sh [--dry-run]

Create all M6 cards for hsh using the existing cards.sh/create-card.sh tooling.

Options:
  -d, --dry-run
      Validate/delegate without modifying GitHub.

  -h, --help
      Display this help message and exit.

Environment:
  CARDS_BIN            Path to cards.sh.
  HSH_M6_STATUS        Initial Project Status. Default: Todo
  HSH_M6_MILESTONE     Optional GitHub milestone.
  HSH_M6_ASSIGNEE      Optional assignee, e.g. @me.
  HSH_M6_PRIORITY      Optional Project Priority value.
  HSH_M6_TYPE          Optional Project Type value.

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

  printf '\rM6 card creation: [%s] %3d%% (%d/%d)' \
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
  "[M6] Run full Bash compatibility regression and document intentional deviations" \
  "$(cat <<'EOF'
## Goal

Establish the 1.0 Bash-compatibility baseline against the pinned/upstream GNU Bash fixtures.

## Scope

- Run the frozen M0 compatibility suite against the M6 release candidate.
- Expand coverage for startup, quoting, expansion, pipes, redirections, traps, job control, completion and non-interactive execution.
- Compare hsh behavior against the pinned GNU Bash baseline.
- Classify every deviation as:
  - bug;
  - intentional hsh extension;
  - unsupported/known limitation.
- Document intentional deviations.
- Block release on unexplained compatibility regressions.

## Dependencies

- M0 Bash baseline/smoke suite
- M1-M5 implementation complete

## Done when

- The compatibility matrix is reproducible.
- Every known deviation has an explicit disposition.
- Blocking Bash regressions are closed before 1.0.

## Acceptance criteria

- 1.0 compatibility status is documented and reproducible.
EOF
)"

create_card \
  "[M6] Promote Linux and macOS platform matrix to blocking support" \
  "$(cat <<'EOF'
## Goal

Promote the secondary M1 platform into the supported 1.0 platform matrix.

## Scope

- Make both Linux and macOS blocking release platforms.
- Define supported compiler/toolchain ranges.
- Validate Bash/C build and Rust agent build on both.
- Validate IPC/session lifecycle on both.
- Validate path, process, signal, TTY and job-control behavior.
- Document WSL support status and limitations.
- Document OS-adapter differences explicitly.

## Dependencies

- M0 primary/secondary platform decision
- M1-M5 platform abstractions

## Done when

- CI blocks release on Linux and macOS failures.
- Platform-specific limitations are documented.
- WSL has an explicit support classification.

## Acceptance criteria

- Linux and macOS are both release-blocking for 1.0.
EOF
)"

create_card \
  "[M6] Expand fuzzing and adversarial testing across IPC, plans, policy, and authorization" \
  "$(cat <<'EOF'
## Goal

Harden every untrusted-input boundary before 1.0.

## Scope

Expand fuzz/adversarial coverage for:

- IPC envelopes;
- JSON/schema decoding;
- ExecutionPlan parsing;
- typed step validation;
- capability derivation;
- cwd/env/target classification;
- policy inputs;
- ConfirmationChallenge/ConfirmRequest flow;
- AuthorizationArtifact parsing/verification;
- ContextResult parsing/resolution;
- provider normalized output;
- oversized/recursive/pathological inputs;
- malformed UTF-8/Unicode edge cases where applicable.

Requirements:

- Fail closed.
- Never create an OS process from malformed/unvalidated input.
- Preserve direct Bash usability after agent/parser failure.

## Dependencies

- M1-M5 security tests

## Done when

- Fuzz targets run automatically in the security pipeline.
- High-severity crashes/bypasses are closed before 1.0.

## Acceptance criteria

- No known parser/policy/authorization bypass remains open.
EOF
)"

create_card \
  "[M6] Complete threat model and security architecture review" \
  "$(cat <<'EOF'
## Goal

Perform a release-level threat-model review of the complete hsh architecture.

## Scope

Review at least:

- C/Rust IPC trust boundary;
- local peer/session authentication;
- provider prompt injection;
- output/file-content injection;
- capability derivation bypass;
- policy/config snapshot races;
- AuthorizationArtifact replay;
- stale target/TOCTOU behavior;
- symlink/path ambiguity;
- PID reuse;
- malicious repository hooks/scripts;
- network/privilege escalation;
- environment-based command behavior;
- local attacker processes under the same user;
- agent crash/restart behavior.

Track findings by severity and disposition.

## Dependencies

- M1-M5 architecture complete

## Done when

- Threat model is version-controlled.
- Critical/high findings are resolved or explicitly block release.
- Residual risks are documented.

## Acceptance criteria

- Security review sign-off exists for 1.0 RC.
EOF
)"

create_card \
  "[M6] Prove agent crash and restart isolation from Bash job-control state" \
  "$(cat <<'EOF'
## Goal

Prove that hsh-agent failure cannot corrupt the core shell session.

## Scope

Test agent failure during:

- idle shell;
- AI planning;
- provider timeout;
- confirmation wait;
- result streaming;
- context operations.

Validate:

- foreground process-group ownership;
- background jobs;
- terminal control;
- signals;
- shell prompt recovery;
- restart/session epoch handling;
- invalidation of pending authorization artifacts;
- direct Bash fallback.

## Dependencies

- Per-session agent lifecycle
- M2 authorization
- M3 context

## Done when

- Agent termination/restart does not corrupt Bash job-control state.
- Pending AI state fails closed.
- Direct Bash remains usable after recovery.

## Acceptance criteria

- Crash/restart isolation is a blocking 1.0 regression suite.
EOF
)"

create_card \
  "[M6] Finalize audit retention, redaction, access, and integrity controls" \
  "$(cat <<'EOF'
## Goal

Make audit behavior production-ready without turning audit storage into a secrets leak.

## Scope

Define and implement:

- retention policy;
- maximum size/rotation behavior;
- redaction rules;
- ownership/file permissions;
- which user/process may read logs;
- append/integrity strategy where practical;
- handling of natural-language prompts containing sensitive values;
- provider/config identifiers without credentials;
- plan/policy/authorization references;
- local execution results without unrestricted stdout/body capture.

Requirements:

- Audit does not authorize.
- Secrets must not be intentionally persisted.
- Failure to audit must follow an explicit policy for high-risk actions.

## Dependencies

- M2 authorization/audit
- M3 privacy/context
- M4 config/provider model

## Done when

- Audit lifecycle is documented and tested.
- Retention/redaction/integrity settings have safe defaults.

## Acceptance criteria

- 1.0 audit behavior is deterministic and privacy-aware.
EOF
)"

create_card \
  "[M6] Build reproducible release packaging and GPL/provenance compliance gate" \
  "$(cat <<'EOF'
## Goal

Produce distributable hsh 1.0 artifacts with reproducible packaging and complete provenance obligations.

## Scope

- Define release packaging for supported platforms.
- Produce reproducible artifacts where practical.
- Include required license notices.
- Include/offer corresponding source as required.
- Preserve GNU Bash provenance.
- Inventory third-party Rust/provider dependencies and licenses.
- Validate release metadata/versioning.
- Sign artifacts where the release process supports signing.
- Block publication if license/provenance checks fail.

## Dependencies

- M0 GPL/provenance checklist
- Platform matrix
- Final dependency set

## Done when

- Release artifacts can be produced from a clean tagged checkout.
- License/provenance checks are automated/documented.
- Distribution gate passes before publishing 1.0.

## Acceptance criteria

- No public 1.0 binary ships without passing the compliance gate.
EOF
)"

create_card \
  "[M6] Freeze v1 contracts, upstream merge policy, and complete 1.0 release-candidate soak" \
  "$(cat <<'EOF'
## Goal

Freeze the public 1.0 engineering baseline and prove release stability before tagging.

## Scope

- Freeze stable v1 IPC contract.
- Freeze stable v1 ExecutionPlan contract.
- Freeze provider adapter contract expected to remain compatible through 1.x where promised.
- Define schema/version compatibility rules.
- Define GNU Bash upstream update/merge policy.
- Define security response process.
- Define supported upgrade/migration behavior.
- Run release-candidate soak on supported platforms.
- Exercise direct Bash, explicit AI, mutation, context, multi-provider and opt-in NL routing paths.
- Close all release blockers before tag.

## Dependencies

- All M6 hardening cards

## Done when

- Stable v1 contracts are documented.
- Upstream/security maintenance policy is documented.
- RC soak completes without unresolved release blockers.
- Repository is ready for the `1.0.0` tag.

## Acceptance criteria

- M6 exit gate for hsh 1.0.0.
EOF
)"

printf '\nSummary: created=%d existing=%d failed=%d total=%d\n' \
  "$CREATED" "$EXISTING" "$FAILED" "$TOTAL"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

exit 0
