#!/usr/bin/env bash

# Script Name: cards.sh
# Purpose: Manage GitHub Issues/cards in a GitHub Projects v2 board.
# Created Date: Sep 11, 2026
# Author: ChatGPT
# Required Packages: bash, gh, jq
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

# https://semver.org/; major.minor.patch
VERSION="1.0.0"

GH_CARD_REPO="${GH_CARD_REPO:-HS-Teams/hsh}"
GH_CARD_PROJECT="${GH_CARD_PROJECT:-2}"
GH_CARD_PROJECT_OWNER="${GH_CARD_PROJECT_OWNER:-HS-Teams}"
CREATE_CARD_BIN="${CREATE_CARD_BIN:-}"
MOVE_CARD_BIN="${MOVE_CARD_BIN:-}"
ITEM_LIMIT="10000"

export GH_CARD_REPO
export GH_CARD_PROJECT
export GH_CARD_PROJECT_OWNER

USAGE='Usage:
  cards.sh <command> [OPTIONS]

Manage GitHub Issues/cards for a GitHub Projects v2 board.

Commands:
  list, ls       List cards, optionally filtering by Status.
  create, new    Create a card using create-card.sh.
  move, mv       Move a card using move-card.sh.
  open, web      Open the GitHub Project in the browser.
  rates          Check the API limits and rates.

Options:
  -h, --help     Display this help message and exit.
  -v, --version  Print version information and exit.

Examples:
  cards.sh list
  cards.sh list --status Todo
  cards.sh list --status "In Progress"
  cards.sh create --title "Implement parser" --priority High
  cards.sh move --issue 12 --next
  cards.sh move --issue 12 --status Done
  cards.sh open
  cards.sh rates

Run:
  cards.sh <command> --help

for command-specific help.'

LIST_USAGE='Usage:
  cards.sh list [OPTIONS]
  cards.sh ls [OPTIONS]

List GitHub Issue cards in the configured GitHub Projects v2 board.

Options:
  -h, --help             Display this help message and exit.
  -q, --json             Emit JSON only.
  -s, --status <status>  Filter cards by Project Status.

Examples:
  cards.sh list
  cards.sh list --status Todo
  cards.sh list --status "In Progress"
  cards.sh list --status Done
  cards.sh list --json
  cards.sh list --status Todo --json'

OPEN_USAGE='Usage:
  cards.sh open
  cards.sh web

Open the configured GitHub Projects v2 board in the default browser.

Options:
  -h, --help  Display this help message and exit.'

# @purpose: Display the main usage and help message.
usage()
{
    printf '%s\n' "${USAGE}"
}

# @purpose: Display script version information.
version()
{
    printf 'cards.sh %s\n' "${VERSION}"
}

# @purpose: Print an error message and exit with the specified status.
# @param $1 [Req]: Exit status.
# @param $2 [Req]: Error message.
die()
{
    local exit_status
    local message

    exit_status="${1}"
    message="${2}"

    printf '[ERROR] %s\n' "${message}" >&2
    exit "${exit_status}"
}

# @purpose: Verify that a required command is available.
# @param $1 [Req]: Command name.
require_command()
{
    local command_name

    command_name="${1}"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        die 3 "${command_name} was not found."
    fi
}

# @purpose: Validate GitHub CLI authentication.
validate_auth()
{
    if ! gh auth status >/dev/null 2>&1; then
        die 4 "GitHub authentication failed. Run 'gh auth login' and try again."
    fi
}

# @purpose: Resolve the directory containing cards.sh.
script_directory()
{
    local source_path
    local source_dir

    source_path="${BASH_SOURCE[0]}"
    source_dir=$(dirname "${source_path}")

    if ! cd "${source_dir}" >/dev/null 2>&1; then
        return 1
    fi

    pwd -P
}

# @purpose: Resolve create-card.sh using environment, script directory, then PATH.
resolve_create_card()
{
    local script_dir
    local candidate

    script_dir=""
    candidate=""

    if [ -n "${CREATE_CARD_BIN}" ]; then
        candidate="${CREATE_CARD_BIN}"

        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi

        if command -v "${candidate}" >/dev/null 2>&1; then
            command -v "${candidate}"
            return 0
        fi
    fi

    if script_dir=$(script_directory); then
        candidate="${script_dir}/create-card.sh"

        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    if command -v create-card.sh >/dev/null 2>&1; then
        command -v create-card.sh
        return 0
    fi

    return 1
}

# @purpose: Resolve move-card.sh using environment, script directory, then PATH.
resolve_move_card()
{
    local script_dir
    local candidate

    script_dir=""
    candidate=""

    if [ -n "${MOVE_CARD_BIN}" ]; then
        candidate="${MOVE_CARD_BIN}"

        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi

        if command -v "${candidate}" >/dev/null 2>&1; then
            command -v "${candidate}"
            return 0
        fi
    fi

    if script_dir=$(script_directory); then
        candidate="${script_dir}/move-card.sh"

        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    if command -v move-card.sh >/dev/null 2>&1; then
        command -v move-card.sh
        return 0
    fi

    return 1
}

# @purpose: Determine whether gh project item-list supports --limit.
supports_item_list_limit()
{
    gh project item-list --help 2>/dev/null | grep -q -- '--limit'
}

# @purpose: Discover canonical Project Status option names from GitHub.
discover_status_options()
{
    local fields_json
    local options

    fields_json=""
    options=""

    if ! fields_json=$(gh project field-list "${GH_CARD_PROJECT}" \
        --owner "${GH_CARD_PROJECT_OWNER}" \
        --format json 2>/dev/null); then
        return 1
    fi

    if ! options=$(printf '%s\n' "${fields_json}" | jq -r '
        .fields[]?
        | select(.name == "Status")
        | .options[]?
        | .name
    '); then
        return 1
    fi

    if [ -z "${options}" ]; then
        return 1
    fi

    printf '%s\n' "${options}"
}

# @purpose: Match user Status input against canonical GitHub Status values.
# @param $1 [Req]: User-provided Status value.
# @param $2 [Req]: Newline-delimited canonical Status options.
canonicalize_status()
{
    local requested
    local options
    local requested_lower
    local option
    local option_lower

    requested="${1}"
    options="${2}"
    requested_lower=""
    option=""
    option_lower=""

    requested_lower=$(printf '%s' "${requested}" | tr '[:upper:]' '[:lower:]')

    while IFS= read -r option; do
        [ -n "${option}" ] || continue

        option_lower=$(printf '%s' "${option}" | tr '[:upper:]' '[:lower:]')

        if [ "${requested_lower}" = "${option_lower}" ]; then
            printf '%s\n' "${option}"
            return 0
        fi
    done <<EOF
${options}
EOF

    return 1
}

# @purpose: Retrieve all practical Project items using JSON output.
# @param $1 [Req]: Whether gh project item-list supports --limit, 1 or 0.
fetch_project_items()
{
    local limit_supported

    limit_supported="${1}"

    if [ "${limit_supported}" -eq 1 ]; then
        gh project item-list "${GH_CARD_PROJECT}" \
            --owner "${GH_CARD_PROJECT_OWNER}" \
            --format json \
            --limit "${ITEM_LIMIT}"
        return
    fi

    gh project item-list "${GH_CARD_PROJECT}" \
        --owner "${GH_CARD_PROJECT_OWNER}" \
        --format json
}

# @purpose: Verify that Project item retrieval was not silently truncated.
# @param $1 [Req]: Raw gh project item-list JSON.
# @param $2 [Req]: Whether --limit was supported, 1 or 0.
validate_item_completeness()
{
    local items_json
    local limit_supported
    local item_count
    local total_count
    local has_total_count

    items_json="${1}"
    limit_supported="${2}"
    item_count=""
    total_count=""
    has_total_count=""

    if ! item_count=$(printf '%s\n' "${items_json}" | jq -r '.items | length'); then
        return 1
    fi

    if ! has_total_count=$(printf '%s\n' "${items_json}" | jq -r 'has("totalCount")'); then
        return 1
    fi

    if [ "${has_total_count}" = "true" ]; then
        if ! total_count=$(printf '%s\n' "${items_json}" | jq -r '.totalCount'); then
            return 1
        fi

        if [ "${total_count}" -gt "${item_count}" ]; then
            printf '[ERROR] Project item listing was truncated before all cards were retrieved.\n' >&2
            return 1
        fi

        return 0
    fi

    if [ "${limit_supported}" -eq 0 ]; then
        printf '[ERROR] Unable to verify that all Project items were retrieved.\n' >&2
        return 1
    fi

    return 0
}

# @purpose: Convert GitHub Project item JSON into cards.sh JSON output.
# @param $1 [Req]: Raw gh project item-list JSON.
# @param $2 [Opt]: Canonical Status filter.
build_cards_json()
{
    local items_json
    local status_filter

    items_json="${1}"
    status_filter="${2:-}"

    printf '%s\n' "${items_json}" | jq --arg status "${status_filter}" '
        [
            .items[]?
            | select((.content.type // "") == "Issue")
            | {
                issue: .content.number,
                title: (.content.title // ""),
                status: (.status // ""),
                url: (.content.url // "")
            }
            | select(.issue != null)
            | select(($status == "") or (.status == $status))
        ]
    '
}

# @purpose: Render card JSON as aligned human-readable output.
# @param $1 [Req]: cards.sh JSON array.
render_cards()
{
    local cards_json
    local card_count

    cards_json="${1}"
    card_count=""

    if ! card_count=$(printf '%s\n' "${cards_json}" | jq -r 'length'); then
        return 1
    fi

    if [ "${card_count}" -eq 0 ]; then
        printf '%s\n' "No cards found."
        return 0
    fi

    printf '%s\n' "${cards_json}" | jq -r '
        .[]
        | [
            (.issue | tostring),
            .status,
            (
                .title
                | gsub("\t"; "\\t")
                | gsub("\r"; "\\r")
                | gsub("\n"; "\\n")
            )
        ]
        | @tsv
    ' |
        while IFS="$(printf '\t')" read -r issue status title; do
            printf '#%-5s %-12s %s\n' "${issue}" "${status}" "${title}"
        done
}

# @purpose: Parse global command-line options.
# @param $1..$N [Opt] : Command-line arguments.
parse_args()
{
    local option

    option=""

    case "${1:-}" in
        --help)
            usage
            exit 0
            ;;
        --version)
            version
            exit 0
            ;;
        --*)
            die 2 "Unknown option: ${1}"
            ;;
    esac

    OPTIND=1

    while getopts ":hv" option; do
        case "${option}" in
            h)
                usage
                exit 0
                ;;
            v)
                version
                exit 0
                ;;
            :)
                die 2 "Option -${OPTARG} requires an argument."
                ;;
            \?)
                die 2 "Unknown option: -${OPTARG}"
                ;;
        esac
    done
}

# @purpose: List Project cards, optionally filtering by Status or emitting JSON.
# @param $1..$N [Opt] : list command options.
command_list()
{
    local status_filter
    local canonical_status
    local status_options
    local json_only
    local items_json
    local cards_json
    local limit_supported

    status_filter=""
    canonical_status=""
    status_options=""
    json_only="0"
    items_json=""
    cards_json=""
    limit_supported="0"

    while [ "$#" -gt 0 ]; do
        case "${1}" in
            -h|--help)
                printf '%s\n' "${LIST_USAGE}"
                return 0
                ;;
            -q|--json)
                json_only="1"
                shift
                ;;
            -s|--status)
                shift

                if [ "$#" -eq 0 ]; then
                    die 2 "Option --status requires an argument."
                fi

                status_filter="${1}"
                shift
                ;;
            --status=*)
                status_filter="${1#--status=}"
                shift
                ;;
            --)
                shift

                if [ "$#" -gt 0 ]; then
                    die 2 "Unexpected argument: ${1}"
                fi
                ;;
            -*)
                die 2 "Unknown list option: ${1}"
                ;;
            *)
                die 2 "Unexpected argument: ${1}"
                ;;
        esac
    done

    require_command "gh"
    require_command "jq"
    validate_auth

    if [ -n "${status_filter}" ]; then
        if ! status_options=$(discover_status_options); then
            die 6 "GitHub Project ${GH_CARD_PROJECT} was not found or is inaccessible."
        fi

        if ! canonical_status=$(canonicalize_status "${status_filter}" "${status_options}"); then
            die 9 "Invalid Status value: ${status_filter}"
        fi
    fi

    if supports_item_list_limit; then
        limit_supported="1"
    fi

    if ! items_json=$(fetch_project_items "${limit_supported}" 2>/dev/null); then
        die 6 "GitHub Project ${GH_CARD_PROJECT} was not found or is inaccessible."
    fi

    if ! validate_item_completeness "${items_json}" "${limit_supported}"; then
        exit 1
    fi

    if ! cards_json=$(build_cards_json "${items_json}" "${canonical_status}"); then
        die 1 "Failed to process GitHub Project item data."
    fi

    if [ "${json_only}" -eq 1 ]; then
        printf '%s\n' "${cards_json}"
        return 0
    fi

    if ! render_cards "${cards_json}"; then
        die 1 "Failed to render GitHub Project card data."
    fi
}

# @purpose: Delegate card creation to create-card.sh.
# @param $1..$N [Opt] : Arguments forwarded unchanged to create-card.sh.
command_create()
{
    local create_bin

    create_bin=""

    if ! create_bin=$(resolve_create_card); then
        die 3 "create-card.sh was not found."
    fi

    "${create_bin}" "$@"
}

# @purpose: Delegate card movement to move-card.sh.
# @param $1..$N [Opt] : Arguments forwarded unchanged to move-card.sh.
command_move()
{
    local move_bin

    move_bin=""

    if ! move_bin=$(resolve_move_card); then
        die 3 "move-card.sh was not found."
    fi

    "${move_bin}" "$@"
}

# @purpose: Open the configured GitHub Project in the default browser.
# @param $1..$N [Opt] : open command options.
command_open()
{
    while [ "$#" -gt 0 ]; do
        case "${1}" in
            -h|--help)
                printf '%s\n' "${OPEN_USAGE}"
                return 0
                ;;
            -*)
                die 2 "Unknown open option: ${1}"
                ;;
            *)
                die 2 "Unexpected argument: ${1}"
                ;;
        esac
    done

    require_command "gh"
    validate_auth

    if ! gh project view "${GH_CARD_PROJECT}" \
        --owner "${GH_CARD_PROJECT_OWNER}" \
        --web; then
        die 6 "GitHub Project ${GH_CARD_PROJECT} was not found or is inaccessible."
    fi
}

# @purpose: Consult the actual GitHub API limit.
command_rates()
{
    local rates limit remaining reset used

    rates=$(gh api rate_limit --jq '.resources.graphql')
    limit="$(printf '%s' "${rates}" | jq -r '.limit')"
    remaining="$(printf '%s' "${rates}" | jq -r '.remaining')"
    reset="$(printf '%s' "${rates}" | jq -r '.reset')"
    used="$(printf '%s' "${rates}" | jq -r '.used')"
    
    printf '\n\033[34mLimit:\033[m %s\n\033[34mUsage:\033[m %s/%s\n\033[34mReset:\033[m %s\n' \
        "$limit" \
        "$used" \
        "$remaining" \
        "$(date -r "$reset")"
    return 0
}

# @purpose: Dispatch cards.sh subcommands.
# @param $1..$N [Opt] : Command and command-specific arguments.
main()
{
    local command

    command=""

    parse_args "$@"

    if [ "$#" -eq 0 ]; then
        usage
        return 2
    fi

    command="${1}"
    shift

    case "${command}" in
        list|ls)
            command_list "$@"
            ;;
        create|new)
            command_create "$@"
            ;;
        move|mv)
            command_move "$@"
            ;;
        open|web)
            command_open "$@"
            ;;
        rates)
            command_rates "$@"
            ;;
        help)
            usage
            ;;
        *)
            die 2 "Unknown command: ${command}"
            ;;
    esac
}

main "$@"
