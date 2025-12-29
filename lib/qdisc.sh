#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

save_qdisc_state() {
  local bdir="$1"
  local iface="$2"
  tc qdisc show dev "$iface" > "$bdir/tc_qdisc_before.txt" 2>/dev/null || true
  ip -d link show "$iface" > "$bdir/ip_link_before.txt" 2>/dev/null || true
  info "Saved qdisc snapshot: $bdir/tc_qdisc_before.txt"
}

restore_qdisc_state() {
  ensure_root
  local bdir="$1"
  local iface="$2"
  local qfile="$bdir/tc_qdisc_before.txt"
  if [[ ! -f "$qfile" ]]; then
    warn "No qdisc snapshot file found, deleting current root qdisc as fallback."
    tc qdisc del dev "$iface" root 2>/dev/null || true
    return 0
  fi

  # Simple, safe restore:
  # - If previous had a root qdisc line, we try to re-add the same kind.
  # - If parsing fails, we delete the current qdisc (kernel default).
  local prev_kind
  prev_kind="$(awk '/^qdisc /{print $2; exit}' "$qfile" 2>/dev/null || true)"
  tc qdisc del dev "$iface" root 2>/dev/null || true

  case "$prev_kind" in
    fq_codel)
      tc qdisc add dev "$iface" root fq_codel 2>/dev/null || true
      ;;
    cake)
      tc qdisc add dev "$iface" root cake 2>/dev/null || true
      ;;
    pfifo_fast|fq|tbf|htb|prio|sfq)
      # best-effort restore for common kinds; without deep parameters.
      tc qdisc add dev "$iface" root "$prev_kind" 2>/dev/null || true
      ;;
    "")
      # No qdisc line found; leave default
      ;;
    *)
      warn "Previous qdisc kind '$prev_kind' not restored (unknown/complex). Left at kernel default."
      ;;
  esac
  info "Restored qdisc (best-effort)."
}

qdisc_set() {
  ensure_root
  need_cmd tc
  need_cmd modprobe

  local iface="$1"
  local mode="$2"   # fq_codel | cake
  local bdir="$3"

  save_qdisc_state "$bdir" "$iface"

  tc qdisc del dev "$iface" root 2>/dev/null || true

  case "$mode" in
    fq_codel)
      modprobe sch_fq_codel 2>/dev/null || true
      tc qdisc add dev "$iface" root fq_codel
      ;;
    cake)
      modprobe sch_cake 2>/dev/null || true
      # Use a conservative CAKE setup. We do NOT set explicit bandwidth
      # because that can unintentionally cap throughput.
      tc qdisc add dev "$iface" root cake besteffort ack-filter
      ;;
    *)
      die "Unknown qdisc mode: $mode (expected: fq_codel|cake)"
      ;;
  esac

  info "Applied qdisc '$mode' on iface '$iface'."
}

qdisc_show() {
  need_cmd tc
  local iface="$1"
  tc qdisc show dev "$iface" || true
}
