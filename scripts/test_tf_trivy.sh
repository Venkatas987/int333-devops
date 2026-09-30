#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
set -euo pipefail

cd ~/int333_check/terraform

echo "=== TERRAFORM FMT CHECK ==="
terraform fmt -check -recursive
echo "terraform fmt: PASS"

echo "=== TERRAFORM VALIDATE ==="
terraform validate
echo "terraform validate: PASS"

echo "=== TRIVY CONFIG SCAN ==="
trivy config --ignorefile .trivyignore .
echo "trivy config: PASS"
