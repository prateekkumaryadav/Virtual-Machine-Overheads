# Usage: bash collect_diskinfo_ubuntu.sh baremetal   OR   vm

LABEL=${1:-"unknown"}
OUTDIR="./results_diskio_ubuntu_${LABEL}"
mkdir -p "$OUTDIR"

echo "===== DISK INFO — $LABEL =====" | tee "$OUTDIR/diskinfo.txt"
echo "Date: $(date)"                  | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Block devices ---" | tee -a "$OUTDIR/diskinfo.txt"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Disk model and firmware (bare metal only) ---" | tee -a "$OUTDIR/diskinfo.txt"
sudo hdparm -I /dev/sda 2>/dev/null | grep -E "Model|Serial|Firmware|capacity" \
    | tee -a "$OUTDIR/diskinfo.txt" || echo "hdparm not available" | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Filesystem mount info ---" | tee -a "$OUTDIR/diskinfo.txt"
mount | grep -E "ext4|xfs|btrfs|vfat" | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Scheduler and queue depth ---" | tee -a "$OUTDIR/diskinfo.txt"
for dev in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
    [ -d "$dev" ] || continue
    name=$(basename $dev)
    sched=$(cat $dev/queue/scheduler 2>/dev/null || echo "N/A")
    qdepth=$(cat $dev/queue/nr_requests 2>/dev/null || echo "N/A")
    rotational=$(cat $dev/queue/rotational 2>/dev/null || echo "N/A")
    echo "  $name: scheduler=$sched  queue_depth=$qdepth  rotational=$rotational" \
        | tee -a "$OUTDIR/diskinfo.txt"
done

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Available space on test volume ---" | tee -a "$OUTDIR/diskinfo.txt"
df -h ~ | tee -a "$OUTDIR/diskinfo.txt"

echo "Done. Saved to $OUTDIR/diskinfo.txt"