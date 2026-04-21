import re

mapping = {
    # ARM CPU
    r"\\subsection{Throughput Analysis}": "images/benchmarks/ARM/1_throughput_bar.png",
    r"\\subsection{Statistical Stability and Variance}": ["images/benchmarks/ARM/2_variance_boxplot.png", "images/benchmarks/ARM/3_clock_stability.png"],
    r"\\subsection{CPU Utilization and Scheduling Behavior}": "images/benchmarks/ARM/4_cpu_time_split.png",
    r"\\subsection{Key Observations}": "images/benchmarks/ARM/5_overhead_summary.png",

    # ARM Disk IO
    r"\\subsection{Sequential Throughput}": "images/benchmarks/ARM/1_seq_throughput.png",
    r"\\subsection{Random IOPS Performance}": "images/benchmarks/ARM/2_random_iops.png",
    r"\\subsection{Block Size Scaling}": "images/benchmarks/ARM/4_blocksize_scaling.png",
    r"\\subsection{fsync Performance}": "images/benchmarks/ARM/5_fsync.png",
    r"\\subsection{Mixed Workload Performance}": "images/benchmarks/ARM/6_mixed_workload.png",
    
    # ARM Network
    r"\\subsection{TCP Throughput}": "images/benchmarks/ARM/1_tcp_throughput.png",
    r"\\subsection{UDP Performance}": "images/benchmarks/ARM/2_udp_performance.png",
    r"\\subsection{Parallel Stream Scaling}": "images/benchmarks/ARM/3_parallel_scaling.png",
    r"\\subsection{Latency Analysis}": "images/benchmarks/ARM/4_rtt_latency.png",
    r"\\subsection{Small Message Performance}": "images/benchmarks/ARM/5_small_message.png",
    
    # x86 CPU
    r"\\subsection{Throughput Performance}": "images/benchmarks/x86/1_throughput_bar.png",
    r"\\subsection{Clock Stability and Variance}": ["images/benchmarks/x86/2_variance_boxplot.png", "images/benchmarks/x86/3_clock_stability.png"],
    r"\\subsection{CPU Utilization Analysis \\(vmstat \\& mpstat\\)}": "images/benchmarks/x86/4_cpu_time_split.png",
    r"\\subsection{Latency Characteristics}": "images/benchmarks/x86/5_latency_distribution.png",
    
    # x86 Disk IO
    r"\\subsection{Random I/O Performance}": "images/benchmarks/x86/2_random_iops.png",
    r"\\subsection{Device-Level Analysis \\(iostat\\)}": "images/benchmarks/x86/7_iostat_device.png",
    r"\\subsection{Mixed Workload \\(70\\% Read / 30\\% Write\\)}": "images/benchmarks/x86/6_mixed_workload.png",
}

def generate_figure(path):
    return f"""
\\begin{{figure}}[H]
    \\centering
    \\includegraphics[width=0.8\\textwidth]{{{path}}}
    \\caption{{Benchmark Plot: {path.split('/')[-1].replace('_',' ')}}}
\\end{{figure}}
"""

with open("Report/report.tex", "r") as f:
    content = f.read()

for title, paths in mapping.items():
    if isinstance(paths, str):
        paths = [paths]
    plots = "".join([generate_figure(p) for p in paths])
    # Replace subsection with subsection + plots
    content = re.sub(title, lambda m: m.group(0) + plots, content)

with open("Report/report.tex", "w") as f:
    f.write(content)

print("Insertion completed.")
