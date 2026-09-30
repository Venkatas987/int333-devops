# End-to-End DevOps Platform
**GitHub Actions - Docker - Kubernetes (k3s) - Terraform - Ansible - Puppet - Nagios**

A complete, reproducible DevOps project. One `git push` tests, builds, scans and ships a containerised app;
one `terraform apply` builds the cloud infrastructure, configures it, deploys the app and starts monitoring it.

Built for the course **INT333: DevOps Advance Configuration Management** (Puppet, Nagios, Terraform, Ansible)
and designed to be a strong CV / portfolio project.

---

## Table of contents
1. [Project overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository structure](#3-repository-structure)
4. [Tools and their roles](#4-tools-and-their-roles)
5. [Prerequisites](#5-prerequisites)
6. [Step-by-step guide](#6-step-by-step-guide)
7. [Verification checklist](#7-verification-checklist)
8. [Syllabus (INT333) mapping](#8-syllabus-int333-mapping)
9. [Troubleshooting](#9-troubleshooting)
10. [Cost, security and cleanup](#10-cost-security-and-cleanup)
11. [Instructions for an AI coding agent](#11-instructions-for-an-ai-coding-agent)
12. [How to present this on a CV](#12-how-to-present-this-on-a-cv)

---

## 1. Project overview

**Goal:** automate the full life of a small web service, from code commit to a monitored production-like environment.

| Stage | What happens | Tool |
|---|---|---|
| Code | Developer pushes to GitHub | Git / GitHub |
| Continuous Integration | Lint, unit tests, build Docker image, vulnerability scan, push to registry | GitHub Actions, Docker, Trivy, GHCR |
| Security Scans | CodeQL static analysis and Gitleaks secret scanning in a separate workflow | GitHub Actions (`security.yml`) |
| Infrastructure | Servers, network rules, SSH keys created as code | Terraform (AWS) |
| Configuration | Servers hardened, Kubernetes installed, app deployed, rollback rescue block | Ansible |
| Continuous Compliance | Baseline config enforced (masterless on servers with 30m cron; master-agent in lab) | Puppet |
| Continuous Monitoring | Host, service and app health checks, alerts, web UI via internal VPC IP | Nagios Core + custom plugin |
| Delivery & Rollback | Rolling updates; rollback via Ansible rescue block and gated GitHub deploy jobs | Kubernetes (k3s) |

**The app** is a tiny Node.js HTTP service (`server.js`) with `GET /` and `GET /healthz`. It is intentionally simple so the
focus stays on the DevOps toolchain around it (no runtime npm dependencies).

---

## 2. Architecture

```
                  +-----------------------------------------------+
   git push ----> |  GitHub                                       |
                  |   ci-cd.yml    : test -> build -> scan -> push|----> GHCR (image registry)
                  |   infra.yml    : terraform/ansible/puppet lint|
                  |   security.yml : CodeQL + Gitleaks scan       |
                  +-----------------------------------------------+

   terraform apply
       |
       |-- creates in AWS ------------------------------------------+
       |     Security group, key pair                               |
       |     EC2 "app"     (Ubuntu 22.04)                           |
       |     EC2 "monitor" (Ubuntu 22.04)                           |
       |                                                            |
       |-- writes ansible/inventory/hosts.ini (with private IPs)    |
       '-- runs ansible-playbook site.yml                           |
              |                                                     |
              |-- wait_for_connection : waits for SSH availability  |
              |-- all hosts : common role (packages, SSH harden)    |
              |-- all hosts : puppet_agent (motd.epp, 30-min cron)  |
              |-- app host  : k3s -> deploys app (NodePort 30080)   |
              |               rescue block: auto rollback on fail   |
              '-- monitor   : Nagios Core + custom plugin + UI      |

   Puppet is masterless via Ansible in the servers (with 30-min cron); master-agent (pull) is the lab exercise.

   Nagios (monitor) ---- checks PING, SSH, HTTP /healthz, response time ----> app host (private IP)
```

**Push vs Pull** (frequently asked in exams)
- **Push** - Terraform and Ansible: you run them when you want a change applied.
- **Pull** - Puppet: in the lab exercise (Practical 5), agents check in with the master on a schedule and correct any drift. In our deployed servers, Puppet runs masterless via Ansible and an automated 30-minute cron job.

---

## 3. Repository structure

```
.
|-- server.js, package.json, test/       # sample Node.js app (0 runtime deps) + unit tests
|-- Dockerfile, .dockerignore            # multi-stage, non-root (node), healthcheck
|-- Makefile                             # single-command developer workflow (test, build, lint, plan)
|-- k8s/                                 # Kubernetes manifests
|   |-- deployment.yaml                  #   rolling update, probes, limits, runAsUser: 1000
|   |-- service.yaml                     #   ClusterIP port 80 -> 3000 (patched to NodePort 30080)
|   |-- ingress.yaml                     #   optional (needs an ingress controller)
|   '-- hpa.yaml                         #   autoscaling 2-6 pods @70% CPU
|-- .github/
|   |-- dependabot.yml                   # automated dependency updates (npm, docker, actions, terraform)
|   '-- workflows/
|       |-- ci-cd.yml                    # test -> build -> scan -> deploy (staging/prod)
|       |-- infra.yml                    # validate Terraform, Ansible, Puppet, Nagios plugin
|       '-- security.yml                 # CodeQL (JS static analysis) + Gitleaks (secret scan)
|-- terraform/
|   |-- versions.tf, variables.tf, main.tf, outputs.tf, inventory.tpl
|   |-- .trivyignore                     # accepted findings with inline justifications
|   |-- terraform.tfvars.example
|   '-- modules/ec2/                     # reusable EC2 module (gp3 encrypted, IMDSv2 required)
|-- ansible/
|   |-- ansible.cfg, site.yml, group_vars/all.yml
|   |-- inventory/                       # hosts.ini is generated by Terraform with private IPs
|   '-- roles/  common | puppet_agent | k3s | app | nagios_server
|-- puppet/
|   |-- manifests/site.pp                # node definitions
|   '-- modules/baseline/                # class, EPP template (motd.epp), custom function
|-- nagios/plugins/check_app_health.sh   # custom Nagios plugin (Bash, 0/1/2/3 exit codes)
'-- scripts/                             # local verification and test runners (C1-C9)
```

---

## 4. Tools and their roles

| Tool | Role in this project | Key files |
|---|---|---|
| **Docker** | Packages the app as a small, non-root image (no runtime npm dependencies) | `Dockerfile` |
| **GitHub Actions** | CI/CD automation, security scanning, pinned versions | `.github/workflows/*.yml` |
| **Kubernetes (k3s)** | Runs the app with self-healing, rolling updates, autoscaling | `k8s/*.yaml` |
| **Terraform** | Creates AWS infrastructure (IaC), state, modules, internal security group rules | `terraform/` |
| **Ansible** | Configures servers, installs k3s and Nagios, deploys app, manages secrets | `ansible/` |
| **Puppet** | Enforces baseline config (motd.epp, packages, user) via standalone role and agent | `puppet/` |
| **Nagios Core** | Continuous monitoring via VPC private IP, custom plugin, web UI | `nagios/`, `ansible/roles/nagios_server` |

---

## 5. Prerequisites

**Accounts:** GitHub, AWS (an IAM user with EC2 permissions; billing alerts enabled).

### Windows users (Important)
- **Use WSL2 with Ubuntu-24.04**.
- Clone and keep the active repository under the Linux home directory (`~/int333_check` or `~/int333`), **never under `/mnt/d` directly**.
- **Why:** SSH private keys require strict permissions (`chmod 600`), and Windows filesystem mounts (`/mnt/d`) do not support POSIX file mode changes natively. Running Ansible or Terraform's `local-exec` under `/mnt/d` will fail with permission errors.

**Local tools** (Linux/macOS/WSL2 Ubuntu-24.04):

| Tool | Minimum | Check |
|---|---|---|
| Git | any | `git --version` |
| Node.js | 20 | `node -v` |
| Docker | 24+ | `docker --version` |
| Terraform | 1.6+ | `terraform -version` |
| Ansible | 2.15+ | `ansible --version` |
| AWS CLI | 2 | `aws sts get-caller-identity` |
| kubectl | any | `kubectl version --client` |
| Puppet agent | 7/8 | `puppet --version` |

**SSH key pair** (used to log in to servers):
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa   # skip if you already have one
```

---

## 6. Step-by-step guide

Follow the phases in order. Phases 1-3 are free and local. Phase 5 onward uses AWS (costs money).

### Phase 1 - Run the app locally
```bash
npm install            # creates package-lock.json (required by "npm ci" in the Dockerfile)
npm test               # unit tests must pass
npm start              # http://localhost:3000  and  /healthz
```
Expected: `GET /healthz` returns `{"status":"ok"}`.

### Phase 2 - Containerise it
```bash
docker build -t devops-demo:local .
docker run --rm -p 3000:3000 devops-demo:local
curl http://localhost:3000/healthz
```
Expected: HTTP 200. The container runs as user `node` (not root).

### Phase 3 - Try Kubernetes locally (recommended before AWS)
```bash
# using kind or minikube
kind create cluster --name demo
kind load docker-image devops-demo:local --name demo
kubectl create namespace staging
kubectl apply -n staging -f k8s/deployment.yaml -f k8s/service.yaml
kubectl set image deployment/myapp myapp=devops-demo:local -n staging
kubectl rollout status deployment/myapp -n staging
kubectl port-forward -n staging svc/myapp 8080:80 &
curl http://localhost:8080/healthz
```
Note: the manifest references an image pull secret `ghcr-pull`. For a local image this is harmless. For a
public GHCR package you can delete the `imagePullSecrets` block.

### Phase 4 - Set up GitHub and the CI/CD pipeline
1. Create a GitHub repository and push this project:
   ```bash
   git init && git add . && git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
2. Replace `OWNER/REPO` in `k8s/deployment.yaml` and `ansible/group_vars/all.yml` with your lowercase
   `github-user/repo` (GHCR requires lowercase).
3. Repo **Settings > Actions > General > Workflow permissions**: set to *Read and write*.
4. Open the **Actions** tab. `ci-cd.yml` runs `test` then `build`. After it passes, the image appears under
   **Packages**. Make the package public (Package settings) or create a pull secret (step 5 below).
5. *(Private package only)* Create a PAT with `read:packages`. You can either let Ansible configure it automatically by setting `-e ghcr_pull_user=<user> -e ghcr_pull_token=<PAT>` (see `roles/app`), or manually create the secret on the cluster:
   ```bash
   kubectl create secret docker-registry ghcr-pull -n staging \
     --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT>
   ```

What the pipeline does:

| Trigger | Jobs |
|---|---|
| Pull request | `test` (lint + unit tests) |
| Push to `main` | `test` > `build` (buildx, cache, push, Trivy scan) > `deploy-staging` |
| Tag `vX.Y.Z` | `test` > `build` > `deploy-production` (needs approval) |

> **About the `deploy-*` jobs:** they use `kubectl` with a `KUBE_CONFIG_B64` secret and need a cluster the
> GitHub runner can reach. In this project the cluster is k3s on EC2, and Ansible is the primary deployer.
> Two options:
> - **Option A (simple, default):** let Ansible deploy: `ansible-playbook site.yml --tags app -e app_image=ghcr.io/<you>/<repo>:<sha>`.
>   You may disable the `deploy-*` jobs in `ci-cd.yml`.
> - **Option B (full CD):** fetch `/etc/rancher/k3s/k3s.yaml` from the app server, change `127.0.0.1` to the server's
>   public IP, base64 it (`base64 -w0`), store it as environment secret `KUBE_CONFIG_B64`, and open TCP 6443 in the
>   security group. Restrict 6443 as tightly as you can; GitHub runner IPs are wide, so a self-hosted runner is safer.

### Phase 5 - Provision AWS with Terraform
```bash
aws configure                                   # access key, secret, region (default ap-south-1)
cd terraform
cp terraform.tfvars.example terraform.tfvars    # set my_ip_cidr = "<your-ip>/32"   (curl ifconfig.me)
terraform init
terraform fmt -recursive && terraform validate
terraform workspace new staging                 # workspaces = separate environments
terraform plan
terraform apply                                 # type "yes"
```
What gets created:
- Key pair (`aws_key_pair`)
- Security group with strict rules:
  - SSH (port 22): restricted to `var.my_ip_cidr` and `self = true`
  - ICMP (ping): `self = true` (enables Nagios to ping the app server)
  - NodePort 30080: public access + `self = true` (enables monitor server to check app)
  - Nagios UI (port 80): restricted to `var.my_ip_cidr`
  - Egress: outbound internet access for apt, GitHub, GHCR
- Two EC2 instances (`app` t3.small, `monitor` t3.micro) using gp3 encrypted storage and IMDSv2.
- Ansible inventory (`hosts.ini`) generated via `inventory.tpl` containing both public and internal VPC `private_ip` addresses for internal, free, reliable monitoring.

`terraform apply` also runs Ansible automatically (`run_ansible = true`). To run Ansible yourself instead:
```bash
terraform apply -var run_ansible=false
cd ../ansible && ansible-playbook site.yml
```
Outputs: `app_url` and `nagios_url`.

### Phase 6 - Configure servers and deploy with Ansible
```bash
cd ansible
# Install collection dependencies (or run 'make deps' from repository root)
ansible-galaxy collection install -r requirements.yml

ansible all -m ping                              # connectivity test (ad-hoc command)
ansible-playbook site.yml --check                # dry run
ansible-playbook site.yml                        # full run
ansible-playbook site.yml --tags app -e app_image=ghcr.io/<you>/<repo>:<tag>   # redeploy only the app
```
Playbook structure & Roles:
- `wait_for_connection` (polls until EC2 SSH responds, replacing static sleeps)
- `common` (essential packages, SSH hardening, chrony)
- `puppet_agent` (installs puppet-agent, copies manifests/modules, runs idempotent `puppet apply --detailed-exitcodes`, and configures a 30-minute cron job for continuous drift correction)
- `k3s` (installs lightweight Kubernetes)
- `app` (applies manifests, sets image, strategic merge-patch to NodePort 30080, optional GHCR secret, waits for rollout in a `block`/`rescue` that automatically runs `kubectl rollout undo` on failure)
- `nagios_server` (installs Nagios Core, apache digest authentication, custom health check plugin, host & service configs using private IP).

Keep secrets safe:
```bash
ansible-vault encrypt_string 'MyStrongPass' --name nagios_admin_password   # paste into group_vars/all.yml
ansible-playbook site.yml --ask-vault-pass
```

### Phase 7 - Puppet (configuration management, pull model)

**7a. Standalone (`puppet apply`) - Automated by Ansible**
The `puppet_agent` Ansible role deploys the modern EPP template (`motd.epp`) and custom Ruby function `env_label.rb` to `/opt/puppet-demo/` and runs:
```bash
sudo /opt/puppetlabs/bin/puppet apply --modulepath=/opt/puppet-demo/modules /opt/puppet-demo/manifests/site.pp
cat /etc/motd                                    # dynamic MOTD rendered from facts and custom function
```

**7b. Master-Agent (Practical 5) - use two VMs (VirtualBox) or two EC2 hosts**
```bash
# Master
sudo apt install -y puppetserver            # after adding the Puppet apt repo
sudo systemctl enable --now puppetserver
sudo mkdir -p /etc/puppetlabs/code/environments/production/{manifests,modules}
sudo cp -r puppet/modules/baseline /etc/puppetlabs/code/environments/production/modules/
sudo cp puppet/manifests/site.pp /etc/puppetlabs/code/environments/production/manifests/

# Agent
sudo apt install -y puppet-agent
sudo /opt/puppetlabs/bin/puppet config set server <master-hostname> --section main
sudo /opt/puppetlabs/bin/puppet agent -t     # sends certificate request

# Master: sign it
sudo /opt/puppetlabs/bin/puppetserver ca list
sudo /opt/puppetlabs/bin/puppetserver ca sign --all

# Agent: apply catalog
sudo /opt/puppetlabs/bin/puppet agent -t
```
The master and agent must resolve each other by name (edit `/etc/hosts`) and reach TCP 8140.

What Puppet manages (`puppet/modules/baseline`): packages, `chrony` service, a `deploy` user, and `/etc/motd`
generated from an ERB template using Facter facts and the custom function `baseline::env_label`.

Demonstrate drift correction: `sudo rm /etc/motd` then run `puppet agent -t`; the file returns.

### Phase 8 - Monitoring with Nagios
Installed and configured by Ansible (role `nagios_server`).

1. Open `nagios_url` (`http://<monitor-ip>/nagios4`). Login: `nagiosadmin` and the password you set.
2. **Hosts** > `app1` should be UP. **Services** should show PING, SSH, `App HTTP /healthz`, `App response time`.
3. Watch soft vs hard states: stop the app (`kubectl scale deploy/myapp --replicas=0 -n staging`, run on the app server as
   `sudo k3s kubectl ...`). The service goes CRITICAL (soft) then CRITICAL (hard) after the retry limit. Restore with `--replicas=2`.
4. Use the web UI to acknowledge a problem, add a comment, and schedule downtime.
5. **Custom plugin** (`nagios/plugins/check_app_health.sh`) - run it by hand:
   ```bash
   /usr/lib/nagios/plugins/check_app_health -H <app-ip> -p 30080 -w 0.5 -c 2
   # OK - HTTP 200 in 0.041s | time=0.041s;0.5;2;0
   ```
   Exit codes follow the Nagios convention: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.

### Phase 9 - Release to production
```bash
git tag v1.0.0 && git push origin v1.0.0
```
The pipeline builds the tagged image. Then deploy with Ansible (or the gated `deploy-production` job if `vars.ENABLE_K8S_DEPLOY == 'true'` and approval is given).
Rollback: handled automatically via Ansible `block`/`rescue` or GitHub Actions `failure()` step, or manually: `sudo k3s kubectl rollout undo deployment/myapp -n production`.

### Phase 10 - Clean up (important)
```bash
cd terraform && terraform destroy
```

---

## 7. Verification checklist

- [ ] `npm test` passes locally and in GitHub Actions
- [ ] Docker image builds; container serves `/healthz` and runs as non-root
- [ ] Image is visible in GHCR, Trivy scan passes
- [ ] `terraform validate` passes; `terraform apply` creates 2 EC2 instances
- [ ] `ansible all -m ping` returns `pong` for both hosts
- [ ] `curl http://<app-ip>:30080/healthz` returns `{"status":"ok"}`
- [ ] Re-running `ansible-playbook site.yml` shows mostly `ok` (idempotent)
- [ ] `puppet apply` creates `/etc/motd`; deleting it and re-running restores it
- [ ] Nagios UI shows host UP and 4 services OK
- [ ] Stopping the app turns Nagios CRITICAL; restoring it turns it OK
- [ ] `terraform destroy` removes everything

---

## 8. Syllabus (INT333) mapping

| Practical | Topic | Where |
|---|---|---|
| 1 | VirtualBox and Puppet/Ansible VMs | Use the lab VMs for Phases 3, 7, 8 |
| 2-3 | Puppet install, manifests | `puppet/manifests/site.pp` |
| 4 | Puppet modules | `puppet/modules/baseline` |
| 5 | Master-Agent, certificates | Phase 7b |
| 6 | Facts and templates | `templates/motd.epp`, `env_label.rb` |
| 7 | Install Nagios Core | `ansible/roles/nagios_server` |
| 8 | Custom Nagios plugin | `nagios/plugins/check_app_health.sh` |
| 9 | Monitor a web server | `templates/app.cfg.j2` (HTTP checks) |
| 10 | Nagios web interface | Phase 8 |
| 11 | Ansible install, inventory, ad-hoc | `ansible/`, `ansible all -m ping` |
| 12 | Playbooks | `ansible/site.yml`, roles, handlers, tags |
| 13 | Ansible + AWS deployment | Phases 5-6 |
| 14 | Terraform install and config | `terraform/` |
| 15 | Terraform + Ansible | `null_resource` + `local-exec` in `main.tf` |

Course outcomes covered: CO1-CO6 (Puppet, Nagios, Terraform, Ansible).

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `npm ci` fails in Docker build | No `package-lock.json` | Run `npm install` and commit the lockfile |
| Pod `ImagePullBackOff` | Private image or wrong name | Make package public or create `ghcr-pull` secret; check lowercase image name |
| Pod `CrashLoopBackOff` | App not listening on 3000 / `/healthz` missing | `kubectl logs`, check probes |
| `readOnlyRootFilesystem` errors | App writes to disk | Mount an `emptyDir` at the write path |
| Ansible `UNREACHABLE` | Instance still booting / SSH IP mismatch | Wait 1 minute; check `my_ip_cidr` matches your current IP |
| Terraform `InvalidKeyPair.Duplicate` | Key pair exists | Change `project` variable or delete old key pair |
| Nagios UI 401 / no login | Digest file wrong or modules off | Re-run `--tags nagios`; check `a2enmod auth_digest` |
| Nagios `check_app_health` UNKNOWN | `bc` or `curl` missing | Ansible installs both; verify with `which bc curl` |
| `puppet agent -t` cert error | Cert not signed / clock skew / name mismatch | Sign on master; sync time; fix `/etc/hosts` |
| Nagios config error on restart | Syntax error in `app.cfg` | `sudo nagios4 -v /etc/nagios4/nagios.cfg` |
| k3s pod OOM | Instance too small | Use t3.small or larger |

---

## 10. Cost, security and cleanup

- **Cost:** t3.small + t3.micro are **not** free-tier. Roughly a few US dollars per week if left running.
  Always run `terraform destroy` after demos. Set an AWS billing alert.
- **Never commit** `terraform.tfvars`, `*.tfstate`, `hosts.ini`, private keys or passwords (`.gitignore` covers these).
- **State:** for real use, enable the S3 + DynamoDB remote backend in `terraform/versions.tf`.
- **Network:** SSH and Nagios UI are limited to your IP. Update `my_ip_cidr` if your IP changes.
- **Secrets:** use Ansible Vault (or AWS Secrets Manager); use GitHub environment secrets for CI.
- **Hardening in place:** non-root containers, read-only root FS, IMDSv2, encrypted volumes, SSH password login disabled,
  Trivy image and Terraform config scans.

---

## 11. Instructions for an AI coding agent

If you are an AI agent (e.g. Antigravity) working on this repository, follow these rules and tasks.

**Context:** the repository is complete but untested end-to-end. Your job is to verify, fix and improve, not to redesign.

**Rules**
1. Never run `terraform apply`, or anything that creates paid cloud resources, without explicit human approval. `terraform plan` is fine.
2. Never commit secrets, keys, `.tfstate` or `hosts.ini`.
3. Keep the structure in section 3. Keep Ansible roles idempotent and Terraform formatted (`terraform fmt`).
4. After every change, run the relevant check:
   `npm test`, `docker build .`, `terraform fmt -check -recursive && terraform init -backend=false && terraform validate`,
   `ansible-lint ansible/site.yml`, `puppet parser validate puppet/manifests/site.pp`, `puppet-lint puppet/`,
   `shellcheck nagios/plugins/check_app_health.sh`.

**Tasks, in order**
1. Run `npm install`; ensure `package-lock.json` exists and `npm test` passes.
2. Build the Docker image and confirm `/healthz` returns 200 as a non-root user.
3. Validate Kubernetes manifests: `kubectl apply --dry-run=client -f k8s/` (or `kubeconform`).
4. Run all linters listed in rule 4 and fix findings.
5. Run `terraform plan` (with a dummy `my_ip_cidr`) and review it; do not apply.
6. Test the Ansible roles against a local VM or container (Vagrant/Molecule) and confirm idempotency (second run: `changed=0` where feasible).
7. Test `puppet apply --noop` and then `puppet apply` in a VM; confirm `/etc/motd` content.
8. Improve (only after 1-7 pass): add a Makefile (`make test build plan lint`), pin GitHub Action versions, add Dependabot config,
   add CodeQL and Gitleaks workflows, add an architecture diagram image, and add Helm or Kustomize overlays for staging/prod.
9. Summarise all changes and any remaining risks in `CHANGELOG.md`.

**Acceptance criteria:** every check in section 7 that can run without cloud resources passes; documentation matches the code.

**Known limitations to be aware of**
- **Not yet tested end-to-end**: The systemd path of Puppet's chrony service, k3s installation and the full `site.yml` run on real EC2 were only verified in pieces/components (due to strict local test safety rules prohibiting cloud provisioning).
- `k8s/ingress.yaml` assumes an nginx ingress controller; k3s ships Traefik. The Ansible role skips ingress and uses a NodePort.
- The `deploy-*` jobs in `ci-cd.yml` require a cluster reachable from GitHub (see Phase 4 note).
- Nagios digest login is generated with a shell one-liner; a stricter approach is `htdigest` or the Ansible `community.general` modules.
- Single-node k3s is for demonstration, not high availability.

---

## 12. How to present this on a CV

> **End-to-End DevOps Platform** | Terraform, Ansible, Puppet, Nagios, Docker, Kubernetes, GitHub Actions
> - Built an automated CI/CD pipeline (GitHub Actions) testing, building, vulnerability-scanning (Trivy), and publishing container images to GHCR, with automated zero-downtime rolling updates and auto-rollback on Kubernetes.
> - Provisioned hardened AWS cloud infrastructure using Terraform (modules, workspaces, state locking) and automated full server configuration and application delivery via Ansible.
> - Enforced baseline system configuration using Puppet (EPP templates, Facter facts, custom Ruby functions) and implemented continuous monitoring with Nagios Core and a custom Bash plugin.
> - Repo: `<link>` | Live demo / screenshots: `<link>`

---

## 13. Screenshot checklist for your CV portfolio

To showcase this project effectively to recruiters and interviewers, collect and include these screenshots:

1. **GitHub Actions Green Runs (`ci-cd.yml`, `infra.yml`, `security.yml`):**
   - Showing all jobs passing: `test`, `build`, `scan` (Trivy 0 vulnerabilities), `terraform`, `ansible`, `puppet`, `CodeQL`, and `Gitleaks`.
2. **Nagios Core Web Dashboard (`/nagios4`):**
   - Host `app1` in `UP` state (green) via private IP ICMP ping.
   - All 4 monitored services in `OK` state: `PING`, `SSH`, `App HTTP /healthz`, and `App response time` with performance graphs.
3. **Terraform Plan Execution Output:**
   - Demonstrating execution of `terraform plan` showing the planned creation of the security group, key pair, EC2 app/monitor instances, and dynamic Ansible inventory generation.
4. **Kubernetes Deployment & Pod Status (`kubectl get pods -n staging -o wide`):**
   - Showing 2 healthy replicas of `myapp` running on `k3s` with zero restarts, non-root execution (`runAsUser: 1000`), and passing readiness/liveness probes.

---

## License
MIT
