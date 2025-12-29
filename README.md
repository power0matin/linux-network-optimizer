# NetOpt

A professional, **safe-by-default** Linux network optimization toolkit designed for servers that handle many concurrent client connections (e.g., VPN/proxy, APIs, WebSocket, game backends).

NetOpt ships a single CLI (`netopt`) that:

- Performs **pre-checks** (kernel, NIC offloads, qdisc, congestion control, queue sizes)
- Applies conservative kernel networking tunings via an `/etc/sysctl.d` drop-in
- Optionally configures a modern egress qdisc (**FQ-CoDel** by default; **CAKE** optional)
- Creates a **backup** before any change, and supports a clean **rollback**
- Is **idempotent**: re-running it won't stack duplicate rules/settings

> Important: NetOpt is not a magic “speed booster”. Your iperf results show heavy TCP retransmissions and unstable throughput with multiple parallel streams — that usually points to **loss/reordering/queueing** somewhere on the path. This tool focuses on _server-side hygiene_ and _bufferbloat control_. If the upstream network is congested or lossy, total throughput may remain limited.

## What NetOpt is good for

- Many concurrent connections (hundreds to tens of thousands)
- Better latency and fairness under load (less “one client destroys everyone”)
- Smoother throughput when the server is busy

## What NetOpt will NOT fix

- Bad upstream routing/peering
- ISP or datacenter congestion
- Faulty cabling / NIC / virtualization host issues
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

### 4) Rollback to previous state

```bash
sudo ./bin/netopt rollback
```

## Profiles

- `safe` (default): conservative kernel tuning; minimal risk; no “aggressive” timeouts.
- `balanced`: slightly more tuning for busy servers; still reasonable defaults.
- `aggressive`: only for advanced operators (not recommended without measurement).

## What gets changed

NetOpt touches:

1. **sysctl drop-in**

   - Writes `/etc/sysctl.d/99-netopt.conf`
   - Applies via `sysctl --system`

2. **qdisc (traffic control)**

   - Sets `fq_codel` (default) on a selected interface, or `cake` if requested
   - Records previous qdisc so rollback can restore

3. **optional checks-only guidance**
   - NIC offload hints (NetOpt reports; does not disable by default)

## Safety model (backup & rollback)

Before any change, NetOpt creates a timestamped backup under:

- `/var/lib/netopt/backups/<timestamp>/`

It stores:

- The previous qdisc config (`tc qdisc show ...`)
- The relevant sysctl keys and current values

Rollback will:

- Remove `/etc/sysctl.d/99-netopt.conf`
- Restore previous sysctl values
- Restore previous qdisc (or delete qdisc if none existed)

## Supported systems

- Ubuntu / Debian (modern kernels)
- Most other Linux distributions may work, but are not primary targets

Required tools:

- `ip`, `tc` (iproute2)
- `sysctl`
- `ethtool` (optional, for reporting NIC offloads)

## Suggested validation

After applying `safe`:

1. Run a consistent test (same target, same time window):
   ```bash
   iperf3 -c <server_ip> -p <port> -t 30 -R
   iperf3 -c <server_ip> -p <port> -t 30 -R -P 2
   ```
2. Monitor retransmits and drops:
   ```bash
   ss -s
   netstat -s | egrep -i 'retran|segments retransmited|timeout|reset' | head -n 80
   tc -s qdisc show dev <iface>
   ```

If throughput improves but latency under load is still bad, consider CAKE **only if** your server is the bottleneck link.

## License

MIT. See `LICENSE`.
