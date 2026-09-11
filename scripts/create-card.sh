#!/usr/bin/env bash

# Script Name: create-card.sh
# Purpose: Create a GitHub Issue, add it to a GitHub Project, and configure card fields.
# Created Date: Sep 11, 2026
# Author: ChatGPT
# Required Packages: bash 3.2+, gh, git
# Powered by: [HomeSetup](https://github.com/yorevs/homesetup)
# GPT: [HHS-Script-Generator](https://chatgpt.com/g/g-ra0RVB9Jo-homesetup-script-generator)
#
# +------------------------------------------------------------------------------+
# | AIs CAN MAKE MISTAKES.                                                       |
# | For your safety, verify important information and code before executing it.  |
# |                                                                              |
# | This program comes with NO WARRANTY, to the extent permitted by law.         |
# +------------------------------------------------------------------------------+

set -e
set -u
set -o pipefail

[[ -f .envrc ]] && source .envrc

SCRIPT_NAME="create-card.sh"

# https://semver.org/; major.minor.patch
VERSION="0.0.1"

USAGE='Usage:
  create-card.sh --title <text> [OPTIONS]

Create a GitHub Issue, add it to a GitHub Project, and configure the
Status, Priority, and Type Project fields.

Options:
  -n, --allow-duplicate
      Allow creation when an open Issue already has the exact title.

  -a, --assignee <user>
      Assign the Issue to a GitHub user. Accepts @me or a username.

  -b, --body <text>
      Issue body. Default: empty.

  -d, --dry-run
      Validate configuration but do not modify GitHub.

  -h, --help
      Display this help message and exit.

  -q, --json
      Emit only JSON on stdout. Logs and errors remain on stderr.

  -l, --label <label>
      Add a label to the Issue. May be specified multiple times.

  -m, --milestone <milestone>
      Assign a milestone to the Issue.

  -p, --priority <value>
      Set the Project Priority field.

  -j, --project <number>
      GitHub Project number.

  -o, --project-owner <owner>
      Project owner. Accepts username, organization, or @me.

  -r, --repo <owner/repository>
      GitHub repository. If omitted, use GH_CARD_REPO or the current
      Git repository as resolved by gh repo view.

  -s, --status <value>
      Set the Project Status field. Default: Backlog.

  -t, --title <text>
      Issue title. Required.

  -y, --type <value>
      Set the Project Type field.

  -v, --version
      Print version information and exit.

Environment:
  GH_CARD_REPO
  GH_CARD_PROJECT
  GH_CARD_PROJECT_OWNER
  GH_CARD_DEFAULT_STATUS
  GH_CARD_DEFAULT_PRIORITY
  GH_CARD_DEFAULT_TYPE

Precedence:
  CLI option > environment variable > built-in default.

Exit codes:
   0  Success
   1  Generic error
   2  Invalid arguments
   3  Missing dependency
   4  Authentication error
   5  Repository not found
   6  Project not found or inaccessible
   7  Error creating Issue
   8  Error adding Issue to Project
   9  Project field does not exist
  10  Invalid Project field value
  11  Error updating Project card
  12  Duplicate open Issue

Examples:
  create-card.sh \
    --title "Implement command parser"

  create-card.sh \
    --title "Implement command parser" \
    --body "Implement the initial command parser." \
    --type "Feature" \
    --priority "High" \
    --status "Backlog" \
    --label "parser" \
    --label "backend" \
    --assignee "@me" \
    --milestone "v0.1.0"'

TITLE=""
BODY=""
TYPE="${GH_CARD_DEFAULT_TYPE-}"
PRIORITY="${GH_CARD_DEFAULT_PRIORITY-}"
STATUS="${GH_CARD_DEFAULT_STATUS-}"
REPOSITORY="${GH_CARD_REPO-}"
PROJECT_NUMBER="${GH_CARD_PROJECT-}"
PROJECT_OWNER="${GH_CARD_PROJECT_OWNER-}"

DRY_RUN=0
JSON_OUTPUT=0
ALLOW_DUPLICATE=0

LABELS=()

PROJECT_ID=""
PROJECT_TITLE=""
PROJECT_FIELDS_CACHE=""

STATUS_FIELD_ID=""
STATUS_OPTION_ID=""
PRIORITY_FIELD_ID=""
PRIORITY_OPTION_ID=""
TYPE_FIELD_ID=""
TYPE_OPTION_ID=""

ISSUE_URL=""
ISSUE_NUMBER=""
ITEM_ID=""

RED=""
GREEN=""
YELLOW=""
BLUE=""
RESET=""

export GH_PROMPT_DISABLED=1

# eval is intentionally not used because dynamically evaluating shell input is
# unsafe and unnecessary for this script.

# @purpose: Initialize terminal colors when stderr is attached to a terminal.
init_colors() {
    if [[ -t 2 && -z "${NO_COLOR-}" ]]; then
        RED=$'\033[31m'
        GREEN=$'\033[32m'
        YELLOW=$'\033[33m'
        BLUE=$'\033[34m'
        RESET=$'\033[m'
    fi
}

# @purpose: Display script usage documentation.
usage() {
    printf '%s\n' "${USAGE}"
}

# @purpose: Display script version.
version() {
    printf '%s %s\n' "${SCRIPT_NAME}" "${VERSION}"
}

# @purpose: Write an informational log message to stderr.
# @param $1..$N [Req]: Message components.
log_info() {
    printf '%b[INFO]%b %s\n' "${BLUE}" "${RESET}" "$*" >&2
}

# @purpose: Write a warning log message to stderr.
# @param $1..$N [Req]: Message components.
log_warn() {
    printf '%b[WARN]%b %s\n' "${YELLOW}" "${RESET}" "$*" >&2
}

# @purpose: Write an error log message to stderr.
# @param $1..$N [Req]: Message components.
log_error() {
    printf '%b[ERROR]%b %s\n' "${RED}" "${RESET}" "$*" >&2
}

# @purpose: Print an error and terminate with a specific exit code.
# @param $1 [Req]: Exit code.
# @param $2..$N [Req]: Error message components.
die() {
    local exit_code

    exit_code=$1
    shift

    log_error "$*"
    exit "${exit_code}"
}

# @purpose: Handle an interrupt or abort signal gracefully.
# @param $1 [Req]: Signal name.
cleanup() {
    local signal_name

    signal_name=$1

    log_warn "Interrupted by ${signal_name}."
    exit 1
}

trap 'cleanup "SIGINT"' INT
trap 'cleanup "SIGABRT"' ABRT

# @purpose: Verify that the running Bash version is 3.2 or newer.
require_bash() {
    if ((BASH_VERSINFO[0] < 3)) ||
        ((BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2)); then
        die 3 "Bash 3.2 or newer is required."
    fi
}

# @purpose: Verify that GitHub CLI is installed.
require_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        log_error "Required command 'gh' was not found."
        printf 'Install GitHub CLI from: https://cli.github.com/\n' >&2
        exit 3
    fi
}

# @purpose: Verify that Git is installed.
require_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "Required command 'git' was not found."
        printf 'On macOS, install the Xcode Command Line Tools with: xcode-select --install\n' >&2
        exit 3
    fi
}

# @purpose: Verify all required local dependencies.
check_dependencies() {
    require_bash
    require_gh
    require_git
}

# @purpose: Verify that GitHub CLI has a valid authenticated session.
check_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI authentication is not valid."
        printf 'Authenticate with: gh auth login\n' >&2
        exit 4
    fi
}

# @purpose: Parse CLI arguments using long-option normalization and getopts.
# @param $1..$N [Opt]: Script command-line arguments.
parse_args() {
    local -a normalized
    local short_option
    local option

    normalized=()
    short_option=""
    option=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allow-duplicate)
                normalized+=("-n")
                shift
                ;;
            --assignee|--body|--label|--milestone|--priority|--project|--project-owner|--repo|--status|--title|--type)
                if [[ $# -lt 2 ]]; then
                    die 2 "Option '$1' requires a value."
                fi

                case "$1" in
                    --assignee) short_option="-a" ;;
                    --body) short_option="-b" ;;
                    --label) short_option="-l" ;;
                    --milestone) short_option="-m" ;;
                    --priority) short_option="-p" ;;
                    --project) short_option="-j" ;;
                    --project-owner) short_option="-o" ;;
                    --repo) short_option="-r" ;;
                    --status) short_option="-s" ;;
                    --title) short_option="-t" ;;
                    --type) short_option="-y" ;;
                esac

                normalized+=("${short_option}" "$2")
                shift 2
                ;;
            --assignee=*)
                normalized+=("-a" "${1#*=}")
                shift
                ;;
            --body=*)
                normalized+=("-b" "${1#*=}")
                shift
                ;;
            --dry-run)
                normalized+=("-d")
                shift
                ;;
            --help)
                normalized+=("-h")
                shift
                ;;
            --json)
                normalized+=("-q")
                shift
                ;;
            --label=*)
                normalized+=("-l" "${1#*=}")
                shift
                ;;
            --milestone=*)
                normalized+=("-m" "${1#*=}")
                shift
                ;;
            --priority=*)
                normalized+=("-p" "${1#*=}")
                shift
                ;;
            --project=*)
                normalized+=("-j" "${1#*=}")
                shift
                ;;
            --project-owner=*)
                normalized+=("-o" "${1#*=}")
                shift
                ;;
            --repo=*)
                normalized+=("-r" "${1#*=}")
                shift
                ;;
            --status=*)
                normalized+=("-s" "${1#*=}")
                shift
                ;;
            --title=*)
                normalized+=("-t" "${1#*=}")
                shift
                ;;
            --type=*)
                normalized+=("-y" "${1#*=}")
                shift
                ;;
            --version)
                normalized+=("-v")
                shift
                ;;
            --)
                normalized+=("--")
                shift

                while [[ $# -gt 0 ]]; do
                    normalized+=("$1")
                    shift
                done
                ;;
            --*)
                die 2 "Unknown option: $1"
                ;;
            *)
                normalized+=("$1")
                shift
                ;;
        esac
    done

    set -- "${normalized[@]}"
    OPTIND=1

    while getopts ":a:b:dhj:l:m:no:p:qr:s:t:vy:" option; do
        case "${option}" in
            a)
                [[ -n "${OPTARG}" ]] || die 2 "--assignee cannot be empty."
                ASSIGNEE="${OPTARG}"
                ;;
            b)
                BODY="${OPTARG}"
                ;;
            d)
                DRY_RUN=1
                ;;
            h)
                usage
                exit 0
                ;;
            j)
                [[ -n "${OPTARG}" ]] || die 2 "--project cannot be empty."
                PROJECT_NUMBER="${OPTARG}"
                ;;
            l)
                [[ -n "${OPTARG}" ]] || die 2 "--label cannot be empty."
                LABELS+=("${OPTARG}")
                ;;
            m)
                [[ -n "${OPTARG}" ]] || die 2 "--milestone cannot be empty."
                MILESTONE="${OPTARG}"
                ;;
            n)
                ALLOW_DUPLICATE=1
                ;;
            o)
                [[ -n "${OPTARG}" ]] || die 2 "--project-owner cannot be empty."
                PROJECT_OWNER="${OPTARG}"
                ;;
            p)
                [[ -n "${OPTARG}" ]] || die 2 "--priority cannot be empty."
                PRIORITY="${OPTARG}"
                ;;
            q)
                JSON_OUTPUT=1
                ;;
            r)
                [[ -n "${OPTARG}" ]] || die 2 "--repo cannot be empty."
                REPOSITORY="${OPTARG}"
                ;;
            s)
                [[ -n "${OPTARG}" ]] || die 2 "--status cannot be empty."
                STATUS="${OPTARG}"
                ;;
            t)
                [[ -n "${OPTARG}" ]] || die 2 "--title cannot be empty."
                TITLE="${OPTARG}"
                ;;
            v)
                version
                exit 0
                ;;
            y)
                [[ -n "${OPTARG}" ]] || die 2 "--type cannot be empty."
                TYPE="${OPTARG}"
                ;;
            :)
                die 2 "Option '-${OPTARG}' requires a value."
                ;;
            \?)
                die 2 "Unknown option: -${OPTARG}"
                ;;
        esac
    done

    shift $((OPTIND - 1))

    if [[ $# -gt 0 ]]; then
        die 2 "Unexpected positional argument: $1"
    fi
}

# Optional Issue properties are initialized after argument parsing declarations
# to remain compatible with set -u on Bash 3.2.
ASSIGNEE=""
MILESTONE=""

# @purpose: Validate required configuration and simple argument formats.
validate_arguments() {
    [[ -n "${TITLE}" ]] || die 2 "--title is required."

    if [[ -z "${STATUS}" ]]; then
        STATUS="Backlog"
    fi

    [[ -n "${PROJECT_NUMBER}" ]] ||
        die 2 "Project number is required via --project or GH_CARD_PROJECT."

    [[ -n "${PROJECT_OWNER}" ]] ||
        die 2 "Project owner is required via --project-owner or GH_CARD_PROJECT_OWNER."

    case "${PROJECT_NUMBER}" in
        *[!0-9]*)
            die 2 "Project number must contain only decimal digits."
            ;;
    esac
}

# @purpose: Resolve and validate the target GitHub repository.
resolve_repository() {
    local resolved_repo

    resolved_repo=""

    if [[ -n "${REPOSITORY}" ]]; then
        if ! resolved_repo=$(
            gh repo view "${REPOSITORY}" \
                --json nameWithOwner \
                --jq '.nameWithOwner'
        ); then
            die 5 "Repository '${REPOSITORY}' was not found or is not accessible."
        fi
    else
        if ! resolved_repo=$(
            gh repo view \
                --json nameWithOwner \
                --jq '.nameWithOwner'
        ); then
            die 5 "Could not determine a GitHub repository from the current Git repository."
        fi
    fi

    [[ -n "${resolved_repo}" ]] || die 5 "GitHub repository resolution returned an empty value."

    REPOSITORY="${resolved_repo}"
}

# @purpose: Validate the GitHub Project and resolve its internal ID and title.
validate_project() {
    local project_metadata

    project_metadata=""

    if ! project_metadata=$(
        gh project view "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --format json \
            --jq '[.id, .title] | @tsv'
    ); then
        log_error "Project '${PROJECT_OWNER}/${PROJECT_NUMBER}' was not found or is not accessible."
        log_warn "If Projects access is missing, run: gh auth refresh -s project"
        exit 6
    fi

    IFS=$'\t' read -r PROJECT_ID PROJECT_TITLE <<< "${project_metadata}"

    [[ -n "${PROJECT_ID}" ]] || die 6 "Project internal ID is empty."
}

# @purpose: Load supported Project field IDs and option IDs once per execution.
load_project_fields() {
    if ! PROJECT_FIELDS_CACHE=$(
        gh project field-list "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --format json \
            --jq '
                .fields[]
                | select(.name == "Status" or .name == "Priority" or .name == "Type")
                | . as $field
                | ([$field.name, $field.id, $field.type, "", ""] | @tsv),
                  ($field.options[]? | [$field.name, $field.id, $field.type, .id, .name] | @tsv)
            '
    ); then
        log_error "Could not list fields for Project '${PROJECT_OWNER}/${PROJECT_NUMBER}'."
        log_warn "If Projects access is missing, run: gh auth refresh -s project"
        exit 6
    fi
}

# @purpose: Validate a Project field and resolve the requested single-select option.
# @param $1 [Req]: Field name.
# @param $2 [Req]: Requested field value.
validate_project_field() {
    local field_name
    local field_value
    local field_id
    local field_type
    local candidate_field_name
    local candidate_field_id
    local candidate_field_type
    local candidate_id
    local candidate_name
    local option_id
    local available_values

    field_name=$1
    field_value=$2
    field_id=""
    field_type=""
    candidate_field_name=""
    candidate_field_id=""
    candidate_field_type=""
    candidate_id=""
    candidate_name=""
    option_id=""
    available_values=""

    while IFS=$'\t' read -r \
        candidate_field_name \
        candidate_field_id \
        candidate_field_type \
        candidate_id \
        candidate_name; do
        [[ "${candidate_field_name}" == "${field_name}" ]] || continue

        if [[ -z "${field_id}" ]]; then
            field_id="${candidate_field_id}"
            field_type="${candidate_field_type}"
        fi

        [[ -n "${candidate_id}" ]] || continue

        if [[ -n "${available_values}" ]]; then
            available_values="${available_values}, ${candidate_name}"
        else
            available_values="${candidate_name}"
        fi

        if [[ "${candidate_name}" == "${field_value}" ]]; then
            option_id="${candidate_id}"
        fi
    done <<< "${PROJECT_FIELDS_CACHE}"

    if [[ -z "${field_id}" ]]; then
        log_error "Project field '${field_name}' does not exist."
        exit 9
    fi

    case "${field_type}" in
        SINGLE_SELECT|SingleSelect|ProjectV2SingleSelectField)
            ;;
        *)
            log_error "Project field '${field_name}' is not a SINGLE_SELECT field."
            printf 'Detected field type: %s\n' "${field_type}" >&2
            exit 11
            ;;
    esac

    if [[ -z "${option_id}" ]]; then
        log_error "Invalid value '${field_value}' for field '${field_name}'."
        printf 'Available values: %s\n' "${available_values}" >&2
        exit 10
    fi

    case "${field_name}" in
        Status)
            STATUS_FIELD_ID="${field_id}"
            STATUS_OPTION_ID="${option_id}"
            ;;
        Priority)
            PRIORITY_FIELD_ID="${field_id}"
            PRIORITY_OPTION_ID="${option_id}"
            ;;
        Type)
            TYPE_FIELD_ID="${field_id}"
            TYPE_OPTION_ID="${option_id}"
            ;;
    esac
}

# @purpose: Validate all requested Project fields before creating the Issue.
validate_requested_fields() {
    validate_project_field "Status" "${STATUS}"

    if [[ -n "${PRIORITY}" ]]; then
        validate_project_field "Priority" "${PRIORITY}"
    fi

    if [[ -n "${TYPE}" ]]; then
        validate_project_field "Type" "${TYPE}"
    fi
}

# @purpose: Detect an open Issue with exactly the same title.
check_duplicate_issue() {
    local issue_list
    local existing_title
    local existing_url

    issue_list=""
    existing_title=""
    existing_url=""

    if ((ALLOW_DUPLICATE == 1)); then
        return 0
    fi

    if ! issue_list=$(
        gh issue list \
            --repo "${REPOSITORY}" \
            --state open \
            --limit 10000 \
            --json title,url \
            --template '{{range .}}{{printf "%s\t%s\n" .title .url}}{{end}}'
    ); then
        die 1 "Could not inspect existing Issues in '${REPOSITORY}'."
    fi

    while IFS=$'\t' read -r existing_title existing_url; do
        if [[ "${existing_title}" == "${TITLE}" ]]; then
            log_error "An open issue with this title already exists:"
            printf '%s\n' "${existing_url}" >&2
            exit 12
        fi
    done <<< "${issue_list}"
}

# @purpose: Display a failure that occurred after the Issue was created.
# @param $1 [Req]: Exit code.
# @param $2 [Req]: Human-readable failed operation.
partial_failure() {
    local exit_code
    local operation

    exit_code=$1
    operation=$2

    log_error "The Issue was created, but a later operation failed."
    printf '\nIssue:\n%s\n\nFailed operation:\n%s\n' \
        "${ISSUE_URL}" \
        "${operation}" >&2

    exit "${exit_code}"
}

# @purpose: Create the GitHub Issue and capture its URL and number.
create_issue() {
    local -a command
    local label

    command=(
        gh issue create
        --repo "${REPOSITORY}"
        --title "${TITLE}"
        --body "${BODY}"
    )

    label=""

    for label in "${LABELS[@]}"; do
        command+=(--label "${label}")
    done

    if [[ -n "${ASSIGNEE}" ]]; then
        command+=(--assignee "${ASSIGNEE}")
    fi

    if [[ -n "${MILESTONE}" ]]; then
        command+=(--milestone "${MILESTONE}")
    fi

    log_info "Creating GitHub Issue in ${REPOSITORY}."

    if ! ISSUE_URL=$("${command[@]}"); then
        log_error "Failed to create GitHub Issue."
        exit 7
    fi

    ISSUE_URL="${ISSUE_URL%$'\n'}"
    ISSUE_NUMBER="${ISSUE_URL##*/}"

    case "${ISSUE_NUMBER}" in
        ''|*[!0-9]*)
            log_error "Issue was created, but its number could not be parsed from the returned URL."
            printf 'Issue URL: %s\n' "${ISSUE_URL}" >&2
            exit 7
            ;;
    esac
}

# @purpose: Add the created Issue to the configured GitHub Project.
add_issue_to_project() {
    log_info "Adding Issue #${ISSUE_NUMBER} to Project ${PROJECT_OWNER}/${PROJECT_NUMBER}."

    if ! ITEM_ID=$(
        gh project item-add "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --url "${ISSUE_URL}" \
            --format json \
            --jq '.id'
    ); then
        partial_failure 8 "Add Issue to Project ${PROJECT_OWNER}/${PROJECT_NUMBER}"
    fi

    if [[ -z "${ITEM_ID}" ]]; then
        partial_failure 8 "Add Issue to Project ${PROJECT_OWNER}/${PROJECT_NUMBER}"
    fi
}

# @purpose: Configure one single-select GitHub Project field on the created item.
# @param $1 [Req]: Field name for logging.
# @param $2 [Req]: Requested field value for logging.
# @param $3 [Req]: Internal Project field ID.
# @param $4 [Req]: Internal single-select option ID.
set_project_field() {
    local field_name
    local field_value
    local field_id
    local option_id

    field_name=$1
    field_value=$2
    field_id=$3
    option_id=$4

    log_info "Setting ${field_name} = ${field_value}."

    if ! gh project item-edit \
        --id "${ITEM_ID}" \
        --project-id "${PROJECT_ID}" \
        --field-id "${field_id}" \
        --single-select-option-id "${option_id}" \
        >/dev/null; then
        partial_failure 11 "${field_name} = ${field_value}"
    fi
}

# @purpose: Configure all requested GitHub Project fields in deterministic order.
configure_project_fields() {
    set_project_field \
        "Status" \
        "${STATUS}" \
        "${STATUS_FIELD_ID}" \
        "${STATUS_OPTION_ID}"

    if [[ -n "${PRIORITY}" ]]; then
        set_project_field \
            "Priority" \
            "${PRIORITY}" \
            "${PRIORITY_FIELD_ID}" \
            "${PRIORITY_OPTION_ID}"
    fi

    if [[ -n "${TYPE}" ]]; then
        set_project_field \
            "Type" \
            "${TYPE}" \
            "${TYPE_FIELD_ID}" \
            "${TYPE_OPTION_ID}"
    fi
}

# @purpose: Escape a string for inclusion in JSON output.
# @param $1 [Req]: Raw string.
json_escape() {
    local value

    value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}

    printf '%s' "${value}"
}

# @purpose: Print a JSON success result.
print_json_result() {
    printf '{\n'
    printf '  "issue": %s,\n' "${ISSUE_NUMBER}"
    printf '  "url": "%s",\n' "$(json_escape "${ISSUE_URL}")"
    printf '  "repository": "%s",\n' "$(json_escape "${REPOSITORY}")"
    printf '  "project": %s,\n' "${PROJECT_NUMBER}"
    printf '  "projectOwner": "%s",\n' "$(json_escape "${PROJECT_OWNER}")"
    printf '  "status": "%s"' "$(json_escape "${STATUS}")"

    if [[ -n "${PRIORITY}" ]]; then
        printf ',\n  "priority": "%s"' "$(json_escape "${PRIORITY}")"
    fi

    if [[ -n "${TYPE}" ]]; then
        printf ',\n  "type": "%s"' "$(json_escape "${TYPE}")"
    fi

    printf '\n}\n'
}

# @purpose: Print the normal human-readable success result.
print_human_result() {
    printf 'Created GitHub card\n\n'
    printf 'Issue:    #%s\n' "${ISSUE_NUMBER}"
    printf 'URL:      %s\n' "${ISSUE_URL}"
    printf 'Project:  %s\n' "${PROJECT_TITLE}"
    printf 'Status:   %s\n' "${STATUS}"

    if [[ -n "${PRIORITY}" ]]; then
        printf 'Priority: %s\n' "${PRIORITY}"
    fi

    if [[ -n "${TYPE}" ]]; then
        printf 'Type:     %s\n' "${TYPE}"
    fi
}

# @purpose: Print the final result in the requested format.
print_result() {
    if ((JSON_OUTPUT == 1)); then
        print_json_result
    else
        print_human_result
    fi
}

# @purpose: Print dry-run JSON without claiming that an Issue was created.
print_dry_run_json() {
    printf '{\n'
    printf '  "dryRun": true,\n'
    printf '  "issue": null,\n'
    printf '  "url": null,\n'
    printf '  "repository": "%s",\n' "$(json_escape "${REPOSITORY}")"
    printf '  "project": %s,\n' "${PROJECT_NUMBER}"
    printf '  "projectOwner": "%s",\n' "$(json_escape "${PROJECT_OWNER}")"
    printf '  "status": "%s"' "$(json_escape "${STATUS}")"

    if [[ -n "${PRIORITY}" ]]; then
        printf ',\n  "priority": "%s"' "$(json_escape "${PRIORITY}")"
    fi

    if [[ -n "${TYPE}" ]]; then
        printf ',\n  "type": "%s"' "$(json_escape "${TYPE}")"
    fi

    printf '\n}\n'
}

# @purpose: Print a human-readable dry-run plan.
print_dry_run_human() {
    local label

    label=""

    printf 'Repository: %s\n' "${REPOSITORY}"
    printf 'Project:    %s/%s\n\n' "${PROJECT_OWNER}" "${PROJECT_NUMBER}"
    printf 'Would create issue:\n'
    printf '  Title:    %s\n' "${TITLE}"

    if [[ -n "${BODY}" ]]; then
        printf '  Body:     %s\n' "${BODY}"
    fi

    for label in "${LABELS[@]}"; do
        printf '  Label:    %s\n' "${label}"
    done

    if [[ -n "${ASSIGNEE}" ]]; then
        printf '  Assignee: %s\n' "${ASSIGNEE}"
    fi

    if [[ -n "${MILESTONE}" ]]; then
        printf '  Milestone: %s\n' "${MILESTONE}"
    fi

    if [[ -n "${TYPE}" ]]; then
        printf '  Type:     %s\n' "${TYPE}"
    fi

    if [[ -n "${PRIORITY}" ]]; then
        printf '  Priority: %s\n' "${PRIORITY}"
    fi

    printf '  Status:   %s\n\n' "${STATUS}"

    printf 'Would add issue to Project.\n'
    printf 'Would set Status = %s.\n' "${STATUS}"

    if [[ -n "${PRIORITY}" ]]; then
        printf 'Would set Priority = %s.\n' "${PRIORITY}"
    fi

    if [[ -n "${TYPE}" ]]; then
        printf 'Would set Type = %s.\n' "${TYPE}"
    fi
}

# @purpose: Print the requested dry-run representation.
print_dry_run() {
    if ((JSON_OUTPUT == 1)); then
        print_dry_run_json
    else
        print_dry_run_human
    fi
}

# @purpose: Execute the complete create-card workflow.
# @param $1..$N [Opt]: Script command-line arguments.
main() {
    init_colors
    parse_args "$@"
    validate_arguments
    check_dependencies
    check_auth
    resolve_repository
    validate_project
    load_project_fields
    validate_requested_fields
    check_duplicate_issue

    if ((DRY_RUN == 1)); then
        print_dry_run
        exit 0
    fi

    create_issue
    add_issue_to_project
    configure_project_fields
    print_result

    exit 0
}

main "$@"
