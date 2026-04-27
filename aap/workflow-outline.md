# AAP Workflow Outline

Target route: `https://aap.apps.ocp.workshop.lan`

Expected admin-capable IdM user: `sysop`

The implemented workflow is named `eigenstate podinfo governed onboarding`.
It runs one job template per demo step and each job template delegates to the
bastion through `aap/playbooks/run-bastion-demo-step.yml`.

## Workflow

1. `deploy`
   runs `playbooks/10-deploy-podinfo.yml`.
2. `bootstrap`
   runs `playbooks/00-bootstrap-idm.yml`.
3. `identity_preflight`
   runs `playbooks/15-preflight-identity.yml`.
4. `onboard`
   runs `playbooks/20-onboard-app-identity.yml`.
5. `validate_route`
   runs `playbooks/30-validate-route.yml`.
6. `access_preflight`
   runs `playbooks/35-preflight-access-policy.yml`.
7. `approve_support_lease`
   pauses for native AAP workflow approval.
8. `github_issue_gate`
   optionally creates and waits on a GitHub issue approval.
9. `open_lease`
   runs `playbooks/40-open-support-lease.yml`.
10. `validate_leased_access`
   runs `playbooks/45-validate-leased-access.yml`.
11. `expire_lease`
   runs `playbooks/50-expire-support-lease.yml`.

## Credential Model

- Machine credential: AAP-to-bastion SSH as `cloud-user`.
- Custom credential type: injects the lab default password as
  `LAB_DEFAULT_PASSWORD`, `IPA_ADMIN_PASSWORD`, and `SUPPORT_USER_PASSWORD`.
- Optional GitHub issue gate credential type: injects `GITHUB_TOKEN`,
  `GITHUB_REPOSITORY`, and `GITHUB_GATE_TIMEOUT`.
- OpenShift access: inherited from the bastion runtime through
  `$HOME/etc/kubeconfig`.
- IdM access: supplied to the bastion runtime through the injected environment.

## Setup Script

`aap/setup-aap-demo.sh` creates the credential type, credentials, inventory,
SCM project, survey, job templates, native approval node, optional GitHub issue
gate, and workflow graph through the AAP controller API.
