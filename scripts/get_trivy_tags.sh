#!/usr/bin/env bash
export PATH=/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH
git ls-remote --tags https://github.com/aquasecurity/trivy-action.git | grep -E "0\.24\.0|0\.28\.0|0\.29\.0|v0\.28\.0" || true
