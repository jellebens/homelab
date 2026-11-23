argocd
======

Installs Argo CD as the `argocd` Helm release (chart `argocd/argo-cd`) in namespace
`argocd`, then bootstraps the cluster from the gitops repo. Everything after
bootstrap is GitOps-managed from `jellebens/gitops` (`platform/argocd-config` tunes
this release; see its README).

Variables (`defaults/main.yml`)
-------------------------------

| Variable | Default | Purpose |
|---|---|---|
| `argocd_chart_version` | `10.9.1` | argo-cd chart version (Argo CD v3.5.3). **Pinned**: without it a rerun upgrades Argo CD to the newest chart. Bump deliberately. |
| `argocd_lab_ca_hosts` | `[harbor.lab.local]` | Hosts trusted with the lab root CA in `argocd-tls-certs-cm`, so the repo-server can pull charts from Harbor. |

Values live in `templates/argocd-values.yml.j2`.

Lab CA trust
------------

The repo-server trusts the lab root CA for every host in `argocd_lab_ca_hosts`
(`configs.tls.certificates`). The CA is read from `roles/k3s/files/lab-root-ca.crt`,
the same file the k3s nodes trust for `harbor.lab.local`, so there is one copy to
rotate. Added on 2026-10-09 for the ARC/Harbor POC (gitops cards #338/#339), where
Argo pulls the ARC charts from `harbor.lab.local/actions/...` via the gitops
repo-creds `harbor-repo`.

**Applying a change without rerunning the whole role:** the live release was updated
on 2026-10-09 with exactly these values, pinned to the deployed chart:

```sh
helm -n argocd upgrade argocd argocd/argo-cd --version 10.9.1 --reuse-values \
  --set-file 'configs.tls.certificates.harbor\.lab\.local=roles/k3s/files/lab-root-ca.crt'
```

Run `--dry-run=server` first and diff it against `helm -n argocd get manifest argocd`.
That upgrade changed only `argocd-tls-certs-cm`. The repo-server reads the mounted
ConfigMap at request time, so no restart is needed.

**Rotating the CA:** replace `roles/k3s/files/lab-root-ca.crt` (see the k3s role
README), then rerun this role or the `helm upgrade` above.
