#!/bin/sh

set -u

log_path="${TMPDIR:-/tmp}/godot-pal-tests-$$.log"
test_script="${GODOT_TEST_SCRIPT:-res://tests/run_tests.gd}"
trap 'rm -f "$log_path"' EXIT HUP INT TERM

godot --headless --path . --log-file "$log_path" -s "$test_script"
test_status=$?

if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$log_path"; then
	echo "Godot reported a script error; see output above." >&2
	exit 1
fi

exit "$test_status"
