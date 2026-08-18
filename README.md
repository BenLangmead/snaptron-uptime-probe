# snaptron-uptime-probe

An off-campus availability probe for <https://snaptron.cs.jhu.edu/>, running on
GitHub-hosted runners every five minutes.

## Why this exists

The Snaptron service has been reporting intermittent outages to a monitor
(uptime.bot) since June 2026. Two things about those reports are hard to
explain as ordinary failures:

- Eight multi-hour outages all lasted between **4h13m48s and 4h17m50s**, a
  four-minute spread over two months. Organic faults do not have a fixed
  duration.
- Thirty-three short outages, median 90 seconds, of which 82% begin between
  21:45 and 22:35 US/Eastern. That is a schedule, not load.

Meanwhile the server itself was demonstrably healthy throughout: during the
4h14m outage on 2026-08-17 its CPU was 97.5-99.6% idle, load average was 0.6 on
48 cores, and there were no interface errors, dropped packets, or socket
pressure.

The leading hypothesis is that something between the internet and the service
blocks the monitor's source address for a fixed period. That cannot be confirmed
with a single observer, because "unreachable from the internet" and "unreachable
from *that prober*" produce identical data.

This repository is a second, independent observer. It probes from Azure IP
space, and it records its own egress IP on every run, so a disagreement between
the two can be attributed to a specific address.

## Reading the results

`results/YYYY-MM-DD.tsv`, one record per line:

```
<utc-iso8601> <TAB> <kind> <TAB> key=value ...
```

| kind | meaning |
|---|---|
| `egress` | the runner's public IP for this run |
| `target` | the probe itself: HTTP code and timings |
| `control` | `www.jhu.edu`, only on failure, to prove the runner's own connectivity |
| `tcp` | port 443/80 reachability, only on failure |
| `dns` | what the hostname resolved to, only on failure |
| `capture` | names a `results/failure-*.txt` with verbose curl output |

**Timestamps are UTC.** The companion collectors on the JHU side log local
Eastern time; convert before comparing.

## Caveats

GitHub's scheduled workflows are best-effort and often run late, so the real
cadence is worse than every five minutes. This probe is reliable for the
multi-hour outages and will miss most of the 90-second ones. It complements,
rather than replaces, a proper uptime service checking at one-minute intervals.

A run that records a failed probe still exits successfully, so a red workflow
badge means the automation broke, not that the site was down.
