#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
VARS_FILE="${DEMO_VARS_FILE:-/tmp/demo/podinfo-vars.yml}"
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

export ANSIBLE_COLLECTIONS_PATH="${COLLECTION_PATHS}"
export PATH

cd "${PROJECT_ROOT}"

if [[ -r "${VARS_FILE}" ]]; then
  ansible-playbook -i 'localhost,' -e "@${VARS_FILE}" \
    "${SCRIPT_DIR}/playbooks/50-expire-support-lease.yml" || true
  ansible-playbook -i 'localhost,' -e "@${VARS_FILE}" \
    "${SCRIPT_DIR}/playbooks/90-cleanup-openshift.yml" || true
else
  oc delete project "${DEMO_NAMESPACE:-ipa-demo}" --ignore-not-found=true || true
fi

kdestroy -A >/dev/null 2>&1 || true
rm -rf /tmp/demo
echo "==> Cleanup complete"
