#!/usr/bin/env bash
set -euo pipefail

AAP_URL="${AAP_URL:-https://aap.apps.ocp.workshop.lan}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
REPO_URL="${REPO_URL:-https://github.com/gprocunier/eigenstate-openshift-app-demo.git}"
ORG_NAME="${ORG_NAME:-Default}"
INVENTORY_NAME="${INVENTORY_NAME:-eigenstate podinfo demo}"
PROJECT_NAME="${PROJECT_NAME:-eigenstate podinfo demo project}"
WORKFLOW_NAME="${WORKFLOW_NAME:-eigenstate podinfo governed onboarding}"
EE_NAME="${EE_NAME:-eigenstate podinfo demo EE}"
EE_IMAGE="${EE_IMAGE:-image-registry.openshift-image-registry.svc:5000/aap/eigenstate-openshift-app-demo-ee:latest}"
EE_PULL_POLICY="${EE_PULL_POLICY:-always}"
LAB_CREDENTIAL_TYPE_NAME="${LAB_CREDENTIAL_TYPE_NAME:-Eigenstate Demo Lab Password}"
LAB_CREDENTIAL_NAME="${LAB_CREDENTIAL_NAME:-eigenstate demo lab password}"
RUNTIME_CREDENTIAL_TYPE_NAME="${RUNTIME_CREDENTIAL_TYPE_NAME:-Eigenstate Demo EE Runtime}"
RUNTIME_CREDENTIAL_NAME="${RUNTIME_CREDENTIAL_NAME:-eigenstate demo EE runtime}"
GITHUB_CREDENTIAL_TYPE_NAME="${GITHUB_CREDENTIAL_TYPE_NAME:-Eigenstate GitHub Issue Gate}"
GITHUB_CREDENTIAL_NAME="${GITHUB_CREDENTIAL_NAME:-eigenstate demo GitHub issue gate}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-gprocunier/eigenstate-openshift-app-demo}"
GITHUB_GATE_TIMEOUT="${GITHUB_GATE_TIMEOUT:-1800}"
ENABLE_GITHUB_ISSUE_GATE="${ENABLE_GITHUB_ISSUE_GATE:-auto}"
SUPPORT_APPROVAL_TIMEOUT="${SUPPORT_APPROVAL_TIMEOUT:-3600}"
IPA_SERVER="${IPA_SERVER:-idm-01.workshop.lan}"
REALM="${REALM:-WORKSHOP.LAN}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-${HOME}/etc/kubeconfig}}"
IPA_CA_CERT_PATH="${IPA_CA_CERT_PATH:-${IPA_CERT:-/etc/ipa/ca.crt}}"
KRB5_CONFIG_PATH="${KRB5_CONFIG_PATH:-/etc/krb5.conf}"

if [[ -z "${AAP_PASSWORD:-}" ]]; then
  echo "AAP_PASSWORD is required" >&2
  exit 64
fi

if [[ -z "${LAB_DEFAULT_PASSWORD:-}" ]]; then
  echo "LAB_DEFAULT_PASSWORD is required" >&2
  exit 64
fi

if [[ "${ENABLE_GITHUB_ISSUE_GATE}" == "auto" ]]; then
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    ENABLE_GITHUB_ISSUE_GATE=true
  else
    ENABLE_GITHUB_ISSUE_GATE=false
  fi
fi

if [[ "${ENABLE_GITHUB_ISSUE_GATE}" == "true" && -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required when ENABLE_GITHUB_ISSUE_GATE=true" >&2
  exit 64
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 69
  }
}

require_cmd base64
require_cmd curl
require_cmd jq

b64_file() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0 "$1"
  else
    base64 "$1" | tr -d '\n'
  fi
}

b64_text() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

if [[ -z "${KUBECONFIG_B64:-}" ]]; then
  if [[ ! -r "${KUBECONFIG_PATH}" ]]; then
    echo "KUBECONFIG_B64 or a readable KUBECONFIG_PATH is required" >&2
    echo "Tried: ${KUBECONFIG_PATH}" >&2
    exit 66
  fi
  KUBECONFIG_B64="$(b64_file "${KUBECONFIG_PATH}")"
fi

if [[ -z "${IPA_CA_CERT_B64:-}" ]]; then
  if [[ ! -r "${IPA_CA_CERT_PATH}" ]]; then
    echo "IPA_CA_CERT_B64 or a readable IPA_CA_CERT_PATH is required" >&2
    echo "Tried: ${IPA_CA_CERT_PATH}" >&2
    exit 66
  fi
  IPA_CA_CERT_B64="$(b64_file "${IPA_CA_CERT_PATH}")"
fi

if [[ -z "${KRB5_CONFIG_B64:-}" ]]; then
  if [[ -r "${KRB5_CONFIG_PATH}" ]]; then
    KRB5_CONFIG_B64="$(b64_file "${KRB5_CONFIG_PATH}")"
  else
    KRB5_CONFIG_B64="$(
      cat <<EOF | b64_text
[libdefaults]
 default_realm = ${REALM}
 dns_lookup_realm = false
 dns_lookup_kdc = false
 rdns = false

[realms]
 ${REALM} = {
  kdc = ${IPA_SERVER}
  admin_server = ${IPA_SERVER}
 }

[domain_realm]
 .workshop.lan = ${REALM}
 workshop.lan = ${REALM}
EOF
    )"
  fi
fi

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
  if api GET "${path}" | jq -e --argjson id "${id}" '.results[]? | select(.id == $id)' >/dev/null; then
    return 0
  fi
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

org_id="$(get_named_id organizations "${ORG_NAME}")"
if [[ -z "${org_id}" ]]; then
  org_id="$(api POST /organizations/ "$(jq -n --arg name "${ORG_NAME}" '{name: $name}')" | jq -r '.id')"
fi

ee_payload="$(jq -n \
  --arg name "${EE_NAME}" \
  --arg image "${EE_IMAGE}" \
  --arg pull "${EE_PULL_POLICY}" \
  --argjson organization "${org_id}" \
  '{
    name: $name,
    image: $image,
    pull: $pull,
    organization: $organization
  }')"
ee_id="$(upsert_named execution_environments "${EE_NAME}" "${ee_payload}")"

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

runtime_type_payload="$(jq -n \
  --arg name "${RUNTIME_CREDENTIAL_TYPE_NAME}" \
  '{
    name: $name,
    kind: "cloud",
    inputs: {
      fields: [
        {id: "kubeconfig_b64", label: "Kubeconfig base64", type: "string", secret: true, multiline: true},
        {id: "krb5_config_b64", label: "krb5.conf base64", type: "string", secret: true, multiline: true},
        {id: "ipa_ca_cert_b64", label: "IPA CA certificate base64", type: "string", secret: true, multiline: true},
        {id: "ipa_server", label: "IPA server", type: "string"},
        {id: "realm", label: "Kerberos realm", type: "string"}
      ],
      required: ["kubeconfig_b64", "krb5_config_b64", "ipa_ca_cert_b64", "ipa_server", "realm"]
    },
    injectors: {
      env: {
        DEMO_KUBECONFIG_B64: "{{ kubeconfig_b64 }}",
        DEMO_KRB5_CONFIG_B64: "{{ krb5_config_b64 }}",
        DEMO_IPA_CA_CERT_B64: "{{ ipa_ca_cert_b64 }}",
        IPA_SERVER: "{{ ipa_server }}",
        REALM: "{{ realm }}"
      }
    }
  }')"
runtime_type_id="$(upsert_named credential_types "${RUNTIME_CREDENTIAL_TYPE_NAME}" "${runtime_type_payload}")"

runtime_credential_payload="$(jq -n \
  --arg name "${RUNTIME_CREDENTIAL_NAME}" \
  --argjson organization "${org_id}" \
  --argjson credential_type "${runtime_type_id}" \
  --arg kubeconfig_b64 "${KUBECONFIG_B64}" \
  --arg krb5_config_b64 "${KRB5_CONFIG_B64}" \
  --arg ipa_ca_cert_b64 "${IPA_CA_CERT_B64}" \
  --arg ipa_server "${IPA_SERVER}" \
  --arg realm "${REALM}" \
  '{
    name: $name,
    organization: $organization,
    credential_type: $credential_type,
    inputs: {
      kubeconfig_b64: $kubeconfig_b64,
      krb5_config_b64: $krb5_config_b64,
      ipa_ca_cert_b64: $ipa_ca_cert_b64,
      ipa_server: $ipa_server,
      realm: $realm
    }
  }')"
runtime_credential_id="$(upsert_named credentials "${RUNTIME_CREDENTIAL_NAME}" "${runtime_credential_payload}")"

github_credential_id=""
if [[ "${ENABLE_GITHUB_ISSUE_GATE}" == "true" ]]; then
  github_type_payload="$(jq -n \
    --arg name "${GITHUB_CREDENTIAL_TYPE_NAME}" \
    '{
      name: $name,
      kind: "cloud",
      inputs: {
        fields: [
          {id: "github_token", label: "GitHub token", type: "string", secret: true},
          {id: "github_repository", label: "GitHub repository", type: "string"},
          {id: "github_gate_timeout", label: "Gate timeout seconds", type: "string"}
        ],
        required: ["github_token", "github_repository"]
      },
      injectors: {
        env: {
          GITHUB_TOKEN: "{{ github_token }}",
          GITHUB_REPOSITORY: "{{ github_repository }}",
          GITHUB_GATE_TIMEOUT: "{{ github_gate_timeout }}"
        }
      }
    }')"
  github_type_id="$(upsert_named credential_types "${GITHUB_CREDENTIAL_TYPE_NAME}" "${github_type_payload}")"

  github_credential_payload="$(jq -n \
    --arg name "${GITHUB_CREDENTIAL_NAME}" \
    --argjson organization "${org_id}" \
    --argjson credential_type "${github_type_id}" \
    --arg github_token "${GITHUB_TOKEN}" \
    --arg github_repository "${GITHUB_REPOSITORY}" \
    --arg github_gate_timeout "${GITHUB_GATE_TIMEOUT}" \
    '{
      name: $name,
      organization: $organization,
      credential_type: $credential_type,
      inputs: {
        github_token: $github_token,
        github_repository: $github_repository,
        github_gate_timeout: $github_gate_timeout
      }
    }')"
  github_credential_id="$(upsert_named credentials "${GITHUB_CREDENTIAL_NAME}" "${github_credential_payload}")"
fi

inventory_payload="$(jq -n \
  --arg name "${INVENTORY_NAME}" \
  --argjson organization "${org_id}" \
  '{name: $name, organization: $organization}')"
inventory_id="$(upsert_named inventories "${INVENTORY_NAME}" "${inventory_payload}")"

host_payload="$(jq -n \
  --arg name localhost \
  --argjson inventory "${inventory_id}" \
  '{
    name: $name,
    inventory: $inventory,
    variables: ({
      ansible_connection: "local",
      ansible_python_interpreter: "{{ ansible_playbook_python }}"
    } | tostring)
  }')"
host_id="$(get_named_id hosts localhost)"
if [[ -n "${host_id}" ]]; then
  host_update_payload="$(jq -n \
    --arg name localhost \
    '{
      name: $name,
      variables: ({
        ansible_connection: "local",
        ansible_python_interpreter: "{{ ansible_playbook_python }}"
      } | tostring)
    }')"
  api PATCH "/hosts/${host_id}/" "${host_update_payload}" >/dev/null
else
  api POST /hosts/ "${host_payload}" >/dev/null
fi

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
    --argjson execution_environment "${ee_id}" \
    --arg demo_step "${step}" \
    '{
      name: $name,
      job_type: "run",
      inventory: $inventory,
      project: $project,
      execution_environment: $execution_environment,
      playbook: "aap/playbooks/run-ee-demo-step.yml",
      extra_vars: ({demo_step: $demo_step} | tostring),
      ask_variables_on_launch: true,
      verbosity: 1
    }')"
  jt_id="$(upsert_named job_templates "${jt_name}" "${jt_payload}")"
  associate_id "/job_templates/${jt_id}/credentials/" "${lab_credential_id}"
  associate_id "/job_templates/${jt_id}/credentials/" "${runtime_credential_id}"
  job_template_ids["${step}"]="${jt_id}"
done

github_gate_job_template_id=""
if [[ "${ENABLE_GITHUB_ISSUE_GATE}" == "true" ]]; then
  github_gate_payload="$(jq -n \
    --arg name "eigenstate podinfo GitHub support approval gate" \
    --argjson inventory "${inventory_id}" \
    --argjson project "${project_id}" \
    --argjson execution_environment "${ee_id}" \
    '{
      name: $name,
      job_type: "run",
      inventory: $inventory,
      project: $project,
      execution_environment: $execution_environment,
      playbook: "aap/playbooks/github-issue-gate.yml",
      ask_variables_on_launch: true,
      verbosity: 1
    }')"
  github_gate_job_template_id="$(upsert_named job_templates "eigenstate podinfo GitHub support approval gate" "${github_gate_payload}")"
  associate_id "/job_templates/${github_gate_job_template_id}/credentials/" "${github_credential_id}"
fi

workflow_payload="$(jq -n \
  --arg name "${WORKFLOW_NAME}" \
  --argjson organization "${org_id}" \
  '{
    name: $name,
    organization: $organization,
    survey_enabled: true,
    ask_variables_on_launch: true
  }')"
workflow_id="$(upsert_named workflow_job_templates "${WORKFLOW_NAME}" "${workflow_payload}")"

survey_payload="$(jq -n \
  '{
    name: "Support lease request",
    description: "Context for the AAP and GitHub approval gates before opening support access.",
    spec: [
      {
        question_name: "Support ticket",
        question_description: "Change, incident, or demo ticket reference.",
        required: true,
        type: "text",
        variable: "support_ticket",
        default: "DEMO-1",
        min: 0,
        max: 128
      },
      {
        question_name: "Support requester",
        question_description: "Person or team requesting the temporary access lease.",
        required: true,
        type: "text",
        variable: "support_requester",
        default: "demo-operator",
        min: 0,
        max: 128
      },
      {
        question_name: "Support reason",
        question_description: "Business or operational reason for opening the support lease.",
        required: true,
        type: "textarea",
        variable: "support_reason",
        default: "Validate temporary support access for the podinfo route.",
        min: 0,
        max: 2048
      },
      {
        question_name: "Lease duration",
        question_description: "IdM principal expiration offset passed to the demo runtime.",
        required: true,
        type: "text",
        variable: "lease_duration",
        default: "00:10",
        min: 0,
        max: 32
      }
    ]
  }')"
api POST "/workflow_job_templates/${workflow_id}/survey_spec/" "${survey_payload}" >/dev/null

existing_nodes="$(api GET "/workflow_job_templates/${workflow_id}/workflow_nodes/" | jq -r '.results[].id')"
for node_id in ${existing_nodes}; do
  api DELETE "/workflow_job_template_nodes/${node_id}/" >/dev/null
done

workflow_steps_before_approval=(
  deploy
  bootstrap
  identity_preflight
  onboard
  validate_route
  access_preflight
)

workflow_steps_after_approval=(
  open_lease
  validate_leased_access
  expire_lease
)

previous_node_id=""
for step in "${workflow_steps_before_approval[@]}"; do
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

approval_payload="$(jq -n \
  --argjson workflow_job_template "${workflow_id}" \
  --argjson timeout "${SUPPORT_APPROVAL_TIMEOUT}" \
  '{
    identifier: "approve_support_lease",
    workflow_job_template: $workflow_job_template,
    approval_node: {
      name: "Approve support lease",
      description: "Approve opening the temporary podinfo support access lease.",
      timeout: $timeout
    }
  }')"
approval_node_id="$(api POST "/workflow_job_templates/${workflow_id}/workflow_nodes/" "${approval_payload}" | jq -r '.id')"
if [[ -n "${previous_node_id}" ]]; then
  associate_id "/workflow_job_template_nodes/${previous_node_id}/success_nodes/" "${approval_node_id}"
fi
previous_node_id="${approval_node_id}"

if [[ "${ENABLE_GITHUB_ISSUE_GATE}" == "true" ]]; then
  github_gate_node_payload="$(jq -n \
    --argjson workflow_job_template "${workflow_id}" \
    --argjson unified_job_template "${github_gate_job_template_id}" \
    '{
      identifier: "github_issue_gate",
      workflow_job_template: $workflow_job_template,
      unified_job_template: $unified_job_template
    }')"
  github_gate_node_id="$(api POST "/workflow_job_templates/${workflow_id}/workflow_nodes/" "${github_gate_node_payload}" | jq -r '.id')"
  associate_id "/workflow_job_template_nodes/${previous_node_id}/success_nodes/" "${github_gate_node_id}"
  previous_node_id="${github_gate_node_id}"
fi

for step in "${workflow_steps_after_approval[@]}"; do
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
echo "Execution environment: ${EE_NAME} (${EE_IMAGE})"
echo "Native support approval: enabled"
echo "GitHub issue gate: ${ENABLE_GITHUB_ISSUE_GATE}"
