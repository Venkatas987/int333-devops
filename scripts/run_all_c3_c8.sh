#!/usr/bin/env bash
# scripts/run_all_c3_c8.sh - Run checks C3-C8 inside WSL Ubuntu-24.04
set -uo pipefail

export PATH="/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH"

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
skip() { echo "  [SKIP] $*"; SKIP=$((SKIP+1)); }

echo "=== Syncing project to ~/int333_check ==="
mkdir -p ~/int333_check
rsync -a --delete --exclude='.git' --exclude='node_modules' /mnt/d/projects/int333/ ~/int333_check/
cd ~/int333_check

echo ""
echo "=========================================="
echo "=== C3: Kubernetes Manifests Check ==="
echo "=========================================="
if command -v kubeconform &>/dev/null; then
    echo "Running kubeconform -strict -summary k8s/..."
    kubeconform -strict -summary k8s/ 2>&1 && ok "kubeconform" || fail "kubeconform"
else
    skip "kubeconform not found"
fi

if command -v kubectl &>/dev/null; then
    echo "Running kubectl apply --dry-run=client..."
    kubectl apply --dry-run=client -f k8s/ 2>&1 && ok "kubectl dry-run" || fail "kubectl dry-run"
else
    skip "kubectl not found"
fi

echo ""
echo "=========================================="
echo "=== C4: Workflows Check (actionlint) ==="
echo "=========================================="
if command -v actionlint &>/dev/null; then
    echo "Running actionlint..."
    actionlint .github/workflows/*.yml 2>&1 && ok "actionlint" || fail "actionlint"
else
    skip "actionlint not found"
fi

echo ""
echo "=========================================="
echo "=== C5: Terraform Check ==="
echo "=========================================="
if command -v terraform &>/dev/null; then
    cd terraform
    echo "Running terraform fmt -check -recursive..."
    terraform fmt -check -recursive 2>&1 && ok "terraform fmt -check" || fail "terraform fmt"

    echo "Running terraform init -backend=false..."
    terraform init -backend=false -input=false 2>&1 | tail -3

    echo "Running terraform validate..."
    terraform validate 2>&1 && ok "terraform validate" || fail "terraform validate"

    cd ..
    if command -v trivy &>/dev/null; then
        echo "Running trivy config terraform/..."
        trivy config --ignorefile terraform/.trivyignore terraform/ 2>&1 && ok "trivy config" || fail "trivy config"
    else
        skip "trivy not found"
    fi
else
    skip "terraform not found"
fi

echo ""
echo "=========================================="
echo "=== C6: Ansible Check ==="
echo "=========================================="
if command -v ansible-playbook &>/dev/null; then
    TMPINV=$(mktemp)
    printf '[app]\napp1 ansible_host=127.0.0.1 private_ip=10.0.1.10\n[monitor]\nmon1 ansible_host=127.0.0.1 private_ip=10.0.1.20\n[all:vars]\nansible_user=ubuntu\nenv_name=staging\n' > "$TMPINV"
    echo "Running ansible-playbook --syntax-check..."
    ansible-playbook -i "$TMPINV" ansible/site.yml --syntax-check 2>&1 && ok "ansible-playbook syntax" || fail "ansible-playbook syntax"
    rm -f "$TMPINV"

    if command -v ansible-lint &>/dev/null; then
        echo "Running ansible-lint..."
        ansible-lint ansible/site.yml 2>&1 && ok "ansible-lint" || fail "ansible-lint"
    else
        skip "ansible-lint not found"
    fi
else
    skip "ansible-playbook not found"
fi

echo ""
echo "=========================================="
echo "=== C7: Puppet Check ==="
echo "=========================================="
if command -v puppet &>/dev/null; then
    echo "Running puppet parser validate..."
    puppet parser validate puppet/manifests/site.pp puppet/modules/baseline/manifests/init.pp 2>&1 \
        && ok "puppet parser validate" || fail "puppet parser validate"

    echo "Running puppet epp validate..."
    puppet epp validate puppet/modules/baseline/templates/motd.epp 2>&1 \
        && ok "puppet epp validate" || fail "puppet epp validate"

    if command -v puppet-lint &>/dev/null; then
        echo "Running puppet-lint..."
        puppet-lint puppet/ 2>&1 && ok "puppet-lint" || fail "puppet-lint"
    else
        skip "puppet-lint not found"
    fi

    echo "Testing custom function env_label..."
    FUNC_OUT=$(puppet apply --modulepath=puppet/modules -e 'notice(baseline::env_label("app-prod-1"))' 2>&1)
    if echo "$FUNC_OUT" | grep -q "PRODUCTION"; then
        ok "puppet custom function (PRODUCTION)"
    else
        fail "puppet custom function"
    fi

    echo "Running puppet apply --noop..."
    puppet apply --noop --modulepath=puppet/modules puppet/manifests/site.pp 2>&1 && ok "puppet apply --noop" || fail "puppet apply --noop"
else
    skip "puppet not found"
fi

echo ""
echo "=========================================="
echo "=== C8: Nagios Plugin Check (6 cases) ==="
echo "=========================================="
bash scripts/test_plugin.sh && ok "all 6 Nagios plugin cases + shellcheck" || fail "Nagios plugin test suite"

echo ""
echo "=========================================="
echo "=== FINAL SUMMARY ==="
echo "PASS: $PASS | FAIL: $FAIL | SKIP: $SKIP"
echo "=========================================="
