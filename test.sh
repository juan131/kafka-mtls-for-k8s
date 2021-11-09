#!/usr/bin/env bash
#
# Kafka with MTLS for K8s 
# Test script
#
# shellcheck disable=SC1090
# shellcheck disable=SC1091
# shellcheck disable=SC2015
# shellcheck disable=SC2129

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
CHECK="\xE2\x9C\x94"
CHARTS=(
    "cert-manager"
    "zookeeper"
    "kafka"
)
CERTS=(
    "kafka-ca"
    "kafka-0-tls"
    "kafka-1-tls"
    "kafka-2-tls"
    "kafka-client"
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
    log "    $script [${YELLOW}-h${RESET}] [${YELLOW}-n ${GREEN}\"namespace\"${RESET}]"
    log ""
    log "${RED}DESCRIPTION${RESET}"
    log "    Script to test Kafka with MTLS on your K8s cluster."
    log ""
    log "    The options are as follow:"
    log ""
    log "      ${YELLOW}-n, --namespace ${GREEN}[namespace]${RESET}   Namespace to use."
    log "      ${YELLOW}-h, --help${RESET}                    Print this help menu."
    log ""
    log "${RED}EXAMPLES${RESET}"
    log "      $script --help"
    log "      $script --namespace \"kafka\""
    log ""
}
error_code=0
print_validation_error() {
    error "$1"
    error_code=1
}

help_menu=0
namespace="kafka"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help_menu=1
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

info "Ensuring charts were succesfully installed..."
for c in "${CHARTS[@]}"; do
    if [[ "$c" = "cert-manager" ]]; then
        silence helm status "$c" -n "kube-system" && info "$c $CHECK" || print_validation_error "$c wasn't installed successfully"
    else
        silence helm status "$c" -n "$namespace" && info "$c $CHECK" || print_validation_error "$c wasn't installed successfully"
    fi
done

info "Ensuring TLS certificates were generated..."
for c in "${CERTS[@]}"; do
    silence kubectl get certificates.cert-manager.io "$c" -n "$namespace" && info "$c cert $CHECK" || print_validation_error "$c Cert Manager certificate does not exist"
    silence kubectl get secret "$c" -n "$namespace" && info "$c TLS secret $CHECK" || print_validation_error "$c TLS secret does not exist"
done

info "Creating Kakfa Client pod..."
silence kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:2 -n "$namespace" --command -- sleep infinity

info "Obtaining TLS certs and creating client.properties for Kakfa Client..."
rm -f "${ROOT_DIR}/resources/client.properties"
cat > "${ROOT_DIR}/resources/client.properties" << EOF
security.protocol=SSL
ssl.keystore.type=PEM
ssl.truststore.type=PEM
EOF
kubectl get secret kafka-client -n "$namespace" -o json | jq -r '.data."ca.crt"' | base64 --decode | sed '$!s/$/ \\/' | echo "ssl.truststore.certificates=$(cat -)" >> "${ROOT_DIR}/resources/client.properties"
kubectl get secret kafka-client -n "$namespace" -o json | jq -r '.data."tls.crt"' | base64 --decode | sed '$!s/$/ \\/' | echo "ssl.keystore.certificate.chain=$(cat -)" >> "${ROOT_DIR}/resources/client.properties"
kubectl get secret kafka-client -n "$namespace" -o json | jq -r '.data."tls.key"' | base64 --decode | openssl pkcs8 -topk8 -nocrypt | sed '$!s/$/ \\/' | echo "ssl.keystore.key=$(cat -)" >> "${ROOT_DIR}/resources/client.properties"

info "Copying client.properties into Kakfa Client..."
kubectl cp -n "$namespace" "${ROOT_DIR}/resources/client.properties" kafka-client:/tmp/client.properties

info "Ensuring the Kafka Client can produce/consume messages..."
produceCommand="echo 'Hello World' | timeout 5 kafka-console-producer.sh --producer.config /tmp/client.properties --broker-list kafka-0.kafka-headless.$namespace.svc.cluster.local:9092,kafka-1.kafka-headless.$namespace.svc.cluster.local:9092,kafka-2.kafka-headless.$namespace.svc.cluster.local:9092 --topic test 2>/dev/null || echo 'error'"
consumeCommand="kafka-console-consumer.sh --consumer.config /tmp/client.properties --bootstrap-server kafka.$namespace.svc.cluster.local:9092 --topic test --from-beginning --timeout-ms 5000"
[[ -z "$(kubectl exec kafka-client --namespace "$namespace" -- bash -c "$produceCommand")" ]] && info "Produce $CHECK" || print_validation_error "Kafka Client cannot produce messages"
[[ "$(kubectl exec kafka-client --namespace "$namespace" -- bash -c "$consumeCommand" 2>/dev/null)" = *"Hello World"* ]] && info "Consume $CHECK" || print_validation_error "Kafka Client cannot consume messages"

info "Ensuring the Kafka Client cannot produce/consume messages without TLS properties..."
produceCommand="echo 'Hello World' | timeout 5 kafka-console-producer.sh --broker-list kafka-0.kafka-headless.$namespace.svc.cluster.local:9092,kafka-1.kafka-headless.$namespace.svc.cluster.local:9092,kafka-2.kafka-headless.$namespace.svc.cluster.local:9092 --topic test 2>/dev/null || echo error"
consumeCommand="kafka-console-consumer.sh --bootstrap-server kafka.$namespace.svc.cluster.local:9092 --topic test --from-beginning --timeout-ms 5000"
[[ -z "$(kubectl exec kafka-client --namespace "$namespace" -- bash -c "$produceCommand")" ]] && print_validation_error "Kafka Client can produce messages without TLS properties" || info "Produce fails $CHECK"
[[ "$(kubectl exec kafka-client --namespace "$namespace" -- bash -c "$consumeCommand" 2>/dev/null)" = *"Hello World"* ]] && print_validation_error "Kafka Client can consume messages without TLS properties" || info "Consume fails $CHECK"

info "Deleting Kakfa Client pod"
silence kubectl delete pod kafka-client -n "$namespace"

[[ "$error_code" -eq 0 ]] || exit "$error_code"
