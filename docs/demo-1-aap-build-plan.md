# Demo 1 AAP Build Plan

## Goal

Build the AAP-driven version of the OpenShift application identity demo.

Success means AAP can launch a governed workflow that deploys `podinfo`,
creates and validates IdM-backed DNS, service principal, keytab, certificate,
vault, HBAC, sudo, and leased support access, then expires the support lease.

## Execution Boundary

- Workstation: edit and publish this demo repository.
- Workstation or build host: build and publish the custom AAP EE image.
- AAP controller: own workflow, inventory, credentials, project, and job
  templates.
- AAP execution environment: run OpenShift, IdM, and validation playbooks
  directly.

## Implementation Steps

1. Publish the standalone demo repository.
2. Build and push the custom execution environment from
   `execution-environment/execution-environment.yml`.
3. Run `aap/setup-aap-demo.sh` with controller and lab credentials supplied by
   environment.
4. Launch `run-demo-aap.sh`.
5. Approve the native AAP support lease gate.
6. If enabled, approve the GitHub issue gate with a `/approve` comment.
7. Validate the route, vault evidence, support access lease, and lease expiry.

## Notes

- The `eigenstate.ipa` collection is resolved from Ansible Galaxy.
- The AAP job templates run in a custom EE image instead of delegating to an
  external runtime host.
- Secrets and runtime files are supplied through AAP credentials and
  environment variables; they are not stored in this repository.
- The workflow survey captures ticket, requester, reason, and lease duration.
- The native AAP approval node demonstrates controller-governed approval.
- The optional GitHub issue gate demonstrates third-party approval before the
  support lease opens.
