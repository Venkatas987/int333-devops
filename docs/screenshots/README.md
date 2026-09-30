# Project Evidence & Screenshots Guide

This directory holds visual verification artifacts demonstrating the working end-to-end DevOps pipeline for INT333 grading and portfolio presentation. Replace the placeholder descriptions below with actual screenshots captured from your deployments.

> [!CAUTION]
> **No Secrets Rule**: Before capturing and committing any screenshot, ensure that sensitive information (AWS Account IDs, secret access keys, private SSH keys, password hashes, and personal tokens) is blurred or omitted.

---

## Required Submission Screenshots Checklist

### 1. GitHub Actions Workflows (`01_github_actions_ci_cd.png`)
- **What to capture:** The GitHub Actions tab showing a green workflow run on the `main` branch.
- **Key elements to highlight:**
  - `test` job (passed `npm ci` and `node --test`)
  - `build` job (Docker multi-stage build, push to GHCR, and clean Trivy container scan)
  - `deploy-staging` / `deploy-production` skipped or green (gated by `vars.ENABLE_K8S_DEPLOY`)

### 2. GitHub Container Registry (`02_ghcr_package.png`)
- **What to capture:** GitHub Packages page for the repository.
- **Key elements to highlight:**
  - Published package `int333` under GitHub Packages
  - Image tags: `sha-<commit_sha>` and `latest`
  - Package visibility set to Public (or imagePullSecrets configured)

### 3. Security Workflows (`03_security_scans.png`)
- **What to capture:** Execution run of `.github/workflows/security.yml`.
- **Key elements to highlight:**
  - CodeQL JavaScript static analysis completing with 0 security alerts
  - Gitleaks git history scan passing with 0 leaked secrets or tokens detected

### 4. AWS EC2 Console & Security Group (`04_aws_ec2_instances.png`)
- **What to capture:** AWS Management Console -> EC2 -> Instances list in `ap-south-1`.
- **Key elements to highlight:**
  - `app` instance (`t3.small`) in `running` state
  - `monitor` instance (`t3.micro`) in `running` state
  - Security group inbound rules displaying port 22 (restricted to student IP), port 30080 (public), and internal SG self-referencing rules (`self = true`)

### 5. Ansible Full Playbook Run (`05_ansible_playbook_run.png`)
- **What to capture:** Terminal output executing `ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml`.
- **Key elements to highlight:**
  - Successful execution of all roles: `common`, `puppet_agent`, `k3s`, `app`, `nagios_server`
  - PLAY RECAP showing `failed=0` and `unreachable=0` across both hosts

### 6. Kubernetes Cluster & Application Deployment (`06_k3s_cluster_status.png`)
- **What to capture:** Terminal SSH session on `app1` running:
  ```bash
  k3s kubectl get all -n devops-demo
  ```
- **Key elements to highlight:**
  - 2 running Pods (`myapp-*`)
  - Service `myapp` with type `NodePort` mapping port 80 to `30080`
  - HorizontalPodAutoscaler `myapp-hpa` configured with min 2, max 6 replicas

### 7. Live Application Endpoint (`07_app_healthz_response.png`)
- **What to capture:** Browser or curl command hitting the live application:
  ```bash
  curl -i http://<app-public-ip>:30080/healthz
  ```
- **Key elements to highlight:**
  - HTTP status `200 OK`
  - JSON payload: `{"status":"ok"}`

### 8. Nagios Core Monitoring Dashboard (`08_nagios_dashboard.png`)
- **What to capture:** Nagios 4 web UI at `http://<monitor-public-ip>/nagios4/cgi-bin/status.cgi?host=app1`.
- **Key elements to highlight:**
  - Host `app1` in UP state
  - All 4 monitored services in GREEN (OK) state:
    1. `PING`
    2. `SSH`
    3. `App HTTP /healthz`
    4. `App response time` (with performance data graph or metrics)

### 9. Puppet MOTD & Automated Drift Correction (`09_puppet_drift_correction.png`)
- **What to capture:** Terminal session demonstrating:
  1. Login banner showing dynamic MOTD with environment classification (`PRODUCTION`, `STAGING`, or `DEVELOPMENT`)
  2. Deletion of `/etc/motd` (`sudo rm -f /etc/motd`)
  3. Catalog re-application (`puppet apply ...`) returning exit code `2`
  4. Immediate restoration of `/etc/motd`
