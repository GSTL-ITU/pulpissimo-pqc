#!/usr/bin/env python3
"""Core vs SoC area summary from Vivado hierarchical utilization reports (PULPissimo).

  area_summary.py <name>=<util_hier.rpt> [<name>=<util_hier.rpt> ...] [-o out.md]

One report: a breakdown of that design (core, FPU, each SoC block).
Several reports: the breakdown of each, plus a side-by-side comparison.

The core is the fabric controller's core instance (cv32e40p_core or ibex_core,
including its register file). The FPU (cv32e40p_fp_wrapper, CV32E40P only)
is listed separately. Everything else is the SoC.
Same table format as ibex-pqc/fpga/scripts/area_summary.py.
"""

import sys

# XC7A100T-1CSG324 (Nexys 4 DDR / Nexys A7-100T)
DEVICE = 'XC7A100T'
AVAILABLE = {'lut': 63400, 'lutram': 19000, 'ff': 126800, 'bram': 135, 'dsp': 240}

COLUMNS = [  # key, header
    ('lut', 'LUTs'),
    ('lutram', 'of which LUTRAM'),
    ('ff', 'FFs'),
    ('bram', 'BRAM (36 Kb)'),
    ('dsp', 'DSPs'),
]

CORE_MODULES = ('cv32e40p_core', 'ibex_core')
FPU_MODULES = ('cv32e40p_fp_wrapper',)

# SoC blocks: (label, module names). Matched by module name (Vivado appends
# __parameterized... to some). Whatever no group claims ends up in the last row.
SOC_GROUPS = [
    ('uDMA peripherals (`udma_subsystem`)', ('udma_subsystem',)),
    ('GPIO', ('gpio_apb_wrap_intf',)),
    ('event generator (`soc_event_generator`)', ('soc_event_generator',)),
    ('timers (`apb_adv_timer`, `apb_timer_unit`)', ('apb_adv_timer', 'apb_timer_unit')),
    ('other peripherals (APB bridge, `soc_ctrl`, ...)', ('soc_peripherals',)),
    ('interconnect (`soc_interconnect_wrap`)', ('soc_interconnect_wrap',)),
    ('debug module and JTAG', ('dm_top', 'dmi_jtag', 'lint_jtag_wrap', 'jtag_tap_top',
                               'tcdm_arbiter_2x1')),
    ('L2 memory (`l2_ram_multi_bank`)', ('l2_ram_multi_bank',)),
    ('pad frame (`padframe_adapter`)', ('padframe_adapter',)),
    ('rest of `fc_subsystem` (interrupt controller, ...)', ('fc_subsystem',)),
]
REST_LABEL = 'boot ROM, CDCs, APB decoder, clock/reset and glue'


class Node:
    def __init__(self, name, module, depth, values):
        self.name = name
        self.module = module
        self.depth = depth
        self.values = values
        self.children = []


def parse(path):
    """Returns the root Node of the hierarchy in a report_utilization -hierarchical file."""
    header = None
    root = None
    stack = []
    for line in open(path):
        if not line.startswith('|'):
            continue
        cells = line.rstrip('\n').split('|')[1:-1]
        if header is None:
            if cells and cells[0].strip() == 'Instance':
                header = [c.strip() for c in cells]
                idx = {h: i for i, h in enumerate(header)}
            continue
        if len(cells) != len(header):
            continue
        raw = cells[0]
        depth = (len(raw) - len(raw.lstrip(' ')) - 1) // 2
        name = raw.strip()
        get = lambda h: float(cells[idx[h]].strip() or 0) if h in idx else 0.0
        values = {
            'lut': get('Total LUTs'),
            'lutram': get('LUTRAMs'),
            'ff': get('FFs'),
            'bram': get('RAMB36') + get('RAMB18') / 2,
            'dsp': get('DSP Blocks') or get('DSP48 Blocks'),
        }
        while stack and stack[-1].depth >= depth:
            stack.pop()
        if name.startswith('('):
            continue  # logic of the parent instance itself, included in its totals
        node = Node(name, cells[1].strip(), depth, values)
        if stack:
            stack[-1].children.append(node)
        else:
            root = node
        stack.append(node)
    if root is None:
        sys.exit(f'error: no utilization table in {path}')
    return root


def base_module(node):
    return node.module.split('__')[0]


def find_all(node, modules):
    """Outermost instances whose module is in modules."""
    if base_module(node) in modules:
        return [node]
    return [m for c in node.children for m in find_all(c, modules)]


def zero():
    return {k: 0.0 for k, _ in COLUMNS}


def add(a, b):
    return {k: a[k] + b[k] for k in a}


def sub(a, b):
    return {k: a[k] - b[k] for k in a}


def total(nodes):
    t = zero()
    for n in nodes:
        t = add(t, n.values)
    return t


def fmt(v, key):
    if key == 'bram':
        return f'{v:g}'
    return f'{int(round(v)):,}'


def row(label, values, total_values):
    cells = [fmt(values[k], k) for k, _ in COLUMNS]
    lut = total_values['lut']
    cells.append(f'{100 * values["lut"] / lut:.0f}%' if lut else '-')
    return '| ' + label + ' | ' + ' | '.join(cells) + ' |'


def soc_groups(root, exclude):
    """[(label, values, [(sublabel, values)])] for the SoC, without the nodes in exclude.

    A group's area is its instances minus whatever is claimed by an earlier
    group or excluded (e.g. `soc_peripherals` minus uDMA, GPIO, timers, ...)."""
    claimed = list(exclude)
    out = []
    for label, modules in SOC_GROUPS:
        nodes = find_all(root, modules)
        inside = [c for c in claimed if any(contains(n, c) for n in nodes)]
        values = sub(total(nodes), total(inside))
        subrows = []
        if modules == ('udma_subsystem',):
            subrows = [(f'{c.name} ({base_module(c)})', c.values) for n in nodes for c in n.children]
        out.append((label, values, subrows))
        claimed += nodes
    outermost = [c for c in claimed if not any(o is not c and contains(o, c) for o in claimed)]
    out.append((REST_LABEL, sub(root.values, total(outermost)), []))
    return out


def contains(outer, inner):
    if outer is inner:
        return True
    return any(contains(c, inner) for c in outer.children)


def breakdown(name, root):
    """(markdown lines, summary dict) for one design."""
    cores = find_all(root, CORE_MODULES)
    if len(cores) != 1:
        sys.exit(f'error: expected one core instance ({"/".join(CORE_MODULES)}) in the {name} report')
    core = cores[0]
    fpus = find_all(root, FPU_MODULES)
    fpu = total(fpus)
    soc = sub(sub(root.values, core.values), fpu)

    out = [f'### {name}', '']
    out.append('| Block | ' + ' | '.join(h for _, h in COLUMNS) + ' | share of LUTs |')
    out.append('|---|' + '---:|' * (len(COLUMNS) + 1))
    out.append(row(f'**Whole design** (`{root.name}`)', root.values, root.values))
    out.append(row(f'**Core** (`{core.name}`: {base_module(core)})', core.values, root.values))
    for c in core.children:
        out.append(row(f'&nbsp;&nbsp;{c.name} ({base_module(c)})', c.values, root.values))
    regfiles = [n for c in core.children for n in find_all(c, (
        'cv32e40p_register_file', 'ibex_register_file_ff', 'ibex_register_file_fpga',
        'ibex_register_file_latch'))]
    for r in regfiles:
        out.append(row(f'&nbsp;&nbsp;&nbsp;&nbsp;of which register file ({base_module(r)})',
                       r.values, root.values))
    if fpus:
        out.append(row('**FPU** (`cv32e40p_fp_wrapper`: fpnew)', fpu, root.values))
    out.append(row('**SoC without core' + (' and FPU' if fpus else '') + '**', soc, root.values))
    groups = soc_groups(root, [core] + fpus)
    for label, values, subrows in groups:
        out.append(row(f'&nbsp;&nbsp;{label}', values, root.values))
        for sl, sv in subrows:
            out.append(row(f'&nbsp;&nbsp;&nbsp;&nbsp;{sl}', sv, root.values))
    out.append('')
    out.append(f'Device usage ({DEVICE}): ' + ', '.join(
        f'{h.replace("of which ", "")} {100 * root.values[k] / AVAILABLE[k]:.1f}%'
        for k, h in COLUMNS))
    out.append('')
    summary = {'Whole design': root.values, 'Core': core.values, 'FPU': fpu,
               'SoC without core and FPU': soc}
    for label, values, _ in groups:
        summary['&nbsp;&nbsp;' + label] = values
    return out, summary


def main(argv):
    args = argv[1:]
    out_path = None
    if '-o' in args:
        i = args.index('-o')
        out_path = args[i + 1]
        del args[i:i + 2]
    if not args:
        sys.exit(__doc__)

    lines = ['# PULPissimo FPGA area: core vs SoC', '']
    summaries = {}
    sections = []
    for a in args:
        name, path = a.split('=', 1)
        sec, summ = breakdown(name, parse(path))
        sections += sec
        summaries[name] = summ

    if len(summaries) > 1:
        lines += ['## Comparison', '']
        names = list(summaries)
        keys = ('lut', 'ff', 'bram', 'dsp')
        lines.append('| | ' + ' | '.join(
            f'{n} {h}' for n in names for k, h in COLUMNS if k in keys) + ' |')
        lines.append('|---|' + '---:|' * (len(keys) * len(names)))
        for part in summaries[names[0]]:
            cells = [fmt(summaries[n].get(part, zero())[k], k) for n in names for k in keys]
            label = f'**{part}**' if not part.startswith('&') else part
            lines.append(f'| {label} | ' + ' | '.join(cells) + ' |')
        lines.append('')

    lines += ['## Breakdown', ''] + sections
    lines += [
        'BRAM counts 36 Kb blocks (a RAMB18 is half). "share of LUTs" is the part of the',
        'whole design\'s LUTs. The core includes its register file. "of which LUTRAM"',
        'counts distributed RAM only (shift registers are not included).',
        '',
    ]
    text = '\n'.join(lines)
    if out_path:
        open(out_path, 'w').write(text)
    print(text)


if __name__ == '__main__':
    main(sys.argv)
