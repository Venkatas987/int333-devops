# ARCHITECTURE.md
# End-to-End DevOps Platform — Beginner's Guide
> Written for INT333 students. After reading this you should be able to explain the project in a viva.

---

## (a) System Diagram

```
+----------------------------------------------------------------------------+
|  Developer's laptop                                                        |
|  git push / git tag vX.Y.Z                                                |
+-----------------------------+----------------------------------------------+
                              |
                              v
+----------------------------------------------------------------------------+
|  GitHub Workflows & Registry                                               |
|                                                                            |
|  +--- ci-cd.yml ------------------------------------------------------+   |
|  |  [test]  npm ci -> node --test                                     |   |
|  |     | (only on push, not PR)                                       |   |
|  |  [build] docker buildx -> push to GHCR -> Trivy scan               |   |
|  |     | (main branch)        | (tag v*.*.*)                          |   |
|  |  [deploy-staging]    [deploy-production]                           |   |
|  |  (Gated: run only when vars.ENABLE_K8S_DEPLOY == 'true')           |   |
|  +--------------------------------------------------------------------+   |
|                                                                            |
|  +--- infra.yml ------------------------------------------------------+   |
|  |  terraform fmt+validate, ansible-lint, puppet-lint, shellcheck     |   |
|  +--------------------------------------------------------------------+   |
|                                                                            |
|  +--- security.yml (separate security workflow) ----------------------+   |
|  |  CodeQL (JS static analysis) + Gitleaks (git history secret scan)  |   |
|  +--------------------------------------------------------------------+   |
|                                                                            |
|  GHCR (GitHub Container Registry) --- stores Docker images            |   |
+----------------------------------------------------------------------------+
                              |
              terraform apply | (one-time / when infra changes)
                              v
+------------ AWS ap-south-1 ------------------------------------------------+
|                                                                            |
|  Security Group:                                                           |
|    22, 80  -> your IP only (var.my_ip_cidr)                                 |
|    30080   -> public (app web traffic)                                      |
|    22, ICMP ping, 30080 -> internal within SG (self=true)                   |
|    Egress  -> 0.0.0.0/0 (all outbound for apt, GHCR, GitHub)                |
|                                                                            |
|  +-------------------------+      +----------------------------------+     |
|  |  EC2: app (t3.small)    |      |  EC2: monitor (t3.micro)         |     |
|  |  Private IP: 10.0.x.x   |      |  Private IP: 10.0.y.y            |     |
|  |                         |      |                                  |     |
|  |  Ansible roles:         |      |  Ansible roles:                  |     |
|  |    common (SSH harden)  |      |    common                        |     |
|  |    puppet_agent (motd)  |      |    puppet_agent (motd)           |     |
|  |    k3s   (Kubernetes)   |      |    nagios_server                 |     |
|  |    app   (deploys image)|      |                                  |     |
|  |                         |      |  Nagios Core:                    |     |
|  |  k3s (single-node k8s): |      |    checks every 5 min via VPC    |     |
|  |    Deployment (2 pods)  |<-----|    Private IP (reliable, free):  |     |
|  |    Service (NodePort    |      |      PING (ICMP self=true)       |     |
|  |      30080, self=true)  |      |      SSH (port 22 self=true)     |     |
|  |    HPA (2-6 pods)       |      |      HTTP /healthz (30080)       |     |
|  |                         |      |      Response time plugin        |     |
|  |  Rollback:              |      |    Web UI: /nagios4              |     |
|  |    Ansible block/rescue |      |                                  |     |
|  |    undoes failed rollout|      |                                  |     |
|  +-------------------------+      +----------------------------------+     |
|                                                                            |
|  Puppet (masterless via Ansible in the servers; master-agent is lab):      |
|    enforces baseline packages, user deploy, dynamic motd.epp, and          |
|    drift correction via cron (runs every 30 minutes)                       |
+----------------------------------------------------------------------------+
```

> [!NOTE]
> **EC2 Hostnames & Puppet Environment Classification**: Default AWS EC2 instances initialize with generic private DNS hostnames (e.g. `ip-10-0-1-23`). Puppet's `site.pp` matches node definitions by hostname regex (`node /^app/`), and our custom Ruby function `baseline::env_label` classifies nodes into `PRODUCTION`, `STAGING`, or `DEVELOPMENT` based on hostname patterns: hostnames containing `prod` map to `PRODUCTION`, hostnames containing `staging` map to `STAGING`, hostnames containing `dev` map to `DEVELOPMENT`, role-prefixed hostnames without an environment tag (`app1`, `monitor1`) default to `STAGING`, and anything else (including EC2 `ip-*` names) falls back to `DEVELOPMENT`. To ensure deterministic role assignment and correct environment labels, the Ansible `common` role explicitly configures the system hostname to `app-<env>-1` or `monitor-<env>-1` via `ansible.builtin.hostname` before Puppet runs.

> [!IMPORTANT]
> **Not yet tested end-to-end**: The systemd service path of Puppet's chrony management (verified via mock/noop on containers without systemd init), the automated single-node k3s installation script, and the full continuous `site.yml` Ansible playbook run on live AWS EC2 instances have been verified component-by-component in isolated Ubuntu 22.04 container tests, syntax checks, and dry-runs, but have not yet been executed end-to-end against live AWS cloud hardware in this sandbox environment.

---


## (b) Journey of one code change - step by step

Suppose you fix a bug in `server.js` and push to GitHub. Here is exactly what happens:

| Step | What happens | Tool |
|------|-------------|------|
| 1 | You run `git push origin main` | Git |
| 2 | GitHub sees the push and starts `ci-cd.yml` (and `security.yml` runs CodeQL + Gitleaks in a separate security workflow) | GitHub Actions |
| 3 | The **test** job runs `npm ci` (clean install) then `node --test`. If tests fail -> pipeline stops and nothing ships | Node.js |
| 4 | Tests pass -> the **build** job starts. It logs in to GHCR using the auto-generated `GITHUB_TOKEN` | GitHub Actions |
| 5 | Docker Buildx builds the image in two stages (builder -> runtime). Only changed layers are rebuilt (cache) | Docker |
| 6 | The image is pushed to GHCR tagged as `sha-<short-hash>` and `latest` | GHCR |
| 7 | Trivy scans the pushed image for known CVEs. If CRITICAL or HIGH CVEs are found -> build fails | Trivy |
| 8 | **Deployment & Rollback**: Ansible is the primary deployer. Alternatively, if `vars.ENABLE_K8S_DEPLOY == 'true'`, the gated **deploy-staging** job runs `kubectl set image` | Ansible / kubectl |
| 9 | Kubernetes (k3s) does a **rolling update**: starts one new pod -> waits for readiness probe -> terminates one old pod | k3s |
| 10 | **Rollback**: Handled via Ansible rescue block (`k3s kubectl rollout undo deployment/myapp -n <ns>`) and in GitHub Actions via `kubectl rollout undo` on failure | Ansible / kubectl |
| 11 | Nagios's 5-minute check cycle hits `/healthz` on the new pod using the VPC private IP. If OK -> green dashboard | Nagios |
| 12 | **Puppet**: runs masterless via Ansible and a 30-minute cron job. If `/etc/motd` is manually altered, Puppet restores it (drift correction) | Puppet |
| 13 | You push `git tag v1.0.0 && git push --tags` -> **deploy-production** fires (gated by `ENABLE_K8S_DEPLOY` and GitHub environment approval) | GitHub Actions |

---

## (c) Why each tool exists

| Tool | Problem it solves | What would go wrong without it |
|------|------------------|-------------------------------|
| **Git / GitHub** | Version control + collaboration | No history, no rollback, no collaboration |
| **GitHub Actions** | Automates test -> build -> deploy on every push | Engineers would have to build and deploy manually (error-prone, inconsistent) |
| **Security Workflow** | CodeQL static analysis & Gitleaks secret scanning in a separate workflow | Vulnerable JS code or committed credentials slip into git history |
| **Docker** | Packages the app with its exact dependencies into a portable image | "Works on my machine" - app behaves differently on the server |
| **Trivy** | Scans the image and Terraform for known security vulnerabilities | Shipping images or infrastructure with known CVEs |
| **GHCR** | Stores Docker images near GitHub | Would need a separate Docker Hub account and secret management |
| **Kubernetes (k3s)** | Self-healing, rolling updates, autoscaling | Manual process to restart crashed apps; downtime during deployments |
| **HPA** | Scales pods automatically under load | Either over-provisioning (wasted money) or crashes during traffic spikes |
| **Terraform** | Creates AWS infrastructure as code, reproducibly | Clicking in the AWS console creates snowflake servers that cannot be recreated |
| **Ansible** | Configures servers idempotently with rollback rescue blocks | Manually SSHing and running commands; servers diverge over time |
| **Puppet** | Enforces baseline config (masterless on servers, master-agent in lab) | Configuration drift - one admin changes something, nobody notices until it breaks |
| **Nagios** | Continuously monitors host/service health via internal private IP | You find out the app is down when a user tweets about it |
| **Custom Nagios plugin** | Validates JSON body + measures response time | Standard `check_http` only checks status codes, not app-level health |

---

## (d) Push vs Pull - everyday analogy

### Push model (Terraform, Ansible, GitHub Actions)
> Pizza order: You order a pizza. The restaurant (you) decides when to send the delivery (the configuration change). Nothing happens until you call.

- You **initiate** the action: `terraform apply`, `ansible-playbook site.yml`, or `git push`.
- The change is **applied immediately**, on demand.
- Good for: **provisioning** (creating servers), **deploying** (rolling out a new image).

### Pull model (Puppet)
> Mailbox: You do not call the post office. Every day the postman checks and delivers whatever letters are there.

- In our servers, Puppet runs **masterless** via the `puppet_agent` Ansible role and a 30-minute cron job for automated drift correction.
- In the INT333 lab exercise (Practical 5), Puppet runs in **master-agent pull mode** where agents check in with a central Puppet Server every 30 minutes over TCP 8140.
- Good for: **continuous compliance** - ensures servers stay in the desired state even if someone makes an unauthorized change.

---

## (e) Glossary

| Term | Definition |
|------|-----------|
| **IaC (Infrastructure as Code)** | Describing servers, networks and firewalls in code files (Terraform HCL) so they can be version-controlled, reviewed and recreated automatically |
| **Idempotent** | Running an operation twice produces the same result as running it once. Ansible tasks are idempotent: `apt install curl` a second time does nothing |
| **Manifest** | A YAML file that describes the desired state of a Kubernetes object (Deployment, Service, etc.) |
| **Soft state (Nagios)** | A check has failed, but fewer than `max_check_attempts` times. Nagios retries before alerting. Prevents false alarms from transient blips |
| **Hard state (Nagios)** | A check has failed `max_check_attempts` times in a row. Nagios sends a notification (email, Slack, etc.) |
| **NodePort** | A Kubernetes Service type that exposes a pod on a fixed port (30000-32767) on every cluster node's IP, making it reachable without a load balancer |
| **Rollout** | The process Kubernetes uses to update a Deployment - gradually replacing old pods with new ones |
| **Rollback** | Reverting to the previous working ReplicaSet (`kubectl rollout undo`) via Ansible rescue block or GHA failure step |
| **GHCR** | GitHub Container Registry - a Docker-compatible image registry built into GitHub |
| **CVE** | Common Vulnerabilities and Exposures - a public database of known security vulnerabilities. Trivy checks images against this |
| **Facter** | Puppet's tool for collecting system information (facts) like hostname, IP, OS, CPU count. Facts are available as `$facts['key']` in manifests |
| **EPP** | Embedded Puppet - modern templating language that mixes Puppet code and text (`motd.epp`) |
| **Catalog** | Puppet's compiled list of resources that an agent must enforce |
| **Drift** | When a server's actual state differs from its desired state |
| **CIDR** | Classless Inter-Domain Routing - IP range notation. `203.0.113.4/32` = exactly one IP; `0.0.0.0/0` = the entire internet |
| **IMDSv2** | Instance Metadata Service v2 - AWS's more secure metadata API. Requires a session token, preventing SSRF attacks |
| **Concurrency (CI)** | The `concurrency` block in GitHub Actions cancels older workflow runs when a new commit arrives, saving CI minutes |
| **Digest** | The SHA256 hash of a Docker image layer set. Using a digest (`@sha256:...`) instead of a tag pins the exact image |
| **HPA** | HorizontalPodAutoscaler - Kubernetes resource that automatically adjusts pod count based on CPU/memory metrics |
| **Rolling update** | Kubernetes strategy that replaces pods one at a time, keeping the service available throughout |
| **Workspace (Terraform)** | An isolated state environment. `terraform workspace new staging` lets you manage staging and production from the same codebase |

---

## (f) 10 Viva / Interview Questions

**Q1. What is the difference between Ansible and Puppet in this project?**
> Both are configuration management tools. **Ansible** is **push/agentless** - it executes tasks over SSH from the control machine to configure servers, install k3s, deploy the app, and handle rollbacks. In our deployed servers, **Puppet** is **masterless via Ansible** (`puppet_agent` role) and scheduled via cron every 30 minutes for automated drift correction. The classic **master-agent pull architecture** (Puppet Server + agent over TCP 8140) is configured as the INT333 lab exercise (Practical 5).

**Q2. What is idempotency and why does it matter?**
> An operation is idempotent if running it N times produces the same result as running it once. It matters because Ansible playbooks and Puppet manifests are run repeatedly. If tasks weren't idempotent, re-running would install packages twice, restart services unnecessarily, or corrupt configurations.

**Q3. How is application rollback handled?**
> Rollback is handled at two levels: (1) In Ansible, the deployment rollout wait is wrapped in a `block`/`rescue` structure: if the rollout fails or times out, the `rescue` block executes `k3s kubectl rollout undo deployment/myapp -n <ns>` to immediately restore the prior working ReplicaSet. (2) In GitHub Actions (`ci-cd.yml`), deploy jobs are gated by repository variable `ENABLE_K8S_DEPLOY == 'true'` and include an `if: failure()` step calling `kubectl rollout undo`.

**Q4. Explain soft vs hard state in Nagios.**
> When a service first fails, Nagios enters a **soft state** - it retries (`retry_interval`) up to `max_check_attempts` times. Only after all retries fail does it enter **hard state** and send a notification. This prevents alerts for transient blips (a 1-second network hiccup).

**Q5. Why do we use a multi-stage Docker build?**
> Stage 1 (builder) runs `npm ci --omit=dev`. Stage 2 (runtime) copies only the application source (`server.js`) and manifests to a clean Alpine image running as non-root user `node`. The final image contains no build tools, compilers, or caches, keeping size tiny (~130MB) and attack surface minimal.

**Q6. What is Terraform state and why is it important?**
> Terraform stores a map of "what it created" in a state file (`terraform.tfstate`). Without it, Terraform cannot track real infrastructure and would attempt duplicate creation or fail on updates. In production, remote state locking (e.g. S3 + DynamoDB) prevents concurrent modification.

**Q7. What does `readOnlyRootFilesystem: true` do in a Kubernetes pod?**
> It prevents the container from modifying its root filesystem at runtime. If an attacker breaches the app, they cannot overwrite binaries, install rootkits, or write persistent backdoor scripts. Any necessary temporary files are constrained to explicitly mounted `emptyDir` volumes.

**Q8. How does Trivy protect the pipeline?**
> Trivy scans container images for CVEs during CI and scans Terraform files for misconfigurations. In `ci-cd.yml`, finding CRITICAL or HIGH vulnerabilities exits with code 1, blocking the build. In `infra.yml`, Trivy inspects security group configurations, validating rules against CIS benchmarks.

**Q9. Where do Gitleaks and CodeQL run?**
> They run in a dedicated, separate security workflow (`.github/workflows/security.yml`). Gitleaks performs deep git history scans (`fetch-depth: 0`) to detect committed secrets and tokens, while CodeQL executes semantic static analysis for JavaScript vulnerabilities.

**Q10. What is a NodePort and why use private IP for internal monitoring?**
> A NodePort exposes a Service on a static port (30000-32767) on the node's IP, avoiding paid cloud load balancers for demo purposes. Nagios monitors the app using the node's internal VPC `private_ip` via the AWS security group `self=true` rule, ensuring monitoring traffic is fast, free from data transfer costs, and resilient to public IP changes.
