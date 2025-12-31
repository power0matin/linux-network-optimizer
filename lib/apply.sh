#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck source=lib/qdisc.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/qdisc.sh"
# shellcheck source=lib/rollback.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/rollback.sh"

sysctl_profile_safe() {
  cat <<'EOF'
# NetOpt - SAFE profile
# Note: keep conservative, avoid controversial toggles.

# Queueing & backlog
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# Buffers (moderate)
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# TCP behavior (safe)
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

# Port range
net.ipv4.ip_local_port_range = 10240 65535

# Keepalive (helps dead peers; not too aggressive)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 6
EOF
}

sysctl_profile_balanced() {
  cat <<'EOF'
# NetOpt - BALANCED profile

net.core.netdev_max_backlog = 32768
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

net.ipv4.ip_local_port_range = 10240 65535

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 6
EOF
}

sysctl_profile_aggressive() {
  cat <<'EOF'
# NetOpt - AGGRESSIVE profile (use only with measurement)

net.core.netdev_max_backlog = 65536
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 32768

net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# More aggressive timeouts
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

net.ipv4.ip_local_port_range = 10240 65535

net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 20
net.ipv4.tcp_keepalive_probes = 5
EOF
}

apply_profile() {
  ensure_root
  need_cmd sysctl
  need_cmd ip
  need_cmd tc
  need_cmd awk
  need_cmd sort

  local profile="$1"
  local iface="${2:-}"
  local qdisc_mode="${3:-fq_codel}"

  if [[ -z "${iface:-}" ]]; then
    iface="$(detect_default_iface)"
  fi

  # Render selected sysctl content first (source of truth)
  local content=""
  case "$profile" in
    safe)       content="$(sysctl_profile_safe)" ;;
    balanced)   content="$(sysctl_profile_balanced)" ;;
    aggressive) content="$(sysctl_profile_aggressive)" ;;
    *) die "Unknown profile: $profile (safe|balanced|aggressive)" ;;
  esac

  local bdir; bdir="$(backup_begin)"
  info "Backup directory: $bdir"

  # Derive sysctl keys from the actual profile content to avoid backup drift
  local -a keys=()
  mapfile -t keys < <(
    printf '%s\n' "$content" \
      | awk -F'=' '
          /^[[:space:]]*#/ { next }
          /^[[:space:]]*$/ { next }
          /^[[:space:]]*[A-Za-z0-9_.]+[[:space:]]*=/ {
            k=$1
            gsub(/[[:space:]]+/, "", k)
            print k
          }' \
      | sort -u
  )

  if ((${#keys[@]} > 0)); then
    backup_sysctl_keys "$bdir" "${keys[@]}"
  else
    info "No sysctl keys detected in profile content; skipping sysctl snapshot."
  fi

  if ! write_sysctl_dropin "$content"; then
    info "Failed to write/apply sysctl drop-in. Attempting rollback..."
    rollback_latest "$iface" || true
    return 1
  fi

  if ! qdisc_set "$iface" "$qdisc_mode" "$bdir"; then
    info "Failed to apply qdisc. Attempting rollback..."
    rollback_latest "$iface" || true
    return 1
  fi

  info "Apply completed."
  echo "$bdir"
}
