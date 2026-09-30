#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
set -euo pipefail

echo "=== TRIVY-ACTION ==="
git ls-remote https://github.com/aquasecurity/trivy-action.git refs/tags/0.24.0 refs/tags/v0.28.0 refs/tags/0.28.0 2>/dev/null || true

echo "=== GITLEAKS-ACTION ==="
git ls-remote https://github.com/gitleaks/gitleaks-action.git refs/tags/v2 refs/tags/v2.3.9 2>/dev/null || true

echo "=== CODEQL-ACTION ==="
git ls-remote https://github.com/github/codeql-action.git refs/tags/v3 2>/dev/null || true
