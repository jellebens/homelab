# homelab
Homelab Ansible Playbooks



# Prerequisites

python3 -m venv ~/.venvs/ansible-navigator
source ~/.venvs/ansible-navigator/bin/activate

pip install --upgrade pip
pip install ansible-builder ansible-navigator

# Build Container
ansible-builder build -t localhost/amarok-ee:1.0 --container-runtime podman -v 3

# Execute runbook in ee
ansible-navigator run playbooks/test.yml -i inventories/lab --execution-environment-image localhost/amarok-ee:1.0 --mode stdout --container-engine podman