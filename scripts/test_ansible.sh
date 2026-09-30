#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
set -euo pipefail

cd ~/int333_check

echo "=== C6: ANSIBLE SYNTAX CHECK WITH TEMP INVENTORY ==="
TMPINV="/tmp/inv_test.ini"
printf '[app]\napp1 ansible_host=127.0.0.1 private_ip=10.0.1.10\n[monitor]\nmon1 ansible_host=127.0.0.1 private_ip=10.0.1.20\n[all:vars]\nansible_user=ubuntu\nenv_name=staging\n' > "$TMPINV"

ansible-playbook -i "$TMPINV" ansible/site.yml --syntax-check
rm -f "$TMPINV"
echo "ansible-playbook syntax-check: PASS"

echo "=== C6: ANSIBLE-LINT ==="
ansible-lint ansible/site.yml
echo "ansible-lint: PASS"
