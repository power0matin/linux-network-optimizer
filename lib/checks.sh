#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

print_header() {
  # echo "NetOpt v$NETOPT_VERSION"
  echo "----------------------------------------"
}

check_kernel() {
  local ver
  ver="$(uname -r)"
  info "Kernel: $ver"
  if [[ "$ver" =~ ^2\.|^3\. ]]; then
    warn "Kernel is quite old; results may be limited. Prefer 4.19+ (or newer)."
  fi
}

check_congestion_control() {
  local cc avail
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  info "TCP congestion control: ${cc:-unknown}"
  info "Available CC: ${avail:-unknown}"
}

check_qdisc() {
  local iface="$1"
  info "Interface: $iface"
  tc qdisc show dev "$iface" 2>/dev/null | sed 's/^/[QDISC] /' || true
}

check_offloads() {
  local iface="$1"
  if ! have_cmd ethtool; then
    warn "ethtool not installed; skipping NIC offload report."
    return 0
  fi
  info "NIC offloads (report only):"
  ethtool -k "$iface" 2>/dev/null | sed 's/^/[ETHTOOL] /' || true
}

check_socket_limits() {
  info "Key sysctl (current):"
  local keys=(
    net.core.somaxconn
    net.ipv4.tcp_max_syn_backlog
    net.core.netdev_max_backlog
    net.ipv4.ip_local_port_range
    net.ipv4.tcp_fin_timeout
    net.ipv4.tcp_tw_reuse
    net.ipv4.tcp_syncookies
    net.ipv4.tcp_mtu_probing
    net.ipv4.tcp_sack
    net.ipv4.tcp_timestamps
    net.ipv4.tcp_rmem
    net.ipv4.tcp_wmem
    net.core.rmem_max
    net.core.wmem_max
  )
  for k in "${keys[@]}"; do
    printf '%-35s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo 'n/a')"
  done
}

check_conntrack() {
  if sysctl -a 2>/dev/null | grep -q '^net.netfilter.nf_conntrack_max'; then
    info "Conntrack:"
    printf '%-35s %s\n' "net.netfilter.nf_conntrack_max" "$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 'n/a')"
    printf '%-35s %s\n' "net.netfilter.nf_conntrack_count" "$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 'n/a')"
  else
    info "Conntrack not available (kernel module not loaded or not in use)."
  fi
}

run_checks() {
  need_cmd ip
  need_cmd tc
  need_cmd sysctl

  local iface="${1:-}"
  if [[ -z "${iface:-}" ]]; then
    iface="$(detect_default_iface)"
  fi

  print_header
  check_kernel
  check_congestion_control
  check_qdisc "$iface"
  check_offloads "$iface"
  check_socket_limits
  check_conntrack

  echo "----------------------------------------"
  info "Checks completed."
}
