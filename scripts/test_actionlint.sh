#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
set -euo pipefail

cd ~/int333_check
echo "=== RUNNING ACTIONLINT ==="
actionlint .github/workflows/*.yml
echo "actionlint: SUCCESS (exit 0)"
