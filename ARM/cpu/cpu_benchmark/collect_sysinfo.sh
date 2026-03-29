#!/bin/bash
# save as: collect_sysinfo.sh
# Run on BOTH bare metal host and VM

echo "===== SYSTEM INFO ====="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo ""

echo "--- OS ---"
sw_vers

echo ""
echo "--- CPU Architecture ---"
uname -m
sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model

echo ""
echo "--- Core Count ---"
echo "Physical cores: $(sysctl -n hw.physicalcpu)"
echo "Logical cores:  $(sysctl -n hw.logicalcpu)"

echo ""
echo "--- CPU Frequency ---"
sysctl -n hw.cpufrequency 2>/dev/null || \
  system_profiler SPHardwareDataType | grep -E "Processor|Speed|Cores"

echo ""
echo "--- Cache Sizes ---"
echo "L1D: $(sysctl -n hw.l1dcachesize 2>/dev/null || echo 'N/A')"
echo "L1I: $(sysctl -n hw.l1icachesize 2>/dev/null || echo 'N/A')"
echo "L2:  $(sysctl -n hw.l2cachesize  2>/dev/null || echo 'N/A')"
echo "L3:  $(sysctl -n hw.l3cachesize  2>/dev/null || echo 'N/A')"

echo ""
echo "--- Memory ---"
echo "Total RAM: $(sysctl -n hw.memsize | awk '{printf "%.1f GB\n", $1/1073741824}')"