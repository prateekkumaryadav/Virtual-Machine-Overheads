#!/usr/bin/env python3
# save as: plot_cpu_results.py
# Usage: python3 plot_cpu_results.py

import os, re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from scipy import stats

plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 11,
    'axes.spines.top': False,
    'axes.spines.right': False,
    'figure.facecolor': 'white',
    'axes.facecolor': '#fafafa',
})

BM_COLOR   = '#1a7a4a'   # teal-green for bare metal
VM_COLOR   = '#6b3fa0'   # purple for VM
OUTDIR     = './plots'
os.makedirs(OUTDIR, exist_ok=True)

# ── helpers ──────────────────────────────────────────────

def load_floats(path):
    with open(path) as f:
        return [float(l.strip()) for l in f if l.strip()]

def ci95(data):
    n = len(data)
    se = stats.sem(data)
    return se * stats.t.ppf(0.975, df=n-1)

def overhead_pct(bm_mean, vm_mean):
    return (bm_mean - vm_mean) / bm_mean * 100

# ── 1. Bar chart: throughput single vs multi-thread ──────

def plot_throughput():
    groups = {
        'Single-thread\n(events/sec)': ('results_baremetal/sysbench_single.txt',
                                         'results_vm/sysbench_single.txt'),
        'Multi-thread\n(events/sec)':  ('results_baremetal/sysbench_multi.txt',
                                         'results_vm/sysbench_multi.txt'),
    }

    fig, ax = plt.subplots(figsize=(8, 5))
    x = np.arange(len(groups))
    w = 0.32

    for i, (label, (bm_path, vm_path)) in enumerate(groups.items()):
        bm = load_floats(bm_path)
        vm = load_floats(vm_path)
        bm_m, vm_m = np.mean(bm), np.mean(vm)
        bm_e, vm_e = ci95(bm), ci95(vm)

        ax.bar(i - w/2, bm_m, w, color=BM_COLOR, yerr=bm_e,
               capsize=5, label='Bare metal' if i == 0 else '')
        ax.bar(i + w/2, vm_m, w, color=VM_COLOR, yerr=vm_e,
               capsize=5, label='VM (UTM)' if i == 0 else '')

        oh = overhead_pct(bm_m, vm_m)
        ax.text(i, max(bm_m, vm_m) * 1.04,
                f'Overhead\n{oh:+.1f}%', ha='center', fontsize=9,
                color='#333')

    ax.set_xticks(x)
    ax.set_xticklabels(groups.keys())
    ax.set_ylabel('Events per second (higher = better)')
    ax.set_title('sysbench CPU Throughput: Bare Metal vs VM', fontsize=13, pad=12)
    ax.legend()
    ax.grid(axis='y', linestyle='--', alpha=0.5)
    fig.tight_layout()
    fig.savefig(f'{OUTDIR}/1_throughput_bar.png', dpi=180)
    plt.close()
    print('Saved: 1_throughput_bar.png')

# ── 2. Box plot: run-to-run variance ─────────────────────

def plot_variance():
    fig, axes = plt.subplots(1, 2, figsize=(10, 5))
    titles = ['Single-thread', 'Multi-thread']
    files  = [('results_baremetal/sysbench_single.txt', 'results_vm/sysbench_single.txt'),
              ('results_baremetal/sysbench_multi.txt',  'results_vm/sysbench_multi.txt')]

    for ax, title, (bm_path, vm_path) in zip(axes, titles, files):
        bm = load_floats(bm_path)
        vm = load_floats(vm_path)
        bp = ax.boxplot([bm, vm],
                        patch_artist=True,
                        medianprops=dict(color='white', linewidth=2),
                        whiskerprops=dict(linewidth=1.2),
                        capprops=dict(linewidth=1.2))
        bp['boxes'][0].set_facecolor(BM_COLOR)
        bp['boxes'][1].set_facecolor(VM_COLOR)
        ax.set_xticklabels(['Bare metal', 'VM'])
        ax.set_ylabel('Events/sec')
        ax.set_title(f'{title} — variance', fontsize=11)
        ax.grid(axis='y', linestyle='--', alpha=0.5)

        # CV annotation
        for j, data in enumerate([bm, vm], 1):
            cv = np.std(data) / np.mean(data) * 100
            ax.text(j, np.min(data) * 0.995, f'CV={cv:.1f}%',
                    ha='center', fontsize=8, color='#555')

    fig.suptitle('Run-to-run Variance (5 runs × 30 s)', fontsize=13)
    fig.tight_layout()
    fig.savefig(f'{OUTDIR}/2_variance_boxplot.png', dpi=180)
    plt.close()
    print('Saved: 2_variance_boxplot.png')

# ── 3. Clock stability — line chart over 20 bursts ───────

def plot_clock_stability():
    bm = load_floats('results_baremetal/clock_stability.txt')
    vm = load_floats('results_vm/clock_stability.txt')
    x  = np.arange(1, len(bm) + 1)

    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(x, bm, 'o-', color=BM_COLOR, label='Bare metal', linewidth=1.8, markersize=5)
    ax.plot(x, vm, 's-', color=VM_COLOR,  label='VM (UTM)',   linewidth=1.8, markersize=5)
    ax.axhline(np.mean(bm), color=BM_COLOR, linestyle='--', alpha=0.4, linewidth=1)
    ax.axhline(np.mean(vm),  color=VM_COLOR,  linestyle='--', alpha=0.4, linewidth=1)
    ax.set_xlabel('Burst number')
    ax.set_ylabel('Events per second')
    ax.set_title('Clock / Boost Stability — 20 × 3-second bursts', fontsize=13, pad=12)
    ax.legend()
    ax.grid(linestyle='--', alpha=0.4)
    fig.tight_layout()
    fig.savefig(f'{OUTDIR}/3_clock_stability.png', dpi=180)
    plt.close()
    print('Saved: 3_clock_stability.png')

# ── 4. sysbench latency: extract and plot 95th pct ───────

def parse_sysbench_latency(path):
    data = {}
    with open(path) as f:
        for line in f:
            for key in ['min', 'avg', 'max', '95th percentile']:
                if key + ':' in line:
                    val = re.search(r'[\d.]+', line.split(':')[1])
                    if val:
                        data[key] = float(val.group())
    return data

def plot_latency():
    bm = parse_sysbench_latency('results_baremetal/sysbench_latency_raw.txt')
    vm = parse_sysbench_latency('results_vm/sysbench_latency_raw.txt')

    keys = ['min', 'avg', '95th percentile', 'max']
    bm_vals = [bm.get(k, 0) for k in keys]
    vm_vals  = [vm.get(k, 0)  for k in keys]
    labels   = ['Min', 'Avg', 'p95', 'Max']

    x = np.arange(len(labels))
    w = 0.32
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.bar(x - w/2, bm_vals, w, color=BM_COLOR, label='Bare metal')
    ax.bar(x + w/2, vm_vals,  w, color=VM_COLOR,  label='VM (UTM)')
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel('Latency per event (ms) — lower is better')
    ax.set_title('Event Latency Distribution: Bare Metal vs VM', fontsize=13, pad=12)
    ax.legend()
    ax.grid(axis='y', linestyle='--', alpha=0.5)
    fig.tight_layout()
    fig.savefig(f'{OUTDIR}/4_latency_distribution.png', dpi=180)
    plt.close()
    print('Saved: 4_latency_distribution.png')

def parse_top_cpu(path):
    user, sys_, idle = [], [], []
    with open(path) as f:
        for line in f:
            # top -l lines look like:
            # CPU usage: 45.23% user, 12.10% sys, 42.67% idle
            if 'CPU usage:' in line:
                m = re.findall(r'([\d.]+)%', line)
                if len(m) >= 3:
                    user.append(float(m[0]))
                    sys_.append(float(m[1]))
                    idle.append(float(m[2]))
    return np.mean(user) if user else 0, np.mean(sys_) if sys_ else 0, np.mean(idle) if idle else 0

def plot_cpu_split():
    """Parse iostat -c output and plot user/sys/idle split for both environments."""
    import re

    def parse_iostat(path):
        user, sys_, idle = [], [], []
        with open(path) as f:
            for line in f:
                # iostat -c lines look like:   cpu   us  sy  id
                # data lines are space-separated floats
                parts = line.strip().split()
                if len(parts) >= 3:
                    try:
                        u, s, i = float(parts[0]), float(parts[1]), float(parts[2])
                        # sanity check: should sum close to 100
                        if 90 <= u + s + i <= 110:
                            user.append(u)
                            sys_.append(s)
                            idle.append(i)
                    except ValueError:
                        continue
        return np.mean(user), np.mean(sys_), np.mean(idle)

    # bm = parse_iostat('results_baremetal/iostat_cpu_split.txt')
    # vm  = parse_iostat('results_vm/iostat_cpu_split.txt')
    bm = parse_top_cpu('results_baremetal/top_cpu_split.txt')
    vm  = parse_top_cpu('results_vm/top_cpu_split.txt')

    labels = ['User %', 'Sys %', 'Idle %']
    x = np.arange(len(labels))
    w = 0.32

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.bar(x - w/2, bm, w, color=BM_COLOR, label='Bare metal')
    ax.bar(x + w/2, vm,  w, color=VM_COLOR,  label='VM (UTM)')
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel('% of CPU time')
    ax.set_title('CPU Time Split Under Load (User / Sys / Idle)', fontsize=13, pad=12)
    ax.legend()
    ax.grid(axis='y', linestyle='--', alpha=0.5)

    # Annotate sys% difference — this is the key overhead indicator
    bm_sys, vm_sys = bm[1], vm[1]
    ax.annotate(f'Δ sys = {vm_sys - bm_sys:+.1f}%\n(hypercall overhead)',
                xy=(1 + w/2, vm_sys), xytext=(1.8, vm_sys + 5),
                arrowprops=dict(arrowstyle='->', color='#555'),
                fontsize=9, color='#333')

    fig.tight_layout()
    fig.savefig(f'{OUTDIR}/5_cpu_time_split.png', dpi=180)
    plt.close()
    print('Saved: 5_cpu_time_split.png')

# ── 5. Summary table printout ─────────────────────────────

def print_summary():
    print('\n' + '='*60)
    print('SUMMARY TABLE')
    print('='*60)
    rows = []
    for label, (bp, vp) in [
        ('Single-thread EPS', ('results_baremetal/sysbench_single.txt',
                               'results_vm/sysbench_single.txt')),
        ('Multi-thread EPS',  ('results_baremetal/sysbench_multi.txt',
                               'results_vm/sysbench_multi.txt')),
        ('Clock stability EPS', ('results_baremetal/clock_stability.txt',
                                 'results_vm/clock_stability.txt')),
    ]:
        bm = load_floats(bp)
        vm = load_floats(vp)
        oh = overhead_pct(np.mean(bm), np.mean(vm))
        t, p = stats.ttest_ind(bm, vm)
        rows.append({
            'Metric': label,
            'BM mean': f'{np.mean(bm):.1f}',
            'VM mean': f'{np.mean(vm):.1f}',
            'Overhead %': f'{oh:+.2f}%',
            'p-value': f'{p:.4f}',
            'Significant?': 'Yes' if p < 0.05 else 'No'
        })
    df = pd.DataFrame(rows)
    print(df.to_string(index=False))
    df.to_csv(f'{OUTDIR}/summary_table.csv', index=False)
    print(f'\nSaved: summary_table.csv')

# ── main ─────────────────────────────────────────────────

if __name__ == '__main__':
    plot_throughput()
    plot_variance()
    plot_clock_stability()
    plot_latency()
    plot_cpu_split()
    print_summary()
    print(f'\nAll plots saved in ./{OUTDIR}/')