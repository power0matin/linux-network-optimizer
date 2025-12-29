# NetOpt

NetOpt is a professional, **safe-by-default** Linux network optimization toolkit for servers that must sustain **many concurrent client connections** (e.g., VPN/proxy nodes, APIs, WebSockets, game backends).

It ships a single CLI (`netopt`) that:

- Runs **pre-checks** (kernel, qdisc, congestion control, queue sizes; plus optional NIC offload reporting)
- Applies conservative Linux network tunings via an `/etc/sysctl.d` drop-in
- Optionally configures a modern egress qdisc (**FQ-CoDel** by default; **CAKE** optional)
- Creates a **backup** before any change and supports a clean **rollback**
- Is **idempotent**: re-running it does not stack duplicate settings or rules

> Important: NetOpt is not a magic “speed booster”. If you see heavy TCP retransmissions and unstable throughput under parallel streams, the root cause is often **loss / reordering / congestion / queueing** somewhere on the path. NetOpt focuses on _server-side hygiene_ and _bufferbloat control_. If the upstream network is congested or lossy, total throughput may remain limited.

## When NetOpt helps

- High concurrency (hundreds to tens of thousands of sockets)
- Better latency and fairness under load (reduces “one client destroys everyone” behavior)
- More stable throughput when the server is busy

## When NetOpt will not help

- Bad routing/peering upstream
- ISP / datacenter congestion
- Faulty cabling, NIC issues, virtualization host bottlenecks
- DDoS / abusive clients (you still need firewall/rate-limit policies)

## Quick start

### 1) Inspect current state (no changes)

```bash
sudo ./bin/netopt check
```

### 2) Apply safe profile (recommended first step)

```bash
sudo ./bin/netopt apply --profile safe
```

### 3) Optionally enable CAKE (only if the server is an edge bottleneck)

```bash
sudo ./bin/netopt qdisc set --mode cake
```

### 4) Roll back to previous state

```bash
sudo ./bin/netopt rollback
```

## Profiles

NetOpt exposes profiles to keep changes understandable and reviewable:

- `safe` (default): conservative kernel tuning; minimal risk; avoids aggressive timeouts.
- `balanced`: additional tuning for busy servers; still within broadly safe defaults.
- `aggressive`: for advanced operators only (not recommended without measurement and rollback plan).

**Operational guidance**

- Start with `safe`.
- Measure.
- Only then consider moving to `balanced`.
- Use `aggressive` only when you fully understand the trade-offs and have a reproducible benchmark.

## What NetOpt changes

NetOpt may touch the following components (depending on which subcommands you use):

### 1) Sysctl drop-in

- Writes: `/etc/sysctl.d/99-netopt.conf`
- Applies via: `sysctl --system`

This approach is:

- **Auditable** (single, explicit file)
- **Reversible** (remove file + restore previous values)
- **Compatible** with distro defaults and other drop-ins (predictable order)

### 2) Qdisc (Traffic Control)

- Sets `fq_codel` by default on the selected interface, or `cake` if requested
- Records the previous qdisc state so rollback can restore it

> Note: CAKE is most effective when the server is the actual **bottleneck** (edge link) and you can control egress behavior meaningfully. If your server is not the bottleneck, CAKE may not improve throughput—and can sometimes reduce peak throughput in exchange for better latency/fairness.

### 3) Checks-only guidance

- Reports relevant NIC offload state (via `ethtool` when available)
- Provides hints; does **not** disable offloads by default (to avoid surprising production impact)

## Safety model: backup & rollback

Before any change, NetOpt creates a timestamped backup under:

- `/var/lib/netopt/backups/<timestamp>/`

Backups include:

- Prior qdisc configuration (`tc qdisc show ...`)
- Relevant sysctl keys and their current values (captured at apply-time)

Rollback will:

- Remove `/etc/sysctl.d/99-netopt.conf`
- Restore previous sysctl values
- Restore previous qdisc (or delete qdisc if none existed)

**Recommendation:** Treat `rollback` as part of your change procedure—run it once on a non-production environment to validate reversibility before production rollout.

## Supported systems

Primary targets:

- Ubuntu / Debian on modern kernels

May work on other Linux distributions, but they are not the primary test targets.

### Required tools

- `ip`, `tc` (iproute2)
- `sysctl`

Optional (for improved reporting):

- `ethtool`

## Suggested validation workflow

After applying `safe`, validate with a consistent test methodology.

### 1) Throughput tests (consistent target and window)

```bash
iperf3 -c <server_ip> -p <port> -t 30 -R
iperf3 -c <server_ip> -p <port> -t 30 -R -P 2
```

If you care about concurrency behavior, also test with higher parallelism (e.g., `-P 8`, `-P 16`) and observe stability.

### 2) Retransmits, drops, and queue stats

```bash
ss -s
netstat -s | egrep -i 'retran|segments retransmited|timeout|reset' | head -n 80
tc -s qdisc show dev <iface>
```

### 3) Interpret results (practical heuristics)

- **Retransmits rising sharply** under load:

  - Often indicates upstream loss/congestion, MTU/PMTUD issues, or path instability.

- **Latency spikes with stable throughput**:

  - Bufferbloat is likely; FQ-CoDel/CAKE can help.

- **Throughput drops but latency improves** after enabling CAKE:

  - That trade-off can be expected when shaping; confirm the server is truly the bottleneck.

## Troubleshooting notes

- If `tc` operations fail:

  - Ensure `iproute2` is installed and the kernel supports the selected qdisc.

- If results worsen after applying:

  - Roll back immediately:

    ```bash
    sudo ./bin/netopt rollback
    ```

  - Then re-run:

    ```bash
    sudo ./bin/netopt check
    ```

  - Compare before/after metrics (qdisc stats, retransmits, CPU, IRQ load).

## Design principles

- **Safe by default**: conservative tunings first; no surprise destructive actions
- **Idempotent**: repeated runs do not stack duplicate configuration
- **Reversible**: every apply has a corresponding rollback path
- **Operator-friendly**: visibility via checks and explicit on-disk artifacts

## License

MIT. See `LICENSE`.
