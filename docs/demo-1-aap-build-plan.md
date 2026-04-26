# Demo 1 AAP Build Plan

## Goal

Build the AAP-driven version of the OpenShift application identity demo.

Success means AAP can launch a governed workflow that deploys `podinfo`,
creates and validates IdM-backed DNS, service principal, keytab, certificate,
vault, HBAC, sudo, and leased support access, then expires the support lease.

## Execution Boundary

- Workstation: edit and publish this demo repository.
- Bastion: run OpenShift, IdM, and validation playbooks.
- AAP controller: own workflow, inventory, credentials, project, and job
  templates.
- AAP execution environment: connect to bastion and invoke the validated
  bastion runtime.

## Implementation Steps

1. Publish the standalone demo repository.
2. Clone or update the repository on bastion.
3. Run `ansible-galaxy collection install -r requirements.yml -p .ansible/collections`.
4. Run `aap/setup-aap-demo.sh` with controller and lab credentials supplied by
   environment.
5. Launch `run-demo-aap.sh`.
6. Validate the route, vault evidence, support access lease, and lease expiry.

## Notes

- The `eigenstate.ipa` collection is resolved from Ansible Galaxy.
- The setup script creates a demo-specific SSH key for AAP-to-bastion access.
- Secrets are supplied through AAP credentials and environment variables; they
  are not stored in this repository.
