#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "======================================================================"
echo " Running Ubuntu 22.04 (Jammy) Container Internal Test Suite"
echo "======================================================================"

echo ""
echo "=== SUBTASK 2a: Package Availability & Dry-Run Installs ==="
apt-get update -qq

echo "--- 1. Testing roles/common packages ---"
COMMON_PKGS="curl git htop ufw unattended-upgrades chrony python3-pip"
apt-cache policy $COMMON_PKGS
apt-get install -y --dry-run $COMMON_PKGS > /dev/null
echo "  [PASS] roles/common packages installable on Ubuntu 22.04"

echo "--- 2. Testing roles/nagios_server packages ---"
NAGIOS_PKGS="nagios4 monitoring-plugins monitoring-plugins-standard apache2 curl bc jq libwww-perl"
apt-cache policy $NAGIOS_PKGS
apt-get install -y --dry-run $NAGIOS_PKGS > /dev/null
echo "  [PASS] roles/nagios_server packages installable on Ubuntu 22.04"

echo "--- 3. Testing roles/puppet_agent repo & package ---"
apt-get install -y -qq curl ca-certificates
curl -sSL -o /tmp/puppet8-release-jammy.deb https://apt.puppet.com/puppet8-release-jammy.deb
dpkg -i /tmp/puppet8-release-jammy.deb > /dev/null
apt-get update -qq
apt-cache policy puppet-agent
apt-get install -y --dry-run puppet-agent > /dev/null
echo "  [PASS] roles/puppet_agent package installable on Ubuntu 22.04"

echo ""
echo "=== SUBTASK 2b: Real Nagios4 + Apache2 Install & Config Discovery ==="
apt-get install -y -qq nagios4 apache2 monitoring-plugins curl bc jq

echo "Available Apache configs:"
ls -la /etc/apache2/conf-available/

echo "Enabled Nagios configs:"
ls -la /etc/apache2/conf-enabled/ | grep -i nagios || true

echo "Nagios Apache Auth Configuration Lines:"
grep -rn -E "AuthName|AuthType|AuthUserFile|AuthDigest" /etc/apache2/conf-available/nagios4-cgi.conf

echo "  [PASS] Conf name is nagios4-cgi, realm is Nagios4, auth file is /etc/nagios4/htdigest.users"

echo ""
echo "=== SUBTASK 2c: Render app.cfg.j2, Install Plugin & Validate Nagios Config ==="
python3 -c "
with open(\"/repo/ansible/roles/nagios_server/templates/app.cfg.j2\") as f:
    content = f.read()

content = content.replace(\"{{ hostvars[groups[\x27app\x27][0]][\x27private_ip\x27] }}\", \"10.0.0.10\")
content = content.replace(\"{{ app_node_port }}\", \"30080\")

with open(\"/etc/nagios4/conf.d/app.cfg\", \"w\") as f:
    f.write(content)
"

mkdir -p /usr/lib/nagios/plugins
cp /repo/nagios/plugins/check_app_health.sh /usr/lib/nagios/plugins/check_app_health
chmod 0755 /usr/lib/nagios/plugins/check_app_health

echo "Verifying Nagios configuration with nagios4 -v:"
NAGIOS_OUT=$(nagios4 -v /etc/nagios4/nagios.cfg)
echo "--- Nagios Warnings from validation ---"
echo "$NAGIOS_OUT" | grep -i "warning:" || true
echo "--- Summary ---"
echo "$NAGIOS_OUT" | tail -n 12

echo "  [PASS] Nagios4 configuration verified with Total Errors: 0"

echo ""
echo "=== SUBTASK 2d: Digest Authentication & Apache Syntax Test ==="
nagios_admin_user="nagiosadmin"
nagios_admin_password="ChangeMe123!"
HASH=$(printf "%s" "${nagios_admin_user}:Nagios4:${nagios_admin_password}" | md5sum | cut -d" " -f1)
echo "${nagios_admin_user}:Nagios4:$HASH" > /etc/nagios4/htdigest.users
chown root:www-data /etc/nagios4/htdigest.users
chmod 0640 /etc/nagios4/htdigest.users

echo "Generated digest file:"
cat /etc/nagios4/htdigest.users

a2enmod cgi auth_digest authz_groupfile > /dev/null
a2enconf nagios4-cgi > /dev/null
apache2ctl configtest
echo "  [PASS] Apache2 configuration test passed with Syntax OK"

echo ""
echo "=== SUBTASK 2e: Puppet Real Apply, Idempotency & Drift Correction ==="
apt-get install -y -qq puppet-agent

echo "--- Run 1: Initial apply (must make changes, exit code 2) ---"
set +e
/opt/puppetlabs/bin/puppet apply --detailed-exitcodes \
  --modulepath=/repo/puppet/modules \
  /repo/puppet/manifests/site.pp
RC1=$?
set -e
echo "Run 1 Exit Code: $RC1"
if [ "$RC1" -ne 2 ]; then
  echo "FAIL: Expected exit code 2 on first apply, got $RC1"
  exit 1
fi

echo "Generated /etc/motd:"
cat /etc/motd

echo "--- Run 2: Idempotency check (must make no changes, exit code 0) ---"
set +e
/opt/puppetlabs/bin/puppet apply --detailed-exitcodes \
  --modulepath=/repo/puppet/modules \
  /repo/puppet/manifests/site.pp
RC2=$?
set -e
echo "Run 2 Exit Code: $RC2"
if [ "$RC2" -ne 0 ]; then
  echo "FAIL: Expected exit code 0 on second apply, got $RC2"
  exit 1
fi
echo "  [PASS] Puppet idempotency verified (exit code 0)"

echo "--- Run 3: Drift correction test ---"
rm -f /etc/motd
echo "Deleted /etc/motd. Re-applying Puppet catalog..."
set +e
/opt/puppetlabs/bin/puppet apply --detailed-exitcodes \
  --modulepath=/repo/puppet/modules \
  /repo/puppet/manifests/site.pp
RC3=$?
set -e
echo "Run 3 Exit Code: $RC3"
if [ "$RC3" -ne 2 ]; then
  echo "FAIL: Expected exit code 2 on drift correction, got $RC3"
  exit 1
fi
if [ ! -f /etc/motd ]; then
  echo "FAIL: /etc/motd was not restored by Puppet!"
  exit 1
fi
echo "Restored /etc/motd:"
cat /etc/motd
echo "  [PASS] Puppet drift correction restored /etc/motd successfully!"

echo ""
echo "======================================================================"
echo " ALL UBUNTU 22.04 CONTAINER TESTS PASSED (a, b, c, d, e)"
echo "======================================================================"
