# 2026-07-01 — Node IP fix, k3s API name, CoreDNS HA

Changes made to the homelab playbooks while migrating `lab.local` DNS to be
cluster-authoritative (the DNS authority itself lives in the separate `gitops`
repo's `platform/coredns-lab`; this doc covers only the **homelab** changes).

| Area | File | Commit |
|---|---|---|
| Node networking | `roles/network/tasks/wired.yml` | `7a1820f` |
| k3s API cert | `roles/k3s/tasks/configure-master.yml` | `17c3a6b` |
| Cluster DNS HA | `roles/cilium/tasks/install-cilium.yml` | `13b6e53` |

---

## 1. Clear stale static IP on the wired connection

**File:** `roles/network/tasks/wired.yml`

**Problem.** The k3s nodes were dual-homed: every node's `eth0` had **two**
IPv4 addresses — the DHCP-reserved `.15x` *and* a leftover manually-configured
`.16x`. NetworkManager applied the static `.16x` as the primary, so k3s
auto-detected the wrong address as its node `InternalIP`
(e.g. master advertised `.160` instead of its reserved `.151`). That meant
kubelet / intra-cluster traffic rode the wrong address, and DHCP reservations,
DNS records, and k3s all disagreed.

Root cause: the `eth0` NetworkManager connection was `ipv4.method auto` (DHCP)
but still carried a leftover `ipv4.addresses` (and `ipv4.gateway`) from earlier
provisioning. `wired.yml` set DNS + `method auto` but never cleared that manual
address.

**Fix.** Added a task that clears the manual addressing so the connection is
pure DHCP:

```yaml
nmcli connection modify "<conn>" ipv4.addresses "" ipv4.gateway ""
```

After the role's reboot, `eth0` has only the reserved `.15x` and k3s re-detects
the correct `InternalIP`.

**Reserved node IPs** (Asus DHCP reservations): master01 `.151`,
node01–05 `.152`–`.156`.

**Operational notes / gotchas:**
- Run **one host at a time** (`serial: 1`). Each host reboots.
- **The master is special.** Changing master01's IP `.160 → .151` moved the
  single-member embedded **etcd**, which then refused to start
  (`not a member of the etcd cluster ... expect https://192.168.50.151:2380`).
  Recovery: snapshot first (`k3s etcd-snapshot save`), then
  `k3s server --cluster-reset` (rewrites membership to the current IP, data
  preserved), then `systemctl start k3s`.
- After node-IP changes, **Cilium `CiliumNode` objects can keep stale IPs** →
  pod-to-pod / DNS timeouts. Fix: `kubectl -n kube-system rollout restart ds/cilium`.

**Verify:**
```bash
# eth0 has only the reserved .15x:
ansible <node> -b -m command -a 'ip -o -4 addr show eth0'
# k3s InternalIP matches the reservation:
kubectl get nodes -o wide
```

---

## 2. Add `k3s.lab.local` to the API server cert (`tls-san`)

**File:** `roles/k3s/tasks/configure-master.yml`

**Why.** The new `lab.local` zone publishes `k3s.lab.local → 192.168.50.151`
(the control-plane). For `kubectl`/argocd to use `https://k3s.lab.local:6443`
with **TLS verification**, that name must be in the apiserver serving cert's
SANs. Previously the cert only covered `k3s-master01.local` + node IPs.

**Change.** Added `k3s.{{ domain }}` (→ `k3s.lab.local`) to the `tls-san` list
in both the init-server and joining-server config blocks. `domain` comes from
`inventories/lab/group_vars/all/values.yml` (`domain: lab.local`).

**Applying it (gotcha).** `configure-master.yml` cannot be run standalone —
`k3s_token` is *registered at runtime* by `install-master-nodes.yml`, so a
standalone run renders an empty token and breaks k3s. To apply on an existing
cluster without a full role run, edit the SAN into the live
`/etc/rancher/k3s/config.yaml` and restart k3s (regenerates the serving cert):

```bash
# add `  - "k3s.lab.local"` under tls-san in /etc/rancher/k3s/config.yaml, then:
systemctl restart k3s
```

**Verify:**
```bash
echo | openssl s_client -connect 192.168.50.151:6443 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName        # should list DNS:k3s.lab.local
kubectl --server=https://k3s.lab.local:6443 get nodes   # works, no --insecure
```

---

## 3. Scale cluster CoreDNS (kube-dns) to 3 replicas

**File:** `roles/cilium/tasks/install-cilium.yml`

**Why.** k3s ships the cluster `kube-dns` CoreDNS with a **single replica**.
When that pod's node got isolated (a router/AiMesh reboot islanded the minilab
segment), in-cluster DNS timed out cluster-wide — a single point of failure.

**Change.** Added a task (runs `run_once` on localhost, after the CNI is up) to
scale the `coredns` deployment to **3** replicas:

```yaml
- name: Scale cluster CoreDNS (kube-dns) to 3 replicas for HA
  delegate_to: localhost
  kubernetes.core.k8s_scale:
    api_version: apps/v1
    kind: Deployment
    name: coredns
    namespace: kube-system
    replicas: 3
    kubeconfig: "{{ kubeconfig }}"
    wait: true
```

**Why it sticks.** The k3s bundled CoreDNS manifest
(`/var/lib/rancher/k3s/server/manifests/coredns.yaml`) **omits `replicas`**, so
the field isn't owned by the k3s deploy controller — scaling it externally is
**not reverted** on k3s restart. CoreDNS already has `topologySpreadConstraints`
(`maxSkew: 1` per hostname, `DoNotSchedule`), so the 3 replicas spread
**one-per-node** automatically; no anti-affinity change needed (and adding pod-spec
fields *would* be reverted by the deploy controller).

**Verify:**
```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide   # 3 pods, 3 nodes
```

---

## Related context (not in this repo)

The DNS authority change lives in the `gitops` repo (`platform/coredns-lab`):
`coredns-lab` is now the **authoritative primary** for `lab.local` (zone-in-git,
3 replicas) on VIP `192.168.50.180`; the DS918 (`.144`) is a slave + DNS2
backup; Asus DHCP hands clients `DNS1=.180 / DNS2=.144`.

**Standing fragility:** the minilab (k3s + switches) sits behind a **wireless
AiMesh backhaul**, so a router reboot islands the whole cluster until the mesh
re-pairs. `DNS2=.144` (DS918, reachable segment) is the safety net that keeps
LAN DNS alive meanwhile. Recommended hardening: **wired backhaul** to the
minilab and a **non-DFS backhaul channel** (36–48) to avoid the radar-scan
delay on reboots. Note: Cilium LoadBalancer VIPs (`.180`, `.200`) do **not**
answer ICMP — test with `dig`/the service port, never `ping`.
