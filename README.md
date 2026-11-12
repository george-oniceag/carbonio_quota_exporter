# carbonio_quota_exporter

Exports Carbonio 26.9 mailbox quotas and usage for Prometheus's node exporter
textfile collector.

Run on the Carbonio server as root (or a user allowed to `su` to `zextras`),
with Python 3 and the Carbonio command-line tools installed:

```sh
sudo python3 carbonio_quota_exporter.py
```

The script writes `/opt/zextras/zmstat/prometheus/carbonio_quotas.prom` by
default. The directory must exist and be configured as a node exporter textfile
collector directory. Use `--output /path/to/file.prom` to select another file.
Schedule the command periodically, for example with cron, to refresh the metrics.

Each account has `carbonio_mailbox_quota_bytes` and
`carbonio_mailbox_used_bytes` gauges, labelled by `account`. A quota of zero
means unlimited. Usage is converted from the size reported by `zmmailbox`;
values without a unit are interpreted as MB, and KB/MB/GB/TB use powers of
1024. The reported usage may be rounded by `zmmailbox`.

The script exits nonzero if any command fails or its output cannot be parsed
(including a missing `zimbraMailQuota` attribute). In that case the existing
metrics file is left unchanged; monitor the scheduled job for failures.