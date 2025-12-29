#!/usr/bin/env bash
set -Eeuo pipefail

# NETOPT_VERSION="1.0.0"  # remove if unused
NETOPT_STATE_DIR="${NETOPT_STATE_DIR:-/var/lib/netopt}"
NETOPT_BACKUP_DIR="${NETOPT_BACKUP_DIR:-$NETOPT_STATE_DIR/backups}"
NETOPT_SYSCTL_DROPIN="${NETOPT_SYSCTL_DROPIN:-/etc/sysctl.d/99-netopt.conf}"

# ---- logging ----
ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }
log() { printf '%s %s\n' "$(ts)" "$*" >&2; }
info() { log "[INFO] $*"; }
warn() { log "[WARN] $*"; }
err() { log "[ERROR] $*"; }
die() { err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

ensure_root() {
  is_root || die "This action requires root. Re-run with sudo."
}

# ---- helpers ----
have_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_default_iface() {
  # Prefer default route interface
  local iface
  iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -n "${iface:-}" ]]; then
    echo "$iface"
    return 0
  fi
  # Fallback: first non-lo interface that is UP
  iface="$(ip -o link show up | awk -F': ' '$2 != "lo" {print $2; exit}')"
  [[ -n "${iface:-}" ]] || die "Could not detect a usable network interface."
  echo "$iface"
}

mkdirp_root() {
  local d="$1"
  mkdir -p "$d"
  chmod 700 "$d" || true
}

backup_begin() {
  ensure_root
  mkdirp_root "$NETOPT_BACKUP_DIR"
  local stamp; stamp="$(date +"%Y%m%d_%H%M%S")"
  local bdir="$NETOPT_BACKUP_DIR/$stamp"
  mkdirp_root "$bdir"
  ln -sfn "$bdir" "$NETOPT_STATE_DIR/current" 2>/dev/null || true
  echo "$bdir"
}

backup_write_kv() {
  local file="$1"; shift
  printf '%s\n' "$@" > "$file"
}

# Save current values for a list of sysctl keys (one per line).
backup_sysctl_keys() {
  local bdir="$1"
  shift
  local outfile="$bdir/sysctl_before.txt"
  : > "$outfile"
  for key in "$@"; do
    if sysctl -a 2>/dev/null | grep -qE "^${key}\s*="; then
      sysctl -n "$key" 2>/dev/null | awk -v k="$key" '{print k"="$0}' >> "$outfile" || true
    fi
  done
  info "Saved sysctl snapshot: $outfile"
}

restore_sysctl_snapshot() {
  ensure_root
  local snapshot="$1"
  [[ -f "$snapshot" ]] || die "Sysctl snapshot not found: $snapshot"
  while IFS='=' read -r key val; do
    [[ -n "${key:-}" ]] || continue
    sysctl -w "${key}=${val}" >/dev/null || true
  done < "$snapshot"
  info "Restored sysctl values from snapshot."
}

write_sysctl_dropin() {
  ensure_root
  local content="$1"
  printf '%s\n' "$content" > "$NETOPT_SYSCTL_DROPIN"
  chmod 644 "$NETOPT_SYSCTL_DROPIN"
  sysctl --system >/dev/null
  info "Applied sysctl drop-in: $NETOPT_SYSCTL_DROPIN"
}

remove_sysctl_dropin() {
  ensure_root
  if [[ -f "$NETOPT_SYSCTL_DROPIN" ]]; then
    rm -f "$NETOPT_SYSCTL_DROPIN"
    sysctl --system >/dev/null || true
    info "Removed sysctl drop-in: $NETOPT_SYSCTL_DROPIN"
  else
    info "No sysctl drop-in present; skipping removal."
  fi
}

readlink_safe() {
  local p="$1"
  if [[ -L "$p" ]]; then
    readlink -f "$p"
  else
    echo ""
  fi
}
