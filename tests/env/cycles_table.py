#!/usr/bin/env python3
"""Markdown table of cycle counts from kyber_cycles / dilithium_cycles logs.

  cycles_table.py <sim.log> [<sim.log> ...]

Each log is a build/sw-<core>/<test>-<variant>/sim.log, from any NTESTS. Per
parameter set, operation and core it gives the first iteration (the fixed
seed, same as NTESTS=1), then median and min-max over all iterations.
Example:

  python3 env/cycles_table.py build/sw-*/kyber_cycles-k*-n5/sim.log
"""

import re
import statistics
import sys

CORES = ('cv32e40p', 'ibex')
CORE_NAMES = {'cv32e40p': 'CV32E40P', 'ibex': 'Ibex'}

STDOUT = re.compile(r'^\[STDOUT[^\]]*\] (.*)$')
COUNT = re.compile(r'^(crypto_\w+)\s*: (\d+) cycles$')
PARAMS = re.compile(r'^(Kyber\d+|Dilithium\d)$')


def parse(path):
    """(parameter set, {operation: [cycles per iteration]})"""
    params, counts, passed = None, {}, False
    for line in open(path):
        if line.startswith('[TB]') and 'PASSED' in line:
            passed = True
        m = STDOUT.match(line.rstrip('\n'))
        if not m:
            continue
        text = m.group(1)
        if PARAMS.match(text):
            params = text
        elif (c := COUNT.match(text)):
            counts.setdefault(c.group(1), []).append(int(c.group(2)))
    if not passed:
        sys.exit(f'error: {path} did not pass')
    if params is None or not counts:
        sys.exit(f'error: no cycle counts in {path}')
    return params, counts


def core_of(path):
    m = re.search(r'sw-(\w+)/', path)
    if not m or m.group(1) not in CORES:
        sys.exit(f'error: no build/sw-<core>/ in {path}')
    return m.group(1)


def sort_key(params):
    m = re.match(r'(\D+)(\d+)', params)
    return m.group(1) != 'Kyber', int(m.group(2))  # Kyber first


def median(values):
    return int(statistics.median(values))  # even count: mean of the middle two, rounded down


def main(paths):
    if not paths:
        sys.exit(__doc__)
    results = {}  # params -> core -> {op: [cycles]}
    for p in paths:
        params, counts = parse(p)
        results.setdefault(params, {})[core_of(p)] = counts

    cores = [c for c in CORES if any(c in r for r in results.values())]
    head = '| Parameter set | Operation | ' + ' | '.join(
        f'{CORE_NAMES[c]} 1 seed | median | min – max' for c in cores) + ' |'
    lines = [head, '|---|---|' + '---:|' * (3 * len(cores))]
    for params in sorted(results, key=sort_key):
        ops = list(next(iter(results[params].values())))
        n = {len(v) for r in results[params].values() for v in r.values()}
        for i, op in enumerate(ops):
            label = f'{params} (n = {"/".join(map(str, sorted(n)))})' if i == 0 else ''
            cells = []
            for c in cores:
                v = results[params].get(c, {}).get(op)
                if not v:
                    cells += ['–'] * 3
                    continue
                cells += [f'{v[0]:,}', f'{median(v):,}', f'{min(v):,} – {max(v):,}']
            lines.append(f'| {label} | `{op}` | ' + ' | '.join(cells) + ' |')
    print('\n'.join(lines))


if __name__ == '__main__':
    main(sys.argv[1:])
