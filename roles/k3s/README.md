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
| `upgrade.yml` | (none) | k3s version upgrade; only via `playbooks/upgrade_k3s.yml`, see below |

Upgrading k3s
-------------

`k3s_version` (`inventories/lab/group_vars/all/k3s.yml`) is the release every
node runs. To upgrade:

1. Pick the new version from the **stable** channel
   (`curl -s https://update.k3s.io/v1-release/channels | jq -r '.data[] | select(.name=="stable") | .latest'`)
   and read its release notes. Move **one Kubernetes minor at a time**
   (v1.35 → v1.36 → v1.37); `upgrade.yml` refuses a bigger jump, and a downgrade.
2. Check the add-ons that pin a Kubernetes range against the new minor:
   Cilium (`roles/cilium`, its docs list the tested versions), Longhorn, Argo CD
   and Kyverno (gitops `platform/*`). Bump those first if needed.
3. Bump `k3s_version`, then run:

   ```sh
   ansible-navigator run playbooks/upgrade_k3s.yml \
     -i inventories/shared -i inventories/lab/k3s.yml \
     --vault-password-file ~/.ansible-vault-pass
   ```

   The play takes an etcd snapshot (`pre-upgrade-<version>-*`, see
   `kubectl get etcdsnapshotfiles`), upgrades the server, then each agent, **one
   node at a time**, by re-running the k3s install script with the same arguments
   the install tasks use. Each node must report the new version, `Ready`, and a
   Ready Cilium agent before the next one starts; any failure stops the run
   (`any_errors_fatal`). Nothing is drained: `KillMode=process` keeps the
   containers running across the k3s restart, as with the registries restart
   above. The server restart makes the API unavailable for about 30 s. A final
   play waits for every node and `ds/cilium` and lists pods that are not Running.
   A node already on `k3s_version` is skipped, so the play can be re-run.
4. Commit the bump (the version history is in the comment above `k3s_version`)
   and note the new version in gitops `AGENTS.md`.

**Do not use `deploy_k3s.yml --tags k3s` for upgrades.** Its master install task
has `creates: /usr/local/bin/k3s`, so it never touches an installed server, while
its agent task re-runs the install script on every worker **in parallel** — the
pin bump would then upgrade all agents at once, ahead of the server.

Rolling back: a Kubernetes minor cannot be downgraded in place (etcd, kubelet).
Restore the `pre-upgrade-*` snapshot with
`k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>` on the
server at the OLD version (reinstall it with `INSTALL_K3S_VERSION=<old>`), then
reinstall the agents at the old version. See the k3s docs on cluster restore.

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
