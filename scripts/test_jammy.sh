#!/usr/bin/env bash
# scripts/test_jammy.sh – spins up an Ubuntu 22.04 container to test roles and configs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Launching Ubuntu 22.04 container test..."
docker run --rm \
  -v "${REPO_DIR}:/repo" \
  -w /repo \
  ubuntu:22.04 \
  bash /repo/scripts/test_jammy_inner.sh

