# Eigenstate OpenShift App Demo

Demo 1 for the Eigenstate OpenShift demo portfolio: governed application
identity onboarding for `podinfo` using the `eigenstate.ipa` Ansible
collection.

The demo proves that an OpenShift route can be onboarded through IdM-backed
DNS, service principal, keytab, certificate issuance, vault evidence, HBAC,
sudo, and a time-boxed support access lease. It supports two execution paths:

- no-AAP: run the playbooks directly from a prepared lab shell
- AAP: launch the same sequence through an AAP workflow and custom execution
  environment

## Repository Layout

- `prepare-demo.sh` creates `/tmp/demo/podinfo-vars.yml` from the live cluster.
- `run-demo-no-aap.sh` runs the direct prepared-shell sequence.
- `run-demo-aap.sh` launches and monitors the AAP workflow.
- `cleanup-demo.sh` expires access and removes runtime OpenShift state.
- `requirements.yml` installs the published `eigenstate.ipa` collection.
- `vars/podinfo.yml` contains default demo variables.
- `playbooks/` contains the demo implementation.
- `aap/` contains controller setup and workflow assets.
- `execution-environment/` contains the AAP EE build definition.
- `docs/demo-1-aap-build-plan.md` captures the AAP build plan.

## Execution Boundary

Run OpenShift and IdM automation inside the AAP execution environment for the
AAP path. Use the workstation for editing, publishing, staging, and building
the EE image. The no-AAP path can still run from a prepared lab shell with
`oc`, Kerberos, IdM client libraries, and the required Ansible collections.

Expected lab defaults:

- OpenShift cluster domain resolves under `apps.ocp.workshop.lan`
- IdM server is reachable as `idm-01.workshop.lan`
- validation host is `mirror-registry.workshop.lan`
- AAP route is `https://aap.apps.ocp.workshop.lan`

## No-AAP Setup

```bash
git clone https://github.com/gprocunier/eigenstate-openshift-app-demo.git
cd eigenstate-openshift-app-demo
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
```

Use an existing Kerberos ticket:

```bash
kinit admin@WORKSHOP.LAN
```

or provide credentials through environment variables:

```bash
export IPA_ADMIN_PRINCIPAL=admin
export IPA_ADMIN_PASSWORD='<password>'
export SUPPORT_USER_PASSWORD='<password>'
```

If `KUBECONFIG` is not set, scripts use `$HOME/etc/kubeconfig` when it exists.
If `oc` is not in `PATH`, scripts look under the generated OpenShift tools path
used by the lab.

## No-AAP Demo

```bash
./prepare-demo.sh
./run-demo-no-aap.sh
```

## AAP Demo

Build and publish the demo EE image first:

```bash
ansible-builder build \
  -f execution-environment/execution-environment.yml \
  -t ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest \
  .
podman push ghcr.io/gprocunier/eigenstate-openshift-app-demo-ee:latest
```

For disconnected or mirrored builds, override
`OPENSHIFT_CLIENT_TARBALL_URL` with a reachable OpenShift client tarball.

Then run the controller setup from a shell that can read the OpenShift
kubeconfig and IPA CA certificate:

```bash
export AAP_PASSWORD='<controller admin password>'
export LAB_DEFAULT_PASSWORD='<lab default password>'
export KUBECONFIG_PATH="$HOME/etc/kubeconfig"
export IPA_CA_CERT_PATH=/etc/ipa/ca.crt
./aap/setup-aap-demo.sh
./run-demo-aap.sh
```

See `aap/README.md` for the controller objects created by setup.

The AAP path demonstrates three approval patterns before opening support
access:

- a workflow survey captures ticket, requester, reason, and lease duration
- a native AAP approval node pauses the workflow after access preflight
- an optional GitHub issue gate waits for a `/approve` issue comment

## Cleanup

```bash
./cleanup-demo.sh
```

Cleanup removes the demo OpenShift namespace and `/tmp/demo` runtime files. It
also attempts to expire the support lease first when the generated vars file is
available.
