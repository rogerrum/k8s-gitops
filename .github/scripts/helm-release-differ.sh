#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$(dirname "${0}")/lib/functions.sh"

set -o errexit
set -o nounset
set -o pipefail
shopt -s lastpipe

show_help() {
cat << EOF
Usage: $(basename "$0") <options>
    -h, --help                      Display help
    --source-chart                  Original helm chart location
    --target-chart                  New helm chart location
    --remove-common-labels          Remove common labels from manifests
EOF
}

main() {
    local source_chart_location=
    local target_chart_location=
    local remove_common_labels=
    parse_command_line "$@"
    check "helm"
    check "yq"
    entry
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            --source-chart)
                if [[ -n "${2:-}" ]]; then
                    source_chart_location="$2"
                    shift
                else
                    echo "ERROR: '--source-chart' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --target-chart)
                if [[ -n "${2:-}" ]]; then
                    target_chart_location="$2"
                    shift
                else
                    echo "ERROR: '--target-chart' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --remove-common-labels)
                remove_common_labels=true
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    if [[ -z "${source_chart_location}" ]]; then
        echo "ERROR: '--source-chart' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "${target_chart_location}" ]]; then
        echo "ERROR: '--target-chart' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$remove_common_labels" ]]; then
        remove_common_labels=false
    fi
}

_resources() {
    local chart_location=${1}

    local resources=

#    helm dep update "$chart_location" > /dev/null 2>&1

    resources=$(helm template "${chart_location}")
    if [[ "${remove_common_labels}" == "true" ]]; then
        labels='.metadata.labels."helm.sh/chart"'
        labels+=',.metadata.labels.chart'
        labels+=',.metadata.labels."app.kubernetes.io/version"'
        labels+=',.spec.template.metadata.labels."helm.sh/chart"'
        labels+=',.spec.template.metadata.labels.chart'
        labels+=',.spec.template.metadata.labels."app.kubernetes.io/version"'
        echo "${resources}" | yq eval "del($labels)" -
    else
        echo "${resources}"
    fi
}

entry() {
    local comments=

    source_chart_name=$(chart_name "${source_chart_location}")
    source_chart_version=$(chart_version "${source_chart_location}")
    source_chart_registry_url=$(chart_registry_url "${source_chart_location}")

    source_resources=$(_resources "${source_chart_location}")
    echo "${source_resources}" > /tmp/source_resources

    target_chart_version=$(chart_version "${target_chart_location}")
    target_chart_name=$(chart_name "${target_chart_location}")
    target_chart_registry_url=$(chart_registry_url "${target_chart_location}")
    target_resources=$(_resources "${target_chart_location}")
    echo "${target_resources}" > /tmp/target_resources

    # Diff the files and always return true
    diff -u /tmp/source_resources /tmp/target_resources > /tmp/diff || true
    # Remove the filenames
    sed -i -e '1,2d' /tmp/diff

    # Store the comment in an array
    comments=()

    # shellcheck disable=SC2016
    comments+=( "$(printf 'Path: `%s`' "${target_chart_location}")" )
    if [[ "${source_chart_name}" != "${target_chart_name}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Chart: `%s` -> `%s`' "${source_chart_name}" "${target_chart_name}")" )
    fi
    if [[ "${source_chart_version}" != "${target_chart_version}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Version: `%s` -> `%s`' "${source_chart_version}" "${target_chart_version}")" )
    fi
    if [[ "${source_chart_registry_url}" != "${target_chart_registry_url}" ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf 'Registry URL: `%s` -> `%s`' "${source_chart_registry_url}" "${target_chart_registry_url}")" )
    fi
    comments+=( "$(printf '\n\n')" )
    if [[ -f /tmp/diff && -s /tmp/diff ]]; then
        # shellcheck disable=SC2016
        comments+=( "$(printf '```diff\n%s\n```' "$(cat /tmp/diff)")" )
    else
        # shellcheck disable=SC2016
        comments+=( "$(printf '```\nNo changes in detected in resources\n```')" )
    fi

    # Join the array with a new line and print it
    printf "%s\n" "${comments[@]}"
}

main "$@"
