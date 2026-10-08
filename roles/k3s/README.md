k3s
===

Installs and configures k3s on the `k3s` group: `masters` run the server,
`workers` run the agent. Tasks (see `tasks/main.yml`), with their tags:

| Tasks | Tags | What |
|---|---|---|
| `enable-cgroup.yml` | `cgroup` | cgroup kernel flags on the Pis (reboots via the `reboot_pi` handler) |
| `install-storage-prereqs.yml` | `storage`, `longhorn` | Longhorn prerequisites |
| `install-master-nodes.yml`, `configure-master.yml` | `k3s`, `masters` | k3s server + node token |
| `install-worker-nodes.yml` | `k3s`, `workers` | k3s agent |
| `configure-registries.yml` | `k3s`, `registries` | containerd trust for the private registries (Harbor) |
| `uninstall.yml` | `k3s-cleanup` | only when that tag is asked for |

Private registries (Harbor)
---------------------------

`configure-registries.yml` lets containerd on every node pull from
**`harbor.lab.local`** (the Harbor registry in gitops `platform/harbor-config`).
For each entry in `k3s_private_registries` (`defaults/main.yml`) it:

1. copies the lab root CA (`files/lab-root-ca.crt`, the same file as
   `gitops/lab-root-ca.crt`) to `/etc/rancher/k3s/lab-root-ca.crt`;
2. pins `<address> <host>` in a managed block in `/etc/hosts`;
3. writes `/etc/rancher/k3s/registries.yaml` with `configs.<host>.tls.ca_file`;
4. if the CA or `registries.yaml` changed, restarts k3s (or k3s-agent) **one node
   at a time**. Each restart waits until containerd answers and has rendered
   `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/<host>/hosts.toml` with the
   CA. If any node fails that check, the whole run stops (`any_errors_fatal`).
   `KillMode=process` on the k3s units keeps running containers alive. The master
   restart makes the API unavailable for about 30 s, so leader-election controllers
   (kyverno, cnpg, longhorn CSI sidecars, cilium-operator) restart once.

Run only this part:

```sh
ansible-navigator run playbooks/deploy_k3s.yml --tags registries \
  -i inventories/shared -i inventories/lab/k3s.yml \
  --vault-password-file ~/.ansible-vault-pass
```

Add `--limit k3s-node05.local` to try one node first, or `--check --diff` to preview.
**Never run the play untagged** for this. The untagged play includes the network
role, which reboots every node in parallel.

### Why the /etc/hosts pin

containerd runs inside the static k3s binary and uses Go's built-in resolver.
That resolver treats every `*.local` name as mDNS and never sends it to the DNS
servers. So `crictl pull harbor.lab.local/...` failed with
`lookup harbor.lab.local: no such host`, even though `getent` and `curl` on the
same node (glibc) resolve it through the DS918. Every `*.lab.local` name behaves
this way for containerd. The pin also keeps image pulls independent of the
in-cluster DNS, which rides on the CNI (see the 2026-09-10 outage in gitops
AGENTS.md). **Keep `address` equal to the gateway VIP**
(`lbipam.cilium.io/ips` in gitops `.config/lab/gateway.yaml`, now `192.168.50.200`).

### Credentials

Only TLS trust is configured, not credentials. Public Harbor projects pull
anonymously. A private project needs an `imagePullSecret` (a Harbor robot
account, sealed into the namespace that pulls).

### Adding a registry

Add an entry to `k3s_private_registries` (`host`, `address`) and rerun with
`--tags registries`. Its cert must come from the lab CA. Any other CA needs its
own `ca_file`, which the template does not support yet.

### Rotating the lab CA

Replace `files/lab-root-ca.crt` with the new `gitops/lab-root-ca.crt` and rerun.
The copy task changes, so every node restarts again, one at a time.
