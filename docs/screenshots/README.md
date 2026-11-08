# Project Evidence & Screenshots Guide

This directory holds visual verification artifacts demonstrating the working end-to-end DevOps pipeline for INT333 grading and portfolio presentation.

> [!CAUTION]
> **No Secrets Rule**: Before capturing and committing any screenshot, ensure that sensitive information (AWS Account IDs, secret access keys, private SSH keys, password hashes, and personal IP addresses) is blurred or omitted.

---

## Verified Live Deployment Details

- **AWS Region:** `eu-north-1` (Stockholm)
- **Kubernetes (k3s) Namespace:** `staging`
- **Application Deployment:** `myapp` (2 fixed replicas, zero restarts)
- **Container Image:** `ghcr.io/venkatas987/int333-devops:sha-ac61325`
- **APP_VERSION:** `sha-ac61325`
- **Service Type & Port:** `NodePort 30080`
- **Application Routes:**
  - `GET /`: App metadata
  - `GET /healthz`: JSON health status probe (`{"status":"ok"}`)
  - `GET /api/status`: Read-only JSON runtime status and metrics
  - `GET /dashboard`: Read-only HTML status dashboard with strict CSP headers
- **Monitoring:** Nagios Core 4 on `mon1` monitoring `app1` via private VPC IP

---

## Screenshot Evidence Status

### Captured Evidence Files (Present in Directory)

| Filename | Description | Status |
|---|---|---|
| `02_nagios_app_services.png` | Nagios Core Services view showing host `app1` UP and all 4 services OK | **CAPTURED** |
| `08_nagios_dashboard.png` | Nagios Core Monitoring Dashboard showing post-recovery healthy state | **CAPTURED** |
| `10_dashboard_healthy.png` | Node.js Status Dashboard (`/dashboard`) showing green HEALTHY badge and pod info | **CAPTURED** |
| `13_nagios_failure.png` | Nagios Service detail showing `App HTTP /healthz` in CRITICAL state during simulated failure | **CAPTURED** |

#### Evidence Details:

1. **`02_nagios_app_services.png` (Nagios App Services Healthy)**
   - **Captured View:** Nagios Core 4 web interface (`/nagios4/cgi-bin/status.cgi?host=app1`).
   - **Key Elements:**
     - Host `app1`: `UP` (green).
     - `App HTTP /healthz`: `OK` (HTTP 200, status payload verified).
     - `App response time`: `OK` (custom plugin performance data).
     - `PING`: `OK` (0% packet loss via AWS Security Group internal ICMP rule).
     - `SSH`: `OK` (port 22 accessible within SG).
   - *Note on Localhost Warning:* The Nagios localhost check lists a `Swap Usage CRITICAL` entry because standard AWS EC2 Ubuntu AMIs do not configure a local swap partition; this is isolated to the monitoring server's local template and is completely unrelated to the `app1` application health.

2. **`08_nagios_dashboard.png` (Nagios Monitoring Dashboard Recovery)**
   - **Captured View:** Nagios Core Services Overview after recovering the application workload.
   - **Key Elements:**
     - Host `app1` UP.
     - All 4 application services verified in green `OK` state following replica recovery.

3. **`10_dashboard_healthy.png` (Application Status Dashboard — Healthy)**
   - **Captured View:** Browser visiting `http://<app-public-ip>:30080/dashboard`.
   - **Key Elements:**
     - Large green **HEALTHY** status badge.
     - "Served by pod: `myapp-767bb84dc-ptvl8` (refreshing every 5s)".
     - Status metric cards: Pod Name, App Version (`sha-ac61325`), Uptime, Memory (RSS), Node.js Runtime (`v22.23.4`), OS Platform (`linux`), Last Updated timestamp.
     - Verified security headers: `Content-Security-Policy: default-src 'self'`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`.

4. **`13_nagios_failure.png` (Nagios Failure Detection)**
   - **Captured View:** Nagios Service State detail for `App HTTP /healthz` during simulated outage (`replicas=0`).
   - **Key Elements:**
     - State: Red **CRITICAL**.
     - Status Information: `connect to address 172.31.6.207 and port 30080: Connection refused. HTTP CRITICAL - Unable to open TCP socket`.
     - Confirms Nagios active monitoring accurately detects pod outage in real time.

---

### Missing / Non-Captured Evidence

The following visual screenshot artifacts were not captured as image files:

- **`09_puppet_drift_correction.png` (Puppet Drift Demonstration):**
  - *Status:* Missing image file.
  - *Verification Note:* Live execution on `app-staging-1` was verified via terminal execution:
    1. Initial `/etc/motd` verified managed by Puppet baseline module.
    2. Removal of `/etc/motd` (`sudo rm -f /etc/motd`) caused configuration drift.
    3. Re-application (`sudo puppet apply --modulepath=/opt/puppet-demo/modules ...`) compiled the catalog and restored `/etc/motd` with `{sha256}83c1bf88d58cc1b5fcf3345435f3f47076d0c20fa69e23ed0f2a7d1c077fa8eb`.
    4. Second apply with `--detailed-exitcodes` completed with **exit code 0** (idempotent, no changes needed).
- **`11_dashboard_down.png` (Status Dashboard — Failure State):**
  - *Status:* Missing image file.
  - *Verification Note:* Failure state was captured via Nagios (`13_nagios_failure.png`).
- **`12_dashboard_pod_toggle.png` (Multi-Pod Load Balancing):**
  - *Status:* Missing image file.
  - *Verification Note:* Multi-pod round-robin load distribution was verified via `scripts/verify_deployment.sh` and 10 sequential calls to `/api/status`, observing alternating responses between `myapp-767bb84dc-72vnb` and `myapp-767bb84dc-ptvl8`.
