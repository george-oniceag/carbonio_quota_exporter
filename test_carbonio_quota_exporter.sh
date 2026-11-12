#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
export PATH="$testdir:$PATH"
export TESTDIR="$testdir"

cat > "$testdir/su" <<'EOF'
#!/usr/bin/env bash
[[ $# == 4 && $1 == - && $2 == zextras && $3 == -c ]] || exit 1
exec bash -c "$4"
EOF
cat > "$testdir/carbonio" <<'EOF'
#!/usr/bin/env bash
if [[ $* == "prov -l gaa" ]]; then
    [[ ${FAIL:-} != list ]] || exit 1
    [[ ${EMPTY:-} == 1 ]] || printf '%s\n' "alice@example.test" "odd'\"\$(touch $TESTDIR/injected)@example.test"
elif [[ $# == 4 && $1 == prov && $2 == ga && $4 == zimbraMailQuota ]]; then
    [[ ${FAIL:-} != quota ]] || exit 1
    if [[ ${FAIL:-} != missing ]]; then
        printf '# name %s\nzimbraMailQuota: %s\n' "$3" "$([[ $3 == alice* ]] && echo 10485760 || echo 0)"
    fi
else
    exit 1
fi
EOF
cat > "$testdir/zmmailbox" <<'EOF'
#!/usr/bin/env bash
[[ $# == 5 && $1 == -z && $2 == -m && $4 == gms && $5 == -v ]] || exit 1
[[ ${FAIL:-} != size ]] || { echo invalid; exit 0; }
printf 'usage scope notice\n%s\n' "$([[ $3 == alice* ]] && echo 1572864 || echo 512)"
EOF
cat > "$testdir/chown" <<'EOF'
#!/usr/bin/env bash
[[ $# == 3 && $1 == zextras:zextras && $2 == -- ]] || exit 1
printf '%s %s %s\n' "$1" "$2" "$3" >> "$TESTDIR/chown.log"
EOF
chmod +x "$testdir/su" "$testdir/carbonio" "$testdir/zmmailbox" "$testdir/chown"

output="$testdir/quotas.prom"
"$root/carbonio_quota_exporter.sh" --output "$output"
grep -Fqx 'carbonio_mailbox_quota_bytes{account="alice@example.test"} 10485760' "$output"
grep -Fqx 'carbonio_mailbox_used_bytes{account="alice@example.test"} 1572864' "$output"
grep -Fqx "carbonio_mailbox_used_bytes{account=\"odd'\\\"\$(touch $testdir/injected)@example.test\"} 512" "$output"
[[ ! -e $testdir/injected ]]
[[ $(stat -c '%a' "$output") == 644 ]]
[[ $(wc -l < "$testdir/chown.log") == 1 ]]
grep -Eq "^zextras:zextras -- $testdir/\\.quotas\\.prom\\.[^/]+$" "$testdir/chown.log"

cp "$output" "$testdir/expected"
for failure in list size quota missing; do
    if FAIL=$failure "$root/carbonio_quota_exporter.sh" --output "$output" 2>/dev/null; then
        echo "Expected failure for $failure" >&2
        exit 1
    fi
    cmp "$output" "$testdir/expected"
done
[[ $(find "$testdir" -name '.quotas.prom.*' | wc -l) == 0 ]]

EMPTY=1 "$root/carbonio_quota_exporter.sh" --output "$output"
grep -Fqx '# TYPE carbonio_mailbox_used_bytes gauge' "$output"
if grep -q '^carbonio_mailbox_' "$output"; then
    echo "Unexpected samples for an empty account list" >&2
    exit 1
fi
echo "Quota exporter tests passed"
