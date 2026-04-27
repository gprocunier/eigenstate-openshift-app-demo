# Demo 1 Talk Track: Governed Application Identity Onboarding

This talk track covers each step of the AAP workflow
`eigenstate podinfo governed onboarding`. The workflow deploys a sample
application into OpenShift, onboards it through a full IdM identity lifecycle,
demonstrates approval-gated temporary access, and proves that access is
revoked when the lease expires.

---

## 1. Deploy

**What happens:** The workflow creates an OpenShift project, deploys the
`podinfo` application as a Deployment with health and readiness probes,
exposes it through a Service, and creates a Route with a DNS-resolvable FQDN
under the cluster wildcard domain.

**Why it matters:** This is the starting state every application team faces.
The app is running and reachable, but the route has no TLS, no identity
backing, and no governance. Anyone with cluster access could have created it.
Nothing ties the route hostname back to a trusted identity authority.
Everything that follows transforms this unmanaged endpoint into a governed
one.

---

## 2. Bootstrap IdM

**What happens:** The workflow registers the route hostname as a host object
in FreeIPA, creates an HTTP service principal for it, generates an initial
keytab, creates a support user and group for the later access lease,
archives the support user password into an IdM vault, and provisions HBAC
and sudo rules scoped to a specific validation host and service.

**Why it matters:** This is where the enterprise identity layer takes
ownership of the application. The host object and service principal establish
the route as a known entity in the IdM trust domain. The keytab proves that
the application can authenticate using Kerberos, which is the foundation for
certificate issuance. The support user, group, HBAC rule, and sudo rule are
all created now but have no active access yet. This separation between
provisioning access objects and activating them is the core of the
least-privilege model the demo enforces.

---

## 3. Identity Preflight

**What happens:** The workflow queries IdM to verify that the DNS wildcard
record resolves, the HTTP service principal exists and has an active keytab,
and the keytab material can be retrieved from IdM. If any check fails, the
workflow stops.

**Why it matters:** Preflight catches configuration drift and partial
failures before the workflow attempts certificate issuance. In production
this is the gate that prevents an operator from onboarding an application
against a misconfigured or stale identity backend. It proves the identity
objects are not just created but queryable and consistent through the
`eigenstate.ipa` collection API.

---

## 4. Onboard Identity

**What happens:** The workflow generates a private key and CSR for the
route FQDN, submits the CSR to FreeIPA's internal CA, receives an
IdM-signed certificate, patches the OpenShift Route object with the
certificate, key, and CA chain to enable edge TLS termination, and archives
the full TLS bundle as structured evidence into an IdM vault.

**Why it matters:** This is the moment the application transitions from
an anonymous HTTP endpoint to a TLS-protected route backed by an
enterprise certificate authority. The certificate was not self-signed,
not issued by a public CA with no organizational context, and not
manually pasted into a Secret. It was issued programmatically by the
same IdM that governs the rest of the organization's identity. The vault
archive creates a tamper-evident record of what was issued, to whom, with
what serial number and validity window, tied to the service principal
that requested it.

---

## 5. Validate Route

**What happens:** The workflow confirms the OpenShift Route object exists
with TLS, makes HTTPS requests to the application's `/version` and
`/metrics` endpoints to prove the route is serving traffic over the
IdM-issued certificate, and retrieves the archived TLS bundle from the
IdM vault to confirm the evidence chain is intact.

**Why it matters:** Validation closes the loop between issuance and
runtime. It proves TLS is not just configured but working, and that the
vault evidence matches what was issued. In an audit scenario, this step
provides the proof that the onboarding was not just attempted but
completed and verified.

---

## 6. Access Policy Preflight

**What happens:** The workflow tests the HBAC rule by simulating an
access check for the support user against the validation host and SSH
service. It also reads the sudo rule to confirm it exists and is
enabled.

**Why it matters:** Before the workflow reaches the approval gate,
it proves that the access policy is correctly configured. If HBAC
would deny the support user or the sudo rule is missing, the workflow
stops before any human approver is asked to make a decision. This
prevents the common failure mode where access is approved but cannot
actually be exercised because the policy objects are misconfigured.

---

## 7. Approve Support Lease (Native AAP Approval)

**What happens:** The workflow pauses at a native AAP approval node.
The survey context from the workflow launch is visible to the approver:
the support ticket, requester, reason, and requested lease duration.
A user with approval rights on the workflow must explicitly approve or
deny the request.

**Why it matters:** This is the human-in-the-loop control point. No
automated step can open support access. The approver sees why access
was requested, who is requesting it, and how long it will last. The
approval is recorded in the AAP audit log with the approver's identity
and timestamp. In a regulated environment, this is the control that
maps to change management and access governance requirements.

---

## 8. GitHub Issue Gate (Optional)

**What happens:** When configured, the workflow creates a GitHub issue
in the demo repository with the full request context and waits for an
external approver to comment `/approve` or `/deny`. The gate polls the
issue comments until a decision arrives or the timeout expires.

**Why it matters:** This demonstrates approval federation. The approval
authority is not limited to AAP users. An external stakeholder, a
security team member, or a change advisory board can approve using a
tool they already use. The issue creates a durable, linkable,
auditable record outside of AAP. This pattern extends to any external
approval system: ServiceNow, Jira, PagerDuty, or a custom webhook.

---

## 9. Open Support Lease

**What happens:** After approval, the workflow activates the support
user by setting a short-lived principal expiration on the IdM user
object. The `eigenstate.ipa.user_lease` module sets both the Kerberos
principal expiration and the password expiration to the requested
duration. The user's group membership is verified as a precondition.

**Why it matters:** The support user existed since bootstrap but had
no active access. Opening the lease does not create new access objects;
it activates an existing, pre-audited user within a time boundary set
by IdM. The expiration is enforced by the KDC, not by an application
timer or a cron job. If nothing else happens, the access expires
automatically. This is the difference between "we gave someone access
and hope someone remembers to revoke it" and "the identity system
itself enforces the boundary."

---

## 10. Validate Leased Access

**What happens:** The workflow retrieves the support user's password
from the IdM vault, obtains a Kerberos ticket for the support user,
and uses that ticket to SSH into the validation host using GSSAPI
authentication. From inside that SSH session, it runs `whoami` and
curls the podinfo route over HTTPS to prove the support user can
reach the application.

**Why it matters:** This is the proof that the entire identity chain
works end-to-end: IdM user, Kerberos ticket, HBAC policy, SSH access,
and application reachability. The SSH session uses GSSAPI, not a
password or key, meaning the access is bound to the Kerberos ticket
lifetime. The validation host is scoped by HBAC; the support user
cannot SSH to arbitrary hosts. This step would fail if any link in
the chain were broken: expired ticket, HBAC denial, network
isolation, or a misconfigured route.

---

## 11. Expire Support Lease

**What happens:** The workflow expires the support user's Kerberos
principal and password in IdM, destroys the cached Kerberos ticket,
and then attempts to obtain a fresh ticket with the same credentials.
The step asserts that the fresh kinit fails, proving that access has
been revoked.

**Why it matters:** Expiration is not a flag in a database; it is
a KDC-enforced state. Even if the password is known, the support user
cannot authenticate after the lease is expired. The negative proof
(kinit fails) is the strongest evidence of revocation. In contrast
to deprovisioning, where the user is deleted and the audit trail
is lost, expiration preserves the full user record, group membership,
vault evidence, and HBAC history for post-incident review while
guaranteeing the access path is closed.
