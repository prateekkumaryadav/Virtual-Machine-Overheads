# Usage: bash collect_sysinfo_cpu_ubuntu.sh baremetal   OR   vm

LABEL=${1:-"unknown"}
OUTDIR="./results_cpu_ubuntu_${LABEL}"
mkdir -p "$OUTDIR"

echo "===== CPU SYSTEM INFO — $LABEL =====" | tee "$OUTDIR/sysinfo.txt"
echo "Date: $(date)"                         | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- CPU Info ---" | tee -a "$OUTDIR/sysinfo.txt"
lscpu | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- Core count ---" | tee -a "$OUTDIR/sysinfo.txt"
echo "Physical cores : $(lscpu | grep 'Core(s) per socket' | awk '{print $NF}')" | tee -a "$OUTDIR/sysinfo.txt"
echo "Logical cores  : $(nproc)" | tee -a "$OUTDIR/sysinfo.txt"
echo "Sockets        : $(lscpu | grep 'Socket(s)' | awk '{print $NF}')" | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- CPU frequency ---" | tee -a "$OUTDIR/sysinfo.txt"
cat /proc/cpuinfo | grep "cpu MHz" | head -8 | tee -a "$OUTDIR/sysinfo.txt"
cpufreq-info -s 2>/dev/null | head -5 | tee -a "$OUTDIR/sysinfo.txt" || true

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- Cache sizes ---" | tee -a "$OUTDIR/sysinfo.txt"
lscpu | grep -i "cache" | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- RAM ---" | tee -a "$OUTDIR/sysinfo.txt"
free -h | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- Virtualization detection ---" | tee -a "$OUTDIR/sysinfo.txt"
systemd-detect-virt 2>/dev/null | tee -a "$OUTDIR/sysinfo.txt" || \
    grep -m1 "hypervisor" /proc/cpuinfo | tee -a "$OUTDIR/sysinfo.txt" || \
    echo "bare metal" | tee -a "$OUTDIR/sysinfo.txt"

echo "" | tee -a "$OUTDIR/sysinfo.txt"
echo "--- Governor and scaling ---" | tee -a "$OUTDIR/sysinfo.txt"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null \
    | tee -a "$OUTDIR/sysinfo.txt" || echo "governor info not available"

echo "Done. Saved to $OUTDIR/sysinfo.txt"