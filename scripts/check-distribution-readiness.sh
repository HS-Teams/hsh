#!/usr/bin/env bash

set -e
set -u
set -o pipefail

SCRIPT_NAME="check-distribution-readiness.sh"
PENDING_VALUE="TBD"

REQUIRED_METADATA_FIELDS=(
    "Release identifier"
    "Source commit"
    "Artifact manifest"
    "Corresponding source location"
    "Dependency/license report"
    "Release owner"
    "Legal reviewer"
    "Approval date"
)

REQUIRED_CHECK_IDS=(
    "SCOPE-CLASSIFIED"
    "SOURCE-PROVENANCE"
    "MODIFICATIONS-RECORDED"
    "COPYRIGHTS-PRESERVED"
    "GPL-COPY-INCLUDED"
    "CORRESPONDING-SOURCE-COMPLETE"
    "SOURCE-ACCESS-PAIRED"
    "INSTALLATION-INFORMATION-REVIEWED"
    "NO-FURTHER-RESTRICTIONS"
    "DEPENDENCIES-INVENTORIED"
    "THIRD-PARTY-NOTICES-INCLUDED"
    "RUST-AND-SDK-LICENSES-REVIEWED"
    "PROCESS-BOUNDARY-NOT-ASSUMED"
    "ARTIFACTS-HASHED"
    "SOURCE-MATCHES-BINARY"
    "LEGAL-REVIEW-APPROVED"
    "RELEASE-OWNER-APPROVED"
)

usage() {
    printf 'Usage: %s <completed-checklist>\n' "${SCRIPT_NAME}"
}

fail() {
    printf '%s: BLOCKED: %s\n' "${SCRIPT_NAME}" "$*" >&2
    exit 1
}

read_metadata_value() {
    local checklist_path
    local field_name

    checklist_path=$1
    field_name=$2

    awk -v prefix="${field_name}: " '
        index($0, prefix) == 1 {
            print substr($0, length(prefix) + 1)
            exit
        }
    ' "${checklist_path}"
}

require_metadata() {
    local checklist_path
    local field_name
    local field_value

    checklist_path=$1
    field_name=$2
    field_value=$(read_metadata_value "${checklist_path}" "${field_name}")

    [[ -n "${field_value}" ]] || fail "missing metadata field '${field_name}'."
    [[ "${field_value}" != "${PENDING_VALUE}" ]] ||
        fail "metadata field '${field_name}' is still ${PENDING_VALUE}."
}

require_approved_check() {
    local checklist_path
    local check_id

    checklist_path=$1
    check_id=$2

    awk -v check_id="${check_id}" '
        {
            normalized = tolower($0)
            marker = "- [x] `" tolower(check_id) "`"
            if (index(normalized, marker) == 1) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${checklist_path}" || fail "required check '${check_id}' is not approved."
}

validate_checklist() {
    local checklist_path
    local gate_status
    local field_name
    local check_id

    checklist_path=$1
    gate_status=$(read_metadata_value "${checklist_path}" "Gate status")
    [[ "${gate_status}" == "APPROVED" ]] ||
        fail "Gate status must be APPROVED."

    for field_name in "${REQUIRED_METADATA_FIELDS[@]}"; do
        require_metadata "${checklist_path}" "${field_name}"
    done

    for check_id in "${REQUIRED_CHECK_IDS[@]}"; do
        require_approved_check "${checklist_path}" "${check_id}"
    done

    if awk '/^[[:space:]]*- \[ \] / { found = 1 } END { exit(found ? 0 : 1) }' "${checklist_path}"; then
        fail "one or more checklist items remain unchecked."
    fi
}

main() {
    local checklist_path

    [[ "$#" -eq 1 ]] || {
        usage >&2
        exit 2
    }

    checklist_path=$1
    [[ -f "${checklist_path}" ]] || {
        printf '%s: checklist not found: %s\n' "${SCRIPT_NAME}" "${checklist_path}" >&2
        exit 2
    }

    validate_checklist "${checklist_path}"
    printf '%s: APPROVED: %s\n' "${SCRIPT_NAME}" "${checklist_path}"
}

main "$@"
