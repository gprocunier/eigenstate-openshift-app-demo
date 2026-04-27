# AAP Demo Setup

This directory contains the AAP-facing assets for the podinfo governed
onboarding demo.

The controller project uses this Git repository as SCM. The job templates run
`aap/playbooks/run-ee-demo-step.yml` inside the custom demo execution
environment. The EE handles OpenShift and IdM work directly.

## Execution Environment

Build and publish the EE image before controller setup:

```bash
ansible-builder build \
  -f execution-environment/execution-environment.yml \
  -t ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest \
  .
podman push ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest
```

For disconnected or mirrored builds, pass a reachable OpenShift client tarball:

```bash
ansible-builder build \
  -f execution-environment/execution-environment.yml \
  --build-arg OPENSHIFT_CLIENT_TARBALL_URL=https://example.invalid/openshift-client-linux.tar.gz \
  -t ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest \
  .
```

Override the image name during setup when needed:

```bash
export EE_IMAGE=registry.example.com/demo/eigenstate-openshift-app-demo-ee:latest
```

## Setup

Run from a shell that can read the OpenShift kubeconfig and IPA CA certificate:

```bash
export AAP_PASSWORD='<controller admin password>'
export LAB_DEFAULT_PASSWORD='<lab default password>'
export KUBECONFIG_PATH="$HOME/etc/kubeconfig"
export IPA_CA_CERT_PATH=/etc/ipa/ca.crt
./aap/setup-aap-demo.sh
```

To enable the external GitHub issue gate:

```bash
export GITHUB_TOKEN='<token with issue write access>'
export GITHUB_REPOSITORY=gprocunier/eigenstate-openshift-app-demo
./aap/setup-aap-demo.sh
```

Defaults:

- controller URL: `https://aap.apps.ocp.workshop.lan`
- Git repository: `https://github.com/gprocunier/eigenstate-openshift-app-demo.git`
- execution environment image: `ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest`
- workflow: `eigenstate podinfo governed onboarding`

The setup script creates:

- custom credential type for the lab password
- custom credential type for EE runtime files: kubeconfig, `krb5.conf`, and IPA CA
- optional custom credential type for the GitHub issue gate
- inventory with localhost execution
- execution environment object
- Git SCM project
- one job template per demo step
- a workflow survey for support ticket, requester, reason, and lease duration
- a native AAP approval node before support access opens
- an optional GitHub issue approval gate before support access opens

## Launch

```bash
export AAP_PASSWORD='<controller admin password>'
./run-demo-aap.sh
```

The workflow runs:

1. deploy podinfo
2. bootstrap IdM demo objects
3. identity preflight
4. onboard route identity
5. validate route and vault evidence
6. access policy preflight
7. native AAP approval
8. optional GitHub issue approval
9. open support lease
10. validate leased access
11. expire support lease

## Approval Behavior

The native AAP approval node pauses the workflow after access policy preflight.
Any user with approval rights on the workflow can approve or deny continuation.

When `GITHUB_TOKEN` is supplied during setup, the workflow also creates an issue
in the configured GitHub repository. The gate waits until a comment containing
`/approve` appears on that issue. A comment containing `/deny` fails the gate.
