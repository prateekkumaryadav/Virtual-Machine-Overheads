#!/bin/bash
# save as: network_benchmark.sh
# Run entirely on BARE METAL HOST
# The VM runs only: iperf3 -s (server mode, listening)
#
# Usage: bash network_benchmark.sh <VM_IP> <HOST_LOOPBACK_IP>
# Example: bash network_benchmark.sh 192.168.64.6 127.0.0.1
#
# Requires iperf3 installed on both machines
# Start iperf3 server on VM first: iperf3 -s -D  (daemon mode)

VM_IP=${1:-"192.168.64.6"}
LO_IP="127.0.0.1"
OUTDIR="./results_network"
DURATION=30        # seconds per test
RUNS=5             # repetitions for statistical stability
PARALLEL_STREAMS=(1 2 4 8)   # for parallel stream scaling test

mkdir -p "$OUTDIR"

echo "===== Network Benchmarks ====="
echo "VM IP        : $VM_IP"
echo "Loopback IP  : $LO_IP"
echo "Duration     : ${DURATION}s per run"
echo "Runs         : $RUNS"
echo "Output       : $OUTDIR"
echo ""
echo "Pre-check: confirming iperf3 server on VM is reachable..."
iperf3 -c "$VM_IP" -t 2 --connect-timeout 3000 &>/dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: Cannot reach iperf3 server on VM at $VM_IP"
    echo "On VM, run: iperf3 -s -D"
    exit 1
fi
echo "  Server reachable. Starting benchmarks."
echo ""

# -------------------------------------------------------
# HELPER: run iperf3 and extract summary JSON
# -------------------------------------------------------
run_iperf() {
    local TARGET=$1
    local OUTFILE=$2
    local EXTRA_ARGS=${@:3}
    iperf3 -c "$TARGET" \
        --time $DURATION \
        --json \
        $EXTRA_ARGS \
        > "$OUTFILE" 2>/dev/null
}

# -------------------------------------------------------
# BENCHMARK 1: Loopback TCP throughput (bare metal baseline)
# Pure kernel networking — no NIC, no driver overhead
# Sets the theoretical ceiling for host-only throughput
# -------------------------------------------------------
echo "=== [1/8] Loopback TCP throughput (baseline) ==="
# Need a local iperf3 server for loopback
iperf3 -s -D --pidfile /tmp/iperf3_lo.pid -p 5202 &>/dev/null
sleep 1
for i in $(seq 1 $RUNS); do
    echo -n "  Run $i/$RUNS ... "
    run_iperf "$LO_IP" "$OUTDIR/loopback_tcp_${i}.json" -p 5202
    echo "done"
done
# Stop local server
kill $(cat /tmp/iperf3_lo.pid 2>/dev/null) 2>/dev/null
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 2: Host↔VM TCP throughput (single stream)
# Measures virtio-net + UTM NAT throughput ceiling
# Single stream = no parallelism, pure per-connection cost
# -------------------------------------------------------
echo ""
echo "=== [2/8] Host→VM TCP throughput (single stream) ==="
for i in $(seq 1 $RUNS); do
    echo -n "  Run $i/$RUNS ... "
    run_iperf "$VM_IP" "$OUTDIR/vm_tcp_send_${i}.json"
    echo "done"
done
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 3: VM→Host TCP throughput (reverse direction)
# --reverse: server sends, client receives
# Tests asymmetry in the NAT path (send vs receive overhead)
# -------------------------------------------------------
echo ""
echo "=== [3/8] VM→Host TCP throughput (reverse) ==="
for i in $(seq 1 $RUNS); do
    echo -n "  Run $i/$RUNS ... "
    run_iperf "$VM_IP" "$OUTDIR/vm_tcp_recv_${i}.json" --reverse
    echo "done"
done
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 4: Host↔VM UDP throughput + packet loss
# UDP removes TCP congestion control — shows raw
# forwarding capacity of the virtio-net + NAT path
# --bandwidth 0 = no rate limit (blast mode)
# Records: throughput, jitter, packet loss %
# -------------------------------------------------------
echo ""
echo "=== [4/8] Host→VM UDP throughput + packet loss ==="
for i in $(seq 1 $RUNS); do
    echo -n "  Run $i/$RUNS ... "
    run_iperf "$VM_IP" "$OUTDIR/vm_udp_send_${i}.json" \
        --udp --bandwidth 0
    echo "done"
done
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 5: Loopback UDP (baseline for UDP)
# -------------------------------------------------------
echo ""
echo "=== [5/8] Loopback UDP throughput (baseline) ==="
iperf3 -s -D --pidfile /tmp/iperf3_lo.pid -p 5202 &>/dev/null
sleep 1
for i in $(seq 1 $RUNS); do
    echo -n "  Run $i/$RUNS ... "
    run_iperf "$LO_IP" "$OUTDIR/loopback_udp_${i}.json" \
        -p 5202 --udp --bandwidth 0
    echo "done"
done
kill $(cat /tmp/iperf3_lo.pid 2>/dev/null) 2>/dev/null
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 6: Parallel stream scaling (TCP)
# Tests 1, 2, 4, 8 parallel TCP streams to VM
# Shows whether multiple connections can saturate
# the virtio-net queue and recover throughput
# -------------------------------------------------------
echo ""
echo "=== [6/8] Parallel TCP streams scaling (1/2/4/8) ==="
for N in "${PARALLEL_STREAMS[@]}"; do
    echo "  Streams: $N"
    for i in $(seq 1 3); do   # 3 runs per stream count
        run_iperf "$VM_IP" "$OUTDIR/vm_tcp_p${N}_${i}.json" \
            --parallel $N
    done
done
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 7: RTT latency — ping (ICMP)
# 200 pings at 10ms intervals to both loopback and VM
# Captures: min/avg/max/stddev RTT
# VM RTT - loopback RTT = pure virtio-net + NAT latency
# -------------------------------------------------------
echo ""
echo "=== [7/8] ICMP ping RTT — loopback vs VM ==="
echo "  Pinging loopback (200 packets)..."
ping -c 200 -i 0.01 -q "$LO_IP" > "$OUTDIR/ping_loopback.txt" 2>&1

echo "  Pinging VM (200 packets)..."
ping -c 200 -i 0.05 -q "$VM_IP" > "$OUTDIR/ping_vm.txt" 2>&1
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 8: TCP latency via iperf3 (--length 1)
# Tiny 1-byte messages — isolates per-message overhead
# of the virtio-net + NAT stack vs pure loopback
# -------------------------------------------------------
echo ""
echo "=== [8/8] TCP small-message latency (--length 1) ==="
# Loopback baseline
iperf3 -s -D --pidfile /tmp/iperf3_lo.pid -p 5202 &>/dev/null
sleep 1
for i in $(seq 1 $RUNS); do
    echo -n "  Loopback run $i/$RUNS ... "
    run_iperf "$LO_IP" "$OUTDIR/loopback_smallmsg_${i}.json" \
        -p 5202 --length 1 --time $DURATION
    echo "done"
done
kill $(cat /tmp/iperf3_lo.pid 2>/dev/null) 2>/dev/null

# VM
for i in $(seq 1 $RUNS); do
    echo -n "  VM run $i/$RUNS ... "
    run_iperf "$VM_IP" "$OUTDIR/vm_smallmsg_${i}.json" \
        --length 1 --time $DURATION
    echo "done"
done
echo "  Done."

echo ""
echo "===== All network benchmarks complete ====="
echo "Results saved in: $OUTDIR"