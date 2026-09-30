#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
set -euo pipefail

cd ~/int333_check

echo "======================================================================"
echo "EVIDENCE 1: Security group ingress rules in terraform/main.tf"
echo "======================================================================"
grep -n -E "ingress \{|description =|from_port|to_port|protocol|cidr_blocks|self" terraform/main.tf | head -30

echo ""
echo "======================================================================"
echo "EVIDENCE 2: templatefile() call in terraform/main.tf"
echo "======================================================================"
grep -n -C 5 "templatefile" terraform/main.tf

echo ""
echo "======================================================================"
echo "EVIDENCE 3: terraform/inventory.tpl contents"
echo "======================================================================"
cat -n terraform/inventory.tpl

echo ""
echo "======================================================================"
echo "EVIDENCE 4: Address line and check commands in app.cfg.j2"
echo "======================================================================"
grep -n -C 3 "hostvars" ansible/roles/nagios_server/templates/app.cfg.j2

echo ""
echo "======================================================================"
echo "EVIDENCE 5: grep -n jq in check_app_health.sh"
echo "======================================================================"
if grep -n "jq" nagios/plugins/check_app_health.sh; then
  echo "jq found"
else
  echo "No occurrences of 'jq' in nagios/plugins/check_app_health.sh"
fi
