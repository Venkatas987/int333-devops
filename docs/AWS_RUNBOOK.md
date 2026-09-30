# AWS Deployment & Operations Runbook

This runbook describes the staged deployment process for the INT333 DevOps platform on AWS EC2, the manual verification checklist, cleanup procedures, and a comprehensive troubleshooting guide for common operational failure modes.

---

## 1. Staged AWS Deployment Procedure

Deploying the full infrastructure in discrete, tagged stages provides clear isolation of failures and avoids monolithic, hard-to-debug runs.

### Prerequisites
- AWS CLI credentials configured or passed via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION="ap-south-1"`).
- SSH keypair generated at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.
- `terraform.tfvars` configured with your public IP CIDR:
  ```hcl
  my_ip_cidr = "203.0.113.4/32"
  ```

---

### Step 1: Provision Cloud Infrastructure (Terraform)
Run Terraform with Ansible provisioning disabled (`run_ansible=false`) to isolate EC2 instance, VPC security group, and dynamic inventory generation:

```bash
cd terraform
terraform init
terraform plan -out=tfplan -var run_ansible=false
terraform apply tfplan
cd ..
```
*Artifacts produced:* `ansible/inventory/hosts.ini` generated automatically from `inventory.tpl`.

---

### Step 2: Verify SSH Connectivity
Poll the provisioned instances until sshd is ready and accept host fingerprints:

```bash
ansible -i ansible/inventory/hosts.ini all -m ping -u ubuntu --private-key ~/.ssh/id_rsa
```
*Expected Result:* `SUCCESS => {"changed": false, "ping": "pong"}` for both `app1` and `monitor1`.

---

### Step 3: Configure Base System (`--tags common`)
Apply SSH hardening, hostname assignment (`app-<env>-1`, `monitor-<env>-1`), package repository updates, and chrony time synchronization:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags common
```
*Verification:* Check `/etc/ssh/sshd_config` for `PermitRootLogin no` and `PasswordAuthentication no`.

---

### Step 4: Apply Puppet Baseline (`--tags puppet`)
Install Puppet 8 agent, synchronize manifests and custom ruby functions, apply local catalog, and establish the 30-minute drift correction cron:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags puppet
```
*Verification:* Inspect `/etc/motd` for the dynamically generated banner displaying the classification label (`PRODUCTION`, `STAGING`, or `DEVELOPMENT`).

---

### Step 5: Install & Configure Monitoring (`--tags monitor`)
Install Nagios Core 4, Apache 2, monitoring plugins, custom `check_app_health` plugin, render `app.cfg`, configure HTTP digest authentication, and enable CGI modules:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --tags monitor
```
*Verification:* Confirm Nagios daemon is active with `sudo systemctl status nagios4`.

---

### Step 6: Deploy Kubernetes & Application (`--tags k3s,app`)
Install single-node k3s, create application namespace, deploy Kubernetes manifests, patch Service to NodePort 30080, and wait for deployment rollout:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml \
  --tags k3s,app \
  -e app_image=ghcr.io/<owner>/int333:latest
```
*Rollback Guarantee:* If the container fails readiness probes within 180 seconds, Ansible's `rescue` block automatically triggers `k3s kubectl rollout undo deployment/myapp -n <ns>` to restore the previous ReplicaSet.

---

## 2. Post-Deployment Verification Checklist

Verify all services end-to-end before declaring the environment healthy:

1. **Application Health via NodePort (Port 30080):**
   ```bash
   APP_IP=$(ansible-inventory -i ansible/inventory/hosts.ini --host app1 | jq -r .ansible_host)
   curl -i http://${APP_IP}:30080/healthz
   ```
   *Expected Output:* `HTTP/1.1 200 OK`, JSON body: `{"status":"ok"}`.

2. **Nagios Web Dashboard:**
   - URL: `http://<monitor-server-public-ip>/nagios4`
   - Authentication: Username `nagiosadmin`, password from `nagios_admin_password`.
   - Verify Service States:
     - `PING`: OK (latency < 100ms)
     - `SSH`: OK (OpenSSH responding)
     - `App HTTP /healthz`: OK (HTTP 200 returned)
     - `App response time`: OK (< 0.5s response latency)

3. **Puppet Configuration Drift Correction:**
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@${APP_IP} "sudo rm -f /etc/motd"
   ssh -i ~/.ssh/id_rsa ubuntu@${APP_IP} "sudo /opt/puppetlabs/bin/puppet apply --modulepath=/etc/puppetlabs/code/environments/production/modules /etc/puppetlabs/code/environments/production/manifests/site.pp"
   ssh -i ~/.ssh/id_rsa ubuntu@${APP_IP} "cat /etc/motd"
   ```
   *Expected Output:* Exit code 2 on drift correction; `/etc/motd` restored.

---

## 3. Teardown Procedure

To avoid unnecessary AWS cloud charges, always destroy the infrastructure when finished:

```bash
cd terraform
terraform destroy -auto-approve
cd ..
rm -f ansible/inventory/hosts.ini
```

---

## 4. Comprehensive Troubleshooting Guide

| Symptom | Probable Cause | Diagnostic Command | Remediation / Fix |
|---------|----------------|-------------------|-------------------|
| **SSH timeout / connection refused** | Security group port 22 not open to caller IP; EC2 instance still booting; wrong SSH key path. | `curl -s https://checkip.amazonaws.com`<br>`aws ec2 describe-security-groups` | Update `my_ip_cidr` in `terraform.tfvars` with current public IP. Wait 60s for instance cloud-init to complete. Verify `-i ~/.ssh/id_rsa`. |
| **apt lock (`Could not get lock /var/lib/apt/lists/lock`)** | Ubuntu `unattended-upgrades` running in background immediately after initial boot. | `ssh ubuntu@<ip> "ps aux \| grep -E 'apt\|dpkg'"` | The Ansible `common` role sets `cache_valid_time: 3600` and retries. Alternatively, wait 90 seconds for automatic package upgrade to finish: `systemctl status unattended-upgrades`. |
| **k3s node NotReady** | Kubelet initializing; node out of memory; system swap enabled; insufficient disk. | `ssh ubuntu@<app_ip> "k3s kubectl get nodes"`<br>`journalctl -u k3s -n 50` | Verify memory with `free -m`. Ensure `t3.small` (2GB RAM) is used for `app`. Disable swap if active: `sudo swapoff -a`. Check `/var/log/syslog`. |
| **`ImagePullBackOff` / `ErrImagePull`** | GHCR image is private and no `imagePullSecrets` or Docker credentials configured in k8s. | `k3s kubectl describe pod -l app=myapp -n devops-demo` | Change GHCR package visibility to **Public** in GitHub Package settings, OR create docker-registry secret: `k3s kubectl create secret docker-registry ghcr-secret --docker-server=ghcr.io --docker-username=<user> --docker-password=<token> -n devops-demo` and add `imagePullSecrets` to `deployment.yaml`. |
| **Nagios 401 Unauthorized / Blank UI** | Digest auth file missing or credentials mismatch; Apache `auth_digest` module disabled; cgi not enabled. | `curl -I http://<ip>/nagios4/`<br>`apache2ctl -M \| grep -E 'cgi\|digest'` | Run `a2enmod auth_digest cgi authz_groupfile && systemctl restart apache2`. Verify `/etc/nagios4/htdigest.users` format: `<user>:Nagios4:<md5sum>`. |
| **Nagios Host / Service DOWN (PING fails)** | AWS security group missing internal VPC traffic rule (`self = true`); ICMP blocked. | `ssh ubuntu@<monitor_ip> "ping -c 3 <app_private_ip>"` | Verify `terraform/main.tf` has SG ingress rule with `protocol = "icmp"`, `from_port = -1`, `to_port = -1`, `self = true`. Do not use public IP for VPC monitoring. |
| **Puppet exit codes confusion (exit 2 treated as failure)** | Puppet apply returns detailed exit codes (`--detailed-exitcodes`): `0` = no changes, `2` = changes applied successfully, `4` = failures, `6` = changes + failures. | `/opt/puppetlabs/bin/puppet apply --detailed-exitcodes ...; echo $?` | Configure CI/Ansible scripts to accept both `0` and `2` as success (`failed_when: result.rc not in [0, 2]`). |
| **Terraform: "no file exists at ~/.ssh/id_rsa.pub"** | Local SSH public key has not been generated before running Terraform. | `ls -la ~/.ssh/id_rsa.pub` | Generate standard RSA keypair: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""`. |
| **AWS vCPU / Instance Quota Error (`VcpuLimitExceeded`)** | AWS account default limit on running On-Demand `t3.small` / `t3.micro` instances in region. | `aws service-quotas get-service-quota ...` | Request quota increase in AWS Service Quotas console, or switch `aws_region` to an alternate supported region (e.g. `ap-south-1`, `eu-west-1`). |
| **IP Address Changed on EC2 instance** | EC2 instance was stopped and restarted, allocating a new public IPv4. | `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress]'` | Re-run `terraform refresh` to update state and regenerate `ansible/inventory/hosts.ini`. Note: Private VPC IPs do NOT change across reboots; internal Nagios checks remain unaffected. |
