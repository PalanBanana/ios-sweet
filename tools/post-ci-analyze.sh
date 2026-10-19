#!/bin/sh
# Classify one CI run from its `gh run view --log` output.
#   tools/post-ci-analyze.sh RUN.log
#
# Prints one POST_CI_VERDICT line, then an ANALYSIS section. Exit status:
#   PASS=0  FAIL=1  COMPILE_ERROR=1  BUILD_ABORTED_BEFORE_VERIFY=2  UNKNOWN=3
# Precedence: no SWEET_PATCH_SUMMARY line -> aborted; summary FAIL -> FAIL, or
# aborted when the reason says the build never reached the patch loop; summary
# PASS -> COMPILE_ERROR when compiler or make errors are present, UNKNOWN when
# the summary's own invariants break, else PASS.
# Writes the Build step's last 100 lines to RUN.log.build-tail.txt. Artifacts
# are not in the log: check them with gh api (CI-FAILURE-PLAYBOOK.md section 2).
set -eu
LC_ALL=C
export LC_ALL

log=${1:?usage: post-ci-analyze.sh RUN.log}

if [ ! -r "$log" ]; then
	echo "POST_CI_VERDICT: UNKNOWN (exit 3)"
	echo "ANALYSIS:"
	echo "  reason: log not readable: $log"
	exit 3
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The verify step's summary; the last one if there are several.
grep 'SWEET_PATCH_SUMMARY:' "$log" > "$tmp/summaries" || true
n_summary=$(wc -l < "$tmp/summaries" | tr -d ' ')
tail -n 1 "$tmp/summaries" 2>/dev/null | sed 's/.*SWEET_PATCH_SUMMARY:/SWEET_PATCH_SUMMARY:/' > "$tmp/summary" || true
summary=$(cat "$tmp/summary")

grep 'SWEET_PATCH_FAILURE:' "$log" | sed 's/.*SWEET_PATCH_FAILURE:/SWEET_PATCH_FAILURE:/' > "$tmp/failures" || true
n_failures=$(wc -l < "$tmp/failures" | tr -d ' ')

# Compiler diagnostics carry a location (path:line:col). Baseline skips print
# "error:" lines too, but without a location, so they do not match here.
grep -oE '[^[:space:]]+:[0-9]+:[0-9]+: (fatal )?error: .*' "$log" | cut -c1-220 > "$tmp/diag" || true
n_diag=$(wc -l < "$tmp/diag" | tr -d ' ')
grep -E '\*\*\* .* Error [0-9]+' "$log" | sed 's/^.*\*\*\*/***/' | cut -c1-220 > "$tmp/make" || true
n_make=$(wc -l < "$tmp/make" | tr -d ' ')
grep '##\[error\]' "$log" | cut -c1-220 > "$tmp/steperr" || true
n_steperr=$(wc -l < "$tmp/steperr" | tr -d ' ')

# The Build step's tail, for the next session. Columns: job, step, timestamp, text.
awk '$1=="build" && $2=="Build"' "$log" | tail -n 100 > "$log.build-tail.txt" || true
n_tail=$(wc -l < "$log.build-tail.txt" | tr -d ' ')

field() {   # field NAME: value of NAME= in the summary, or empty
	echo "$summary" | tr ' ' '\n' | grep "^$1=" | head -n 1 | cut -d= -f2-
}
reason=$(echo "$summary" | sed -n 's/.*reason="\(.*\)"$/\1/p')

verdict=UNKNOWN
code=3
why=
if [ "$n_summary" -eq 0 ]; then
	verdict=BUILD_ABORTED_BEFORE_VERIFY; code=2
	why="no SWEET_PATCH_SUMMARY line: the verify step did not run"
else
	result=$(field result)
	if [ "$result" = FAIL ]; then
		case "$reason" in
		*"build log not found"*|*"build log not readable"*|*"no 'Applying patch' lines"*|*"stage scripts ran"*)
			verdict=BUILD_ABORTED_BEFORE_VERIFY; code=2
			why="build stopped before the patch loop: $reason" ;;
		*)
			verdict=FAIL; code=1
			why="patch check failed: $reason" ;;
		esac
	elif [ "$result" = PASS ]; then
		applied=$(field applied); expected=$(field expected_applied)
		failed=$(field failed); baseline=$(field baseline_skipped)
		ours=$(field ours); ours_applied=$(field ours_applied); stage=$(field stage_scripts)
		# Invariants of a clean run; a PASS that breaks one is not trusted.
		missing=
		for v in "$applied" "$expected" "$failed" "$baseline" "$ours" "$ours_applied" "$stage"; do
			[ -n "$v" ] || missing=yes
		done
		if [ -n "$missing" ] || [ "$failed" != 0 ] || [ "$baseline" != 4 ] || [ "$ours_applied" != "$ours" ] \
			|| [ "$applied" != "$expected" ] || [ "$n_failures" -ne 0 ] || [ "${stage%/*}" != "${stage#*/}" ]; then
			verdict=UNKNOWN; code=3
			why="summary says PASS but its invariants do not hold"
		elif [ "$n_diag" -ne 0 ] || [ "$n_make" -ne 0 ]; then
			verdict=COMPILE_ERROR; code=1
			why="patches applied, but the build reported compiler or make errors"
		elif [ "$n_steperr" -ne 0 ]; then
			verdict=UNKNOWN; code=3
			why="a step reported ##[error] without compiler diagnostics"
		else
			verdict=PASS; code=0
			why="patches applied as expected and the build reported no errors"
		fi
	else
		verdict=UNKNOWN; code=3
		why="summary has no result= field"
	fi
fi

echo "POST_CI_VERDICT: $verdict (exit $code)"
echo "ANALYSIS:"
echo "  summary: ${summary:-absent}"
echo "  failures: $n_failures SWEET_PATCH_FAILURE line(s)"
head -n 20 "$tmp/failures" | sed 's/^/    /'
echo "  compile_errors: $n_diag diagnostic(s), $n_make make error(s)"
head -n 20 "$tmp/diag" | sed 's/^/    /'
head -n 5 "$tmp/make" | sed 's/^/    /'
echo "  step_errors: $n_steperr line(s) with ##[error]"
head -n 5 "$tmp/steperr" | sed 's/^/    /'
echo "  build_tail: $log.build-tail.txt ($n_tail line(s))"
echo "  artifacts: not visible in the log; check xnu-build-log and xnu-kernel with gh api"
echo "  reason: $why"
exit "$code"
