#!/bin/sh
# Check the blacktop/darwin-xnu-build log for patch application.
#   tools/check-patch-log.sh dxb/build.log xnu/patches
#
# build.sh's patches() only warns when `git apply --check` fails, so a green
# build can still lack patches. This fails unless:
#   - every NNNN-*.patch in xnu/patches shows as applied,
#   - every stage script (xnu/patches/*.sh) ran, and
#   - every skipped patch is in BASELINE_SKIPS: blacktop skips those four on a
#     pristine xnu-8796.141.3 tree too, so they are not caused by this repo.
# Prints one SWEET_PATCH_SUMMARY line. Exit status 1 on any failure.
# Keep BASELINE_SKIPS in step with the DXB_SHA pinned in .github/workflows/xnu.yml.
set -eu
LC_ALL=C
export LC_ALL

log=${1:?usage: check-patch-log.sh BUILD_LOG PATCH_DIR}
pdir=${2:?usage: check-patch-log.sh BUILD_LOG PATCH_DIR}

BASELINE_SKIPS="TrustCache.patch iobuffermemd_monterey.patch skywalk_sonoma.patch syntax_checker_sonoma.patch"

if [ ! -f "$log" ]; then
	echo "SWEET_PATCH_SUMMARY: result=FAIL build log not found: $log"
	exit 1
fi
if [ ! -d "$pdir" ]; then
	echo "SWEET_PATCH_SUMMARY: result=FAIL patch dir not found: $pdir"
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Our patches and stage scripts, by file name.
ls "$pdir" | grep '^[0-9][0-9][0-9][0-9]-.*\.patch$' | sort > "$tmp/ours"
ours=$(wc -l < "$tmp/ours" | tr -d ' ')
scripts=$(ls "$pdir" | grep -c '\.sh$' || true)

# build.sh prints these through running()/warning(), which add ANSI colour
# codes in front, so match the text and not the start of the line.
grep -o 'Applying patch: [^[:space:]]*' "$log" | sed 's|.*/||' | sort -u > "$tmp/applied" || true
grep 'Skipping patch ' "$log" | sed 's/.*Skipping patch //; s/[[:space:]].*//; s|.*/||' | sort -u > "$tmp/skipped" || true
printf '%s\n' $BASELINE_SKIPS | sort -u > "$tmp/baseline"

applied_total=$(grep -c 'Applying patch: ' "$log" || true)
skipped_total=$(grep -c 'Skipping patch ' "$log" || true)
ran=$(grep -c 'Running script: ' "$log" || true)

# Skipped but not on the baseline list: always a failure, ours or not.
comm -23 "$tmp/skipped" "$tmp/baseline" > "$tmp/unknown"
# Ours that were neither applied nor skipped (never attempted).
comm -23 "$tmp/ours" "$tmp/applied" > "$tmp/unapplied"
comm -23 "$tmp/unapplied" "$tmp/skipped" > "$tmp/unattempted"

baseline_hit=$(comm -12 "$tmp/skipped" "$tmp/baseline" | wc -l | tr -d ' ')
applied_ours=$(comm -12 "$tmp/ours" "$tmp/applied" | wc -l | tr -d ' ')
failed=$(( $(wc -l < "$tmp/unknown" | tr -d ' ') + $(wc -l < "$tmp/unattempted" | tr -d ' ') ))

result=PASS
reason=
if [ "$applied_total" -eq 0 ]; then
	result=FAIL; reason="no 'Applying patch' lines (log format changed?)"
elif [ "$ours" -eq 0 ]; then
	result=FAIL; reason="no NNNN-*.patch files in $pdir"
elif [ "$ran" -ne "$scripts" ]; then
	result=FAIL; reason="stage scripts ran $ran of $scripts"
elif [ "$failed" -ne 0 ]; then
	result=FAIL; reason="$failed patch(es) not applied as expected"
fi

echo "SWEET_PATCH_SUMMARY: result=$result applied=$applied_total skipped=$skipped_total baseline_skipped=$baseline_hit failed=$failed ours=$ours ours_applied=$applied_ours stage_scripts=$ran/$scripts${reason:+ reason=\"$reason\"}"
{ sed 's/^/SWEET_PATCH_FAILURE: skipped /' "$tmp/unknown"; sed 's/^/SWEET_PATCH_FAILURE: not attempted /' "$tmp/unattempted"; } | head -n 20

if [ "$result" = PASS ]; then
	exit 0
fi
exit 1
