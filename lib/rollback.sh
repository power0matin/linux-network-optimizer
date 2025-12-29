#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck source=lib/qdisc.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/qdisc.sh"

rollback_latest() {
  ensure_root
  need_cmd ip
  need_cmd tc
  need_cmd sysctl

  local iface="${1:-}"
  if [[ -z "${iface:-}" ]]; then
    iface="$(detect_default_iface)"
  fi

  local cur
  cur="$(readlink_safe "$NETOPT_STATE_DIR/current")"
  [[ -n "$cur" ]] || die "No 'current' backup found at $NETOPT_STATE_DIR/current. Cannot rollback."

  info "Rolling back using backup: $cur"

  # Restore sysctl values (before removing drop-in so we can return exactly)
  if [[ -f "$cur/sysctl_before.txt" ]]; then
    restore_sysctl_snapshot "$cur/sysctl_before.txt"
  else
    warn "Missing sysctl snapshot; only removing drop-in."
  fi

  remove_sysctl_dropin

  # Restore qdisc best-effort
  restore_qdisc_state "$cur" "$iface"

  info "Rollback completed."
}

list_backups() {
  if [[ ! -d "$NETOPT_BACKUP_DIR" ]]; then
    echo "No backups found."
    return 0
  fi
  find "$NETOPT_BACKUP_DIR" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort || true
}
