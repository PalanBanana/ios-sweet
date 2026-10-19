#!/bin/sh
# Fixture tests for tools/post-ci-analyze.sh, and for the Build-column awk that
# CI-FAILURE-PLAYBOOK.md uses. Fixtures are copied to a temp directory first,
# because the analyzer writes RUN.log.build-tail.txt next to its input.
#   tools/test-post-ci-analyze.sh
set -eu
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
analyzer="$here/post-ci-analyze.sh"
fx="$here/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$fx"/*.log "$fx"/gh-log-sample.txt "$tmp/"

total=0
passed=0

# verdict NAME FIXTURE WANT_VERDICT WANT_EXIT
verdict() {
	total=$((total + 1))
	rc=0
	sh "$analyzer" "$tmp/$2" > "$tmp/out" 2>&1 || rc=$?
	got=$(sed -n 's/^POST_CI_VERDICT: \([A-Z_]*\).*/\1/p' "$tmp/out" | head -n 1)
	if [ "$got" = "$3" ] && [ "$rc" -eq "$4" ]; then
		passed=$((passed + 1))
		echo "PASS  $1 -> $got (exit $rc)"
	else
		echo "FAIL  $1: got=$got exit=$rc want=$3/$4"
		sed 's/^/        /' "$tmp/out" | head -n 8
	fi
}

verdict "pass" pass.log PASS 0
verdict "fail (patch skipped)" fail.log FAIL 1
verdict "aborted (no summary line)" aborted.log BUILD_ABORTED_BEFORE_VERIFY 2
verdict "compile error (summary PASS)" compile-error.log COMPILE_ERROR 1
verdict "unknown (PASS with broken invariant)" unknown.log UNKNOWN 3

# Build-column filter: default field splitting, as in the playbook.
build_new() { awk '$1=="build" && $2=="Build"' "$1"; }
build_old() { awk -F'\t' '$2=="Build"' "$1"; }
expected=$(grep -cF "$(printf 'build\tBuild\t')" "$tmp/gh-log-sample.txt" || true)

total=$((total + 1))
new_tab=$(build_new "$tmp/gh-log-sample.txt" | wc -l | tr -d ' ')
tr '\t' ' ' < "$tmp/gh-log-sample.txt" > "$tmp/space.txt"
new_space=$(build_new "$tmp/space.txt" | wc -l | tr -d ' ')
old_tab=$(build_old "$tmp/gh-log-sample.txt" | wc -l | tr -d ' ')
old_space=$(build_old "$tmp/space.txt" | wc -l | tr -d ' ')
echo "awk Build column: expected=$expected new(tab)=$new_tab new(space)=$new_space old(tab)=$old_tab old(space)=$old_space"
if [ "$new_tab" -eq "$expected" ] && [ "$new_space" -eq "$expected" ] && [ "$expected" -gt 0 ]; then
	passed=$((passed + 1))
	echo "PASS  awk default-FS filter matches the Build step in tab and space layouts"
else
	echo "FAIL  awk default-FS filter: expected=$expected new(tab)=$new_tab new(space)=$new_space"
fi
if [ "$old_space" -eq 0 ]; then
	printf '%s\n' "NOTE  the old -F'\\t' filter returns nothing on a space layout (why the playbook changed)"
fi

# Last 100 of the matching lines (the playbook's tail).
total=$((total + 1))
i=1
while [ "$i" -le 150 ]; do
	printf 'build\tBuild\t2026-10-19T12:00:00.0000000Z line %03d\n' "$i"
	i=$((i + 1))
done > "$tmp/long.txt"
last=$(build_new "$tmp/long.txt" | tail -n 100)
first_of_tail=$(printf '%s\n' "$last" | head -n 1 | sed 's/.*line //')
if [ "$(printf '%s\n' "$last" | wc -l | tr -d ' ')" -eq 100 ] && [ "$first_of_tail" = "051" ]; then
	passed=$((passed + 1))
	echo "PASS  tail -n 100 of 150 Build lines starts at line 051"
else
	echo "FAIL  tail: count=$(printf '%s\n' "$last" | wc -l | tr -d ' ') first=$first_of_tail"
fi

echo "$passed/$total passed"
if [ "$passed" -eq "$total" ]; then
	exit 0
fi
exit 1
