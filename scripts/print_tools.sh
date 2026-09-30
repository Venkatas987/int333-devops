#!/usr/bin/env bash
export PATH="/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH"

echo "=== TOOL VERSIONS IN WSL Ubuntu-24.04 ==="
tools=(
  "node:node -v"
  "docker:docker --version"
  "terraform:terraform -version"
  "ansible:ansible --version"
  "ansible-lint:ansible-lint --version"
  "puppet:puppet --version"
  "puppet-lint:puppet-lint --version"
  "shellcheck:shellcheck --version"
  "kubectl:kubectl version --client"
  "kind:kind --version"
  "kubeconform:kubeconform -v"
  "actionlint:actionlint -version"
  "trivy:trivy -v"
)

printf "%-15s | %-50s\n" "Tool" "Version"
printf "%-15s-+-%-50s\n" "---------------" "--------------------------------------------------"

for item in "${tools[@]}"; do
  name="${item%%:*}"
  cmd="${item#*:}"
  
  if command -v "$name" &>/dev/null; then
    ver=$($cmd 2>&1 | head -1 | tr -d '\r')
    printf "%-15s | %-50s\n" "$name" "$ver"
  else
    printf "%-15s | %-50s\n" "$name" "MISSING / NOT INSTALLED"
  fi
done
