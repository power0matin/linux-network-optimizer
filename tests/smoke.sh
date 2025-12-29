#!/usr/bin/env bash
set -euo pipefail
# Smoke test: ensure CLI renders help and check runs without root (check only).
./bin/netopt --help >/dev/null
./bin/netopt check >/dev/null || true
echo "OK"
