# Homelab
Homelab Ansible Playbooks

## Prerequisites
```bash
python3 -m venv ~/.venvs/ansible-navigator
source ~/.venvs/ansible-navigator/bin/activate

pip install --upgrade pip
pip install ansible-builder ansible-navigator
```

### Logon to docker.io
```bash
podman login docker.io
```

### Check login info
```bash
podman login --get-login docker.io
```

## Build Container
```bash
ansible-builder build -t jellebens/ansible-excecution-environment:1.0 --container-runtime podman -v 3

podman push jellebens/ansible-excecution-environment:1.0
```

## Create a role
ansible-galaxy role init roles/k3s

## Encrypt secret
ansible-vault encrypt_string 'mySecretValue' --name "ansible_ssh_pass" --vault-password-file ~/.ansible-vault-pass

## Execute runbook in ee
```bash
ansible-navigator run playbooks/deploy_homelab.yml  -i inventories/shared -i inventories/lab/mercurius.yml --vault-password-file ~/.ansible-vault-pass
```

Use --tags to only run specific roles

