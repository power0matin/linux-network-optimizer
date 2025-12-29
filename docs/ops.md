# Operational Notes

## When to use CAKE?

CAKE is most effective when your server is at the *bottleneck link* (edge), and you can set an accurate shaping bandwidth.
On datacenter servers with high capacity NICs and unknown upstream shaping, enabling CAKE without a bandwidth limit may still help with latency but can be unpredictable.

NetOpt's CAKE setup **does not set bandwidth** to avoid unintended caps.

## When to avoid changing congestion control?

Switching TCP congestion control (e.g., to BBR) can improve throughput on some paths, but may reduce fairness in some environments.
NetOpt reports current CC but does not change it.

If you want to experiment:
- Measure before/after consistently
- Rollback if you see worse behavior
