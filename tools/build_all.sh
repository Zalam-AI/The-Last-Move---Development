#!/usr/bin/env bash
# Rebuild (or verify) THE LAST MOVE.
#
#   tools/build_all.sh            import, run every test suite, export both builds
#   tools/build_all.sh --check    import + tests only (fast, no export)
#
# Export templates are expected in
#   ~/.local/share/godot/export_templates/4.6.3.stable/
# If they are missing, fetch them once:
#   curl -LO https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz
#   unzip -j Godot_v4.6.3-stable_export_templates.tpz \
#         "templates/windows_release_x86_64.exe" "templates/windows_debug_x86_64.exe" \
#         "templates/linux_release.x86_64" "templates/version.txt" \
#         -d ~/.local/share/godot/export_templates/4.6.3.stable/
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

echo "== import =="
"$GODOT" --headless --path . --import >/dev/null
echo "== audio manifest =="
python3 tools/build_audio_manifest.py | tail -5

FAIL=0
run_suite() {
	local scene="$1" label="$2"
	"$GODOT" --headless --path . "$scene" > "/tmp/tml_$label.log" 2>&1 || FAIL=1
	grep -E "checks,|properties with issues|RESULT:" "/tmp/tml_$label.log" | sed "s/^/  [$label] /"
}
echo "== test suites =="
run_suite res://tests/test_runner.tscn core
run_suite res://tests/level_audit.tscn levels
run_suite res://tests/carry_test.tscn carry
run_suite res://tests/systems_test.tscn systems
run_suite res://tests/creature_test.tscn creatures
run_suite res://tests/campaign_test.tscn campaign

echo "== multiplayer (1 host + 2 clients) =="
bash tools/mp_test.sh 2 22 | tail -6 || FAIL=1

if [ $CHECK_ONLY -eq 0 ]; then
	echo "== export =="
	mkdir -p dist/windows dist/linux
	"$GODOT" --headless --path . --export-release "Windows Desktop" \
		dist/windows/TheLastMove.exe >/dev/null
	"$GODOT" --headless --path . --export-release "Linux (verification)" \
		dist/linux/TheLastMove.x86_64 >/dev/null
	rm -f dist/windows/*.zip dist/linux/*.zip
	(cd dist/windows && zip -q -9 TheLastMove-windows-x86_64.zip TheLastMove.exe && rm TheLastMove.exe)
	(cd dist/linux && zip -q -9 TheLastMove-linux-x86_64.zip TheLastMove.x86_64 && rm TheLastMove.x86_64)
	ls -la dist/windows dist/linux
	echo "== exported bundle boots =="
	mkdir -p /tmp/tml_dist && unzip -o -q dist/linux/TheLastMove-linux-x86_64.zip -d /tmp/tml_dist
	/tmp/tml_dist/TheLastMove.x86_64 --headless --quit-after 90 2>&1 |
		grep -E "\[DB\]|\[Audio\]|SCRIPT ERROR" | sed 's/^/  /'
fi

if [ $FAIL -eq 0 ]; then
	echo "BUILD OK"
else
	echo "BUILD FAILED"
	exit 1
fi
