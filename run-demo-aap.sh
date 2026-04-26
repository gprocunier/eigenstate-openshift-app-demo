#!/usr/bin/env bash
set -euo pipefail

AAP_URL="${AAP_URL:-https://aap.apps.ocp.workshop.lan}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
WORKFLOW_NAME="${WORKFLOW_NAME:-eigenstate podinfo governed onboarding}"

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

launch="$(api POST "/workflow_job_templates/${workflow_id}/launch/" '{}')"
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
