#!/usr/bin/env bash
set -euo pipefail

AAP_URL="${AAP_URL:-https://aap.apps.ocp.workshop.lan}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
WORKFLOW_NAME="${WORKFLOW_NAME:-eigenstate podinfo governed onboarding}"
SUPPORT_TICKET="${SUPPORT_TICKET:-DEMO-1}"
SUPPORT_REQUESTER="${SUPPORT_REQUESTER:-demo-operator}"
SUPPORT_REASON="${SUPPORT_REASON:-Validate temporary support access for the podinfo route.}"
LEASE_DURATION="${LEASE_DURATION:-00:10}"

if [[ -z "${AAP_PASSWORD:-}" ]]; then
  echo "AAP_PASSWORD is required" >&2
  exit 64
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

workflow_id="$(api GET "/workflow_job_templates/?name=$(urlencode "${WORKFLOW_NAME}")" | jq -r '.results[0].id // empty')"
if [[ -z "${workflow_id}" ]]; then
  echo "workflow not found: ${WORKFLOW_NAME}" >&2
  echo "Run aap/setup-aap-demo.sh first." >&2
  exit 66
fi

launch_payload="$(jq -n \
  --arg support_ticket "${SUPPORT_TICKET}" \
  --arg support_requester "${SUPPORT_REQUESTER}" \
  --arg support_reason "${SUPPORT_REASON}" \
  --arg lease_duration "${LEASE_DURATION}" \
  '{
    extra_vars: {
      support_ticket: $support_ticket,
      support_requester: $support_requester,
      support_reason: $support_reason,
      lease_duration: $lease_duration
    }
  }')"
launch="$(api POST "/workflow_job_templates/${workflow_id}/launch/" "${launch_payload}")"
workflow_job_id="$(jq -r '.workflow_job // .id // empty' <<<"${launch}")"
if [[ -z "${workflow_job_id}" ]]; then
  echo "unable to determine launched workflow job id" >&2
  echo "${launch}" >&2
  exit 1
fi

echo "Launched workflow job ${workflow_job_id}"

while true; do
  job="$(api GET "/workflow_jobs/${workflow_job_id}/")"
  status="$(jq -r '.status' <<<"${job}")"
  echo "Workflow status: ${status}"
  case "${status}" in
    successful)
      exit 0
      ;;
    failed|error|canceled)
      exit 1
      ;;
  esac
  sleep 10
done
