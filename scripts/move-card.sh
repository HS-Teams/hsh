#!/usr/bin/env bash

# Script Name: move-card.sh
# Purpose: Move an existing GitHub Issue card between Status columns in a GitHub Projects v2 board.
# Created Date: Sep 11, 2026
# Author: ChatGPT
# Required Packages: bash 3.2+, gh, jq
# Powered by: https://github.com/yorevs/homesetup
# GPT: https://chatgpt.com/g/g-ra0RVB9Jo-homesetup-script-generator
#
# +------------------------------------------------------------------------------+
# | AIs CAN MAKE MISTAKES.                                                       |
# | For your safety, verify important information and code before executing it.  |
# |                                                                              |
# | This program comes with NO WARRANTY, to the extent permitted by law.         |
# +------------------------------------------------------------------------------+

set -u

SCRIPT_NAME='move-card.sh'

# https://semver.org/; major.minor.patch
VERSION='0.0.1'

USAGE='Usage:
  move-card.sh --issue "<number>" (--next | --previous | --status "<value>") [OPTIONS]

Move an existing GitHub Issue card between Status columns of a GitHub
Projects v2 board.

Examples:
  move-card.sh --issue "12" --next
  move-card.sh --issue "12" --previous
  move-card.sh --issue "12" --status "Done"
  move-card.sh --issue "12" --next --dry-run

Options:
  -d, --dry-run          Resolve the transition without modifying the Project item.
  -h, --help             Display this help message and exit.
  -i, --issue "<number>" GitHub Issue number in the configured repository.
  -n, --next             Move forward one Status state.
  -p, --previous         Move backward one Status state.
  -q, --json             Write successful results as JSON only.
  -s, --status "<value>" Move directly to Todo, In Progress, or Done.
  -v, --version          Print version information and exit.

Environment:
  GH_CARD_REPO           Repository. Default: HS-Teams/hsh
  GH_CARD_PROJECT        Project number. Default: 2
  GH_CARD_PROJECT_OWNER  Project owner. Default: HS-Teams

Exit codes:
  0   Success
  1   Generic error
  2   Invalid arguments
  3   Missing dependency
  4   GitHub authentication error
  5   Repository or Issue not found
  6   Project not found or inaccessible
  7   Issue is not present in the Project
  8   Status field not found
  9   Invalid Status value
  10  Error updating Project item'

GH_CARD_REPO="${GH_CARD_REPO-HS-Teams/hsh}"
GH_CARD_PROJECT="${GH_CARD_PROJECT-2}"
GH_CARD_PROJECT_OWNER="${GH_CARD_PROJECT_OWNER-HS-Teams}"

REPO="${GH_CARD_REPO}"
PROJECT_NUMBER="${GH_CARD_PROJECT}"
PROJECT_OWNER="${GH_CARD_PROJECT_OWNER}"

FALLBACK_STATUS_FIELD_ID='PVTSSF_lADOBQMyE84BjOB4zhiDNh4'
FALLBACK_STATUS_TODO_ID='f75ad846'
FALLBACK_STATUS_IN_PROGRESS_ID='47fc9ee4'
FALLBACK_STATUS_DONE_ID='98236657'

PROJECT_ITEMS_LIMIT='10000'

ISSUE_NUMBER=''
MOVE_MODE=''
REQUESTED_STATUS=''
TARGET_STATUS=''
CURRENT_STATUS=''

ACTION_COUNT='0'
DRY_RUN='0'
JSON_MODE='0'
SHOW_HELP='0'
SHOW_VERSION='0'
BOUNDARY='0'
CHANGED='0'

PROJECT_JSON=''
PROJECT_ID=''
FIELD_LIST_JSON=''
FIELD_SOURCE=''
STATUS_FIELD_JSON=''
STATUS_FIELD_ID=''
STATUS_OPTIONS_DISCOVERED='0'

ISSUE_JSON=''
ITEMS_JSON=''
ITEM_MATCH_JSON=''
ITEM_ID=''
TARGET_OPTION_ID=''

ERR_RED=''
ERR_RESET=''

# @purpose: Display usage information.
usage() {
    printf '%s\n' "${USAGE}"
}

# @purpose: Display script version information.
version() {
    printf '%s %s\n' "${SCRIPT_NAME}" "${VERSION}"
}

# @purpose: Enable stderr colors when output is interactive and JSON mode is disabled.
configure_colors() {
    if [[ "${JSON_MODE}" -eq 0 && -t 2 ]]; then
        ERR_RED='\033[31m'
        ERR_RESET='\033[m'
    fi
}

# @purpose: Print an error message and exit with the requested status.
# @param $1 [Req]: Exit status.
# @param $2 [Req]: Error message.
die() {
    local exit_code
    local message

    exit_code="${1}"
    message="${2}"

    printf '%bERROR%b: %s\n' "${ERR_RED}" "${ERR_RESET}" "${message}" >&2
    exit "${exit_code}"
}

# @purpose: Print an invalid-argument error with usage information and exit.
# @param $1 [Req]: Invalid-argument error message.
die_invalid() {
    local message

    message="${1}"

    printf '%bERROR%b: %s\n\n' "${ERR_RED}" "${ERR_RESET}" "${message}" >&2
    printf '%s\n' "${USAGE}" >&2
    exit 2
}

# @purpose: Verify that the GitHub CLI is installed.
require_gh() {
    if ! command -v 'gh' >/dev/null 2>&1; then
        die 3 'Required dependency "gh" was not found. Install it from https://cli.github.com/.'
    fi
}

# @purpose: Verify that jq is installed.
require_jq() {
    if ! command -v 'jq' >/dev/null 2>&1; then
        die 3 'Required dependency "jq" was not found. Install it from https://jqlang.github.io/jq/.'
    fi
}

# @purpose: Verify that GitHub CLI authentication is valid.
check_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        die 4 'GitHub CLI authentication failed. Authenticate with "gh auth login".'
    fi
}

# @purpose: Parse short and long command-line options using getopts.
# @param $1..$N [Opt] : Command-line arguments.
parse_args() {
    local -a normalized
    local opt

    normalized=()
    opt=''

    while [[ "$#" -gt 0 ]]; do
        case "${1}" in
            '--dry-run')
                normalized[${#normalized[@]}]='-d'
                ;;
            '--help')
                normalized[${#normalized[@]}]='-h'
                ;;
            '--issue')
                if [[ "$#" -lt 2 ]]; then
                    die_invalid 'Option "--issue" requires a value.'
                fi
                normalized[${#normalized[@]}]='-i'
                normalized[${#normalized[@]}]="${2}"
                shift
                ;;
            '--issue='*)
                normalized[${#normalized[@]}]='-i'
                normalized[${#normalized[@]}]="${1#*=}"
                ;;
            '--next')
                normalized[${#normalized[@]}]='-n'
                ;;
            '--previous')
                normalized[${#normalized[@]}]='-p'
                ;;
            '--json')
                normalized[${#normalized[@]}]='-q'
                ;;
            '--status')
                if [[ "$#" -lt 2 ]]; then
                    die_invalid 'Option "--status" requires a value.'
                fi
                normalized[${#normalized[@]}]='-s'
                normalized[${#normalized[@]}]="${2}"
                shift
                ;;
            '--status='*)
                normalized[${#normalized[@]}]='-s'
                normalized[${#normalized[@]}]="${1#*=}"
                ;;
            '--version')
                normalized[${#normalized[@]}]='-v'
                ;;
            '--')
                normalized[${#normalized[@]}]='--'
                shift

                while [[ "$#" -gt 0 ]]; do
                    normalized[${#normalized[@]}]="${1}"
                    shift
                done

                break
                ;;
            '--'*)
                die_invalid "Unknown option: ${1}"
                ;;
            *)
                normalized[${#normalized[@]}]="${1}"
                ;;
        esac

        shift
    done

    set -- "${normalized[@]}"
    OPTIND=1

    while getopts ':dhi:npqs:v' opt; do
        case "${opt}" in
            'd')
                DRY_RUN='1'
                ;;
            'h')
                SHOW_HELP='1'
                ;;
            'i')
                if [[ "${OPTARG}" == '-'.* ]]; then
                    die_invalid 'Option "-i/--issue" requires an Issue number.'
                fi
                ISSUE_NUMBER="${OPTARG}"
                ;;
            'n')
                ACTION_COUNT=$((ACTION_COUNT + 1))
                MOVE_MODE='next'
                ;;
            'p')
                ACTION_COUNT=$((ACTION_COUNT + 1))
                MOVE_MODE='previous'
                ;;
            'q')
                JSON_MODE='1'
                ;;
            's')
                if [[ "${OPTARG}" == '-'.* ]]; then
                    die_invalid 'Option "-s/--status" requires a Status value.'
                fi
                ACTION_COUNT=$((ACTION_COUNT + 1))
                MOVE_MODE='status'
                REQUESTED_STATUS="${OPTARG}"
                ;;
            'v')
                SHOW_VERSION='1'
                ;;
            ':')
                die_invalid "Option \"-${OPTARG}\" requires a value."
                ;;
            '?')
                die_invalid "Unknown option: -${OPTARG}"
                ;;
        esac
    done

    shift "$((OPTIND - 1))"

    if [[ "$#" -ne 0 ]]; then
        die_invalid "Unexpected positional argument: ${1}"
    fi
}

# @purpose: Validate required command-line arguments and requested Status values.
validate_args() {
    if [[ "${ACTION_COUNT}" -ne 1 ]]; then
        die_invalid 'Exactly one of "--next", "--previous", or "--status" must be supplied.'
    fi

    case "${ISSUE_NUMBER}" in
        ''|*[!0-9]*)
            die_invalid '"--issue" must be a positive integer.'
            ;;
    esac

    case "${ISSUE_NUMBER}" in
        [1-9]*)
            ;;
        *)
            die_invalid '"--issue" must be a positive integer without leading zeroes.'
            ;;
    esac

    if [[ "${MOVE_MODE}" == 'status' ]]; then
        case "${REQUESTED_STATUS}" in
            'Todo'|'In Progress'|'Done')
                ;;
            *)
                die 9 "Invalid Status value: \"${REQUESTED_STATUS}\". Expected \"Todo\", \"In Progress\", or \"Done\"."
                ;;
        esac
    fi
}

# @purpose: Validate repository, Project number, and Project owner configuration.
validate_config() {
    local repo_owner
    local repo_name

    repo_owner=''
    repo_name=''

    if [[ -z "${PROJECT_OWNER}" ]]; then
        die 2 '"GH_CARD_PROJECT_OWNER" must not be empty.'
    fi

    case "${PROJECT_NUMBER}" in
        ''|*[!0-9]*)
            die 2 '"GH_CARD_PROJECT" must be a positive integer.'
            ;;
    esac

    case "${PROJECT_NUMBER}" in
        [1-9]*)
            ;;
        *)
            die 2 '"GH_CARD_PROJECT" must be a positive integer without leading zeroes.'
            ;;
    esac

    case "${REPO}" in
        */*)
            ;;
        *)
            die 2 '"GH_CARD_REPO" must use the "owner/repository" format.'
            ;;
    esac

    repo_owner="${REPO%%/*}"
    repo_name="${REPO#*/}"

    if [[ -z "${repo_owner}" || -z "${repo_name}" || "${repo_name}" == */* ]]; then
        die 2 '"GH_CARD_REPO" must contain exactly one non-empty "owner/repository" pair.'
    fi
}

# @purpose: Resolve and validate the GitHub Projects v2 Project node ID.
load_project() {
    if ! PROJECT_JSON="$(
        gh project view "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --format 'json' \
            2>/dev/null
    )"; then
        die 6 "Project \"${PROJECT_NUMBER}\" for \"${PROJECT_OWNER}\" was not found or is inaccessible."
    fi

    if ! PROJECT_ID="$(printf '%s' "${PROJECT_JSON}" | jq -r '.id // empty')"; then
        die 6 'Unable to parse the Project node ID.'
    fi

    if [[ -z "${PROJECT_ID}" ]]; then
        die 6 'The Project response did not contain a Project node ID.'
    fi
}

# @purpose: Retrieve Project single-select fields through GitHub GraphQL as a discovery fallback.
load_fields_via_graphql() {
    local query
    local raw
    local normalized

    query=''
    raw=''
    normalized=''

    query='
query($id: ID!) {
  node(id: $id) {
    ... on ProjectV2 {
      fields(first: 100) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}'

    if ! raw="$(
        gh api graphql \
            -f "query=${query}" \
            -F "id=${PROJECT_ID}" \
            2>/dev/null
    )"; then
        return 1
    fi

    if ! normalized="$(
        printf '%s' "${raw}" |
            jq -c '{fields: [.data.node.fields.nodes[]? | select(.id? != null)]}'
    )"; then
        return 1
    fi

    FIELD_LIST_JSON="${normalized}"
    return 0
}

# @purpose: Extract the unique Status field and its option-discovery state from loaded field data.
extract_status_field() {
    local count
    local candidate
    local field_id
    local options_state

    count=''
    candidate=''
    field_id=''
    options_state=''

    if ! count="$(
        printf '%s' "${FIELD_LIST_JSON}" |
            jq -r '
                (if type == "array" then . else (.fields // []) end)
                | [.[]? | select(.name == "Status")]
                | length
            '
    )"; then
        return 1
    fi

    if [[ "${count}" != '1' ]]; then
        return 1
    fi

    if ! candidate="$(
        printf '%s' "${FIELD_LIST_JSON}" |
            jq -c '
                (if type == "array" then . else (.fields // []) end)
                | [.[]? | select(.name == "Status")]
                | .[0]
            '
    )"; then
        return 1
    fi

    if ! field_id="$(printf '%s' "${candidate}" | jq -r '.id // empty')"; then
        return 1
    fi

    if [[ -z "${field_id}" ]]; then
        return 1
    fi

    if ! options_state="$(
        printf '%s' "${candidate}" |
            jq -r '
                if (has("options") and ((.options | type) == "array"))
                then "1"
                else "0"
                end
            '
    )"; then
        return 1
    fi

    STATUS_FIELD_JSON="${candidate}"
    STATUS_FIELD_ID="${field_id}"
    STATUS_OPTIONS_DISCOVERED="${options_state}"

    return 0
}

# @purpose: Discover the Status field and its options, preferring gh project field-list results.
load_status_field() {
    FIELD_SOURCE=''

    if FIELD_LIST_JSON="$(
        gh project field-list "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --format 'json' \
            2>/dev/null
    )"; then
        FIELD_SOURCE='project-field-list'

        if ! extract_status_field; then
            if load_fields_via_graphql && extract_status_field; then
                FIELD_SOURCE='graphql'
            else
                die 8 'A unique "Status" field could not be found in the Project.'
            fi
        fi
    else
        if load_fields_via_graphql && extract_status_field; then
            FIELD_SOURCE='graphql'
        else
            die 8 'The "Status" field could not be discovered in the Project.'
        fi
    fi

    if [[ "${STATUS_OPTIONS_DISCOVERED}" -eq 0 && "${FIELD_SOURCE}" != 'graphql' ]]; then
        if load_fields_via_graphql && extract_status_field; then
            FIELD_SOURCE='graphql'
        fi
    fi

    if [[ "${STATUS_OPTIONS_DISCOVERED}" -eq 0 &&
        "${STATUS_FIELD_ID}" != "${FALLBACK_STATUS_FIELD_ID}" ]]; then
        die 8 'The "Status" field exists, but its single-select options could not be inspected.'
    fi
}

# @purpose: Verify that the GitHub Issue exists in the configured repository.
ensure_issue_exists() {
    local actual_number

    actual_number=''

    if ! ISSUE_JSON="$(
        gh issue view "${ISSUE_NUMBER}" \
            --repo "${REPO}" \
            --json 'number,url' \
            2>/dev/null
    )"; then
        die 5 "Issue \"#${ISSUE_NUMBER}\" does not exist in repository \"${REPO}\", or it is inaccessible."
    fi

    if ! actual_number="$(printf '%s' "${ISSUE_JSON}" | jq -r '.number // empty')"; then
        die 5 "Unable to validate Issue \"#${ISSUE_NUMBER}\" in repository \"${REPO}\"."
    fi

    if [[ "${actual_number}" != "${ISSUE_NUMBER}" ]]; then
        die 5 "Issue \"#${ISSUE_NUMBER}\" was not returned from repository \"${REPO}\"."
    fi
}

# @purpose: Locate the Project item representing the Issue using repository and Issue number.
load_project_item() {
    local match_count

    match_count=''

    if ! ITEMS_JSON="$(
        gh project item-list "${PROJECT_NUMBER}" \
            --owner "${PROJECT_OWNER}" \
            --format 'json' \
            --limit "${PROJECT_ITEMS_LIMIT}" \
            2>/dev/null
    )"; then
        die 6 "Unable to inspect items in Project \"${PROJECT_NUMBER}\" for \"${PROJECT_OWNER}\"."
    fi

    if ! ITEM_MATCH_JSON="$(
        printf '%s' "${ITEMS_JSON}" |
            jq -c \
                --arg 'repo' "${REPO}" \
                --arg 'issue' "${ISSUE_NUMBER}" '
                def repo_name:
                  if ((.content.repository? // null) | type) == "string" then
                    .content.repository
                  elif (.content.repository?.nameWithOwner? // "") != "" then
                    .content.repository.nameWithOwner
                  elif ((.repository? // null) | type) == "string" then
                    .repository
                  elif (.repository?.nameWithOwner? // "") != "" then
                    .repository.nameWithOwner
                  else
                    ""
                  end;

                [
                  .items[]?
                  | select((.content.type? // "") == "Issue")
                  | select((repo_name | ascii_downcase) == ($repo | ascii_downcase))
                  | select(
                      ((.content.number? // -1) | tostring)
                      == (($issue | tonumber) | tostring)
                    )
                ]
                | {count: length, item: (.[0] // null)}
                '
    )"; then
        die 1 'Unable to inspect Project item data.'
    fi

    if ! match_count="$(
        printf '%s' "${ITEM_MATCH_JSON}" |
            jq -r '.count // 0'
    )"; then
        die 1 'Unable to determine the number of matching Project items.'
    fi

    if [[ "${match_count}" == '0' ]]; then
        die 7 \
            "Issue \"#${ISSUE_NUMBER}\" in \"${REPO}\" is not present in Project \"${PROJECT_NUMBER}\"."
    fi

    if [[ "${match_count}" != '1' ]]; then
        die 1 \
            "Issue \"#${ISSUE_NUMBER}\" matched multiple Project items; refusing to update an ambiguous item."
    fi

    if ! ITEM_ID="$(
        printf '%s' "${ITEM_MATCH_JSON}" |
            jq -r '.item.id // empty'
    )"; then
        die 1 'Unable to parse the Project item ID.'
    fi

    if [[ -z "${ITEM_ID}" ]]; then
        die 1 'The matching Project item did not contain an item ID.'
    fi

    if ! CURRENT_STATUS="$(
        printf '%s' "${ITEM_MATCH_JSON}" |
            jq -r '.item.status // .item.Status // empty'
    )"; then
        CURRENT_STATUS=''
    fi
}

# @purpose: Query the current Status when item-list did not expose it.
load_current_status() {
    local query
    local raw
    local status

    query=''
    raw=''
    status=''

    if [[ -n "${CURRENT_STATUS}" ]]; then
        return 0
    fi

    query='
query($itemId: ID!) {
  node(id: $itemId) {
    ... on ProjectV2Item {
      fieldValues(first: 100) {
        nodes {
          ... on ProjectV2ItemFieldSingleSelectValue {
            name
            optionId
            field {
              ... on ProjectV2SingleSelectField {
                id
                name
              }
            }
          }
        }
      }
    }
  }
}'

    if ! raw="$(
        gh api graphql \
            -f "query=${query}" \
            -F "itemId=${ITEM_ID}" \
            2>/dev/null
    )"; then
        die 1 "Unable to determine the current Status for Issue \"#${ISSUE_NUMBER}\"."
    fi

    if ! status="$(
        printf '%s' "${raw}" |
            jq -r \
                --arg 'field_id' "${STATUS_FIELD_ID}" '
                [
                  .data.node.fieldValues.nodes[]?
                  | select((.field.id? // "") == $field_id)
                  | .name
                ]
                | .[0] // empty
                '
    )"; then
        die 1 "Unable to parse the current Status for Issue \"#${ISSUE_NUMBER}\"."
    fi

    CURRENT_STATUS="${status}"

    if [[ -z "${CURRENT_STATUS}" ]]; then
        die 1 "Issue \"#${ISSUE_NUMBER}\" does not currently have a value in the \"Status\" field."
    fi

    case "${CURRENT_STATUS}" in
        'Todo'|'In Progress'|'Done')
            ;;
        *)
            die 1 "Issue \"#${ISSUE_NUMBER}\" has unsupported current Status value: \"${CURRENT_STATUS}\"."
            ;;
    esac
}

# @purpose: Compute the target Status from the current Status and requested movement.
compute_target_status() {
    TARGET_STATUS=''
    BOUNDARY='0'
    CHANGED='0'

    case "${MOVE_MODE}" in
        'next')
            case "${CURRENT_STATUS}" in
                'Todo')
                    TARGET_STATUS='In Progress'
                    ;;
                'In Progress')
                    TARGET_STATUS='Done'
                    ;;
                'Done')
                    TARGET_STATUS='Done'
                    BOUNDARY='1'
                    ;;
                *)
                    die 1 "Cannot move forward from unknown Status: \"${CURRENT_STATUS}\"."
                    ;;
            esac
            ;;
        'previous')
            case "${CURRENT_STATUS}" in
                'Todo')
                    TARGET_STATUS='Todo'
                    BOUNDARY='1'
                    ;;
                'In Progress')
                    TARGET_STATUS='Todo'
                    ;;
                'Done')
                    TARGET_STATUS='In Progress'
                    ;;
                *)
                    die 1 "Cannot move backward from unknown Status: \"${CURRENT_STATUS}\"."
                    ;;
            esac
            ;;
        'status')
            TARGET_STATUS="${REQUESTED_STATUS}"
            ;;
        *)
            die 2 'No valid movement mode was selected.'
            ;;
    esac

    if [[ "${CURRENT_STATUS}" != "${TARGET_STATUS}" ]]; then
        CHANGED='1'
    fi
}

# @purpose: Resolve and validate the target single-select option ID for the Status field.
resolve_target_option() {
    local option_count
    local option_id

    option_count=''
    option_id=''

    if [[ "${STATUS_OPTIONS_DISCOVERED}" -eq 1 ]]; then
        if ! option_count="$(
            printf '%s' "${STATUS_FIELD_JSON}" |
                jq -r \
                    --arg 'name' "${TARGET_STATUS}" \
                    '[.options[]? | select(.name == $name)] | length'
        )"; then
            die 9 "Unable to validate target Status value: \"${TARGET_STATUS}\"."
        fi

        if [[ "${option_count}" == '0' ]]; then
            die 9 "Target Status does not exist in the Project: \"${TARGET_STATUS}\"."
        fi

        if [[ "${option_count}" != '1' ]]; then
            die 9 "Target Status is ambiguous in the Project: \"${TARGET_STATUS}\"."
        fi

        if ! option_id="$(
            printf '%s' "${STATUS_FIELD_JSON}" |
                jq -r \
                    --arg 'name' "${TARGET_STATUS}" \
                    '[.options[]? | select(.name == $name) | .id][0] // empty'
        )"; then
            option_id=''
        fi

        if [[ -n "${option_id}" ]]; then
            TARGET_OPTION_ID="${option_id}"
            return 0
        fi
    fi

    if [[ "${STATUS_FIELD_ID}" != "${FALLBACK_STATUS_FIELD_ID}" ]]; then
        die 9 "Target option ID could not be resolved for Status: \"${TARGET_STATUS}\"."
    fi

    case "${TARGET_STATUS}" in
        'Todo')
            option_id="${FALLBACK_STATUS_TODO_ID}"
            ;;
        'In Progress')
            option_id="${FALLBACK_STATUS_IN_PROGRESS_ID}"
            ;;
        'Done')
            option_id="${FALLBACK_STATUS_DONE_ID}"
            ;;
        *)
            die 9 "Invalid Status value: \"${TARGET_STATUS}\"."
            ;;
    esac

    TARGET_OPTION_ID="${option_id}"
}

# @purpose: Update the existing Project item Status unless the transition is a no-op or dry-run.
perform_update() {
    if [[ "${CHANGED}" -eq 0 || "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi

    if ! gh project item-edit \
        --id "${ITEM_ID}" \
        --project-id "${PROJECT_ID}" \
        --field-id "${STATUS_FIELD_ID}" \
        --single-select-option-id "${TARGET_OPTION_ID}" \
        >/dev/null; then
        die 10 \
            "Failed to update Issue \"#${ISSUE_NUMBER}\" from \"${CURRENT_STATUS}\" to \"${TARGET_STATUS}\"."
    fi
}

# @purpose: Print the successful transition result in text or JSON format.
print_result() {
    local changed_json

    changed_json='false'

    if [[ "${CHANGED}" -eq 1 ]]; then
        changed_json='true'
    fi

    if [[ "${JSON_MODE}" -eq 1 ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            jq -n \
                --argjson 'issue' "${ISSUE_NUMBER}" \
                --arg 'projectItemId' "${ITEM_ID}" \
                --arg 'from' "${CURRENT_STATUS}" \
                --arg 'to' "${TARGET_STATUS}" \
                --arg 'projectId' "${PROJECT_ID}" \
                --arg 'statusFieldId' "${STATUS_FIELD_ID}" \
                --arg 'targetOptionId' "${TARGET_OPTION_ID}" \
                --argjson 'changed' "${changed_json}" \
                '{
                  issue: $issue,
                  projectItemId: $projectItemId,
                  from: $from,
                  to: $to,
                  projectId: $projectId,
                  statusFieldId: $statusFieldId,
                  targetOptionId: $targetOptionId,
                  changed: $changed,
                  dryRun: true
                }'
            return 0
        fi

        jq -n \
            --argjson 'issue' "${ISSUE_NUMBER}" \
            --arg 'from' "${CURRENT_STATUS}" \
            --arg 'to' "${TARGET_STATUS}" \
            --argjson 'changed' "${changed_json}" \
            '{
              issue: $issue,
              from: $from,
              to: $to,
              changed: $changed
            }'

        return 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf 'Issue: #%s\n' "${ISSUE_NUMBER}"
        printf 'Project item ID: %s\n' "${ITEM_ID}"
        printf 'Current status: %s\n' "${CURRENT_STATUS}"
        printf 'Target status: %s\n' "${TARGET_STATUS}"
        printf 'Project ID: %s\n' "${PROJECT_ID}"
        printf 'Status field ID: %s\n' "${STATUS_FIELD_ID}"
        printf 'Target option ID: %s\n' "${TARGET_OPTION_ID}"
        return 0
    fi

    if [[ "${CHANGED}" -eq 0 ]]; then
        printf 'Issue #%s is already at %s.\n' "${ISSUE_NUMBER}" "${TARGET_STATUS}"
        return 0
    fi

    printf 'Issue #%s: %s -> %s\n' \
        "${ISSUE_NUMBER}" \
        "${CURRENT_STATUS}" \
        "${TARGET_STATUS}"
}

# @purpose: Execute validation, discovery, transition, and output workflow.
# @param $1..$N [Opt] : Command-line arguments.
main() {
    parse_args "$@"

    if [[ "${SHOW_HELP}" -eq 1 ]]; then
        usage
        return 0
    fi

    if [[ "${SHOW_VERSION}" -eq 1 ]]; then
        version
        return 0
    fi

    configure_colors
    validate_args
    validate_config
    require_gh
    require_jq
    check_auth
    load_project
    load_status_field
    ensure_issue_exists
    load_project_item
    load_current_status
    compute_target_status
    resolve_target_option
    perform_update
    print_result

    return 0
}

main "$@"
exit "$?"
