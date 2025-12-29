#!/usr/bin/env bash
set -euo pipefail
# Example: apply safe profile + fq_codel
sudo ./bin/netopt apply --profile safe --qdisc fq_codel
sudo ./bin/netopt check
