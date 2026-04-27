# AAP Demo Setup

This directory contains the AAP-facing assets for the podinfo governed
onboarding demo.

The controller project uses this Git repository as SCM. The job templates run
`aap/playbooks/run-ee-demo-step.yml` inside the custom demo execution
environment. The EE handles OpenShift and IdM work directly.

## Execution Environment

Build and publish the EE image before controller setup:

The upstream `ee-minimal-rhel9` base image ships `microdnf` instead of `dnf`.
When `ansible-builder` generates a build context that calls `dnf` in its
assemble scripts, the build fails on a clean host without cached layers.
Pass `--build-arg PKGMGR=/usr/bin/microdnf` to work around this, or use
a standalone Containerfile that calls `microdnf` directly for system
package installation.

```bash
ansible-builder build \
  -f execution-environment/execution-environment.yml \
  --build-arg PKGMGR=/usr/bin/microdnf \
  --build-arg PYCMD=/usr/bin/python3.12 \
  -t eigenstate-openshift-app-demo-ee:latest
```

The included EE definition uses the supported AAP minimal RHEL 9 execution
environment base. Build hosts must provide RHEL 9 package content that includes
`ipa-client`, `python3-ipaclient`, and `python3-ipalib`; the stock UBI repos
visible inside the base image only provide the generic Kerberos client tools.
Use a subscribed RHEL build host, mounted entitlements, or a mirrored RHEL 9
content source when building the image. Keep `PYCMD=/usr/bin/python3.12` so
ansible-builder uses the AAP Python runtime after RHEL packages install
`/usr/bin/python3`. The EE also installs the matching upstream FreeIPA 4.12.2
Python packages into the AAP Python 3.12 runtime because RHEL 9 does not ship
`python3.12-ipalib` or `python3.12-ipaclient` RPMs.

In the lab, build on an entitled host and push the image to the OpenShift
integrated registry in the `aap` namespace. AAP pulls the image by default from:

```text
image-registry.openshift-image-registry.svc:5000/aap/eigenstate-openshift-app-demo-ee:latest
```

For disconnected or mirrored builds, pass a reachable OpenShift client tarball:

```bash
ansible-builder build \
  -f execution-environment/execution-environment.yml \
  --build-arg OPENSHIFT_CLIENT_TARBALL_URL=https://example.invalid/openshift-client-linux.tar.gz \
  --build-arg PKGMGR=/usr/bin/microdnf \
  --build-arg PYCMD=/usr/bin/python3.12 \
  -t eigenstate-openshift-app-demo-ee:latest
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
- execution environment image: `image-registry.openshift-image-registry.svc:5000/aap/eigenstate-openshift-app-demo-ee:latest`
- execution environment pull policy: `always`
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
