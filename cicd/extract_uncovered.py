#!/usr/bin/env python3
# coding=utf-8
#
# Copyright (c) 2026 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# ...
# See the License for the specific language governing permissions and
# limitations under the License.
#

"""
extract_uncovered.py — P6 Coverage Analysis

Parses lcov .info files to extract uncovered branches and generates a
structured JSON report for the agent (P7) to act on.

Usage:
    python3 extract_uncovered.py --info <path> --src-root <path> --output <path> [--parts P1,P2] [--baseline <path>]

Output JSON structure:
{
    "summary": { "line_rate": "...", "branch_rate": "...",
                 "uncovered_branches": N, "total_branches": N,
                 "files_analyzed": N, "files_with_uncovered": N },
    "baseline_delta": { ... },                    // only if --baseline given
    "files": [
        { "file": "path/relative/to/ohos/root",
          "uncovered_branches": [
              { "line": 42, "block": 1, "branch": 0,
                "function": "Foo::Bar",
                "code_snippet": "if (x > 0) {",
                "context_before": ["  // some code"],
                "context_after":  ["    do_something();"]
              }
          ],
          "uncovered_line_count": N
        }
    ]
}
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict


def parse_lcov_info(info_path):
    """Parse an lcov .info file and return records per source file."""
    records = {}
    current_sf = None
    current = None

    with open(info_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('SF:'):
                current_sf = line[3:]
                current = {
                    'file': current_sf,
                    'da': [],       # (line, count)
                    'fn': {},       # name -> line
                    'fnda': {},     # name -> hit count
                    'brda': [],     # (line, block, branch, taken)
                    'brf': 0,
                    'brh': 0,
                    'lf': 0,
                    'lh': 0,
                }
            elif current is None:
                continue  # skip lines before first SF:
            elif line.startswith('DA:'):
                parts = line[3:].split(',')
                if len(parts) >= 2:
                    current['da'].append((int(parts[0]), int(parts[1])))
            elif line.startswith('FN:'):
                # FN:line,name
                m = re.match(r'(\d+),(.+)', line[3:])
                if m:
                    current['fn'][m.group(2)] = int(m.group(1))
            elif line.startswith('FNDA:'):
                # FNDA:count,name
                m = re.match(r'(\d+),(.+)', line[5:])
                if m:
                    current['fnda'][m.group(2)] = int(m.group(1))
            elif line.startswith('BRDA:'):
                # BRDA:line,block,branch,taken
                parts = line[5:].split(',')
                if len(parts) >= 4:
                    taken_str = parts[3].strip()
                    taken = -1 if taken_str == '-' else int(taken_str)
                    current['brda'].append((int(parts[0]), int(parts[1]),
                                            int(parts[2]), taken))
            elif line.startswith('BRF:'):
                current['brf'] = int(line[4:])
            elif line.startswith('BRH:'):
                current['brh'] = int(line[4:])
            elif line.startswith('LF:'):
                current['lf'] = int(line[3:])
            elif line.startswith('LH:'):
                current['lh'] = int(line[3:])
            elif line.startswith('end_of_record'):
                if current_sf and current:
                    records[current_sf] = current
                current_sf = None
                current = None

    return records


def find_uncovered_branches(record):
    """Return list of (line, block, branch) tuples that were never hit."""
    uncovered = []
    for line, block, branch, taken in record['brda']:
        if taken == -1:
            uncovered.append((line, block, branch))
    return uncovered


def function_at_line(record, line_no):
    """Find the function name that contains the given line."""
    best_fn = None
    best_line = -1
    for fn_name, fn_line in record['fn'].items():
        if fn_line <= line_no and fn_line > best_line:
            best_fn = fn_name
            best_line = fn_line
    return best_fn


def read_code_snippet(file_path, line_no, context_lines=2):
    """Read code snippet around a given line number."""
    snippet = {
        'code': '',
        'context_before': [],
        'context_after': [],
    }
    if not os.path.isfile(file_path):
        return snippet

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()

    idx = line_no - 1  # 0-indexed
    if idx < 0 or idx >= len(lines):
        return snippet

    snippet['code'] = lines[idx].rstrip('\n')

    start = max(0, idx - context_lines)
    for i in range(start, idx):
        snippet['context_before'].append(lines[i].rstrip('\n'))

    end = min(len(lines), idx + context_lines + 1)
    for i in range(idx + 1, end):
        snippet['context_after'].append(lines[i].rstrip('\n'))

    return snippet


def compute_metrics(records):
    """Aggregate line and branch metrics across all records."""
    total_lf = 0
    total_lh = 0
    total_brf = 0
    total_brh = 0
    total_uncovered = 0

    for rec in records.values():
        total_lf += rec['lf']
        total_lh += rec['lh']
        total_brf += rec['brf']
        total_brh += rec['brh']
        total_uncovered += len(find_uncovered_branches(rec))

    line_rate = (total_lh / total_lf * 100) if total_lf > 0 else 0.0
    branch_rate = (total_brh / total_brf * 100) if total_brf > 0 else 0.0

    return {
        'line_rate': f'{line_rate:.1f}%',
        'branch_rate': f'{branch_rate:.1f}%',
        'line_hit': total_lh,
        'line_total': total_lf,
        'branch_hit': total_brh,
        'branch_total': total_brf,
        'uncovered_branches': total_uncovered,
    }


def filter_by_part(records, src_root, parts):
    """Keep only records whose file path belongs to one of the given parts.
    
    This uses the all_subsystem_config.json to map part names to source paths.
    If parts is empty, return all records.
    """
    if not parts:
        return records

    # Try to load part->path mapping
    devtest_dir = os.path.join(src_root, 'test', 'testfwk', 'developer_test')
    config_path = os.path.join(devtest_dir, 'local_coverage', 'all_subsystem_config.json')

    part_paths = []
    if os.path.isfile(config_path):
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        for part in parts:
            if part in config and 'path' in config[part]:
                for p in config[part]['path']:
                    abs_p = os.path.normpath(os.path.join(src_root, p))
                    part_paths.append(abs_p)
    else:
        # Fallback: test if part name appears as a directory component
        part_paths = parts

    # Filter records
    filtered = {}
    for file_path, rec in records.items():
        norm_path = os.path.normpath(file_path)
        for pp in part_paths:
            if norm_path.startswith(pp):
                filtered[file_path] = rec
                break

    return filtered


def build_report(records, src_root, parts=None):
    """Build the full uncovered-branch report."""
    # Apply part filter
    filtered = filter_by_part(records, src_root, parts or [])

    summary = compute_metrics(filtered)

    files = []
    files_with_uncovered = 0
    seen_files = set()

    for file_path, rec in sorted(filtered.items()):
        uncovered = find_uncovered_branches(rec)
        if not uncovered:
            continue

        files_with_uncovered += 1
        abs_path = file_path if os.path.isabs(file_path) else os.path.join(src_root, file_path)

        branch_list = []
        for line_no, block, branch in uncovered:
            fn_name = function_at_line(rec, line_no)
            snippet = read_code_snippet(abs_path, line_no, context_lines=3)
            branch_list.append({
                'line': line_no,
                'block': block,
                'branch': branch,
                'function': fn_name or '',
                'code': snippet['code'],
                'context_before': snippet['context_before'],
                'context_after': snippet['context_after'],
            })

        # Deduplicate uncovered lines (multiple branches on same line)
        unique_lines = sorted(set(b[0] for b in uncovered))

        rel_path = os.path.relpath(file_path, src_root) if os.path.isabs(file_path) else file_path
        files.append({
            'file': rel_path,
            'uncovered_branches': branch_list,
            'uncovered_line_count': len(unique_lines),
        })

    report = {
        'summary': summary,
        'total_files': len(filtered),
        'files_with_uncovered': files_with_uncovered,
        'files': files,
    }

    return report


def compare_baseline(current_records, baseline_path, src_root, parts=None):
    """Compare current .info against a baseline .info and produce delta."""
    baseline_records = parse_lcov_info(baseline_path)

    current_report = build_report(current_records, src_root, parts)
    baseline_report = build_report(baseline_records, src_root, parts)

    c = current_report['summary']
    b = baseline_report['summary']

    delta = {
        'baseline_file': baseline_path,
        'line_delta_pct': _pct_delta(c['line_rate'], b['line_rate']),
        'branch_delta_pct': _pct_delta(c['branch_rate'], b['branch_rate']),
        'uncovered_branches_delta': c['uncovered_branches'] - b['uncovered_branches'],
        'baseline_line_rate': b['line_rate'],
        'baseline_branch_rate': b['branch_rate'],
        'baseline_uncovered_branches': b['uncovered_branches'],
    }

    return delta


def _pct_delta(current, baseline):
    """Compare two percentage strings like '65.0%' and return delta string."""
    c = float(current.strip('%'))
    b = float(baseline.strip('%'))
    d = c - b
    sign = '+' if d >= 0 else ''
    return f'{sign}{d:.1f}%'


def main():
    parser = argparse.ArgumentParser(
        description='P6: Extract uncovered branches from lcov .info file')
    parser.add_argument('--info', required=True,
                        help='Path to ohos_codeCoverage.info')
    parser.add_argument('--src-root', required=True,
                        help='OpenHarmony source root')
    parser.add_argument('--output', required=True,
                        help='Output JSON report path')
    parser.add_argument('--parts', default='',
                        help='Comma-separated part names to filter by')
    parser.add_argument('--baseline', default=None,
                        help='Optional baseline .info file for comparison')
    args = parser.parse_args()

    if not os.path.isfile(args.info):
        print(f'ERROR: --info file not found: {args.info}')
        sys.exit(1)
    if not os.path.isdir(args.src_root):
        print(f'ERROR: --src-root not a directory: {args.src_root}')
        sys.exit(1)

    parts = [p.strip() for p in args.parts.split(',') if p.strip()]

    print(f'Parsing {args.info}...')
    records = parse_lcov_info(args.info)
    print(f'  Found {len(records)} source files in coverage data.')

    report = build_report(records, args.src_root, parts)

    if args.baseline and os.path.isfile(args.baseline):
        print(f'Comparing against baseline: {args.baseline}')
        delta = compare_baseline(records, args.baseline, args.src_root, parts)
        report['baseline_delta'] = delta
        print(f'  Line delta:      {delta["line_delta_pct"]}')
        print(f'  Branch delta:    {delta["branch_delta_pct"]}')
        print(f'  Uncovered delta: {delta["uncovered_branches_delta"]:+d}')

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f'')
    print(f'Summary:')
    print(f'  Line coverage:   {report["summary"]["line_hit"]} / {report["summary"]["line_total"]}  ({report["summary"]["line_rate"]})')
    print(f'  Branch coverage: {report["summary"]["branch_hit"]} / {report["summary"]["branch_total"]}  ({report["summary"]["branch_rate"]})')
    print(f'  Files with uncovered branches: {report["files_with_uncovered"]} / {report["total_files"]}')
    print(f'  Total uncovered branches:      {report["summary"]["uncovered_branches"]}')
    print(f'')
    print(f'Report written to: {args.output}')


if __name__ == '__main__':
    main()
