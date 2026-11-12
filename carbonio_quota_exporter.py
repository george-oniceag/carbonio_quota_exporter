#!/usr/bin/env python3

import argparse
from decimal import Decimal
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


DEFAULT_OUTPUT = "/opt/zextras/zmstat/prometheus/carbonio_quotas.prom"
SIZE_PATTERN = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([KMGT]?B)?\s*$", re.IGNORECASE)
QUOTA_PATTERN = re.compile(r"^zimbraMailQuota:\s*(\d+)\s*$", re.MULTILINE)


def run_as_zextras(command):
    result = subprocess.run(
        ["su", "-", "zextras", "-c", command],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def mailbox_used_bytes(output):
    match = SIZE_PATTERN.fullmatch(output)
    if not match:
        raise ValueError(f"unrecognized mailbox size: {output.strip()!r}")
    unit = (match.group(2) or "MB").upper()
    multiplier = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}[unit]
    return int(Decimal(match.group(1)) * multiplier)


def mailbox_quota_bytes(output):
    match = QUOTA_PATTERN.search(output)
    if not match:
        raise ValueError("zimbraMailQuota is missing or invalid")
    return int(match.group(1))


def escape_label(value):
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def collect_metrics():
    accounts = run_as_zextras("carbonio prov -l gaa").splitlines()
    lines = [
        "# HELP carbonio_mailbox_quota_bytes Configured mailbox quota in bytes (0 means unlimited).",
        "# TYPE carbonio_mailbox_quota_bytes gauge",
        "# HELP carbonio_mailbox_used_bytes Mailbox storage used in bytes.",
        "# TYPE carbonio_mailbox_used_bytes gauge",
    ]
    for account in accounts:
        account = account.strip()
        if not account:
            continue
        quoted_account = shlex.quote(account)
        used = mailbox_used_bytes(
            run_as_zextras(f"zmmailbox -z -m {quoted_account} gms")
        )
        quota = mailbox_quota_bytes(
            run_as_zextras(f"carbonio prov ga {quoted_account} zimbraMailQuota")
        )
        label = escape_label(account)
        lines.append(f'carbonio_mailbox_quota_bytes{{account="{label}"}} {quota}')
        lines.append(f'carbonio_mailbox_used_bytes{{account="{label}"}} {used}')
    return "\n".join(lines) + "\n"


def write_metrics(path, metrics):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(metrics)
            os.fchmod(output.fileno(), 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description="Export Carbonio mailbox quotas for Prometheus.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="output .prom file")
    args = parser.parse_args()
    try:
        write_metrics(args.output, collect_metrics())
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"carbonio quota export failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
