#!/usr/bin/env bash
export PATH="$HOME/.local/bin:/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$PATH"

echo "=== USER & SUDO ==="
whoami
sudo -n true 2>/dev/null && echo "SUDO_NOPASSWD: YES" || echo "SUDO_NOPASSWD: NO"

echo "=== TOOL VERSIONS ==="
which node >/dev/null 2>&1 && echo "Node: $(node -v)" || echo "Node: NOT_FOUND"
which npm >/dev/null 2>&1 && echo "NPM: $(npm -v)" || echo "NPM: NOT_FOUND"
which docker >/dev/null 2>&1 && echo "Docker: $(docker --version)" || echo "Docker: NOT_FOUND"
which kubectl >/dev/null 2>&1 && echo "Kubectl: $(kubectl version --client 2>&1 | head -1)" || echo "Kubectl: NOT_FOUND"
which terraform >/dev/null 2>&1 && echo "Terraform: $(terraform -version | head -1)" || echo "Terraform: NOT_FOUND"
which ansible >/dev/null 2>&1 && echo "Ansible: $(ansible --version | head -1)" || echo "Ansible: NOT_FOUND"
which ansible-lint >/dev/null 2>&1 && echo "Ansible-lint: $(ansible-lint --version | head -1)" || echo "Ansible-lint: NOT_FOUND"
which puppet >/dev/null 2>&1 && echo "Puppet: $(puppet --version 2>&1)" || echo "Puppet: NOT_FOUND"
which puppet-lint >/dev/null 2>&1 && echo "Puppet-lint: $(puppet-lint --version 2>&1)" || echo "Puppet-lint: NOT_FOUND"
which shellcheck >/dev/null 2>&1 && echo "Shellcheck: $(shellcheck --version | head -2 | tail -1)" || echo "Shellcheck: NOT_FOUND"
which actionlint >/dev/null 2>&1 && echo "Actionlint: $(actionlint -version)" || echo "Actionlint: NOT_FOUND"
which kubeconform >/dev/null 2>&1 && echo "Kubeconform: $(kubeconform -v)" || echo "Kubeconform: NOT_FOUND"
which trivy >/dev/null 2>&1 && echo "Trivy: $(trivy -v 2>&1 | head -1)" || echo "Trivy: NOT_FOUND"
which kind >/dev/null 2>&1 && echo "Kind: $(kind --version 2>&1)" || echo "Kind: NOT_FOUND"
which curl >/dev/null 2>&1 && echo "Curl: $(curl --version | head -1)" || echo "Curl: NOT_FOUND"
which bc >/dev/null 2>&1 && echo "Bc: $(bc --version | head -1)" || echo "Bc: NOT_FOUND"
