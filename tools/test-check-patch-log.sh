#!/bin/sh
# Cases for tools/check-patch-log.sh. Each log is built from the real patch
# directory, so the expected counts follow the repo: ours plus the four
# blacktop patches. Run from the repository root.
#   tools/test-check-patch-log.sh [PATCH_DIR]
set -eu
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
checker="$here/check-patch-log.sh"
pdir=${1:-xnu/patches}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

esc=$(printf '\033')
run="${esc}[35;01m ⇒ ${esc}[0m"
warn="${esc}[33;01m[warning] ${esc}[0m"
bt_applied="kas_info.patch machine_routines.patch skywalk_ventura.patch syntax_checker_ventura.patch"
bt_skipped="TrustCache.patch iobuffermemd_monterey.patch skywalk_sonoma.patch syntax_checker_sonoma.patch"

ls "$pdir" | grep '^[0-9][0-9][0-9][0-9]-.*\.patch$' | sort > "$tmp/ours"
ls "$pdir" | grep '\.sh$' | sort > "$tmp/scripts"
ours_n=$(wc -l < "$tmp/ours" | tr -d ' ')
scripts_n=$(wc -l < "$tmp/scripts" | tr -d ' ')
expected_n=$((ours_n + 4))

# A complete build log for the real patch directory.
mk_log() {
	out=$1
	: > "$out"
	while read -r s; do
		printf '%sRunning script: /x/dxb/patches/%s\n' "$run" "$s" >> "$out"
	done < "$tmp/scripts"
	while read -r p; do
		printf '%sApplying patch: /x/dxb/patches/%s\n' "$run" "$p" >> "$out"
	done < "$tmp/ours"
	for p in $bt_applied; do
		printf '%sApplying patch: /x/dxb/patches/%s\n' "$run" "$p" >> "$out"
	done
	for p in $bt_skipped; do
		printf '%sSkipping patch /x/dxb/patches/%s (already upstream, previously applied, or malformed): error: continuation\n' "$warn" "$p" >> "$out"
	done
}

total=0
passed=0

# check NAME WANT_RC NEEDLE LOG [PATCH_DIR] [FAILURE_LINES]
check() {
	total=$((total + 1))
	dir=${5:-$pdir}
	rc=0
	sh "$checker" "$4" "$dir" > "$tmp/out" 2>&1 || rc=$?
	ok=yes
	[ "$rc" -eq "$2" ] || ok=no
	grep -F -q -- "$3" "$tmp/out" || ok=no
	if [ -n "${6:-}" ]; then
		n=$(grep -c '^SWEET_PATCH_FAILURE' "$tmp/out" || true)
		[ "$n" -eq "$6" ] || ok=no
	fi
	if [ "$ok" = yes ]; then
		passed=$((passed + 1))
		echo "PASS  $1"
	else
		echo "FAIL  $1: exit=$rc want=$2, needle='$3'"
		sed 's/^/        /' "$tmp/out" | head -n 6
	fi
}

mk_log "$tmp/base.log"
pick_ours() { grep "^$1" "$tmp/ours"; }
drop_applied() {   # drop_applied NAME FROM TO: remove one applied line
	grep -v -F "Applying patch: /x/dxb/patches/$1" "$2" > "$3"
}

# 1. complete log passes
check "pass: complete log" 0 "result=PASS applied=$expected_n skipped=4 baseline_skipped=4 failed=0 ours=$ours_n ours_applied=$ours_n expected_applied=$expected_n stage_scripts=$scripts_n/$scripts_n" "$tmp/base.log"

# 2. same log with CRLF line endings still passes
sed 's/$/\r/' "$tmp/base.log" > "$tmp/crlf.log"
check "pass: CRLF log" 0 "result=PASS" "$tmp/crlf.log"

# 3. one of ours skipped instead of applied (names the patch)
p=$(pick_ours 0042-)
drop_applied "$p" "$tmp/base.log" "$tmp/c.log"
printf '%sSkipping patch /x/dxb/patches/%s (already upstream, previously applied, or malformed): error: does not apply\n' "$warn" "$p" >> "$tmp/c.log"
check "ours skipped: 0042" 1 "SWEET_PATCH_FAILURE: skipped $p" "$tmp/c.log"

# 4. unknown skip that is not on the baseline list
cp "$tmp/base.log" "$tmp/c.log"
printf '%sSkipping patch /x/dxb/patches/zzz-new.patch (malformed)\n' "$warn" >> "$tmp/c.log"
check "unknown skip: zzz-new.patch" 1 "SWEET_PATCH_FAILURE: skipped zzz-new.patch" "$tmp/c.log"

# 5. one of ours never attempted (neither applied nor skipped)
p=$(pick_ours 0070-)
drop_applied "$p" "$tmp/base.log" "$tmp/c.log"
check "ours never attempted: 0070" 1 "SWEET_PATCH_FAILURE: not attempted $p" "$tmp/c.log"

# 6. a patch name that is not in the repo applies
cp "$tmp/base.log" "$tmp/c.log"
printf '%sApplying patch: /x/dxb/patches/0882-fake.patch\n' "$run" >> "$tmp/c.log"
check "unexpected applied: 0882-fake.patch" 1 "SWEET_PATCH_FAILURE: unexpected applied 0882-fake.patch" "$tmp/c.log"

# 7. count short: one blacktop patch missing (applied=87, expected 88)
drop_applied "kas_info.patch" "$tmp/base.log" "$tmp/c.log"
check "count short: 87 of 88, kas_info missing" 1 "SWEET_PATCH_FAILURE: not attempted kas_info.patch" "$tmp/c.log"

# 8. stage script missing from the run (ran 2 of 3)
last=$(tail -n 1 "$tmp/scripts")
grep -v -F "Running script: /x/dxb/patches/$last" "$tmp/base.log" > "$tmp/c.log"
check "stage script missing (ran 2 of 3)" 1 "reason=\"stage scripts ran $((scripts_n - 1)) of $scripts_n\"" "$tmp/c.log"

# 9. build aborted at the first stage script: nothing after it ran
grep -F "Running script" "$tmp/base.log" | head -n 1 > "$tmp/c.log"
check "stage aborted at first script" 1 "reason=\"stage scripts ran 1 of $scripts_n\"" "$tmp/c.log"

# 10. all stage scripts ran, then the build stopped before any patch
grep -F "Running script" "$tmp/base.log" > "$tmp/c.log"
printf 'error: stage script failed\n' >> "$tmp/c.log"
check "patch loop never ran" 1 "SWEET_PATCH_FAILURE: patch loop did not run" "$tmp/c.log" "" 1

# 11. empty log
: > "$tmp/c.log"
check "empty log" 1 "stage scripts ran 0 of $scripts_n" "$tmp/c.log"

# 12. build log missing
check "build log missing" 1 "build log not found" "$tmp/nope.log" "" ""

# 13. patch directory missing
check "patch dir missing" 1 "patch dir not found" "$tmp/base.log" "$tmp/nope-dir"

# 14. patch directory with no NNNN-*.patch files
mkdir "$tmp/empty-dir"
check "no NNNN-*.patch files" 1 "no NNNN-*.patch files" "$tmp/base.log" "$tmp/empty-dir"

# 15. an extra stage script in the patch directory (3 of 4 ran)
mkdir "$tmp/pdir4"
while read -r p; do : > "$tmp/pdir4/$p"; done < "$tmp/ours"
while read -r s; do : > "$tmp/pdir4/$s"; done < "$tmp/scripts"
: > "$tmp/pdir4/0099-extra.sh"
check "extra stage script (3 of 4 ran)" 1 'reason="stage scripts ran 3 of 4"' "$tmp/base.log" "$tmp/pdir4"

# 16. more than 20 failures: 20 shown, then the overflow count
tail -n 60 "$tmp/ours" > "$tmp/drop"
cp "$tmp/base.log" "$tmp/c.log"
while read -r p; do
	drop_applied "$p" "$tmp/c.log" "$tmp/c2.log"
	mv "$tmp/c2.log" "$tmp/c.log"
done < "$tmp/drop"
check "cap: 60 missing, 20 shown + 40 more" 1 "SWEET_PATCH_FAILURE: +40 more" "$tmp/c.log" "" 21

# 17. the same patch applied twice (log concatenated from two builds)
p=$(head -n 1 "$tmp/ours")
cp "$tmp/base.log" "$tmp/c.log"
printf '%sApplying patch: /x/dxb/patches/%s\n' "$run" "$p" >> "$tmp/c.log"
check "duplicate apply line: $p" 1 "SWEET_PATCH_FAILURE: duplicate applied $p" "$tmp/c.log" "" 1

echo "$passed/$total passed"
if [ "$passed" -eq "$total" ]; then
	exit 0
fi
exit 1
