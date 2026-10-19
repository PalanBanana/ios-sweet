#!/bin/sh
# Check the blacktop/darwin-xnu-build log for patch application.
#   tools/check-patch-log.sh dxb/build.log xnu/patches
#
# build.sh's patches() only warns when `git apply --check` fails, so a green
# build can still lack patches. The log must show:
#   - every NNNN-*.patch in xnu/patches applied, exactly once;
#   - the four blacktop patches in BLACKTOP_APPLIED applied, exactly once;
#   - no other patch applied;
#   - every other skipped patch in BASELINE_SKIPS: blacktop skips those four on
#     a pristine xnu-8796.141.3 tree too, so they are not caused by this repo;
#   - every stage script (xnu/patches/*.sh) ran.
# Prints one SWEET_PATCH_SUMMARY line, then at most 20 SWEET_PATCH_FAILURE lines.
# Exit status 1 on any failure. Keep both lists in step with DXB_SHA in
# .github/workflows/xnu.yml.
set -eu
LC_ALL=C
export LC_ALL

log=${1:?usage: check-patch-log.sh BUILD_LOG PATCH_DIR}
pdir=${2:?usage: check-patch-log.sh BUILD_LOG PATCH_DIR}

BLACKTOP_APPLIED="kas_info.patch machine_routines.patch skywalk_ventura.patch syntax_checker_ventura.patch"
BASELINE_SKIPS="TrustCache.patch iobuffermemd_monterey.patch skywalk_sonoma.patch syntax_checker_sonoma.patch"

if [ ! -f "$log" ]; then
	echo "SWEET_PATCH_SUMMARY: result=FAIL build log not found: $log"
	exit 1
fi
if [ ! -r "$log" ]; then
	echo "SWEET_PATCH_SUMMARY: result=FAIL build log not readable: $log"
	exit 1
fi
if [ ! -d "$pdir" ]; then
	echo "SWEET_PATCH_SUMMARY: result=FAIL patch dir not found: $pdir"
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Our patches and stage scripts, by file name.
ls "$pdir" | grep '^[0-9][0-9][0-9][0-9]-.*\.patch$' | sort > "$tmp/ours" || true
ls "$pdir" | grep '\.sh$' | sort > "$tmp/scripts" || true
ours=$(wc -l < "$tmp/ours" | tr -d ' ')
scripts=$(wc -l < "$tmp/scripts" | tr -d ' ')

printf '%s\n' $BLACKTOP_APPLIED | sort -u > "$tmp/bt_expected"
sort -u "$tmp/ours" "$tmp/bt_expected" > "$tmp/expected"
expected_n=$(wc -l < "$tmp/expected" | tr -d ' ')
printf '%s\n' $BASELINE_SKIPS | sort -u > "$tmp/baseline"

# build.sh prints these through running() and warning(), which put ANSI colour
# codes in front, so match the text and not the start of the line.
grep -o 'Applying patch: [^[:space:]]*' "$log" | sed 's|.*/||' | sort > "$tmp/applied_all" || true
sort -u "$tmp/applied_all" > "$tmp/applied"
uniq -d "$tmp/applied_all" > "$tmp/dups" || true
grep 'Skipping patch ' "$log" | sed 's/.*Skipping patch //; s/[[:space:]].*//; s|.*/||' | sort -u > "$tmp/skipped" || true
applied_total=$(wc -l < "$tmp/applied_all" | tr -d ' ')
skipped_total=$(grep -c 'Skipping patch ' "$log" || true)
ran=$(grep -c 'Running script: ' "$log" || true)

# Skipped but not on the baseline list: always a failure, ours or not.
comm -23 "$tmp/skipped" "$tmp/baseline" > "$tmp/unknown"
baseline_hit=$(comm -12 "$tmp/skipped" "$tmp/baseline" | wc -l | tr -d ' ')
# Applied but not expected.
comm -23 "$tmp/applied" "$tmp/expected" > "$tmp/unexpected"
# Expected but neither applied nor skipped (never attempted).
comm -23 "$tmp/expected" "$tmp/applied" > "$tmp/missing_all"
comm -23 "$tmp/missing_all" "$tmp/skipped" > "$tmp/missing"
applied_ours=$(comm -12 "$tmp/ours" "$tmp/applied" | wc -l | tr -d ' ')

dups=$(wc -l < "$tmp/dups" | tr -d ' ')
n_unknown=$(wc -l < "$tmp/unknown" | tr -d ' ')
n_missing=$(wc -l < "$tmp/missing" | tr -d ' ')
n_unexpected=$(wc -l < "$tmp/unexpected" | tr -d ' ')
failed=$((n_unknown + n_missing + n_unexpected + dups))

result=PASS
reason=
if [ "$ours" -eq 0 ]; then
	result=FAIL; reason="no NNNN-*.patch files in $pdir"
elif [ "$ran" -ne "$scripts" ]; then
	result=FAIL; reason="stage scripts ran $ran of $scripts"
elif [ "$applied_total" -eq 0 ]; then
	result=FAIL; reason="no 'Applying patch' lines: build stopped before the patch loop, or log format changed"
elif [ "$failed" -ne 0 ]; then
	result=FAIL; reason="$failed patch check(s) failed"
fi

echo "SWEET_PATCH_SUMMARY: result=$result applied=$applied_total skipped=$skipped_total baseline_skipped=$baseline_hit failed=$failed ours=$ours ours_applied=$applied_ours expected_applied=$expected_n stage_scripts=$ran/$scripts${reason:+ reason=\"$reason\"}"

details="$tmp/details"
if [ "$result" = FAIL ] && [ "$applied_total" -eq 0 ]; then
	echo "SWEET_PATCH_FAILURE: patch loop did not run ($expected_n patches expected, 0 applied)" > "$details"
else
	{
		sed 's/^/SWEET_PATCH_FAILURE: skipped /' "$tmp/unknown"
		sed 's/^/SWEET_PATCH_FAILURE: not attempted /' "$tmp/missing"
		sed 's/^/SWEET_PATCH_FAILURE: unexpected applied /' "$tmp/unexpected"
		sed 's/^/SWEET_PATCH_FAILURE: duplicate applied /' "$tmp/dups"
	} > "$details"
fi
total_detail=$(wc -l < "$details" | tr -d ' ')
head -n 20 "$details"
if [ "$total_detail" -gt 20 ]; then
	echo "SWEET_PATCH_FAILURE: +$((total_detail - 20)) more"
fi

if [ "$result" = PASS ]; then
	exit 0
fi
exit 1
