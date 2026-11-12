#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
testdir=$(mktemp -d)
trap 'rm -f -- "$testdir/su" "$testdir/carbonio" "$testdir/updated" "$testdir/output" "$testdir/error" "$testdir/injected"; rmdir -- "$testdir"' EXIT
export PATH="$testdir:$PATH"
export TESTDIR="$testdir"

cat > "$testdir/su" <<'EOF'
#!/usr/bin/env bash
[[ $# == 4 && $1 == - && $2 == zextras && $3 == -c ]] || exit 1
exec bash -c "$4"
EOF
cat > "$testdir/carbonio" <<'EOF'
#!/usr/bin/env bash
if [[ $# == 4 && $1 == prov && $2 == ga && $4 == zimbraMailQuota ]]; then
    [[ ${FAIL:-} != read ]] || exit 1
    [[ ${FAIL:-} != missing ]] || exit 0
    printf 'zimbraMailQuota: %s\n' "${CURRENT_QUOTA:-2147483648}"
elif [[ $# == 5 && $1 == prov && $2 == ma && $4 == zimbraMailQuota ]]; then
    [[ ${FAIL:-} != write ]] || exit 1
    printf '%s\n%s\n' "$3" "$5" > "$TESTDIR/updated"
else
    exit 1
fi
EOF
chmod +x "$testdir/su" "$testdir/carbonio"

account="odd'\"\$(touch $testdir/injected)@example.test"
printf '%s\n%s\n' "$account" 1.5 | "$root/carbonio_quota_manager.sh" > "$testdir/output"
grep -Fq 'Current quota: 2.000000 GB (2147483648 bytes)' "$testdir/output"
printf '%s\n%s\n' "$account" 1610612736 | cmp - "$testdir/updated"
[[ ! -e $testdir/injected ]]

printf '%s\n%s\n' alice@example.test 0 | CURRENT_QUOTA=0 "$root/carbonio_quota_manager.sh" > "$testdir/output"
grep -Fq 'Current quota: unlimited (0 bytes)' "$testdir/output"
printf '%s\n%s\n' alice@example.test 0 | cmp - "$testdir/updated"

printf '%s\n%s\n' alice@example.test 0.000000001 | "$root/carbonio_quota_manager.sh" > "$testdir/output"
printf '%s\n%s\n' alice@example.test 1 | cmp - "$testdir/updated"

printf '%s\n%s\n' alice@example.test 8589934591.999999999 | "$root/carbonio_quota_manager.sh" > "$testdir/output"
printf '%s\n%s\n' alice@example.test 9223372036854775807 | cmp - "$testdir/updated"

for value in -1 abc 1.1234567890 8589934592; do
    rm -f -- "$testdir/updated"
    if printf '%s\n%s\n' alice@example.test "$value" | "$root/carbonio_quota_manager.sh" > "$testdir/output" 2> "$testdir/error"; then
        echo "Expected failure for quota $value" >&2
        exit 1
    fi
    [[ -s $testdir/error && ! -e $testdir/updated ]]
done

for failure in read missing write; do
    rm -f -- "$testdir/updated"
    if printf '%s\n%s\n' alice@example.test 1 | FAIL=$failure "$root/carbonio_quota_manager.sh" > "$testdir/output" 2> "$testdir/error"; then
        echo "Expected failure for $failure" >&2
        exit 1
    fi
    [[ -s $testdir/error && ! -e $testdir/updated ]]
done

for input in '' 'alice@example.test'; do
    rm -f -- "$testdir/updated"
    if printf '%s\n' "$input" | "$root/carbonio_quota_manager.sh" > "$testdir/output" 2> "$testdir/error"; then
        echo "Expected failure for incomplete input" >&2
        exit 1
    fi
    [[ -s $testdir/error && ! -e $testdir/updated ]]
done

echo "Quota manager tests passed"
