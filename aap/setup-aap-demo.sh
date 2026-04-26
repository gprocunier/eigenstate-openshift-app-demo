#!/usr/bin/env bash
set -euo pipefail

AAP_URL="${AAP_URL:-https://aap.apps.ocp.workshop.lan}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
REPO_URL="${REPO_URL:-https://github.com/gprocunier/eigenstate-openshift-app-demo.git}"
ORG_NAME="${ORG_NAME:-Default}"
INVENTORY_NAME="${INVENTORY_NAME:-eigenstate podinfo demo}"
PROJECT_NAME="${PROJECT_NAME:-eigenstate podinfo demo project}"
WORKFLOW_NAME="${WORKFLOW_NAME:-eigenstate podinfo governed onboarding}"
MACHINE_CREDENTIAL_NAME="${MACHINE_CREDENTIAL_NAME:-eigenstate demo bastion ssh}"
LAB_CREDENTIAL_TYPE_NAME="${LAB_CREDENTIAL_TYPE_NAME:-Eigenstate Demo Lab Password}"
LAB_CREDENTIAL_NAME="${LAB_CREDENTIAL_NAME:-eigenstate demo lab password}"
BASTION_HOST_NAME="${BASTION_HOST_NAME:-bastion-01}"
BASTION_HOST="${BASTION_HOST:-172.16.0.30}"
BASTION_USER="${BASTION_USER:-cloud-user}"
BASTION_KEY_PATH="${BASTION_KEY_PATH:-/tmp/demo/aap-demo-bastion-ed25519}"

if [[ -z "${AAP_PASSWORD:-}" ]]; then
  echo "AAP_PASSWORD is required" >&2
  exit 64
fi

if [[ -z "${LAB_DEFAULT_PASSWORD:-}" ]]; then
  echo "LAB_DEFAULT_PASSWORD is required" >&2
  exit 64
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 69
  }
}

require_cmd curl
require_cmd jq
require_cmd ssh-keygen

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local tmp
  tmp="$(mktemp)"
  local status
  if [[ -n "${body}" ]]; then
    status="$(curl -sk -u "${AAP_USERNAME}:${AAP_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -o "${tmp}" -w '%{http_code}' \
      -X "${method}" --data "${body}" \
      "${AAP_URL}/api/controller/v2${path}")"
  else
    status="$(curl -sk -u "${AAP_USERNAME}:${AAP_PASSWORD}" \
      -o "${tmp}" -w '%{http_code}' \
      -X "${method}" \
      "${AAP_URL}/api/controller/v2${path}")"
  fi
  if [[ ! "${status}" =~ ^2 ]]; then
    echo "AAP API ${method} ${path} failed with HTTP ${status}" >&2
    sed 's/^/  /' "${tmp}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  cat "${tmp}"
  rm -f "${tmp}"
}

urlencode() {
  jq -nr --arg value "$1" '$value|@uri'
}

get_named_id() {
  local collection="$1"
  local name="$2"
  api GET "/${collection}/?name=$(urlencode "${name}")" | jq -r '.results[0].id // empty'
}

upsert_named() {
  local collection="$1"
  local name="$2"
  local payload="$3"
  local id
  id="$(get_named_id "${collection}" "${name}")"
  if [[ -n "${id}" ]]; then
    api PATCH "/${collection}/${id}/" "${payload}" >/dev/null
    echo "${id}"
  else
    api POST "/${collection}/" "${payload}" | jq -r '.id'
  fi
}

associate_id() {
  local path="$1"
  local id="$2"
  api POST "${path}" "$(jq -n --argjson id "${id}" '{id: $id}')" >/dev/null
}

wait_unified_job() {
  local path="$1"
  local label="$2"
  local status
  while true; do
    status="$(api GET "${path}" | jq -r '.status')"
    echo "${label}: ${status}"
    case "${status}" in
      successful)
        return 0
        ;;
      failed|error|canceled)
        return 1
        ;;
    esac
    sleep 5
  done
}

mkdir -p "$(dirname "${BASTION_KEY_PATH}")"
chmod 700 "$(dirname "${BASTION_KEY_PATH}")"
if [[ ! -f "${BASTION_KEY_PATH}" ]]; then
  ssh-keygen -t ed25519 -N '' -C eigenstate-aap-demo -f "${BASTION_KEY_PATH}" >/dev/null
fi
chmod 600 "${BASTION_KEY_PATH}"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "${HOME}/.ssh/authorized_keys"
chmod 600 "${HOME}/.ssh/authorized_keys"
if ! grep -qxF "$(cat "${BASTION_KEY_PATH}.pub")" "${HOME}/.ssh/authorized_keys"; then
  cat "${BASTION_KEY_PATH}.pub" >> "${HOME}/.ssh/authorized_keys"
fi

org_id="$(get_named_id organizations "${ORG_NAME}")"
if [[ -z "${org_id}" ]]; then
  org_id="$(api POST /organizations/ "$(jq -n --arg name "${ORG_NAME}" '{name: $name}')" | jq -r '.id')"
fi

machine_type_id="$(get_named_id credential_types Machine)"
if [[ -z "${machine_type_id}" ]]; then
  echo "AAP Machine credential type was not found" >&2
  exit 1
fi

lab_type_payload="$(jq -n \
  --arg name "${LAB_CREDENTIAL_TYPE_NAME}" \
  '{
    name: $name,
    kind: "cloud",
    inputs: {
      fields: [
        {id: "lab_password", label: "Lab default password", type: "string", secret: true}
      ],
      required: ["lab_password"]
    },
    injectors: {
      env: {
        LAB_DEFAULT_PASSWORD: "{{ lab_password }}",
        IPA_ADMIN_PASSWORD: "{{ lab_password }}",
        SUPPORT_USER_PASSWORD: "{{ lab_password }}"
      }
    }
  }')"
lab_type_id="$(upsert_named credential_types "${LAB_CREDENTIAL_TYPE_NAME}" "${lab_type_payload}")"

private_key="$(cat "${BASTION_KEY_PATH}")"
machine_credential_payload="$(jq -n \
  --arg name "${MACHINE_CREDENTIAL_NAME}" \
  --argjson organization "${org_id}" \
  --argjson credential_type "${machine_type_id}" \
  --arg username "${BASTION_USER}" \
  --arg ssh_key_data "${private_key}" \
  '{
    name: $name,
    organization: $organization,
    credential_type: $credential_type,
    inputs: {
      username: $username,
      ssh_key_data: $ssh_key_data
    }
  }')"
machine_credential_id="$(upsert_named credentials "${MACHINE_CREDENTIAL_NAME}" "${machine_credential_payload}")"

lab_credential_payload="$(jq -n \
  --arg name "${LAB_CREDENTIAL_NAME}" \
  --argjson organization "${org_id}" \
  --argjson credential_type "${lab_type_id}" \
  --arg lab_password "${LAB_DEFAULT_PASSWORD}" \
  '{
    name: $name,
    organization: $organization,
    credential_type: $credential_type,
    inputs: {
      lab_password: $lab_password
    }
  }')"
lab_credential_id="$(upsert_named credentials "${LAB_CREDENTIAL_NAME}" "${lab_credential_payload}")"

inventory_payload="$(jq -n \
  --arg name "${INVENTORY_NAME}" \
  --argjson organization "${org_id}" \
  '{name: $name, organization: $organization}')"
inventory_id="$(upsert_named inventories "${INVENTORY_NAME}" "${inventory_payload}")"

host_payload="$(jq -n \
  --arg name "${BASTION_HOST_NAME}" \
  --argjson inventory "${inventory_id}" \
  --arg ansible_host "${BASTION_HOST}" \
  --arg ansible_user "${BASTION_USER}" \
  '{
    name: $name,
    inventory: $inventory,
    variables: ({
      ansible_host: $ansible_host,
      ansible_user: $ansible_user,
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    } | tostring)
  }')"
upsert_named hosts "${BASTION_HOST_NAME}" "${host_payload}" >/dev/null

project_payload="$(jq -n \
  --arg name "${PROJECT_NAME}" \
  --argjson organization "${org_id}" \
  --arg scm_url "${REPO_URL}" \
  '{
    name: $name,
    organization: $organization,
    scm_type: "git",
    scm_url: $scm_url,
    scm_clean: true,
    scm_update_on_launch: true,
    scm_update_cache_timeout: 0
  }')"
project_id="$(upsert_named projects "${PROJECT_NAME}" "${project_payload}")"

project_update="$(api POST "/projects/${project_id}/update/" '{}')"
project_update_id="$(jq -r '.id // empty' <<<"${project_update}")"
if [[ -n "${project_update_id}" ]]; then
  wait_unified_job "/project_updates/${project_update_id}/" "Project sync"
fi

declare -A step_names=(
  [deploy]="podinfo deploy"
  [bootstrap]="podinfo bootstrap IdM"
  [identity_preflight]="podinfo identity preflight"
  [onboard]="podinfo onboard identity"
  [validate_route]="podinfo validate route"
  [access_preflight]="podinfo access policy preflight"
  [open_lease]="podinfo open support lease"
  [validate_leased_access]="podinfo validate leased access"
  [expire_lease]="podinfo expire support lease"
)

ordered_steps=(
  deploy
  bootstrap
  identity_preflight
  onboard
  validate_route
  access_preflight
  open_lease
  validate_leased_access
  expire_lease
)

declare -A job_template_ids=()
for step in "${ordered_steps[@]}"; do
  jt_name="eigenstate ${step_names[${step}]}"
  jt_payload="$(jq -n \
    --arg name "${jt_name}" \
    --argjson inventory "${inventory_id}" \
    --argjson project "${project_id}" \
    --arg demo_step "${step}" \
    '{
      name: $name,
      job_type: "run",
      inventory: $inventory,
      project: $project,
      playbook: "aap/playbooks/run-bastion-demo-step.yml",
      extra_vars: ({demo_step: $demo_step} | tostring),
      verbosity: 1
    }')"
  jt_id="$(upsert_named job_templates "${jt_name}" "${jt_payload}")"
  associate_id "/job_templates/${jt_id}/credentials/" "${machine_credential_id}"
  associate_id "/job_templates/${jt_id}/credentials/" "${lab_credential_id}"
  job_template_ids["${step}"]="${jt_id}"
done

workflow_payload="$(jq -n \
  --arg name "${WORKFLOW_NAME}" \
  --argjson organization "${org_id}" \
  '{name: $name, organization: $organization}')"
workflow_id="$(upsert_named workflow_job_templates "${WORKFLOW_NAME}" "${workflow_payload}")"

existing_nodes="$(api GET "/workflow_job_templates/${workflow_id}/workflow_nodes/" | jq -r '.results[].id')"
for node_id in ${existing_nodes}; do
  api DELETE "/workflow_job_template_nodes/${node_id}/" >/dev/null
done

previous_node_id=""
for step in "${ordered_steps[@]}"; do
  node_payload="$(jq -n \
    --arg identifier "${step}" \
    --argjson workflow_job_template "${workflow_id}" \
    --argjson unified_job_template "${job_template_ids[${step}]}" \
    '{
      identifier: $identifier,
      workflow_job_template: $workflow_job_template,
      unified_job_template: $unified_job_template
    }')"
  node_id="$(api POST "/workflow_job_templates/${workflow_id}/workflow_nodes/" "${node_payload}" | jq -r '.id')"
  if [[ -n "${previous_node_id}" ]]; then
    associate_id "/workflow_job_template_nodes/${previous_node_id}/success_nodes/" "${node_id}"
  fi
  previous_node_id="${node_id}"
done

echo "AAP demo objects are ready."
echo "Workflow: ${WORKFLOW_NAME}"
echo "Project: ${PROJECT_NAME}"
echo "Inventory: ${INVENTORY_NAME}"
