#!/usr/bin/env bash
# Multi-process multiplayer test: one host + N clients, each in its own OS process.
# Usage: tools/mp_test.sh [clients=1] [seconds=26]
# Exit code 0 only when every process reports [MP] done ok=true.
set -u
CLIENTS="${1:-1}"
SECONDS_RUN="${2:-26}"
PORT=$((7800 + CLIENTS * 10 + RANDOM % 7))
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="$ROOT/tests/mp_logs"
rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"
GODOT="${GODOT:-godot}"

echo "== MP test: 1 host + $CLIENTS clients, port $PORT, ${SECONDS_RUN}s =="

"$GODOT" --headless --path "$ROOT" -- --mp-probe --mp-role=host --mp-mission=willow \
	--mp-seed=42 --mp-port="$PORT" --mp-seconds="$SECONDS_RUN" --mp-expected="$CLIENTS" \
	> "$LOGDIR/host.log" 2>&1 &
HOST_PID=$!
sleep 2

PIDS=()
for i in $(seq 1 "$CLIENTS"); do
	"$GODOT" --headless --path "$ROOT" -- --mp-probe --mp-role=client --mp-mission=willow \
		--mp-seed=42 --mp-port="$PORT" --mp-ip=127.0.0.1 --mp-seconds="$SECONDS_RUN" \
		--mp-expected="$CLIENTS" > "$LOGDIR/client$i.log" 2>&1 &
	PIDS+=($!)
	sleep 1.2
done

wait "$HOST_PID"; HOST_RC=$?
FAIL=0
for p in "${PIDS[@]}"; do
	wait "$p"
done

print_summary() {
	local f="$1" label="$2"
	local done_line
	done_line=$(grep -a "\[MP\] done" "$f" | tail -1)
	local last
	last=$(grep -a "^\[MP\] role=" "$f" | tail -1)
	echo "  $label: $last"
	echo "  $label: ${done_line:-NO DONE LINE}"
	case "$done_line" in
		*"ok=true"*) ;;
		*) FAIL=1 ;;
	esac
}

echo "-- results --"
print_summary "$LOGDIR/host.log" "host"
i=1
for p in "${PIDS[@]}"; do
	print_summary "$LOGDIR/client$i.log" "client$i"
	i=$((i + 1))
done

# the crew count must agree across processes
HOST_PEERS=$(grep -a "summary role=host" "$LOGDIR/host.log" | tail -1 | sed -n 's/.*peers=\([0-9]*\).*/\1/p')
for p in "${PIDS[@]}"; do
	:
done
i=1
for p in "${PIDS[@]}"; do
	CP=$(grep -a "summary role=client" "$LOGDIR/client$i.log" | tail -1 | sed -n 's/.*peers=\([0-9]*\).*/\1/p')
	if [ "n" != "x" ] && [ "${CP:-0}" != "${HOST_PEERS:-0}" ]; then
		echo "  MISMATCH: host peers=${HOST_PEERS:-?} client$i peers=${CP:-?}"
		FAIL=1
	fi
	i=$((i + 1))
done

if grep -aq "SCRIPT ERROR" "$LOGDIR"/*.log; then
	echo "  SCRIPT ERRORS present:"
	grep -ah "SCRIPT ERROR" "$LOGDIR"/*.log | sort -u | head -10
	FAIL=1
fi

if [ $FAIL -eq 0 ]; then
	echo "  RESULT: PASS ($((1 + CLIENTS)) processes agree)"
else
	echo "  RESULT: FAIL (logs in $LOGDIR)"
fi
exit $FAIL
