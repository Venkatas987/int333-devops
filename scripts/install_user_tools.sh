#!/usr/bin/env bash
set -e
mkdir -p ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

echo "=== Installing user-space DevOps tools ==="

# 1. Terraform
if ! command -v terraform &>/dev/null; then
    echo "Installing Terraform..."
    curl -fsSL https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip -o /tmp/terraform.zip
    unzip -q -o /tmp/terraform.zip -d ~/.local/bin/
    rm -f /tmp/terraform.zip
fi

# 2. Actionlint
if ! command -v actionlint &>/dev/null; then
    echo "Installing Actionlint..."
    curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz -o /tmp/actionlint.tar.gz
    tar -xzf /tmp/actionlint.tar.gz -C ~/.local/bin/ actionlint
    rm -f /tmp/actionlint.tar.gz
fi

# 3. Kubeconform
if ! command -v kubeconform &>/dev/null; then
    echo "Installing Kubeconform..."
    curl -fsSL https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz -o /tmp/kubeconform.tar.gz
    tar -xzf /tmp/kubeconform.tar.gz -C ~/.local/bin/ kubeconform
    rm -f /tmp/kubeconform.tar.gz
fi

# 4. Kind
if ! command -v kind &>/dev/null; then
    echo "Installing Kind..."
    curl -fsSL -Lo ~/.local/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
    chmod +x ~/.local/bin/kind
fi

# 5. Trivy
if ! command -v trivy &>/dev/null; then
    echo "Installing Trivy..."
    curl -fsSL https://github.com/aquasecurity/trivy/releases/download/v0.56.2/trivy_0.56.2_Linux-64bit.tar.gz -o /tmp/trivy.tar.gz
    tar -xzf /tmp/trivy.tar.gz -C ~/.local/bin/ trivy
    rm -f /tmp/trivy.tar.gz
fi

# 6. Ansible (via pipx or pip)
if ! command -v ansible &>/dev/null; then
    echo "Installing Ansible via pip/pipx..."
    pipx install --include-deps ansible 2>/dev/null || pip install --user ansible --break-system-packages 2>/dev/null || pip install --user ansible 2>/dev/null || echo "Ansible install skipped"
fi

# 7. Puppet-lint
if ! command -v puppet-lint &>/dev/null; then
    echo "Installing puppet-lint..."
    gem install --user-install puppet-lint 2>/dev/null || /opt/puppetlabs/puppet/bin/gem install --user-install puppet-lint 2>/dev/null || echo "puppet-lint install skipped"
fi

echo "PATH: $PATH"
echo "All done user tool install!"
