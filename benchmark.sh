#!/bin/bash
# benchmark.sh - Run .ko compiler 3600 times with monitoring
# Usage: ./benchmark.sh

set -e

echo "=== .ko Language Compiler Benchmark ==="
echo "Running 3600 iterations..."
echo ""

TOTAL=3600
PROGRAMS=(
    "examples/simple.ko"
    "examples/medium.ko"
)

START_TIME=$(date +%s%N)

for ((i=1; i<=TOTAL; i++)); do
    PROG=${PROGRAMS[$((i % ${#PROGRAMS[@]}))]}
    zig build run -- "$PROG" > /dev/null 2>&1 || true
    
    if (( i % 100 == 0 )); then
        ELAPSED=$(( ($(date +%s%N) - START_TIME) / 1000000 ))
        echo "Progress: $i/$TOTAL iterations (${ELAPSED}ms elapsed)"
    fi
done

END_TIME=$(($(date +%s%N)))
TOTAL_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo ""
echo "=== Benchmark Complete ==="
echo "Total iterations: $TOTAL"
echo "Total time: ${TOTAL_MS} ms"
echo "Average per iteration: $(( TOTAL_MS / TOTAL )) ms"
echo ""
echo "Monitor with: htop -p \$(pgrep -f 'zig build run')"
