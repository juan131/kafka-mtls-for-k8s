#!/usr/bin/env bash
#
# Kafka with MTLS for K8s 
# Setup script
#
# shellcheck disable=SC1090
# shellcheck disable=SC1091

# Copyright (c) 2021 Bitnami
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# Constants
ROOT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd)"
CHARTS=(
    "cert-manager"
    "zookeeper"
    "kafka"
)

# Load Libraries
. "${ROOT_DIR}/lib/liblog.sh"
. "${ROOT_DIR}/lib/libutil.sh"

# Axiliar functions
print_menu() {
    local script
    script=$(basename "${BASH_SOURCE[0]}")
    log "${RED}NAME${RESET}"
    log "    $(basename -s .sh "${BASH_SOURCE[0]}")"
    log ""
    log "${RED}SYNOPSIS${RESET}"
    log "    $script [${YELLOW}-uh${RESET}] [${YELLOW}-n ${GREEN}\"namespace\"${RESET}] [${YELLOW}--disable-zookeeper${RESET}]"
    log ""
    log "${RED}DESCRIPTION${RESET}"
    log "    Script to setup Kafka with MTLS on your K8s cluster."
    log ""
    log "    The options are as follow:"
    log ""
    log "      ${YELLOW}-n, --namespace ${GREEN}[namespace]${RESET}   Namespace to use."
    log "      ${YELLOW}-h, --help${RESET}                    Print this help menu."
    log "      ${YELLOW}--disable-zookeeper${RESET}           Disable deploying Zookeeper resources."
    log "      ${YELLOW}-u, --dry-run${RESET}                 Enable \"dry run\" mode."
    log ""
    log "${RED}EXAMPLES${RESET}"
    log "      $script --help"
    log "      $script --namespace \"kafka\""
    log ""
}

help_menu=0
dry_run=0
namespace="kafka"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help_menu=1
            ;;
        -u|--dry-run)
            dry_run=1
            ;;
        --disable-zookeeper)
            for c in "${!CHARTS[@]}"; do                    
                [[ "${CHARTS[c]}" = "zookeeper" ]] && unset 'CHARTS[c]'
            done
            ;;
        -n|--namespace)
            shift; namespace="${1:?missing namespace}"
            ;;
        *)
            error "Invalid command line flag $1" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ "$help_menu" -eq 1 ]]; then
    print_menu
    exit 0
fi
if [[ "$dry_run" -eq 1 ]]; then
    info "DRY RUN mode enabled!"
    info "Charts to deploy:"
    for c in "${CHARTS[@]}"; do
        if [[ "$c" = "cert-manager" ]]; then
            info "Chart bitnami/${c} into namespace 'kube-system'"
        else
            info "Chart bitnami/${c} into namespace '$namespace'"
        fi
    done
    exit 0
fi

info "Adding 'bitnami' chart repository..."
silence helm repo add bitnami https://charts.bitnami.com/bitnami
info "Updating bitnami chart repository..."
silence helm repo update bitnami
info "Creating required namespace..."
silence kubectl create ns "$namespace" || true
for c in "${CHARTS[@]}"; do
    if [[ "$c" = "cert-manager" ]]; then
        info "Installing $c in namespace 'kube-system'..."
        silence helm install --wait "$c" "bitnami/${c}" -f "${ROOT_DIR}/values/${c}-values.yaml" -n "kube-system"
        info "Creating required issuers and certificates..."
        silence kubectl apply -f "${ROOT_DIR}/resources/ca.yaml" -n "$namespace"
        silence kubectl apply -f "${ROOT_DIR}/resources/certs.yaml" -n "$namespace"
    else
        info "Installing $c in namespace '$namespace'..."
        silence helm install --wait "$c" "bitnami/${c}" -f "${ROOT_DIR}/values/${c}-values.yaml" -n "$namespace"
    fi
done
