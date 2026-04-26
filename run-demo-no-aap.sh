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

if [[ ! -r "${VARS_FILE}" ]]; then
  echo "missing ${VARS_FILE}; run ${SCRIPT_DIR}/prepare-demo.sh first" >&2
  exit 66
fi

export ANSIBLE_COLLECTIONS_PATH="${COLLECTION_PATHS}"
export PATH

run_playbook_local() {
  local name="$1"
  shift
  echo
  echo "==> ${name}"
  ansible-playbook -i 'localhost,' -e "@${VARS_FILE}" "$@"
}

run_playbook_inventory() {
  local name="$1"
  local inventory="$2"
  shift 2
  echo
  echo "==> ${name}"
  ansible-playbook -i "${inventory}" -e "@${VARS_FILE}" "$@"
}

cd "${PROJECT_ROOT}"

SECONDS=0
run_playbook_local "Deploy podinfo" "${SCRIPT_DIR}/playbooks/10-deploy-podinfo.yml"
run_playbook_local "Bootstrap demo IdM objects" "${SCRIPT_DIR}/playbooks/00-bootstrap-idm.yml"
run_playbook_local "Preflight IdM application identity" "${SCRIPT_DIR}/playbooks/15-preflight-identity.yml"
run_playbook_local "Issue cert, archive vault material, and patch route" "${SCRIPT_DIR}/playbooks/20-onboard-app-identity.yml"
run_playbook_local "Validate HTTPS route and vault proof" "${SCRIPT_DIR}/playbooks/30-validate-route.yml"
run_playbook_local "Preflight support access policy" "${SCRIPT_DIR}/playbooks/35-preflight-access-policy.yml"
run_playbook_local "Open support lease" "${SCRIPT_DIR}/playbooks/40-open-support-lease.yml"
run_playbook_local "Validate leased access" "${SCRIPT_DIR}/playbooks/45-validate-leased-access.yml"

echo
printf 'Elapsed: %02d:%02d\n' "$((SECONDS / 60))" "$((SECONDS % 60))"
