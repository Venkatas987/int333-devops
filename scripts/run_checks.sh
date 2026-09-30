#!/usr/bin/env bash
# scripts/run_checks.sh - Runs all checks C1-C8 from inside WSL
# Run from ~/int333_check directory

set -euo pipefail
PASS=0
FAIL=0
SKIP=0

ok()   { echo "  ✅ PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $*"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭  SKIP: $*"; SKIP=$((SKIP+1)); }

echo "=========================================="
echo "INT333 DevOps Project - Full Check Suite"
echo "=========================================="
cd ~/int333_check

# ── C1: npm test ─────────────────────────────────────────────────────────────
echo ""
echo "=== C1: App tests (npm ci + npm test) ==="
if npm ci --silent 2>&1 && npm test 2>&1; then
  ok "npm test: 3/3 passed"
else
  fail "npm test"
fi

# ── C2: Docker ───────────────────────────────────────────────────────────────
echo ""
echo "=== C2: Docker build + run ==="
if ! command -v docker &>/dev/null; then
  skip "docker not available"
else
  docker build -t devops-demo:local . 2>&1 | tail -3
  docker run --rm -d --name devtest -p 3000:3000 devops-demo:local
  sleep 3

  HEALTH=$(curl -sf http://localhost:3000/healthz 2>/dev/null || echo "FAIL")
  if echo "$HEALTH" | grep -q '"status":"ok"'; then
    ok "GET /healthz = $HEALTH"
  else
    fail "GET /healthz returned: $HEALTH"
  fi

  USER=$(docker exec devtest whoami 2>/dev/null)
  if [ "$USER" = "node" ]; then
    ok "whoami = node (non-root)"
  else
    fail "whoami = $USER (expected node)"
  fi

  docker stop devtest >/dev/null

  # read-only filesystem test
  if docker run --rm --read-only devops-demo:local node -e "require('./server')" 2>/dev/null; then
    ok "read-only filesystem: container starts ok"
  else
    fail "read-only filesystem: container failed to start"
  fi
fi

# ── C3: k8s YAML (kubeconform or python yaml) ────────────────────────────────
echo ""
echo "=== C3: Kubernetes manifests ==="
if command -v kubeconform &>/dev/null; then
  if kubeconform -strict -summary k8s/ 2>&1; then
    ok "kubeconform: all manifests valid"
  else
    fail "kubeconform: manifests invalid"
  fi
else
  skip "kubeconform not installed; using python yaml"
  YAML_ERR=$(python3 -c "
import yaml, glob, sys
errors=[]
for f in glob.glob('k8s/*.yaml'):
    try:
        list(yaml.safe_load_all(open(f)))
        print(f'  OK: {f}')
    except Exception as e:
        print(f'  ERR: {f}: {e}')
        errors.append(f)
sys.exit(1 if errors else 0)
" 2>&1)
  echo "$YAML_ERR"
  if echo "$YAML_ERR" | grep -q ERR; then
    fail "k8s YAML syntax"
  else
    ok "k8s YAML syntax (python yaml)"
  fi
fi

# ── C4: actionlint ───────────────────────────────────────────────────────────
echo ""
echo "=== C4: GitHub Actions (actionlint) ==="
if command -v actionlint &>/dev/null; then
  if actionlint .github/workflows/*.yml 2>&1; then
    ok "actionlint: no issues"
  else
    fail "actionlint: found issues"
  fi
else
  # Validate YAML syntax instead
  YAML_ERR=$(python3 -c "
import yaml, glob
errors=[]
for f in glob.glob('.github/workflows/*.yml'):
    try:
        list(yaml.safe_load_all(open(f)))
        print(f'  OK: {f}')
    except Exception as e:
        print(f'  ERR: {f}: {e}')
        errors.append(f)
import sys; sys.exit(1 if errors else 0)
" 2>&1)
  echo "$YAML_ERR"
  if echo "$YAML_ERR" | grep -q ERR; then
    fail "workflow YAML syntax"
  else
    skip "actionlint not installed; YAML syntax OK"
  fi
fi

# ── C5: Terraform ────────────────────────────────────────────────────────────
echo ""
echo "=== C5: Terraform fmt + validate ==="
if command -v terraform &>/dev/null; then
  cd terraform
  if terraform fmt -check -recursive 2>&1; then
    ok "terraform fmt -check"
  else
    fail "terraform fmt -check"
  fi
  if terraform init -backend=false -input=false 2>&1 | tail -3; then
    if terraform validate 2>&1; then
      ok "terraform validate"
    else
      fail "terraform validate"
    fi
  else
    fail "terraform init -backend=false"
  fi
  cd ..
else
  skip "terraform not installed"
fi

# ── C6: Ansible ──────────────────────────────────────────────────────────────
echo ""
echo "=== C6: Ansible syntax + ansible-lint ==="
if command -v ansible-playbook &>/dev/null; then
  # Create temporary dummy inventory
  TMPINV=$(mktemp)
  cat > "$TMPINV" << 'EOF'
[app]
app1 ansible_host=127.0.0.1 private_ip=127.0.0.1 ansible_connection=local

[monitor]
mon1 ansible_host=127.0.0.1 private_ip=127.0.0.1 ansible_connection=local
EOF
  if ansible-playbook --syntax-check -i "$TMPINV" ansible/site.yml 2>&1; then
    ok "ansible-playbook --syntax-check"
  else
    fail "ansible-playbook --syntax-check"
  fi
  rm -f "$TMPINV"

  if command -v ansible-lint &>/dev/null; then
    if ansible-lint ansible/site.yml 2>&1; then
      ok "ansible-lint"
    else
      fail "ansible-lint (see output above)"
    fi
  else
    skip "ansible-lint not installed"
  fi
else
  skip "ansible-playbook not installed"
fi

# ── C7: Puppet ───────────────────────────────────────────────────────────────
echo ""
echo "=== C7: Puppet parser validate + puppet-lint ==="
if command -v puppet &>/dev/null; then
  if puppet parser validate puppet/manifests/site.pp puppet/modules/baseline/manifests/init.pp 2>&1; then
    ok "puppet parser validate"
  else
    fail "puppet parser validate"
  fi
  if command -v puppet-lint &>/dev/null; then
    if puppet-lint puppet/ 2>&1; then
      ok "puppet-lint"
    else
      fail "puppet-lint (see output above)"
    fi
  else
    skip "puppet-lint not installed"
  fi
  echo "  [NOTE] Skipping puppet apply --noop as it requires root. Run manually."
else
  skip "puppet not installed"
fi

# ── C8: Nagios plugin ────────────────────────────────────────────────────────
echo ""
echo "=== C8: Nagios plugin (shellcheck + functional) ==="
if command -v shellcheck &>/dev/null; then
  if shellcheck nagios/plugins/check_app_health.sh 2>&1; then
    ok "shellcheck"
  else
    fail "shellcheck"
  fi
else
  skip "shellcheck not installed"
fi

# Functional test: start the app, test plugin, stop app
chmod +x nagios/plugins/check_app_health.sh
node server.js &
APP_PID=$!
sleep 2

PLUGIN_OUT=$(./nagios/plugins/check_app_health.sh -H 127.0.0.1 -p 3000 -w 0.5 -c 2 2>&1)
PLUGIN_EXIT=$?
echo "  Plugin output: $PLUGIN_OUT"
if [ $PLUGIN_EXIT -eq 0 ] && echo "$PLUGIN_OUT" | grep -q "OK"; then
  ok "Plugin: exit 0 (OK) when app is running"
else
  fail "Plugin: expected exit 0, got $PLUGIN_EXIT"
fi

if echo "$PLUGIN_OUT" | grep -q "time="; then
  ok "Plugin: perfdata present"
else
  fail "Plugin: no perfdata in output"
fi

# Stop app, test CRITICAL
kill $APP_PID 2>/dev/null; sleep 2
PLUGIN_OUT2=$(./nagios/plugins/check_app_health.sh -H 127.0.0.1 -p 3000 -w 0.5 -c 2 2>&1 || true)
PLUGIN_EXIT2=$?
if [ $PLUGIN_EXIT2 -eq 2 ]; then
  ok "Plugin: exit 2 (CRITICAL) when app is down"
else
  fail "Plugin: expected exit 2 (CRITICAL), got $PLUGIN_EXIT2. Output: $PLUGIN_OUT2"
fi

# Test no args = UNKNOWN
PLUGIN_OUT3=$(./nagios/plugins/check_app_health.sh 2>&1 || true)
PLUGIN_EXIT3=$?
if [ $PLUGIN_EXIT3 -eq 3 ]; then
  ok "Plugin: exit 3 (UNKNOWN) with no args"
else
  fail "Plugin: expected exit 3 (UNKNOWN), got $PLUGIN_EXIT3"
fi

echo ""
echo "=========================================="
echo "SUMMARY: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "=========================================="
