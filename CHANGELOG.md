# CHANGELOG.md

All changes made by the AI agent (Antigravity) to build this repository from scratch.

---

## [1.0.0] — 2026-09-30

### Created from scratch

#### Root files
| File | Notes |
|------|-------|
| `server.js` | Provided in the prompt; written verbatim + inline beginner comments added |
| `package.json` | Added `"lint": "echo 'No linter configured'"` so `npm run lint --if-present` works in CI |
| `test/server.test.js` | New file. Uses `node:test` (built-in, Node 20+). Three tests: /healthz→200, /→200, unknown→404. A mock req/res helper avoids any network dependency |
| `package-lock.json` | Generated with `npm install --package-lock-only` (confirmed: `npm test` passes, 3/3) |
| `.gitignore` | Covers node_modules, .env*, *.tfstate*, .terraform/, terraform/terraform.tfvars, ansible/inventory/hosts.ini, *.retry |
| `.dockerignore` | Excludes node_modules, .git, .github, k8s, terraform, ansible, puppet, nagios, *.md, .env* |
| `Dockerfile` | Multi-stage node:20-alpine. Stage 1: `npm ci --omit=dev`. Stage 2: non-root `node` user, EXPOSE 3000, HEALTHCHECK via wget (Alpine has no curl by default), CMD node server.js |

#### k8s/
| File | Notes |
|------|-------|
| `deployment.yaml` | 2 replicas, RollingUpdate (maxUnavailable 0, maxSurge 1), readiness+liveness on /healthz:3000, requests 100m/128Mi, limits 500m/256Mi, runAsNonRoot, allowPrivilegeEscalation false, readOnlyRootFilesystem true, drop ALL capabilities |
| `service.yaml` | ClusterIP, port 80→3000 |
| `ingress.yaml` | ingressClassName nginx, host myapp.example.com |
| `hpa.yaml` | autoscaling/v2, min 2, max 6, CPU 70% |

#### .github/workflows/
| File | Notes |
|------|-------|
| `ci-cd.yml` | Triggers: push main, tags v*.*.*, PRs. concurrency cancel-in-progress. Jobs: test (setup-node 20 + npm cache), build (login GHCR, buildx, metadata-action sha/semver/latest, build-push gha cache, Trivy SARIF upload), deploy-staging (main), deploy-production (tags, environment). Both deploy jobs: decode KUBE_CONFIG_B64, kubectl apply, set image with digest, rollout status, rollout undo on failure |
| `infra.yml` | Triggers on changes to terraform/ ansible/ puppet/ nagios/. Jobs: terraform (fmt -check, init -backend=false, validate, Trivy config scan), ansible (pip install ansible ansible-lint, syntax-check, ansible-lint), puppet (gem install puppet puppet-lint, parser validate, puppet-lint), nagios-plugin (shellcheck) |

#### terraform/
| File | Notes |
|------|-------|
| `versions.tf` | required_version >=1.6; providers aws~>5.0, local~>2.5, null~>3.2; S3+DynamoDB backend commented out |
| `variables.tf` | region, project, instance_type, public_key_path, private_key_path, my_ip_cidr (no default), run_ansible (bool) |
| `main.tf` | aws provider with default_tags; locals env=workspace; Ubuntu 22.04 AMI data source (owner 099720109477); aws_key_pair; security_group (22+80 from my_ip_cidr, 30080 public, all egress); module "app" (instance_type var) + module "monitor" (t3.micro); local_file for hosts.ini from inventory.tpl; null_resource local-exec ansible-playbook (count = run_ansible) |
| `inventory.tpl` | [app] + [monitor] + [all:vars] with ansible_user, key_path, env_name |
| `outputs.tf` | app_url, nagios_url, app_public_ip, monitor_public_ip, ssh_app, ssh_monitor |
| `terraform.tfvars.example` | Example with 203.0.113.4/32 placeholder |
| `modules/ec2/main.tf` | aws_instance with 20GB encrypted gp3 root volume, IMDSv2 http_tokens=required, tags Name+Role |
| `modules/ec2/variables.tf` | name, ami_id, instance_type, key_name, security_group_id, role |
| `modules/ec2/outputs.tf` | id, public_ip, private_ip |

#### ansible/
| File | Notes |
|------|-------|
| `ansible.cfg` | inventory, roles_path, host_key_checking False, become True, yaml callback, timeout 60, pipelining True |
| `group_vars/all.yml` | app_image (OWNER/REPO placeholder), app_namespace staging, app_node_port 30080, nagios_admin_user, nagios_admin_password (placeholder with Vault instructions) |
| `site.yml` | 3 plays: all→common, app→k3s+app, monitor→nagios_server; all with tags |
| `inventory/.gitkeep` | Keeps directory tracked; explains how to create hosts.ini manually |
| `roles/common/tasks/main.yml` | apt update, install packages, harden sshd (PermitRootLogin no, PasswordAuthentication no, validate with sshd -t), ensure chrony running |
| `roles/common/handlers/main.yml` | Restart sshd |
| `roles/k3s/tasks/main.yml` | Install via curl get.k3s.io (creates: /usr/local/bin/k3s), start service, wait until Ready |
| `roles/app/tasks/main.yml` | Create /opt/k8s dir, copy manifests, create namespace (idempotent), apply deployment+service, set image, patch to NodePort, wait rollout |
| `roles/nagios_server/tasks/main.yml` | Install nagios4+plugins+apache2+curl+bc; copy plugin; template app.cfg.j2; create htdigest; enable apache modules; a2enconf nagios4; start services |
| `roles/nagios_server/handlers/main.yml` | Restart nagios4, Restart apache2 |
| `roles/nagios_server/templates/app.cfg.j2` | Commands check_app_http + check_app_health; host app1 (IP from hostvars); 4 services: PING, SSH, App HTTP /healthz, App response time |

#### puppet/
| File | Notes |
|------|-------|
| `manifests/site.pp` | node default { include baseline }; node /^app/ { include baseline + jq + net-tools } |
| `modules/baseline/manifests/init.pp` | Typed params (packages Array[String], ntp_svc String); packages; chrony service with require; env_label = baseline::env_label(...); /etc/motd from epp template; user deploy |
| `modules/baseline/templates/motd.epp` | EPP (not ERB) template — Puppet's modern template language. Shows hostname, env_label, OS, memory, CPU |
| `modules/baseline/lib/puppet/functions/baseline/env_label.rb` | Puppet 4.x function API; maps hostname regex → PRODUCTION/STAGING/DEVELOPMENT |

#### nagios/plugins/
| File | Notes |
|------|-------|
| `check_app_health.sh` | getopts -H -p -w -c; curl /healthz with 10s timeout and --write-out for HTTP code; validates 200 + `"status":"ok"` in body; second curl for response time; bc for float comparison; perfdata time=Xs;warn;crit;0; exit 0/1/2/3 |

#### Documentation
| File | Notes |
|------|-------|
| `ARCHITECTURE.md` | ASCII diagram, 13-step code-change journey, tool table (problem + what breaks without it), push vs pull analogy (pizza vs mailbox), 20-term glossary, 10 viva Q&A |
| `CHANGELOG.md` | This file |

---

## [1.1.0] — 2026-09-30

### Bugs Fixed (B1 – B8)

| Bug ID | Problem | Resolution | Files Changed |
|--------|---------|------------|---------------|
| **B1** | Nagios marks app host DOWN due to missing ICMP/SSH/Port rules and public IP routing | Added `self = true` ingress rules for ICMP (ping), SSH (22), and NodePort (30080) in AWS security group; passed `app_private_ip` and `monitor_private_ip` via `inventory.tpl`; configured `app.cfg.j2` to monitor via VPC private IP | `terraform/main.tf`<br>`terraform/inventory.tpl`<br>`ansible/roles/nagios_server/templates/app.cfg.j2` |
| **B2** | Windows CRLF line endings break Linux shebangs and bash scripts | Created `.gitattributes` enforcing `eol=lf` for all shell, YAML, HCL, and template files; converted all project scripts to Unix LF | `.gitattributes`<br>`nagios/plugins/check_app_health.sh` |
| **B3** | Nagios `htdigest` here-string/pipe unreliable across shell versions | Replaced with idempotent MD5 calculation using `printf` and `md5sum` written directly to `/etc/nagios4/htdigest.users` with `0640 root:www-data` | `ansible/roles/nagios_server/tasks/main.yml` |
| **B4** | `apt` lock contention on freshly booted EC2 instances | Added `lock_timeout: 180` to every `ansible.builtin.apt` task across all roles | `ansible/roles/common/tasks/main.yml`<br>`ansible/roles/nagios_server/tasks/main.yml`<br>`ansible/roles/puppet_agent/tasks/main.yml` |
| **B5** | Trivy flags accepted demo infrastructure rules in Terraform | Created `terraform/.trivyignore` with explicit justifications for open egress (AVD-AWS-0104/AWS-0104) and public demo NodePort (AVD-AWS-0107/AWS-0107, AVD-AWS-0172/AWS-0172); added missing description to SG egress rule; updated `infra.yml` with `trivyignores: "terraform/.trivyignore"` | `terraform/.trivyignore`<br>`terraform/main.tf`<br>`.github/workflows/infra.yml` |
| **B6** | Private image pull requires Docker registry secret | Added optional task in `ansible/roles/app` that creates `ghcr-pull` secret when `ghcr_pull_user` and `ghcr_pull_token` are passed | `ansible/roles/app/tasks/main.yml`<br>`README.md` |
| **B7** | Puppet was disconnected from servers | Created `ansible/roles/puppet_agent` that installs `puppet-agent`, syncs manifests and modules to `/opt/puppet-demo/`, and runs `puppet apply --detailed-exitcodes` idempotently (rc 0 or 2 = success) | `ansible/roles/puppet_agent/tasks/main.yml`<br>`ansible/site.yml` |
| **B8** | Code review discoveries verified against actual codebase | Replaced array index [0] JSON-patch in `roles/app` with strategic merge-patch; verified `curl` and `bc` installed for Nagios plugin; verified zero runtime dependencies in `Dockerfile`; added `runAsUser: 1000` to `k8s/deployment.yaml` for Kubernetes non-numeric user compatibility; fixed unescaped `%{` in `inventory.tpl` | `ansible/roles/app/tasks/main.yml`<br>`Dockerfile`<br>`k8s/deployment.yaml`<br>`terraform/inventory.tpl` |

### New Files Created (Part D)

| File | Purpose |
|------|---------|
| `Makefile` | Standard workflow targets: `install`, `test`, `build`, `lint`, `plan`, `clean` |
| `.github/dependabot.yml` | Automated weekly dependency updates for npm, Docker base images, GitHub Actions, and Terraform providers |
| `.github/workflows/security.yml` | Static application security testing (CodeQL for JS) and secret scanning (Gitleaks) |
| `terraform/.trivyignore` | Documented exceptions for demo AWS security group configurations |
| `ansible/roles/puppet_agent/` | Standalone Puppet baseline enforcement role |
| `scripts/test_plugin.sh` | Automated test suite verifying all 6 Nagios exit code cases (0, 1, 2, 3) and shellcheck |
| `scripts/run_c3_c7.sh` | Execution harness for C3-C7 validators in WSL |
| `scripts/test_c9_kind.ps1` | End-to-end local Kubernetes cluster lifecycle test using Kind |

### Checks Performed & Real Verification Results

| Check | Tool / Command | Real Status | Verification Evidence / Command Output Summary |
|-------|----------------|-------------|------------------------------------------------|
| **C1** | `npm test` | ✅ PASS | 3/3 tests passed in 157ms (`node:test`) |
| **C2** | Docker build & run | ✅ PASS | Multi-stage image built (`devops-demo:local`); detached `/healthz` returned `{"status":"ok"}`; `whoami` returned `node`; real read-only test returned `{"status":"ok"}`; health status transitioned to `healthy` |
| **C3** | `kubeconform -strict -summary k8s/` | ✅ PASS | Summary: 4 resources found in 4 files - Valid: 4, Invalid: 0, Errors: 0, Skipped: 0 |
| **C4** | `actionlint .github/workflows/*.yml` | ✅ PASS | Clean exit (code 0) across `ci-cd.yml`, `infra.yml`, and `security.yml` |
| **C5** | Terraform fmt, init, validate, Trivy | ✅ PASS | `terraform fmt -check -recursive`: PASS; `terraform init -backend=false`: PASS; `terraform validate`: Success! The configuration is valid; `trivy config`: 0 misconfigurations |
| **C5-plan** | `terraform plan` | ⏭ NOT RUN | Requires AWS credentials for AMI data source lookup (safety rule: credentials not configured) |
| **C6** | Ansible syntax & `ansible-lint` | ✅ PASS | `ansible-playbook --syntax-check`: PASS; `ansible-lint`: 0 failure(s), 0 warning(s) in 8 files processed, profile 'production' |
| **C7** | Puppet validate, custom func, noop | ✅ PASS | `puppet parser validate`: PASS; `puppet epp validate`: PASS; `puppet-lint`: PASS; `baseline::env_label("app-prod-1")`: returned `PRODUCTION`; `puppet apply --noop`: compiled and applied catalog |
| **C8** | Nagios plugin 6-case test suite | ✅ PASS | `test_plugin.sh`: Case 1 (Healthy -> 0 with `time=`): PASS; Case 2 (Slow -> 1): PASS; Case 3 (Critical -> 2): PASS; Case 4 (Stopped -> 2): PASS; Case 5 (No args -> 3): PASS; Case 6 (Unknown opt -Z -> 3): PASS; `shellcheck`: PASS |
| **C9** | Kind local Kubernetes lifecycle | ✅ PASS | `kind create cluster demo` -> `kind load docker-image` -> applied manifests -> `rollout status` completed successfully -> port-forward `/healthz` returned `{"status":"ok"}` -> `kind delete cluster` |

---

### Top 5 Remaining Risks for Real AWS Deployment

1. **AWS Credentials & Quotas:** `terraform plan` and `apply` require real AWS credentials (`aws configure`) with permissions for EC2, VPC, and Security Groups, and available t3.small/t3.micro instance quota in `ap-south-1`.
2. **KUBE_CONFIG_B64 Secret Connectivity:** Automated CI/CD deployment jobs (`deploy-staging`, `deploy-production`) in `ci-cd.yml` require a reachable k3s API endpoint (port 6443) from GitHub runners; jobs remain cleanly gated (`vars.ENABLE_K8S_DEPLOY == 'true'`) until configured.
3. **AWS Provider AMI Lookup:** The `aws_ami.ubuntu` data source requires cloud access to query Canonical AMIs; without credentials, `terraform validate` passes but `terraform plan` must be run on real AWS.
4. **Digest Authentication in Nagios:** The generated MD5 digest authentication relies on the standard `Nagios4` realm. If browser caching occurs, use private browsing or incognito to authenticate to `/nagios4`.
5. **NodePort 30080 AWS Ingress:** Port 30080 is exposed publicly for demo purposes. In production, this should be fronted by an Application Load Balancer or restricted to specific VPN/bastion CIDRs.

---

## [1.2.0] — 2026-09-30

### Hardening, Supply Chain Security & Architecture Alignment

#### 1. Gated Kubernetes CI/CD Deployment (`ci-cd.yml`)
- Added `if: vars.ENABLE_K8S_DEPLOY == 'true' && <condition>` to both `deploy-staging` and `deploy-production` jobs.
- Added `continue-on-error: true` to the SARIF upload step alongside `security-events: write` permission to prevent build failures if Code Scanning or SARIF upload is disabled on the repository.
- Verified with `actionlint` (clean exit 0).

#### 2. Supply Chain Security Pinning
- Pinned all security action references to full immutable commit SHAs with trailing version tag comments:
  - `aquasecurity/trivy-action@18f2510ee396bbf400402947b394f2dd8c87dbb0 # v0.29.0` (in `ci-cd.yml` and `infra.yml`)
  - `github/codeql-action/*@87ef0dc97def48aa960fbf026a2563ee9dbdb470 # v3` (in `ci-cd.yml` and `security.yml`)
  - `gitleaks/gitleaks-action@dcedce43c6f43de0b836d1fe38946645c9c638dc # v2` (in `security.yml`)
- Dependabot configured for weekly pull requests on the `github-actions` ecosystem.

#### 3. Terraform Hardening
- Added validation block to `var.my_ip_cidr` enforcing valid IPv4 CIDR notation and explicitly rejecting `0.0.0.0/0`.
- Replaced broad ignore entries in `terraform/.trivyignore` for public port 30080 with an inline `#trivy:ignore:AVD-AWS-0107` comment and justification on the ingress rule in `terraform/main.tf`.
- Kept `.trivyignore` exclusively for the accepted outbound egress rule (`AVD-AWS-0104`). Re-verified with `trivy config` (0 misconfigurations).

#### 4. Ansible Playbook & Roles Enhancement
- Replaced static `sleep 30` in Terraform `local-exec` with a dedicated initial play in `ansible/site.yml` using `ansible.builtin.wait_for_connection` (timeout 300s, `gather_facts: false`).
- Wrapped deployment rollout wait in `ansible/roles/app/tasks/main.yml` in a `block`/`rescue` construct that executes `k3s kubectl rollout undo deployment/myapp -n {{ app_namespace }}` if rollout fails or times out.
- Configured an automated 30-minute cron job in `ansible/roles/puppet_agent` to continuously enforce baseline configuration and remediate drift.
- Added `jq` to the apt package list in `ansible/roles/nagios_server`.
- Re-verified with `ansible-playbook --syntax-check` and `ansible-lint` (0 failures, 0 warnings, production profile).

#### 5. Documentation & Viva Exam Synchronization
- Updated `README.md` and `ARCHITECTURE.md` to clearly specify:
  - Puppet is masterless via Ansible in the deployed servers (with 30-min cron for drift correction); master-agent (pull) is the lab exercise.
  - Rollback is handled via Ansible rescue block and gated GitHub Actions deploy jobs.
  - Gitleaks and CodeQL run in a separate security workflow (`security.yml`).

---

## [1.3.0] — 2026-09-30

### Precision Hardening, Verification & Audit

#### 1. Ansible Rollout Logic Correction
- In `ansible/roles/app/tasks/main.yml`, confirmed the primary block task executes `k3s kubectl rollout status deployment/myapp -n {{ app_namespace }} --timeout=180s` with `changed_when: false`.
- The `k3s kubectl rollout undo` command is strictly restricted to the `rescue` section to recover from failed rollouts, followed by `ansible.builtin.fail`.
- Audited all roles (`common`, `k3s`, `app`, `nagios_server`, `puppet_agent`) to confirm 100% alignment between task descriptions and executed commands.

#### 2. SHA Pin Verification via `git ls-remote`
- Verified all pinned Action SHAs against GitHub remote tag references:
  - `aquasecurity/trivy-action`: `v0.29.0` -> `18f2510ee396bbf400402947b394f2dd8c87dbb0` (Exact Match)
  - `github/codeql-action`: `v3` -> `87ef0dc97def48aa960fbf026a2563ee9dbdb470` / `1190a975f95ce23525efb6a3fc21ea29567c1b52` (Exact Match)
  - `gitleaks/gitleaks-action`: `v2` -> `dcedce43c6f43de0b836d1fe38946645c9c638dc` / `ff98106e4c7b2bc287b24eaf42907196329070c7` (Exact Match)

#### 3. Terraform Path Resolution (`pathexpand`) & Validation Proof
- Wrapped `var.public_key_path` in `file(pathexpand(var.public_key_path))` for `aws_key_pair.this`.
- Wrapped `var.private_key_path` in `pathexpand(var.private_key_path)` for inventory generation and local-exec invocation.
- Confirmed zero static sleep statements in `terraform/main.tf`.
- Tested and proved CIDR validation: `terraform plan -var "my_ip_cidr=0.0.0.0/0"` failed explicitly with:
  `The my_ip_cidr value must be a valid IPv4 CIDR block and cannot be 0.0.0.0/0.`

#### 4. Nagios Plugin Silent Error Handling
- Changed `getopts` in `nagios/plugins/check_app_health.sh` to silent mode (`:H:p:w:c:`).
- Added explicit `:` (missing argument) and `\?` (unknown option) handling, ensuring exactly one clean UNKNOWN line is output to stdout with exit code 3.
- Re-tested with 6/6 test suite passes and clean shellcheck.

#### 5. Documentation Cleanup
- Replaced legacy `motd.erb` reference in `README.md` syllabus mapping with `motd.epp`.
- Verified zero occurrences of `motd.erb` in the entire repository.

---

## [1.4.0] — 2026-09-30

### Commit SHA Pinning, Ubuntu 22.04 Jammy Container Testing & Hostname Harmonization

#### 1. Action Commit SHA Peeled Verification
- Pinned all GitHub Actions to exact commit objects, peeling annotated tags (`refs/tags/v*^{}`) where required:
  - `aquasecurity/trivy-action`: `18f2510ee396bbf400402947b394f2dd8c87dbb0` (commit, lightweight `v0.29.0`)
  - `github/codeql-action/*`: `1190a975f95ce23525efb6a3fc21ea29567c1b52` (commit, peeled `v3^{}`)
  - `gitleaks/gitleaks-action`: `ff98106e4c7b2bc287b24eaf42907196329070c7` (commit, peeled `v2^{}`)
- Verified each SHA using `git fetch -q --depth 1 ... && git cat-file -t FETCH_HEAD`, confirming all resolve to `commit`.
- Validated workflows with `actionlint` (clean exit code 0).

#### 2. Ubuntu 22.04 (Jammy) Container Test Suite (`scripts/test_jammy.sh`)
- Built an automated container test harness executing inside standard `ubuntu:22.04` throwaway containers:
  - **Subtask 2a (Package Policy & Dry-run):** Tested all packages across `roles/common`, `roles/nagios_server`, and `roles/puppet_agent`. Replaced obsolete `nagios-plugins`/`nagios-plugins-extra` with Ubuntu 22.04 packages `monitoring-plugins` and `monitoring-plugins-standard`.
  - **Subtask 2b (Apache & Nagios Configs):** Installed real `nagios4`, `apache2`, and plugins. Discovered exact configuration parameters: conf file is `nagios4-cgi.conf` (`a2enconf nagios4-cgi`), AuthName/Realm is `Nagios4`, and AuthUserFile is `/etc/nagios4/htdigest.users`. Updated `ansible/roles/nagios_server` tasks.
  - **Subtask 2c (Template & Pre-flight):** Rendered `app.cfg.j2` with test values (`private_ip=10.0.0.10`, `app_node_port=30080`), installed plugin to `/usr/lib/nagios/plugins/check_app_health` (0755), and ran `nagios4 -v /etc/nagios4/nagios.cfg` -> `Total Errors: 0`.
  - **Subtask 2d (Digest Auth & Syntax):** Generated digest auth with role one-liner, enabled `cgi`, `auth_digest`, `authz_groupfile`, ran `apache2ctl configtest` -> `Syntax OK`.
  - **Subtask 2e (Puppet Real Apply & Drift):** Installed Puppet 8 from official jammy repo. Applied `site.pp` locally twice: Run 1 exit code 2 (changes applied), Run 2 exit code 0 (fully idempotent). Deleted `/etc/motd` and ran Run 3: exit code 2 with `/etc/motd` restored.
  - Configured `$manage_service = ($facts['service_provider'] == 'systemd')` in `puppet/modules/baseline/manifests/init.pp` so Puppet manages chrony on real systemd hosts while omitting daemon management in container test harnesses.

#### 3. Hostname Resolution & Environment Classification Harmonization
- Aligned rollback wording in `ARCHITECTURE.md` with `ci-cd.yml` (`k3s kubectl rollout undo`).
- Added system hostname task in `ansible/roles/common` (`app-<env>-1` / `monitor-<env>-1`) and added local `/etc/hosts` entry (`127.0.1.1 <hostname>`) to ensure local name resolution without sudo warnings.
- Harmonized `baseline::env_label` Ruby function and `ARCHITECTURE.md`:
  - `*prod*` -> `PRODUCTION`
  - `*staging*` -> `STAGING`
  - `*dev*` -> `DEVELOPMENT`
  - `app*`/`mon*` default -> `STAGING`
  - default / EC2 `ip-*` -> `DEVELOPMENT`
- Validated with real Puppet apply:
  - `baseline::env_label("app-staging-1")` -> `STAGING`
  - `baseline::env_label("app-prod-1")` -> `PRODUCTION`
  - `baseline::env_label("monitor-dev-1")` -> `DEVELOPMENT`

#### 4. Line Ending Verification
- Enforced `eol=lf` for all markdown files (`*.md`) in `.gitattributes`.
- Ran `dos2unix` across the entire codebase and confirmed `git ls-files --eol | grep -v 'i/lf'` returns empty output (100% LF in the git index).

#### 5. Nagios Template Inheritance Fix & Live Container Validation
- **Template Inheritance Analysis:** Analyzed Debian/Ubuntu Nagios 4 template structures (`/etc/nagios4/objects/templates.cfg` and `/etc/nagios4/nagios.cfg`). Discovered that while `templates.cfg` was loaded, `app.cfg.j2` previously lacked `use linux-server` and `use generic-service` inheritance directives, as well as explicit `check_period`, `notification_period`, and `contact_groups` directives.
- **Explicit Template Definition:** Updated `ansible/roles/nagios_server/templates/app.cfg.j2` to make all directives fully explicit:
  - Host `app1`: `use linux-server`, `check_period 24x7`, `notification_period 24x7`, `contact_groups admins`.
  - All 4 services (`PING`, `SSH`, `App HTTP /healthz`, `App response time`): `use generic-service`, `check_period 24x7`, `notification_period 24x7`, `contact_groups admins`.
- **Validation:** Executed `nagios4 -v /etc/nagios4/nagios.cfg` in Ubuntu 22.04 container. All 9 warnings eliminated, resulting in `Total Warnings: 0, Total Errors: 0`.
- **Live Nagios Test in Container (No Systemd):**
  - Tested live monitoring loop in Ubuntu 22.04 container using a test-only configuration copy with `check_interval 1`, `retry_interval 1`, and `max_check_attempts 2`.
  - Ran a lightweight Python HTTP service on `127.0.0.1:3000` responding to `/healthz` with `{"status":"ok"}`.
  - Started `nagios4 -d` background daemon. Polled `/var/lib/nagios4/status.dat` and verified initial execution: `PING` OK (0), `App HTTP /healthz` OK (0), `App response time` OK (0), and `SSH` CRITICAL (2) (expected: no SSH daemon running inside container).
  - Terminated mock HTTP service. Polled `status.dat` and verified live state transitions: both `App HTTP /healthz` and `App response time` transitioned to CRITICAL (2) (`Connection refused`).

#### 6. Terraform Lifecycle Hardening & Ansible Dependency Automation
- **Terraform Instance Lifecycle:** Added `lifecycle { ignore_changes = [ami] }` to `aws_instance.this` in `terraform/modules/ec2/main.tf` to prevent accidental instance recreation upon upstream Canonical AMI updates without hardcoding AMI IDs. Verified with `terraform fmt -check` and `terraform validate` (`Success!`).
- **Ansible Play Order & Dependencies:** Confirmed play sequence in `ansible/site.yml`: `wait_for_connection` -> `common` (hostname) -> `puppet_agent` -> `k3s` -> `app` -> `nagios_server`. Created `ansible/requirements.yml` (`community.general`, `ansible.posix`), added `make deps` target to `Makefile`, and documented in `README.md`.
- **Ansible Check Mode Evaluation:** Ran `ansible-playbook --check --diff` against a Jammy container over the Docker connection plugin (`ansible_connection=docker`), capturing diffs for package installations, SSH hardening, and Nagios configuration rendering.
- **Operations Documentation:** Created `docs/AWS_RUNBOOK.md` with staged deployment walkthrough, verification checklist, and 10-point failure troubleshooting table. Created `docs/screenshots/README.md` listing submission evidence artifacts. Added "Not yet tested end-to-end" notices to `README.md` and `ARCHITECTURE.md`.

---

### Top 5 Remaining Risks for Real AWS Deployment & Mitigations

1. **AWS IAM Credentials & EC2 Quota Limitations**
   - **Risk:** `terraform apply` cannot provision resources without active AWS credentials (`aws configure`) and sufficient t3.small / t3.micro EC2 vCPU quota in `ap-south-1`.
   - **Mitigation:** Execute `terraform plan` first to review planned resources. Configure an AWS IAM user or role with least-privilege policies restricted to EC2, VPC, and Security Groups, and check AWS Service Quotas before provisioning.

2. **K3s Cluster API Reachability for GitHub Actions Deployments**
   - **Risk:** Automated CD jobs (`deploy-staging`, `deploy-production`) in `ci-cd.yml` require network access to port 6443 on the app server to run `kubectl apply` and `kubectl rollout status`.
   - **Mitigation:** Deploy jobs are gated by repository variable `ENABLE_K8S_DEPLOY == 'true'`. Ansible (`site.yml --tags app`) remains the primary, secure deployer over SSH. To enable GitHub Actions deployments, configure an SSH jump host, WireGuard/Tailscale VPN, or restrict security group port 6443 to GitHub Runner CIDR blocks.

3. **Public Demo NodePort 30080 Exposure**
   - **Risk:** In `terraform/main.tf`, port 30080 is exposed to `0.0.0.0/0` for portfolio demo access without TLS encryption or WAF protection.
   - **Mitigation:** Documented and ignored for demo purposes via `#trivy:ignore:AVD-AWS-0107`. For production workloads, remove public 30080 ingress, set Service type to `ClusterIP`, and route public ingress through an AWS Application Load Balancer with ACM TLS certificates and AWS WAF.

4. **Dynamic Canonical Ubuntu AMI Resolution**
   - **Risk:** The `data "aws_ami" "ubuntu"` data source queries the latest Ubuntu 22.04 LTS image. If Canonical publishes a new kernel/build, subsequent `terraform apply` runs could trigger unintended instance replacements if AMI filters change.
   - **Mitigation:** Added `lifecycle { ignore_changes = [ami] }` to the `aws_instance` resource in `terraform/modules/ec2/main.tf` so that dynamic upstream AMI updates never trigger instance destruction or replacement for running servers. No AMI ID is hardcoded.

5. **Apt Frontend Lock Contention on Boot**
   - **Risk:** Fresh AWS EC2 instances execute `unattended-upgrades` immediately upon first boot, which can lock `/var/lib/dpkg/lock-frontend` and fail initial Ansible provisioning tasks.
   - **Mitigation:** Added `lock_timeout: 180` to all `ansible.builtin.apt` tasks across all roles and placed an initial `wait_for_connection` (300s timeout) play in `ansible/site.yml` to allow instance cloud-init scripts to settle before tasks execute.




