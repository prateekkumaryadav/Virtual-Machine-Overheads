# Usage: bash diskio_benchmark.sh baremetal   OR   bash diskio_benchmark.sh vm
#
# Requires: brew install fio
# WARNING: creates and deletes a ~4GB test file in $TESTDIR

LABEL=${1:-"unknown"}
OUTDIR="./results_diskio_${LABEL}"
TESTDIR="$HOME/fio_test"
TESTFILE="$TESTDIR/fio_testfile"
FILESIZE="2g"          # 2GB — large enough to exceed RAM cache on 6GB VM
RUNTIME=60             # seconds per fio job
IODEPTH=32             # queue depth — standard for NVMe/virtio benchmarks
NUMJOBS=1              # keep at 1 for latency/sequential; we vary for IOPS

mkdir -p "$OUTDIR" "$TESTDIR"

# Confirm enough free space (need ~4GB: 2GB file + headroom)
FREE_GB=$(df -g "$TESTDIR" | awk 'NR==2{print $4}')
if [ "$FREE_GB" -lt 4 ]; then
    echo "ERROR: Need at least 4GB free in $TESTDIR, only ${FREE_GB}GB available."
    exit 1
fi

echo "===== Disk I/O Benchmarks — $LABEL ====="
echo "Test file : $TESTFILE ($FILESIZE)"
echo "Output dir: $OUTDIR"
echo "Runtime   : ${RUNTIME}s per job"
echo ""

# Helper: flush page cache between tests
# 'purge' forces macOS to reclaim cached pages — critical for cold-cache accuracy
flush_cache() {
    echo "  [cache flush] Running purge (may prompt for sudo)..."
    sudo purge
    sleep 3
}

# -------------------------------------------------------
# BENCHMARK 1: Sequential Write throughput
# libaio unavailable on macOS — use psync (synchronous pwrite)
# bs=1M: large block size maximises sequential throughput
# direct I/O bypasses page cache — measures raw storage path
# -------------------------------------------------------
echo "=== [1/7] Sequential write (1M blocks, direct I/O) ==="
flush_cache
fio \
  --name=seq_write \
  --filename="$TESTFILE" \
  --rw=write \
  --bs=1m \
  --size=$FILESIZE \
  --numjobs=$NUMJOBS \
  --iodepth=$IODEPTH \
  --ioengine=posixaio \
  --direct=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/seq_write.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 2: Sequential Read throughput
# Re-reads the file written above (cold cache after purge)
# -------------------------------------------------------
echo ""
echo "=== [2/7] Sequential read (1M blocks, direct I/O) ==="
flush_cache
fio \
  --name=seq_read \
  --filename="$TESTFILE" \
  --rw=read \
  --bs=1m \
  --size=$FILESIZE \
  --numjobs=$NUMJOBS \
  --iodepth=$IODEPTH \
  --ioengine=posixaio \
  --direct=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/seq_read.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 3: Random Write IOPS
# bs=4k: typical filesystem block size, worst case for SSDs
# random pattern stresses the virtio ring buffer and host
# APFS CoW path on every 4k write
# -------------------------------------------------------
echo ""
echo "=== [3/7] Random write IOPS (4K blocks, direct I/O) ==="
flush_cache
fio \
  --name=rand_write \
  --filename="$TESTFILE" \
  --rw=randwrite \
  --bs=4k \
  --size=$FILESIZE \
  --numjobs=$NUMJOBS \
  --iodepth=$IODEPTH \
  --ioengine=posixaio \
  --direct=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/rand_write.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 4: Random Read IOPS
# Cold cache read of random 4K blocks
# Exposes virtio round-trip latency per I/O request
# -------------------------------------------------------
echo ""
echo "=== [4/7] Random read IOPS (4K blocks, direct I/O) ==="
flush_cache
fio \
  --name=rand_read \
  --filename="$TESTFILE" \
  --rw=randread \
  --bs=4k \
  --size=$FILESIZE \
  --numjobs=$NUMJOBS \
  --iodepth=$IODEPTH \
  --ioengine=posixaio \
  --direct=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/rand_read.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 5: Mixed 70/30 read/write (random)
# Models real workload: databases, application servers
# iodepth=32 + mixed pattern stresses the virtio queue
# heavily — most representative of production overhead
# -------------------------------------------------------
echo ""
echo "=== [5/7] Mixed 70R/30W random (4K blocks, direct I/O) ==="
flush_cache
fio \
  --name=mixed_rw \
  --filename="$TESTFILE" \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --size=$FILESIZE \
  --numjobs=$NUMJOBS \
  --iodepth=$IODEPTH \
  --ioengine=posixaio \
  --direct=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/mixed_rw.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 6: fsync latency (synchronous writes)
# bs=4k, iodepth=1, fsync=1: forces a full flush to
# physical storage after every single write
# This is the most punishing test for the VM because:
#   each fsync must propagate: guest APFS → virtio →
#   host APFS → NVMe — two filesystem flush operations
# -------------------------------------------------------
echo ""
echo "=== [6/7] fsync latency (4K, iodepth=1, sync) ==="
flush_cache
fio \
  --name=fsync_lat \
  --filename="$TESTFILE" \
  --rw=write \
  --bs=4k \
  --size=$FILESIZE \
  --numjobs=1 \
  --iodepth=1 \
  --ioengine=sync \
  --fsync=1 \
  --direct=0 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=json \
  --output="$OUTDIR/fsync_lat.json"
echo "  Done."

# -------------------------------------------------------
# BENCHMARK 7: Sequential read/write at varying block sizes
# Tests 4K, 64K, 512K, 1M — builds a throughput-vs-blocksize
# curve, revealing where the virtio overhead becomes
# negligible relative to transfer size
# -------------------------------------------------------
echo ""
echo "=== [7/7] Block size scaling (seq read+write, 4K→1M) ==="
for BS in 4k 64k 512k 1m; do
    echo "  Block size: $BS"
    flush_cache
    fio \
      --name="bsscale_read_${BS}" \
      --filename="$TESTFILE" \
      --rw=read \
      --bs=$BS \
      --size=$FILESIZE \
      --numjobs=1 \
      --iodepth=$IODEPTH \
      --ioengine=posixaio \
      --direct=1 \
      --runtime=30 \
      --time_based \
      --group_reporting \
      --output-format=json \
      --output="$OUTDIR/bsscale_read_${BS}.json"

    flush_cache
    fio \
      --name="bsscale_write_${BS}" \
      --filename="$TESTFILE" \
      --rw=write \
      --bs=$BS \
      --size=$FILESIZE \
      --numjobs=1 \
      --iodepth=$IODEPTH \
      --ioengine=posixaio \
      --direct=1 \
      --runtime=30 \
      --time_based \
      --group_reporting \
      --output-format=json \
      --output="$OUTDIR/bsscale_write_${BS}.json"
done
echo "  Done."

# -------------------------------------------------------
# Cleanup test file (comment out if you want to re-run
# individual tests without recreating the file)
# -------------------------------------------------------
echo ""
echo "Cleaning up test file..."
rm -f "$TESTFILE"
rmdir "$TESTDIR" 2>/dev/null

echo ""
echo "===== All disk I/O benchmarks complete ====="
echo "Results saved in: $OUTDIR"
echo "Transfer this folder to your host for plotting."