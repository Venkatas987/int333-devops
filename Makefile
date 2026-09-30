# Makefile
# WHY: A Makefile gives every developer (and the CI pipeline) a single,
# documented command for each workflow step.  Instead of remembering long
# commands, you just type `make test` or `make lint`.
#
# Usage:
#   make install   – install Node dependencies
#   make test      – run unit tests
#   make build     – build the Docker image locally
#   make lint      – run all available linters/validators
#   make plan      – Terraform plan with dummy values (no cloud resources created)
#   make clean     – remove generated/temporary files

# Default shell for all recipe lines.
SHELL := /bin/bash

# Phony targets are not files – always run them when requested.
.PHONY: install test build lint plan clean deps

# ── Dependencies ──────────────────────────────────────────────────────────────
# WHY: Installs external Ansible collection dependencies specified in requirements.yml.
deps:
	@echo "==> Installing Ansible collection dependencies"
	ansible-galaxy collection install -r ansible/requirements.yml

# ── Install ───────────────────────────────────────────────────────────────────
# WHY: `npm ci` (clean install) is stricter than `npm install` and is the
# recommended command for CI environments.
install:
	@echo "==> Installing Node.js dependencies"
	npm ci

# ── Test ──────────────────────────────────────────────────────────────────────
# WHY: Run this before every commit to catch regressions early.
test: install
	@echo "==> Running unit tests"
	npm test

# ── Build ─────────────────────────────────────────────────────────────────────
# WHY: Builds the Docker image locally so you can test it before pushing.
# Requires Docker to be running.
build:
	@echo "==> Building Docker image"
	docker build -t devops-demo:local .
	@echo "==> Testing /healthz inside the container"
	docker run --rm -d --name devops-test -p 13000:3000 devops-demo:local
	sleep 2
	curl -sf http://localhost:13000/healthz || (docker stop devops-test; exit 1)
	@echo "==> Verifying non-root user"
	docker exec devops-test whoami
	docker stop devops-test
	@echo "==> Testing read-only filesystem"
	docker run --rm --read-only devops-demo:local node -e "require('./server')" && echo "READ_ONLY_OK"

# ── Lint ──────────────────────────────────────────────────────────────────────
# WHY: Linters catch bugs and style issues before they hit CI.
# Each tool is called with `|| true` unless we want the whole target to fail.
# actionlint and kubeconform exit non-zero on failure.
lint:
	@echo "==> Kubernetes manifests (kubeconform)"
	@if command -v kubeconform &>/dev/null; then \
		kubeconform -strict -summary k8s/; \
	else \
		echo "  kubeconform not installed – skipping"; \
	fi

	@echo "==> GitHub Actions workflows (actionlint)"
	@if command -v actionlint &>/dev/null; then \
		actionlint .github/workflows/*.yml; \
	else \
		echo "  actionlint not installed – skipping"; \
	fi

	@echo "==> Terraform fmt + validate"
	@if command -v terraform &>/dev/null; then \
		cd terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false && terraform validate; \
	else \
		echo "  terraform not installed – skipping"; \
	fi

	@echo "==> Ansible YAML syntax check"
	@if command -v ansible-playbook &>/dev/null; then \
		cd ansible && ansible-playbook --syntax-check site.yml -i /dev/null && cd .. && ansible-lint ansible/site.yml; \
	else \
		echo "  ansible-playbook not installed – skipping"; \
	fi

	@echo "==> Puppet validate + lint"
	@if command -v puppet &>/dev/null; then \
		puppet parser validate puppet/manifests/site.pp puppet/modules/baseline/manifests/init.pp; \
		puppet-lint puppet/ || true; \
	else \
		echo "  puppet not installed – skipping"; \
	fi

	@echo "==> Nagios plugin (shellcheck)"
	@if command -v shellcheck &>/dev/null; then \
		shellcheck nagios/plugins/check_app_health.sh; \
	else \
		echo "  shellcheck not installed – skipping"; \
	fi
	@echo "==> Lint complete"

# ── Plan ──────────────────────────────────────────────────────────────────────
# WHY: `terraform plan` shows exactly what would be created/changed/destroyed
# WITHOUT making any changes.  Always run this before `terraform apply`.
# NEVER run terraform apply from this Makefile – always ask the team first.
plan:
	@echo "==> Terraform plan (DUMMY VALUES – no real AWS credentials)"
	@echo "    Set real values in terraform/terraform.tfvars before running plan"
	cd terraform && terraform init -backend=false -input=false && \
		terraform plan \
		  -var="my_ip_cidr=203.0.113.4/32" \
		  -var="public_key_path=/dev/null" \
		  -var="private_key_path=/dev/null" \
		  -input=false || true

# ── Clean ─────────────────────────────────────────────────────────────────────
# WHY: Removes generated files so you start fresh.
# Does NOT delete terraform state or the AWS resources!
clean:
	@echo "==> Cleaning generated files"
	rm -rf node_modules
	rm -f  ansible/inventory/hosts.ini
	rm -rf terraform/.terraform
	@echo "==> Done"
