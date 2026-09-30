#!/usr/bin/env bash
export PATH="/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$HOME/.local/bin:$PATH"

PASS_COUNT=0
FAIL_COUNT=0

# shellcheck disable=SC2317
cleanup() {
  if [ -n "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

PLUGIN="./nagios/plugins/check_app_health.sh"
chmod +x "$PLUGIN"

echo "=== TASK 1: Nagios Plugin Test Suite ==="

# Start app on port 3005
PORT=3005 node server.js >/dev/null 2>&1 &
APP_PID=$!
sleep 2

# Case 1: Healthy (-w 5 -c 10 -> exit 0)
OUT1=$("$PLUGIN" -H 127.0.0.1 -p 3005 -w 5 -c 10 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$OUT1" | grep -q "time="; then
  echo "  Case 1 (Healthy -> 0 with time=): PASS ($OUT1)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 1 (Healthy -> 0 with time=): FAIL (rc=$rc, out=$OUT1)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Case 2: Forces slow (-w 0.00001 -c 10 -> exit 1)
OUT2=$("$PLUGIN" -H 127.0.0.1 -p 3005 -w 0.00001 -c 10 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  echo "  Case 2 (Warning threshold exceeded -> 1): PASS ($OUT2)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 2 (Warning threshold exceeded -> 1): FAIL (rc=$rc, out=$OUT2)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Case 3: Forces critical (-w 0.00001 -c 0.00002 -> exit 2)
OUT3=$("$PLUGIN" -H 127.0.0.1 -p 3005 -w 0.00001 -c 0.00002 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "  Case 3 (Critical threshold exceeded -> 2): PASS ($OUT3)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 3 (Critical threshold exceeded -> 2): FAIL (rc=$rc, out=$OUT3)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Case 4: Server stopped (connection refused -> exit 2)
kill "$APP_PID" 2>/dev/null
wait "$APP_PID" 2>/dev/null
unset APP_PID
sleep 1

OUT4=$("$PLUGIN" -H 127.0.0.1 -p 3005 -w 5 -c 10 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "  Case 4 (Connection refused -> 2): PASS ($OUT4)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 4 (Connection refused -> 2): FAIL (rc=$rc, out=$OUT4)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Case 5: No arguments -> exit 3
OUT5=$("$PLUGIN" 2>&1)
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "  Case 5 (No arguments -> 3): PASS ($OUT5)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 5 (No arguments -> 3): FAIL (rc=$rc, out=$OUT5)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Case 6: Unknown option (-Z -> exit 3)
OUT6=$("$PLUGIN" -Z 2>&1)
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "  Case 6 (Unknown option -Z -> 3): PASS ($OUT6)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  Case 6 (Unknown option -Z -> 3): FAIL (rc=$rc, out=$OUT6)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "=== Shellcheck on Plugin & Test Script ==="
shellcheck "$PLUGIN"
rc_sc1=$?
shellcheck "$0"
rc_sc2=$?

if [ "$rc_sc1" -eq 0 ] && [ "$rc_sc2" -eq 0 ]; then
  echo "  Shellcheck: PASS"
else
  echo "  Shellcheck: FAIL (plugin rc=$rc_sc1, test script rc=$rc_sc2)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
else
  exit 1
fi
