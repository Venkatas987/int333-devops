#!/usr/bin/env bash
export PATH="/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH"

set -uo pipefail

echo "=========================================="
echo "=== C3: Kubernetes Manifest Validation ==="
echo "=========================================="
cd ~/int333_check
kubeconform -strict -summary k8s/
rc_c3=$?
echo "Kubeconform exit code: $rc_c3"

echo ""
echo "=========================================="
echo "=== C4: GitHub Actions Workflow Lint ==="
echo "=========================================="
actionlint .github/workflows/*.yml
rc_c4=$?
echo "Actionlint exit code: $rc_c4"

echo ""
echo "=========================================="
echo "=== C5: Terraform Validation & Trivy ==="
echo "=========================================="
cd ~/int333_check/terraform
terraform fmt -check -recursive
rc_tffmt=$?
terraform init -backend=false -input=false
rc_tfinit=$?
terraform validate
rc_tfval=$?
cd ~/int333_check
trivy config --ignorefile terraform/.trivyignore terraform/
rc_trivy=$?
echo "Terraform fmt ($rc_tffmt), init ($rc_tfinit), validate ($rc_tfval), trivy ($rc_trivy)"

echo ""
echo "=========================================="
echo "=== C6: Ansible Syntax & Lint ==="
echo "=========================================="
cd ~/int333_check
TMP_INV="/tmp/test_ansible_inv.ini"
cat << 'EOF' > "$TMP_INV"
[app]
app1 ansible_host=10.0.1.10 private_ip=10.0.1.10

[monitor]
mon1 ansible_host=10.0.1.20 private_ip=10.0.1.20

[all:vars]
ansible_user=ubuntu
ansible_connection=local
env_name=staging
EOF

ansible-playbook -i "$TMP_INV" --syntax-check ansible/site.yml
rc_ans_syntax=$?
rm -f "$TMP_INV"

ansible-lint ansible/site.yml
rc_ans_lint=$?
echo "Ansible syntax ($rc_ans_syntax), lint ($rc_ans_lint)"

echo ""
echo "=========================================="
echo "=== C7: Puppet Validation & Noop Apply ==="
echo "=========================================="
cd ~/int333_check
puppet parser validate puppet/manifests/site.pp puppet/modules/baseline/manifests/init.pp
rc_pup_val=$?

puppet epp validate puppet/modules/baseline/templates/motd.epp
rc_pup_epp=$?

puppet-lint puppet/
rc_pup_lint=$?

echo "Testing custom function baseline::env_label('app-prod-1')..."
PUP_FUNC_OUT=$(puppet apply --modulepath=puppet/modules -e 'notice(baseline::env_label("app-prod-1"))' 2>&1)
echo "$PUP_FUNC_OUT"
if echo "$PUP_FUNC_OUT" | grep -q "Notice: Scope.*PRODUCTION"; then
  rc_pup_func=0
  echo "Puppet custom function output contains PRODUCTION: PASS"
else
  rc_pup_func=1
  echo "Puppet custom function failed: FAIL"
fi

echo "Running puppet apply --noop on site.pp..."
puppet apply --noop --modulepath=puppet/modules puppet/manifests/site.pp
rc_pup_noop=$?
echo "Puppet parser ($rc_pup_val), epp ($rc_pup_epp), lint ($rc_pup_lint), func ($rc_pup_func), noop ($rc_pup_noop)"

echo ""
echo "=========================================="
echo "=== Summary of C3-C7 ==="
echo "C3 Kubeconform: $rc_c3"
echo "C4 Actionlint: $rc_c4"
echo "C5 Terraform: fmt=$rc_tffmt init=$rc_tfinit val=$rc_tfval trivy=$rc_trivy"
echo "C6 Ansible: syntax=$rc_ans_syntax lint=$rc_ans_lint"
echo "C7 Puppet: parser=$rc_pup_val epp=$rc_pup_epp lint=$rc_pup_lint func=$rc_pup_func noop=$rc_pup_noop"
echo "=========================================="
