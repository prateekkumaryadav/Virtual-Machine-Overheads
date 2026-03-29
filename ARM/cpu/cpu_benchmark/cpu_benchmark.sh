#!/bin/bash
# save as: cpu_benchmark.sh
# Usage: bash cpu_benchmark.sh baremetal   OR   bash cpu_benchmark.sh vm

LABEL=${1:-"unknown"}
OUTDIR="./results_${LABEL}"
mkdir -p "$OUTDIR"

THREADS_SINGLE=1
# THREADS_MULTI=$(sysctl -n hw.logicalcpu)   # uses all available logical cores
THREADS_MULTI=5   # uses 5 logical cores
DURATION=30   # seconds per run
RUNS=5        # repetitions for statistical stability

echo "Starting CPU benchmarks — label: $LABEL"
echo "Logical cores: $THREADS_MULTI"
echo "Results → $OUTDIR"
echo ""

# -------------------------------------------------------
# BENCHMARK 1: sysbench prime number sieve (single-thread)
# Measures: raw integer throughput, scheduling latency
# -------------------------------------------------------
echo "=== sysbench: single-thread prime sieve ==="
for i in $(seq 1 $RUNS); do
  echo -n "  Run $i/$RUNS ... "
  sysbench cpu \
    --cpu-max-prime=20000 \
    --threads=$THREADS_SINGLE \
    --time=$DURATION \
    run 2>/dev/null | grep "events per second" | awk '{print $NF}' \
    >> "$OUTDIR/sysbench_single.txt"
  echo "done"
done

# -------------------------------------------------------
# BENCHMARK 2: sysbench prime number sieve (multi-thread)
# Measures: parallel throughput, hypervisor vCPU scheduling
# -------------------------------------------------------
echo ""
echo "=== sysbench: multi-thread prime sieve ($THREADS_MULTI threads) ==="
for i in $(seq 1 $RUNS); do
  echo -n "  Run $i/$RUNS ... "
  sysbench cpu \
    --cpu-max-prime=20000 \
    --threads=$THREADS_MULTI \
    --time=$DURATION \
    run 2>/dev/null | grep "events per second" | awk '{print $NF}' \
    >> "$OUTDIR/sysbench_multi.txt"
  echo "done"
done

# -------------------------------------------------------
# BENCHMARK 3: sysbench latency stats (single-thread)
# Captures: min/avg/max/95th-pct latency per event (ms)
# -------------------------------------------------------
echo ""
echo "=== sysbench: latency distribution (single-thread) ==="
sysbench cpu \
  --cpu-max-prime=20000 \
  --threads=$THREADS_SINGLE \
  --time=$DURATION \
  --histogram=on \
  run 2>/dev/null > "$OUTDIR/sysbench_latency_raw.txt"
echo "  Raw output saved."

# -------------------------------------------------------
# BENCHMARK 4: stress-ng — CPU method suite (timed)
# Tests multiple stressors: ackermann, bitops, double, euler,
# explog, fft, fibonacci, matrixprod, trig, etc.
# --metrics gives ops/sec per stressor → rich comparison data
# -------------------------------------------------------
echo ""
echo "=== stress-ng: multi-stressor suite ==="
stress-ng \
  --cpu $THREADS_MULTI \
  --cpu-method all \
  --metrics \
  --timeout ${DURATION}s \
  --log-file "$OUTDIR/stressng_raw.txt" \
  2>&1 | tee -a "$OUTDIR/stressng_raw.txt"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 5: wall/user/sys time breakdown
# Measures: how much CPU time goes to user vs kernel mode
# A higher sys% in VM suggests hypervisor call overhead
# -------------------------------------------------------
echo ""
echo "=== Timing breakdown: user vs sys time ==="
for i in $(seq 1 $RUNS); do
  echo -n "  Run $i/$RUNS ... "
  { time sysbench cpu \
    --cpu-max-prime=20000 \
    --threads=$THREADS_SINGLE \
    --time=10 \
    run 2>/dev/null ; } 2>> "$OUTDIR/time_breakdown.txt"
  echo "---" >> "$OUTDIR/time_breakdown.txt"
  echo "done"
done

# -------------------------------------------------------
# BENCHMARK 6: Context switch rate under load
# macOS-compatible: vm_stat + top -l (no vmstat/iostat -c)
# -------------------------------------------------------
echo ""
echo "=== Context switch rate under load ==="

# Start background load
sysbench cpu --cpu-max-prime=20000 --threads=$THREADS_MULTI --time=30 run &>/dev/null &
SBPID=$!

# vm_stat correct macOS syntax: vm_stat <interval> (prints until killed)
# capture 20 samples with 1s interval using a timed subshell
( vm_stat 1 > "$OUTDIR/vmstat_under_load.txt" ) &
VMSPID=$!

# top -l (logging mode) samples CPU us/sy/id — macOS equivalent of iostat cpu
# -l 20 = 20 snapshots, -s 1 = 1 second interval, -n 0 = no process rows
top -l 20 -s 1 -n 0 > "$OUTDIR/top_cpu_split.txt" &
TOPPID=$!

wait $SBPID

# kill samplers cleanly after load finishes
kill $VMSPID 2>/dev/null
kill $TOPPID 2>/dev/null
wait $VMSPID 2>/dev/null
wait $TOPPID 2>/dev/null

echo "  Done."

# -------------------------------------------------------
# BENCHMARK 7: Turbo/boost behaviour — clock scaling check
# Apple Silicon doesn't expose frequency via sysctl during load,
# but we can check dispatch times to infer throttling
# -------------------------------------------------------
echo ""
echo "=== Clock consistency check (repeated short bursts) ==="
for i in $(seq 1 20); do
  sysbench cpu \
    --cpu-max-prime=10000 \
    --threads=$THREADS_SINGLE \
    --time=3 \
    run 2>/dev/null | grep "events per second" | awk '{print $NF}' \
    >> "$OUTDIR/clock_stability.txt"
done
echo "  Done. 20 burst samples saved."

echo ""
echo "All benchmarks complete. Results in: $OUTDIR"