# homelab
Homelab Ansible Playbooks



# Prerequisites

python3 -m venv ~/.venvs/ansible-navigator
source ~/.venvs/ansible-navigator/bin/activate

pip install --upgrade pip
pip install ansible-builder ansible-navigator

# Logon to docker.io
podman login docker.io

## Check login info
podman login --get-login docker.io


# Build Container
ansible-builder build -t jellebens/ansible-excecution-environment:1.0 --container-runtime podman -v 3

podman push jellebens/ansible-excecution-environment:1.0

# Execute runbook in ee
ansible-navigator run playbooks/deploy_homelab.yml  -i inventories/shared -i inventories/lab/mercurius.yml --vault-password-file ~/.ansible-vault-pass