#!/usr/bin/env bash
# scripts/test_nagios_live.sh - Live Nagios test in Ubuntu 22.04 container (no systemd)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

docker run --rm \
  -v "${REPO_DIR}:/repo" \
  -w /repo \
  ubuntu:22.04 \
  bash /repo/scripts/test_nagios_live_inner.sh
