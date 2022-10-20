#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
shopt -s lastpipe

check() {
    command -v "${1}" >/dev/null 2>&1 || {
        echo >&2 "ERROR: ${1} is not installed or not found in \$PATH" >&2
        exit 1
    }
}

chart_name() {
    local chart_loc=
    chart_loc="${1}"
    yq eval .name "${chart_loc}/Chart.yaml" 2>/dev/null
}

chart_version() {
    local chart_loc=
    chart_loc="${1}"
    yq eval ".dependencies[0].version // .version " "${chart_loc}/Chart.yaml" 2>/dev/null
}

chart_registry_url() {
    local chart_loc=
    chart_loc="${1}"
    yq eval ".dependencies[0].repository" "${chart_loc}/Chart.yaml" 2>/dev/null
}
