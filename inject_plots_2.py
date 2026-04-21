import re

mapping = {
    # ARM Network Extra
    r"\\subsection{Small Message Performance}": "images/benchmarks/ARM/5_small_message.png",
    
    # x86 Disk IO extra
    r"\\subsection{Sequential Throughput}": "images/benchmarks/x86/1_seq_throughput.png",
    r"\\subsection{Block Size Scaling}": "images/benchmarks/x86/4_blocksize_scaling.png",
    r"\\subsection{fsync Performance}": "images/benchmarks/x86/5_fsync.png",
    r"\\subsection{Latency Analysis}": "images/benchmarks/x86/3_latency_comparison.png",
}

def generate_figure(path):
    return f"""
\\begin{{figure}}[H]
    \\centering
    \\includegraphics[width=0.8\\textwidth]{{{path}}}
    \\caption{{Benchmark Plot: {path.split('/')[-1].split('.')[0].replace('_',' ')}}}
\\end{{figure}}
"""

with open("Report/report.tex", "r") as f:
    content = f.read()

for title, paths in mapping.items():
    if isinstance(paths, str):
        paths = [paths]
    plots = "".join([generate_figure(p) for p in paths])
    
    # Simple replace
    # To avoid double replacing, check if the string is already wrapped with the image
    for path in paths:
        if path not in content:
            content = re.sub(title, lambda m: m.group(0) + generate_figure(path), content)

with open("Report/report.tex", "w") as f:
    f.write(content)

print("Second insertion completed.")
