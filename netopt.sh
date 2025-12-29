#!/usr/bin/env bash
set -Eeuo pipefail

# Linux Network Optimizer - One-liner installer/launcher
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/netopt.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/netopt.sh) check
#   bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/netopt.sh) apply --profile balanced --qdisc fq_codel --iface eth0

REPO_URL_DEFAULT="https://github.com/power0matin/linux-network-optimizer.git"
REF_DEFAULT="main"
INSTALL_DIR_DEFAULT="/opt/linux-network-optimizer"

REPO_URL="${NETOPT_REPO_URL:-$REPO_URL_DEFAULT}"
REF="${NETOPT_REF:-$REF_DEFAULT}"
INSTALL_DIR="${NETOPT_INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }

pkg_install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y --no-install-recommends "$@" >/dev/null
}

pkg_install_yum() { yum install -y "$@" >/dev/null; }
pkg_install_dnf() { dnf install -y "$@" >/dev/null; }
pkg_install_pacman() { pacman -Sy --noconfirm "$@" >/dev/null; }

ensure_deps() {
  local missing=()
  for c in curl git; do
    need_cmd "$c" || missing+=("$c")
  done
  need_cmd ip || missing+=("iproute2")
  need_cmd update-ca-certificates || missing+=("ca-certificates")

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  log "Missing deps: ${missing[*]}"
  if need_cmd apt-get; then
    pkg_install_apt ca-certificates curl git iproute2
  elif need_cmd dnf; then
    pkg_install_dnf ca-certificates curl git iproute
  elif need_cmd yum; then
    pkg_install_yum ca-certificates curl git iproute
  elif need_cmd pacman; then
    pkg_install_pacman ca-certificates curl git iproute2
  else
    die "No supported package manager found. Install manually: curl git ca-certificates iproute2"
  fi
}

clone_or_update() {
  mkdir -p "$(dirname "$INSTALL_DIR")"

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating repo in: $INSTALL_DIR"
    git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL" >/dev/null 2>&1 || true
    git -C "$INSTALL_DIR" fetch --prune origin >/dev/null
    git -C "$INSTALL_DIR" reset --hard "origin/$REF" >/dev/null
  else
    if [[ -d "$INSTALL_DIR" ]]; then
      local backup="${INSTALL_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
      log "Existing dir found. Moving to: $backup"
      mv "$INSTALL_DIR" "$backup"
    fi
    log "Cloning repo to: $INSTALL_DIR"
    git clone --depth 1 --branch "$REF" "$REPO_URL" "$INSTALL_DIR" >/dev/null
  fi
}

fix_perms() {
  # Make scripts executable (git should carry +x, but keep it robust)
  find "$INSTALL_DIR/bin" -maxdepth 1 -type f -name "netopt*" -exec chmod +x {} \; 2>/dev/null || true
  find "$INSTALL_DIR/tests" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
}

usage() {
  cat >&2 <<EOF
netopt.sh - installer/launcher

Env:
  NETOPT_REPO_URL     (default: $REPO_URL_DEFAULT)
  NETOPT_REF          (default: $REF_DEFAULT)
  NETOPT_INSTALL_DIR  (default: $INSTALL_DIR_DEFAULT)

Examples:
  # interactive menu
  bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-network-optimizer/main/netopt.sh)

  # run CLI directly (same as: /opt/linux-network-optimizer/bin/netopt ...)
  bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-network-optimizer/main/netopt.sh) check
  bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-network-optimizer/main/netopt.sh) apply --profile balanced --qdisc fq_codel --iface eth0
EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if ! is_root; then
    # re-exec with sudo, preserving env vars (repo/ref/install_dir)
    exec sudo -E bash "$0" "$@"
  fi

  ensure_deps
  clone_or_update
  fix_perms

  if [[ ! -x "$INSTALL_DIR/bin/netopt" ]]; then
    die "netopt not found or not executable: $INSTALL_DIR/bin/netopt"
  fi

  # If no args => run menu. If args => passthrough to CLI.
  if (( $# == 0 )); then
    if [[ -x "$INSTALL_DIR/bin/netopt-menu" ]]; then
      exec "$INSTALL_DIR/bin/netopt-menu"
    else
      exec "$INSTALL_DIR/bin/netopt" --help
    fi
  else
    exec "$INSTALL_DIR/bin/netopt" "$@"
  fi
}

main "$@"
