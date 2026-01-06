#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./init-ansible.sh my-ansible-project
#   ./init-ansible.sh            # defaults to current directory name
#
# What it creates:
#   ansible.cfg
#   inventories/dev|test|prod
#   group_vars, host_vars
#   roles/, playbooks/, collections/, filter_plugins/, library/
#   requirements.yml
#   .gitignore

PROJECT_DIR="${1:-$(basename "$(pwd)")}"

if [[ "$PROJECT_DIR" != "." ]]; then
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"
fi

mkdir -p \
  inventories/{dev,test,prod}/{group_vars,host_vars} \
  playbooks \
  roles \
  collections \
  filter_plugins \
  library \
  scripts

# Default inventory files per env
cat > inventories/dev/hosts.yml <<'YAML'
all:
  children:
    linux:
      hosts:
        example1.local:
        example2.local:
YAML

cp -n inventories/dev/hosts.yml inventories/test/hosts.yml || true
cp -n inventories/dev/hosts.yml inventories/prod/hosts.yml || true

# Global vars (example)
mkdir -p group_vars
cat > group_vars/all.yml <<'YAML'
---
ansible_user: admin
ansible_become: true
ansible_become_method: sudo
# ansible_ssh_private_key_file: ~/.ssh/id_ed25519
YAML

# Starter playbook
cat > playbooks/site.yml <<'YAML'
---
- name: Site
  hosts: all
  gather_facts: true
  tasks:
    - name: Ping
      ansible.builtin.ping:
YAML

# requirements.yml (collections)
cat > requirements.yml <<'YAML'
---
collections:
  - name: ansible.posix
  - name: community.general
  - name: kubernetes.core
YAML

# Default ansible.cfg
cat > ansible.cfg <<'CFG'
[defaults]
# Pick one as your default; you can still override with -i inventories/prod/hosts.yml
inventory = inventories/dev/hosts.yml

# Keep output readable and deterministic
stdout_callback = yaml
bin_ansible_callbacks = True
callbacks_enabled = profile_tasks

# Safer defaults
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent
forks = 20
timeout = 30

# Roles/collections resolution
roles_path = roles
collections_paths = collections

# Facts/cache (optional; off by default)
# fact_caching = jsonfile
# fact_caching_connection = .ansible_cache
# fact_caching_timeout = 86400

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False

[ssh_connection]
pipelining = True
# ControlPersist speeds up repeated SSH connections
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o PreferredAuthentications=publickey,password
control_path = %(directory)s/%%h-%%p-%%r
CFG

# .gitignore
cat > .gitignore <<'GIT'
artifacts/
context/
*.retry
*.log
.artifacts/
.ansible/
.ansible_cache/
__pycache__/
.vscode/
.idea/
.DS_Store
*.pem
*.key
GIT

echo "✅ Ansible project initialized in: $(pwd)"
echo
echo "Next steps:"
echo "  1) Install collections: ansible-galaxy collection install -r requirements.yml"
echo "  2) Run: ansible-playbook playbooks/site.yml"
echo "  3) Switch env: ansible-playbook -i inventories/prod/hosts.yml playbooks/site.yml"
