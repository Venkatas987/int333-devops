#!/usr/bin/env bash
# nagios/plugins/check_app_health.sh
#
# WHY THIS SCRIPT EXISTS:
# The standard Nagios `check_http` plugin can verify HTTP status codes but
# cannot parse a JSON body or output response-time performance data.
# This custom plugin:
#   1. Hits GET /healthz on the specified host:port.
#   2. Verifies the HTTP response code is 200.
#   3. Verifies the body contains `"status":"ok"`.
#   4. Measures the response time and compares to WARNING/CRITICAL thresholds.
#   5. Outputs a performance data string so Nagios can graph response time.
#
# Nagios plugin exit codes (standard convention):
#   0 = OK
#   1 = WARNING
#   2 = CRITICAL
#   3 = UNKNOWN  (error in plugin execution / arguments)
#
# Output format:
#   STATUS - message | time=X.XXXs;warn;crit;0
#
# Usage:
#   check_app_health.sh -H <host> -p <port> -w <warn_secs> -c <crit_secs>

# Defaults
HOST=""
PORT="30080"
WARN="0.5"
CRIT="2"

usage() {
  echo "UNKNOWN - Usage: $0 -H <host> -p <port> -w <warn_secs> -c <crit_secs>"
  exit 3
}

# Parse options (leading colon enables silent error handling)
while getopts ":H:p:w:c:" opt; do
  case "$opt" in
    H) HOST="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    w) WARN="$OPTARG" ;;
    c) CRIT="$OPTARG" ;;
    :)
      echo "UNKNOWN - Option -${OPTARG} requires an argument"
      exit 3
      ;;
    \?)
      echo "UNKNOWN - Invalid option: -${OPTARG}"
      exit 3
      ;;
    *) usage ;;
  esac
done

if [ -z "$HOST" ]; then
  echo "UNKNOWN - Missing -H (hostname)"
  exit 3
fi

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# 1. Fetch health endpoint
HTTP_CODE=$(curl --silent --max-time 10 --output "$TMPFILE" --write-out "%{http_code}" "http://${HOST}:${PORT}/healthz")
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ]; then
  echo "CRITICAL - curl failed (host unreachable or connection refused) | time=0s;${WARN};${CRIT};0"
  exit 2
fi

# 2. Check HTTP status code
if [ "$HTTP_CODE" != "200" ]; then
  echo "CRITICAL - HTTP ${HTTP_CODE} (expected 200) | time=0s;${WARN};${CRIT};0"
  exit 2
fi

# 3. Check JSON body
if ! grep -q '"status":"ok"' "$TMPFILE"; then
  BODY=$(head -c 100 "$TMPFILE")
  echo "CRITICAL - Unexpected body: ${BODY} | time=0s;${WARN};${CRIT};0"
  exit 2
fi

# 4. Measure response time
RESPONSE_TIME=$(curl --silent --max-time 10 --output /dev/null --write-out "%{time_total}" "http://${HOST}:${PORT}/healthz")
CURL_TIME_EXIT=$?

if [ "$CURL_TIME_EXIT" -ne 0 ] || [ -z "$RESPONSE_TIME" ]; then
  RESPONSE_TIME="0"
fi

# 5. Evaluate thresholds with bc
IS_CRIT=$(echo "${RESPONSE_TIME} > ${CRIT}" | bc -l 2>/dev/null)
IS_WARN=$(echo "${RESPONSE_TIME} > ${WARN}" | bc -l 2>/dev/null)

PERFDATA="time=${RESPONSE_TIME}s;${WARN};${CRIT};0"

if [ "$IS_CRIT" = "1" ]; then
  echo "CRITICAL - HTTP 200 but slow: ${RESPONSE_TIME}s (threshold: ${CRIT}s) | ${PERFDATA}"
  exit 2
fi

if [ "$IS_WARN" = "1" ]; then
  echo "WARNING - HTTP 200 but slow: ${RESPONSE_TIME}s (threshold: ${WARN}s) | ${PERFDATA}"
  exit 1
fi

echo "OK - HTTP 200 in ${RESPONSE_TIME}s | ${PERFDATA}"
exit 0
