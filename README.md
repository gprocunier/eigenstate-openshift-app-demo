# Eigenstate OpenShift App Demo

Demo 1 for the Eigenstate OpenShift demo portfolio: governed application
identity onboarding for `podinfo` using the `eigenstate.ipa` Ansible
collection.

The demo proves that an OpenShift route can be onboarded through IdM-backed
DNS, service principal, keytab, certificate issuance, vault evidence, HBAC,
sudo, and a time-boxed support access lease. It supports two execution paths:

- no-AAP: run the playbooks directly on the bastion
- AAP: launch the same sequence through an AAP workflow

## Repository Layout

- `prepare-demo.sh` creates `/tmp/demo/podinfo-vars.yml` from the live cluster.
- `run-demo-no-aap.sh` runs the direct bastion sequence.
- `run-demo-aap.sh` launches and monitors the AAP workflow.
- `cleanup-demo.sh` expires access and removes runtime OpenShift state.
- `requirements.yml` installs the published `eigenstate.ipa` collection.
- `vars/podinfo.yml` contains default demo variables.
- `playbooks/` contains the demo implementation.
- `aap/` contains controller setup and workflow assets.
- `docs/demo-1-aap-build-plan.md` captures the AAP build plan.

## Execution Boundary

Run OpenShift and IdM automation from the bastion. Use the workstation only for
editing, publishing, and staging. The AAP workflow connects to bastion and
executes the same validated playbooks there.

Expected lab defaults:

- OpenShift cluster domain resolves under `apps.ocp.workshop.lan`
- IdM server is reachable as `idm-01.workshop.lan`
- validation host is `mirror-registry.workshop.lan`
- AAP route is `https://aap.apps.ocp.workshop.lan`

## Bastion Setup

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

From the bastion checkout:

```bash
export AAP_PASSWORD='<controller admin password>'
export LAB_DEFAULT_PASSWORD='<lab default password>'
./aap/setup-aap-demo.sh
./run-demo-aap.sh
```

See `aap/README.md` for the controller objects created by setup.

## Cleanup

```bash
./cleanup-demo.sh
```

Cleanup removes the demo OpenShift namespace and `/tmp/demo` runtime files. It
also attempts to expire the support lease first when the generated vars file is
available.
