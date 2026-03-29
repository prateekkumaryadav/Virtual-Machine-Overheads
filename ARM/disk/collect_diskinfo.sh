#!/bin/bash
# save as: collect_diskinfo.sh
LABEL=${1:-"unknown"}
OUTDIR="./results_diskio_${LABEL}"
mkdir -p "$OUTDIR"

echo "===== DISK INFO — $LABEL =====" | tee "$OUTDIR/diskinfo.txt"
echo "Date: $(date)" | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Block devices ---" | tee -a "$OUTDIR/diskinfo.txt"
diskutil list | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Storage hardware ---" | tee -a "$OUTDIR/diskinfo.txt"
system_profiler SPStorageDataType | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- NVMe/virtio details ---" | tee -a "$OUTDIR/diskinfo.txt"
ioreg -l | grep -i "IOBlockStorageDevice\|virtio\|NVMe\|Vendor\|Model\|BSDName" \
  | grep -v "=#\|IOObject" | head -40 | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Filesystem mount info ---" | tee -a "$OUTDIR/diskinfo.txt"
mount | tee -a "$OUTDIR/diskinfo.txt"

echo "" | tee -a "$OUTDIR/diskinfo.txt"
echo "--- Available space on test volume ---" | tee -a "$OUTDIR/diskinfo.txt"
df -h ~ | tee -a "$OUTDIR/diskinfo.txt"

echo "Done. Saved to $OUTDIR/diskinfo.txt"