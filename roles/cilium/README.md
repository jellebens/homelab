# cilium

Installs Cilium as the k3s CNI (kube-proxy replacement, L2 announcements,
Ingress controller, Gateway API, Hubble) from the OCI Helm chart, and the
Gateway API CRDs it depends on. Runs once, delegated to localhost against
`{{ kubeconfig }}`.

## Order of work

1. `install-gateway-api-crds.yml` — apply the Gateway API CRD bundle at
   `cilium_gateway_api_version`, server-side, then wait until they are established.
2. `install-cilium.yml` — Helm-install the chart at `cilium_chart_version`
   with `templates/cilium-values.yml.j2`, wait for the agent DaemonSet and
   the operator, then scale the cluster CoreDNS to 3 replicas.

The CRDs go first because the Cilium operator checks for them at startup:
with a missing or too-old bundle its Gateway API controller does not start,
and every HTTPRoute created from then on stays unprogrammed (empty status,
404 from Envoy) while routes programmed earlier keep working. That is how the
`ceres-firmware` route failed on 2026-09-15 after an unpinned rerun had moved
Cilium to 1.20.1 on top of hand-applied v1.4.0 CRDs.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `cilium_chart_version` | `"1.20.1"` | Helm chart version. Always pinned. |
| `cilium_gateway_api_version` | `"v1.6.1"` | Gateway API release Cilium's docs list for that chart version. |
| `cilium_gateway_api_channel` | `standard` | CRD channel directory in the Gateway API repo. |
| `cilium_gateway_api_crds` | 7 CRDs | The bundle Cilium requires, incl. `tlsroutes` and `backendtlspolicies`. |

**Bump the two versions together.** Each Cilium minor names the Gateway API
release it needs in
`https://docs.cilium.io/en/v<major.minor>/network/servicemesh/gateway-api/gateway-api/`.

From the inventory (`inventories/lab/group_vars/all/k3s.yml`): `k3s_api`
(control-plane IP, never a DNS name) and `k3s_port`.

## What lives elsewhere

The Gateway, its listeners, every HTTPRoute and ReferenceGrant are gitops:
`platform/gateway-config` (+ `.config/lab/gateway.yaml`) and the landing
zones, reconciled by Argo CD. This role only provides the CRDs and the
controller.

## Run

```bash
ansible-navigator run playbooks/deploy_k3s.yml -i inventories/shared -i inventories/lab/mercurius.yml --vault-password-file ~/.ansible-vault-pass --tags cilium
```
