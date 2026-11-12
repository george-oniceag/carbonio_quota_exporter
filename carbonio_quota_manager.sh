#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 0 ]]; then
    echo "Usage: $0" >&2
    exit 1
fi

if ! read -r -p "Username (account email): " account || [[ -z $account ]]; then
    echo "A username is required." >&2
    exit 1
fi

quoted_account=${account//\'/\'\\\'\'}
quoted_account="'$quoted_account'"
if ! quota_output=$(su - zextras -c "carbonio prov ga $quoted_account zimbraMailQuota"); then
    echo "Failed to read quota for $account." >&2
    exit 1
fi

quota=
while IFS= read -r line; do
    if [[ $line =~ ^zimbraMailQuota:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        quota=${BASH_REMATCH[1]}
        break
    fi
done <<< "$quota_output"
if [[ -z $quota ]]; then
    echo "zimbraMailQuota is missing or invalid for $account." >&2
    exit 1
fi

if [[ $quota =~ ^0+$ ]]; then
    echo "Current quota: unlimited ($quota bytes)"
else
    awk -v quota="$quota" 'BEGIN { printf "Current quota: %.6f GB (%s bytes)\n", quota / 1073741824, quota }'
fi

if ! read -r -p "New quota in GB (0 for unlimited): " new_quota; then
    echo "A new quota is required." >&2
    exit 1
fi
if [[ ! $new_quota =~ ^([0-9]+)(\.([0-9]{1,9}))?$ ]]; then
    echo "Enter a non-negative number of GB with at most 9 decimal places." >&2
    exit 1
fi
whole=${BASH_REMATCH[1]}
fraction=${BASH_REMATCH[3]:-}
whole=${whole#"${whole%%[!0]*}"}
whole=${whole:-0}
if [[ ${#whole} -gt 10 ]] || { [[ ${#whole} -eq 10 ]] && [[ $whole > 8589934591 ]]; }; then
    echo "Quota is too large." >&2
    exit 1
fi

bytes=$((whole * 1073741824))
if [[ -n $fraction ]]; then
    scale=$((10 ** ${#fraction}))
    bytes=$((bytes + (10#$fraction * 1073741824 + scale / 2) / scale))
fi
if ! su - zextras -c "carbonio prov ma $quoted_account zimbraMailQuota $bytes"; then
    echo "Failed to update quota for $account." >&2
    exit 1
fi
echo "Quota updated for $account: $bytes bytes."
