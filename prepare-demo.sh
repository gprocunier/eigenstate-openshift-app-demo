#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
DEMO_DIR="${DEMO_DIR:-/tmp/demo}"
VARS_FILE="${DEMO_DIR}/podinfo-vars.yml"
COLLECTION_PATHS="${ANSIBLE_COLLECTIONS_PATH:-${PROJECT_ROOT}/.ansible/collections:${HOME}/.ansible/collections:/usr/share/ansible/collections:/usr/local/share/ansible/collections}"

if ! command -v oc >/dev/null 2>&1; then
  for tools_dir in /opt/openshift/aws-metal-openshift-demo/generated/tools/*/bin; do
    if [[ -x "${tools_dir}/oc" ]]; then
      PATH="${tools_dir}:${PATH}"
      break
    fi
  done
fi

if [[ -z "${KUBECONFIG:-}" && -r "${HOME}/etc/kubeconfig" ]]; then
  export KUBECONFIG="${HOME}/etc/kubeconfig"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 69
  }
}

require_cmd ansible-playbook
require_cmd oc
require_cmd klist
require_cmd openssl

export ANSIBLE_COLLECTIONS_PATH="${COLLECTION_PATHS}"
export PATH

mkdir -p "${DEMO_DIR}"
chmod 700 "${DEMO_DIR}"

CLUSTER_DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
APP_FQDN="${APP_FQDN:-podinfo.${CLUSTER_DOMAIN}}"
SERVICE_PRINCIPAL="${SERVICE_PRINCIPAL:-HTTP/${APP_FQDN}}"
DNS_ZONE="${DNS_ZONE:-${CLUSTER_DOMAIN#*.}}"
DNS_RECORD_NAME="${DNS_RECORD_NAME:-*.${CLUSTER_DOMAIN%%.*}}"

cat > "${VARS_FILE}" <<EOF
---
demo_namespace: ${DEMO_NAMESPACE:-ipa-demo}
app_name: ${APP_NAME:-podinfo}
app_image: ${APP_IMAGE:-ghcr.io/stefanprodan/podinfo:6.7.1}
app_port: ${APP_PORT:-9898}
service_name: ${SERVICE_NAME:-podinfo}
route_name: ${ROUTE_NAME:-podinfo}
route_fqdn: ${APP_FQDN}
service_principal: ${SERVICE_PRINCIPAL}
dns_zone: ${DNS_ZONE}
dns_record_name: "${DNS_RECORD_NAME}"
tls_secret: ${TLS_SECRET:-podinfo-idm-tls}
vault_name: ${VAULT_NAME:-podinfo-tls}
lease_user: ${LEASE_USER:-podinfo-support-autobot}
lease_group: ${LEASE_GROUP:-podinfo-support}
lease_duration: "${LEASE_DURATION:-00:10}"
validation_host: ${VALIDATION_HOST:-mirror-registry.workshop.lan}
support_sudo_rule: ${SUPPORT_SUDO_RULE:-podinfo-support-validation}
EOF

echo "==> Wrote ${VARS_FILE}"
echo "Route FQDN: ${APP_FQDN}"
echo "Service principal: ${SERVICE_PRINCIPAL}"
echo "IdM DNS record: ${DNS_RECORD_NAME}.${DNS_ZONE}"
echo "Collection path: ${ANSIBLE_COLLECTIONS_PATH}"

if ! klist >/dev/null 2>&1 && [[ -z "${IPA_ADMIN_PASSWORD:-}" && -z "${IPA_KEYTAB:-}" ]]; then
  echo "warning: no current Kerberos ticket and neither IPA_ADMIN_PASSWORD nor IPA_KEYTAB is set" >&2
fi
