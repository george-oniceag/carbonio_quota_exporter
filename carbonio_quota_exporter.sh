#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

output=/opt/zextras/zmstat/prometheus/carbonio_quotas.prom
if [[ ${1:-} == "--output" && $# -eq 2 ]]; then
    output=$2
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--output path]" >&2
    exit 1
fi

mailbox_used_bytes() {
    local size=${1##*$'\n'}
    if [[ ! $size =~ ^[0-9]+$ ]]; then
        echo "Unrecognized mailbox size: $1" >&2
        return 1
    fi
    printf '%s' "$size"
}

mailbox_quota_bytes() {
    local line
    while IFS= read -r line; do
        if [[ $line =~ ^zimbraMailQuota:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return
        fi
    done <<< "$1"
    echo "zimbraMailQuota is missing or invalid" >&2
    return 1
}

accounts=$(su - zextras -c "carbonio prov -l gaa")
directory=$(dirname -- "$output")
filename=$(basename -- "$output")
temporary=$(mktemp -- "$directory/.$filename.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT

{
    echo "# HELP carbonio_mailbox_quota_bytes Configured mailbox quota in bytes (0 means unlimited)."
    echo "# TYPE carbonio_mailbox_quota_bytes gauge"
    echo "# HELP carbonio_mailbox_used_bytes Mailbox storage used in bytes."
    echo "# TYPE carbonio_mailbox_used_bytes gauge"
    while IFS= read -r account; do
        [[ -n $account ]] || continue
        quoted_account=${account//\'/\'\\\'\'}
        quoted_account="'$quoted_account'"
        size=$(su - zextras -c "zmmailbox -z -m $quoted_account gms -v")
        used=$(mailbox_used_bytes "$size")
        quota_output=$(su - zextras -c "carbonio prov ga $quoted_account zimbraMailQuota")
        quota=$(mailbox_quota_bytes "$quota_output")
        label=${account//\\/\\\\}
        label=${label//\"/\\\"}
        printf 'carbonio_mailbox_quota_bytes{account="%s"} %s\n' "$label" "$quota"
        printf 'carbonio_mailbox_used_bytes{account="%s"} %s\n' "$label" "$used"
    done <<< "$accounts"
} > "$temporary"

chown zextras:zextras -- "$temporary"
chmod 644 -- "$temporary"
mv -fT -- "$temporary" "$output"
