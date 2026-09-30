#!/usr/bin/env bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== 1. Installing packages ==="
apt-get update -qq >/dev/null
apt-get install -y -qq nagios4 monitoring-plugins monitoring-plugins-standard curl bc jq iputils-ping procps python3 &>/dev/null

echo "=== 2. Installing custom health check plugin ==="
mkdir -p /usr/lib/nagios/plugins
cp /repo/nagios/plugins/check_app_health.sh /usr/lib/nagios/plugins/check_app_health
chmod 0755 /usr/lib/nagios/plugins/check_app_health

echo "=== 3. Starting mock HTTP server on 127.0.0.1:3000 ==="
cat << 'PYEOF' > /tmp/mock_app.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Hello DevOps")
    def log_message(self, format, *args):
        pass

server = HTTPServer(("127.0.0.1", 3000), HealthHandler)
server.serve_forever()
PYEOF

python3 /tmp/mock_app.py &
APP_PID=$!
echo "Mock App running with PID: $APP_PID"
sleep 2

echo -n "Mock App health check test: "
curl -s http://127.0.0.1:3000/healthz || echo "curl failed"
echo ""

echo "=== 4. Rendering test-only app.cfg with 127.0.0.1 and check_interval=1 ==="
cat << 'PYEOF' > /tmp/render_cfg.py
with open("/repo/ansible/roles/nagios_server/templates/app.cfg.j2") as f:
    cfg = f.read()

# Replace variables with local test values
cfg = cfg.replace("{{ hostvars[groups['app'][0]]['private_ip'] }}", "127.0.0.1")
cfg = cfg.replace("{{ app_node_port }}", "3000")

# Lower check interval for fast test turnaround
cfg = cfg.replace("check_interval          5", "check_interval          1")
cfg = cfg.replace("retry_interval          1", "retry_interval          1")
cfg = cfg.replace("max_check_attempts      4", "max_check_attempts      2")
cfg = cfg.replace("max_check_attempts      3", "max_check_attempts      2")

with open("/etc/nagios4/conf.d/app.cfg", "w") as f:
    f.write(cfg)
PYEOF

python3 /tmp/render_cfg.py

echo "=== Rendered /etc/nagios4/conf.d/app.cfg ==="
cat /etc/nagios4/conf.d/app.cfg

echo ""
echo "=== Verifying nagios configuration ==="
nagios4 -v /etc/nagios4/nagios.cfg | grep -E "Total (Warnings|Errors)"

echo "=== 5. Starting Nagios daemon in background ==="
mkdir -p /var/run/nagios4 /var/lib/nagios4 /var/log/nagios4 /var/cache/nagios4
chown -R nagios:nagios /var/run/nagios4 /var/lib/nagios4 /var/log/nagios4 /var/cache/nagios4
nagios4 -d /etc/nagios4/nagios.cfg
sleep 2

ps aux | grep nagios4

cat << 'PYEOF' > /tmp/parse_status.py
import sys
import re

status_file = "/var/lib/nagios4/status.dat"
try:
    with open(status_file, "r") as f:
        content = f.read()
except Exception as e:
    print(f"status.dat not ready: {e}")
    sys.exit(1)

blocks = re.findall(r"servicestatus\s*\{([^}]+)\}", content)
state_map = {"0": "OK", "1": "WARNING", "2": "CRITICAL", "3": "UNKNOWN"}

results = []
for block in blocks:
    host_match = re.search(r"host_name=(\S+)", block)
    desc_match = re.search(r"service_description=([^\n]+)", block)
    state_match = re.search(r"current_state=(\d+)", block)
    output_match = re.search(r"plugin_output=([^\n]+)", block)
    checked_match = re.search(r"has_been_checked=(\d+)", block)
    attempts_match = re.search(r"current_attempt=(\d+)", block)
    
    if host_match and desc_match and host_match.group(1) == "app1":
        desc = desc_match.group(1).strip()
        state_code = state_match.group(1) if state_match else "?"
        state = state_map.get(state_code, state_code)
        checked = checked_match.group(1) if checked_match else "0"
        attempts = attempts_match.group(1) if attempts_match else "0"
        output = output_match.group(1).strip() if output_match else "N/A"
        results.append((desc, state_code, state, checked, attempts, output))

if not results:
    print("No app1 services found in status.dat yet.")
    sys.exit(1)

all_checked = all(r[3] == "1" for r in results)
for desc, state_code, state, checked, attempts, output in sorted(results):
    chk_str = "CHECKED" if checked == "1" else "PENDING"
    print(f"  Service: {desc:<22} | State: {state:<8} (code {state_code}) | Attempt: {attempts} | {chk_str} | Output: {output}")

if not all_checked:
    sys.exit(2)
PYEOF

echo ""
echo "=== 6. Waiting for Nagios to execute initial checks (~60-90s) ==="
for i in $(seq 1 30); do
    echo "--- Polling status.dat (attempt $i/30) ---"
    if python3 /tmp/parse_status.py; then
        echo "All services have run!"
        break
    fi
    sleep 4
done

echo ""
echo "=== 7. Service Status while Mock App is RUNNING ==="
python3 /tmp/parse_status.py || true

echo ""
echo "=== 8. Stopping Mock App (killing PID $APP_PID) ==="
kill -9 $APP_PID || true
sleep 2

echo "Verifying mock app is stopped:"
curl -s http://127.0.0.1:3000/healthz || echo "Connection refused (mock app is down)"

echo ""
echo "=== 9. Waiting for Nagios to detect service failures (transition to CRITICAL) ==="
for i in $(seq 1 25); do
    echo "--- Polling status.dat after app shutdown (attempt $i/25) ---"
    python3 /tmp/parse_status.py || true
    
    # Check if both App HTTP /healthz and App response time are CRITICAL (current_state=2)
    APP_HTTP_CRIT=$(grep -A 12 "service_description=App HTTP /healthz" /var/lib/nagios4/status.dat 2>/dev/null | grep -c "current_state=2" || true)
    APP_RESP_CRIT=$(grep -A 12 "service_description=App response time" /var/lib/nagios4/status.dat 2>/dev/null | grep -c "current_state=2" || true)
    
    if [ "$APP_HTTP_CRIT" -ge 1 ] && [ "$APP_RESP_CRIT" -ge 1 ]; then
        echo "Detected both App HTTP /healthz and App response time in CRITICAL state!"
        break
    fi
    sleep 4
done

echo ""
echo "=== 10. FINAL Service Status showing states after app shutdown ==="
python3 /tmp/parse_status.py || true

echo ""
echo "=== 11. Stopping Nagios daemon ==="
killall nagios4 2>/dev/null || true
echo "Live Nagios test completed successfully!"
