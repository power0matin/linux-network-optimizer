# NetOpt

<!-- repo-badges:start -->
<p align="center">
  <a href="https://hits.sh/github.com/power0matin/linux-network-optimizer/"><img src="https://hits.sh/github.com/power0matin/linux-network-optimizer.svg?style=flat-square&amp;label=Views&amp;labelColor=18181B&amp;color=0EA5E9&amp;logo=github" alt="Repository Views"/></a>
  <a href="https://github.com/power0matin/linux-network-optimizer/stargazers"><img src="https://img.shields.io/github/stars/power0matin/linux-network-optimizer?style=flat-square&amp;label=Stars&amp;labelColor=18181B&amp;color=F59E0B&amp;logo=github&amp;logoColor=white" alt="GitHub Stars"/></a>
  <a href="https://github.com/power0matin/linux-network-optimizer/forks"><img src="https://img.shields.io/github/forks/power0matin/linux-network-optimizer?style=flat-square&amp;label=Forks&amp;labelColor=18181B&amp;color=6366F1&amp;logo=github&amp;logoColor=white" alt="GitHub Forks"/></a>
  <a href="https://github.com/power0matin/linux-network-optimizer/issues"><img src="https://img.shields.io/github/issues/power0matin/linux-network-optimizer?style=flat-square&amp;label=Issues&amp;labelColor=18181B&amp;color=22C55E&amp;logo=github&amp;logoColor=white" alt="GitHub Issues"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/power0matin/linux-network-optimizer?style=flat-square&amp;label=License&amp;labelColor=18181B&amp;color=EF4444&amp;logo=github&amp;logoColor=white" alt="GitHub License"/></a>
</p>
<!-- repo-badges:end -->

> A safe-by-default Linux network optimization toolkit for high-concurrency servers (VPN/Proxy, APIs, WebSockets, game backends).

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](#)

**Quick links:** [Installation](#installation) · [Quickstart](#quickstart) · [Usage](#usage) · [Safety--rollback](#safety--rollback) · [Development](#development) · [Contributing](#contributing) · [Security](#security) · [License](#license) · [Contact](#-contact)

## Overview

NetOpt helps you apply **conservative, auditable, and reversible** Linux networking improvements on servers that must handle **many concurrent TCP/UDP connections**.

It ships a single CLI (`netopt`) that:

- Runs **pre-checks** (kernel, qdisc, congestion control, queue sizes; optional NIC offload reporting)
- Applies safe kernel tunings via an `/etc/sysctl.d` drop-in
- Optionally configures a modern egress qdisc (**FQ-CoDel** by default; **CAKE** optional)
- Creates a **backup** before any change and supports a clean **rollback**
- Is **idempotent**: re-running does not stack duplicate configuration

> Important: NetOpt is not a magic “speed booster”.
> If you see heavy TCP retransmissions and unstable throughput under parallel streams, the root cause is often **loss / reordering / congestion / queueing** somewhere on the path.
> NetOpt focuses on _server-side hygiene_ and _bufferbloat control_. If upstream is congested or lossy, total throughput may remain limited.

### Non-goals (what NetOpt will NOT fix)

- Bad upstream routing/peering
- ISP / datacenter congestion
- Faulty cabling, NIC problems, virtualization host bottlenecks
- DDoS / abusive clients (you still need firewall/rate-limit policies)

## Features

**Core**

- Safe sysctl tuning via a single drop-in file (`/etc/sysctl.d/99-netopt.conf`)
- Pre-checks for common misconfigurations
- Backup + rollback for every apply
- Idempotent changes (re-run safe)

**Advanced**

- Egress qdisc: `fq_codel` (default) or `cake` (optional)
- Optional reporting of NIC offloads (`ethtool`) and queueing hints

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Security notes (curl|bash)](#security-notes-curlbash)
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [Usage](#usage)
- [Safety & rollback](#safety--rollback)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Development](#development)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [Changelog](#changelog)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)
- [📬 Contact](#-contact)

## Requirements

### Supported systems

Primary targets:

- Ubuntu / Debian on modern kernels

May work on other Linux distributions, but they are not primary test targets.

### Required tools

- `bash`
- `ip`, `tc` (iproute2)
- `sysctl`

Optional (for improved reporting):

- `ethtool`

## Installation

### Option A) One-liner (quickest)

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-network-optimizer/main/netopt.sh)
```

### Option B) Clone & run (recommended for production)

```bash
git clone https://github.com/power0matin/linux-network-optimizer.git
cd linux-network-optimizer
sudo bash ./netopt.sh
```

> If your repo layout includes `./bin/netopt`, you can use the CLI directly after installation (see below).

## Security notes (curl|bash)

Running a remote script as root is fast but reduces auditability.

Recommended production workflow:

1. Download:

   ```bash
   curl -fsSL -o netopt.sh \
     https://raw.githubusercontent.com/power0matin/linux-network-optimizer/main/netopt.sh
   ```

2. Inspect:

   ```bash
   less netopt.sh
   ```

3. (Optional) Pin to a specific commit for reproducibility:

   ```bash
   curl -fsSL -o netopt.sh \
     https://raw.githubusercontent.com/power0matin/linux-network-optimizer/<COMMIT_SHA>/netopt.sh
   ```

4. Execute:

   ```bash
   sudo bash netopt.sh
   ```

## Quickstart

### 1) Inspect current state (no changes)

```bash
sudo ./bin/netopt check
```

Expected outcome:

- A readable report of kernel/networking state and recommendations
- No system changes

### 2) Apply safe profile (recommended first step)

```bash
sudo ./bin/netopt apply --profile safe
```

Expected outcome:

- `/etc/sysctl.d/99-netopt.conf` written
- `sysctl --system` applied
- Backup created under `/var/lib/netopt/backups/<timestamp>/`

### 3) Optionally set CAKE (only if server is the edge bottleneck)

```bash
sudo ./bin/netopt qdisc set --mode cake
```

Expected outcome:

- qdisc configured on the selected egress interface
- previous qdisc state captured for rollback

### 4) Roll back to previous state

```bash
sudo ./bin/netopt rollback
```

Expected outcome:

- sysctl drop-in removed (if created by NetOpt)
- prior sysctl values restored
- prior qdisc restored (or removed if none existed)

## Configuration

NetOpt uses explicit on-disk artifacts to remain auditable and reversible.

### Files and paths

- Sysctl drop-in:

  - `/etc/sysctl.d/99-netopt.conf`

- Backups:

  - `/var/lib/netopt/backups/<timestamp>/`

> Notes:
>
> - Exact keys and values are defined by the selected profile.
> - Backups capture the previous values at apply-time.

### Interface selection (qdisc)

If your server has multiple interfaces, choose the correct egress interface:

```bash
ip route get 1.1.1.1
ip -br link
```

Then apply qdisc on a specific interface (example `eth0`):

```bash
sudo ./bin/netopt qdisc set --iface eth0 --mode fq_codel
# or (alias)
sudo ./bin/netopt qdisc set --iface eth0 --mode fq_codel

# or
sudo ./bin/netopt qdisc set --iface eth0 --mode cake
# or (alias)
sudo ./bin/netopt qdisc set --iface eth0 --mode cake
```

## Usage

### Common workflows

**Baseline assessment (no changes)**

```bash
sudo ./bin/netopt check
```

**Apply conservative tuning**

```bash
sudo ./bin/netopt apply --profile safe
```

**If you are the bottleneck and want better latency under load**

```bash
sudo ./bin/netopt qdisc set --dev eth0 --mode fq_codel
```

**Try CAKE only when the server is truly the edge bottleneck**

```bash
sudo ./bin/netopt qdisc set --dev eth0 --mode cake
```

**Undo changes**

```bash
sudo ./bin/netopt rollback
```

## Safety & rollback

NetOpt follows a “change with escape hatch” model.

Before any change, it creates a timestamped backup under:

- `/var/lib/netopt/backups/<timestamp>/`

Backups include:

- Prior qdisc configuration (`tc qdisc show ...`)
- Relevant sysctl keys and their values (captured at apply-time)

Rollback will:

- Remove `/etc/sysctl.d/99-netopt.conf`
- Restore prior sysctl values
- Restore prior qdisc (or delete qdisc if none existed)

Recommendation:

- Always validate rollback on a staging server before production rollout.

## Suggested validation

After applying `safe`, validate with a consistent test methodology.

### 1) Throughput tests (consistent target and window)

```bash
iperf3 -c <server_ip> -p <port> -t 30 -R
iperf3 -c <server_ip> -p <port> -t 30 -R -P 2
```

### 2) Retransmits, drops, and queue stats

```bash
ss -s
netstat -s | egrep -i 'retran|segments retransmited|timeout|reset' | head -n 80
tc -s qdisc show dev <iface>
```

### 3) Practical interpretation

- Retransmits rising sharply under load:

  - Often indicates upstream loss/congestion, MTU/PMTUD issues, or path instability.

- Latency spikes with stable throughput:

  - Bufferbloat is likely; FQ-CoDel/CAKE can help.

- Throughput drops but latency improves after enabling CAKE:

  - Expected trade-off when shaping; confirm the server is the bottleneck.

## Troubleshooting

- `tc` operations fail:

  - Ensure `iproute2` is installed and kernel supports selected qdisc.

- Results worsen after applying:

  - Roll back immediately:

    ```bash
    sudo ./bin/netopt rollback
    ```

  - Re-check:

    ```bash
    sudo ./bin/netopt check
    ```

## Architecture

### Project structure (typical)

```text
linux-network-optimizer/
  netopt.sh
  bin/
    netopt
  README.md
  LICENSE
```

### High-level flow

```mermaid
flowchart LR
  A[Operator] --> B[netopt check/apply/qdisc/rollback]
  B --> C[/etc/sysctl.d/99-netopt.conf]
  B --> D[/var/lib/netopt/backups/]
  B --> E[tc qdisc]
```

## Development

### Local setup

```bash
git clone https://github.com/power0matin/linux-network-optimizer.git
cd linux-network-optimizer
```

### Conventions

- Keep changes reversible (every apply must have rollback logic)
- Prefer conservative defaults; document any trade-offs
- Use clear CLI output: what changed, where, and how to rollback

### Suggested commit convention

Conventional Commits:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `refactor: ...`

## Testing

At minimum, validate on:

- fresh VM (Ubuntu/Debian)
- typical VPS environment
- (optional) container or CI smoke test

Recommended checks:

- `./bin/netopt check` produces output and exits 0
- `apply --profile safe` creates sysctl file + backup
- `rollback` returns the system to baseline
- `qdisc set` applies expected qdisc and can rollback

## Roadmap

- [ ] Add CI smoke tests (lint/shellcheck + dry-run)
- [ ] Add `--dry-run` mode for apply/qdisc
- [ ] Expand documentation for profile keys and rationale
- [ ] Add `docs/` with deeper networking notes

## Changelog

See GitHub Releases (or add a `CHANGELOG.md` if you want SemVer tracking).

## Contributing

Contributions are welcome.

Suggested workflow:

1. Fork the repo
2. Create a feature branch: `git checkout -b feat/your-change`
3. Make changes with clear commits
4. Open a PR with:

   - What changed
   - Why it changed
   - How to test
   - Rollback impact (if any)

If you add or modify tunings, please include:

- Before/after measurements (iperf3 + retransmits + qdisc stats)
- Rationale and risk notes

## Security

If you discover a security issue:

- Please avoid opening a public issue immediately.
- Prefer responsible disclosure via email (see Contact below).

General warning:

- Avoid running unreviewed remote scripts as `root` in production.
- Prefer pinning to a commit hash and auditing changes.

## License

MIT. See [LICENSE](LICENSE).

## 📬 Contact

**Matin Shahabadi (متین شاه‌آبادی / متین شاه آبادی)**

- Website: [matinshahabadi.ir](https://matinshahabadi.ir)
- Email: [me@matinshahabadi.ir](mailto:me@matinshahabadi.ir)
- GitHub: [power0matin](https://github.com/power0matin)
- LinkedIn: [matin-shahabadi](https://www.linkedin.com/in/matin-shahabadi)
