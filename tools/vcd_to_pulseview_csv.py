#!/usr/bin/env python3
"""
@file vcd_to_pulseview_csv.py
@brief Converts VCD to CSV suitable for import into PulseView with X/Z cleanup and bus support.

@mainpage VCD to PulseView CSV Converter

@section overview Overview
This script converts Value Change Dump (VCD) files to CSV format suitable for import into
Sigrok PulseView. It handles Icarus Verilog-style buses and provides cleanup for X/Z states.

@section features Features
- Supports scalar signals (width = 1) and buses (width > 1) with names like `state_o[2:0]`
- X/Z cleanup logic:
  - 0/1 → as is
  - z/Z → 1 (open-drain, line released, pull-up = logic 1)
  - x/X → previous signal value, or 1 if no history
- Time values in seconds (from VCD timescale)
- Multiple signal selection methods:
  - Via GTKWave save file (--gtkw)
  - Via explicit signal list (--signal)
  - All scalar signals (default)
- Time range limiting (--tmin/--tmax)
- Uniform time grid output (--uniform-step)
- Missing signal tolerance (--ignore-missing)

@section usage Usage Examples
@code
# Convert with GTKWave signal list
python vcd_to_pulseview_csv.py input.vcd --gtkw save.gtkw -o output.csv

# Convert specific signals with time range
python vcd_to_pulseview_csv.py input.vcd -s "clk" -s "data[7:0]" \
    --tmin 100ns --tmax 200ns -o output.csv

# Convert with uniform 10ns grid
python vcd_to_pulseview_csv.py input.vcd --uniform-step 10ns -o output.csv
@endcode

@section notes Notes
- Bus format: `$var wire <N> <id> base [MSB:LSB] $end`
- Bus changes: `b010 <id>`
- Individual bits: `base[MSB]`, `base[MSB-1]`, ..., `base[LSB]`
- Time units: fs, ps, ns, us, ms, s (seconds if no suffix)

@author Igor Gorbunov <igor@gorbunov.tel>

@par License
SPDX-License-Identifier: Apache-2.0

Copyright 2025 Igor Gorbunov

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at:

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

import re
import sys
from typing import Dict, List, Optional, Tuple

RE_TIME    = re.compile(r'^#(\d+)\s*$')
RE_TS      = re.compile(r'^(\s*)(\d+)\s*([fpnumk]?s)\s*$', re.IGNORECASE)
RE_SCALAR  = re.compile(r'^([01xXzZ])(\S+)\s*$')
RE_VECTOR  = re.compile(r'^[bB]([01xXzZ]+)\s+(\S+)\s*$')
RE_TSPEC   = re.compile(r'^\s*([0-9]*\.?[0-9]+)\s*([fpnumk]?s)?\s*$',
                        re.IGNORECASE)
RE_BUSNAME = re.compile(r'^(.+)\[(\d+):(\d+)\]$')
RE_BUSBIT  = re.compile(r'^(.+)\[(\d+)\]$')

UNIT_TO_PS = {
    'fs': 1e-3,
    'ps': 1.0,
    'ns': 1e3,
    'us': 1e6,
    'ms': 1e9,
    's':  1e12,
}


def parse_var_line(line: str):
    """
    @brief Parse $var ... line as in Icarus VCD.
    
    @details Format:
        $var <type> <size> <id> <ref> [<range>] $end
        
    Examples:
        $var wire 1 ! mdc $end
        $var wire 3 # state_o [2:0] $end
        
    @param line Input line from VCD file
    @return Tuple (width, sid, ref, rng) or None if parsing fails
    """
    toks = line.split()
    if len(toks) < 5 or toks[0] != '$var':
        return None
    try:
        width = int(toks[2])
    except ValueError:
        return None
    sid = toks[3]
    ref = toks[4]
    rng = None
    if len(toks) >= 7 and toks[5].startswith('[') and toks[5].endswith(']'):
        rng = toks[5]  # e.g., "[2:0]"
    return width, sid, ref, rng


def parse_timescale(lines) -> float:
    """
    @brief Determine timescale in picoseconds.
    
    @param lines List of lines from VCD file
    @return Timescale factor in picoseconds
    """
    ts_factor_ps = 1.0
    in_ts = False
    for line in lines:
        line_stripped = line.strip()
        if line_stripped == '$timescale':
            in_ts = True
            continue
        if in_ts:
            m = RE_TS.match(line)
            if m:
                _, factor_str, unit = m.groups()
                factor = int(factor_str)
                unit = unit.lower()
                if unit not in UNIT_TO_PS:
                    break
                ts_factor_ps = factor * UNIT_TO_PS[unit]
            if line_stripped == '$end':
                break
    return ts_factor_ps


def sanitize_bit(val: str, prev: str) -> str:
    """
    @brief Convert single bit to 0/1 with X/Z handling.
    
    @details Logic:
        0/1 -> as is
        z/Z -> 1 (open-drain, line released, pull-up = logic 1)
        x/X -> previous signal value, or 1 if no history
        
    @param val Current bit value
    @param prev Previous bit value
    @return Cleaned bit value (0 or 1)
    """
    v = val.lower()
    if v in ('0', '1'):
        return v
    if v == 'z':
        # Line released -> pull-up = 1
        return '1'
    # x: keep previous or 1
    if prev in ('0', '1'):
        return prev
    return '1'


def parse_gtkw_signals(gtkw_path: str) -> List[str]:
    """
    @brief Parse .gtkw file and extract signal list.
    
    @details Logic:
    - Take all lines that:
      * are not empty;
      * first character not in "[*@#;-".
      (ignore service lines like -group_end etc.)
    - From first "column" (before space) take signal name.
    - Trim hierarchy to leaf: a.b.c.state_o[2:0] -> state_o[2:0].
    - If name is like base[MSB:LSB], expand into base[MSB], base[MSB-1], ...
      down to LSB.
    - Remove duplicates, preserve order.
    
    @param gtkw_path Path to GTKWave save file
    @return List of signal names
    """
    signals: List[str] = []
    seen: set = set()

    try:
        with open(gtkw_path, 'r') as f:
            for line in f:
                s = line.strip()
                if not s:
                    continue
                if s[0] in '[*@#;-':
                    continue

                full = s.split()[0]
                leaf = full.split('.')[-1]

                m_bus = RE_BUSNAME.match(leaf)
                if m_bus:
                    base, msb_str, lsb_str = m_bus.groups()
                    msb = int(msb_str)
                    lsb = int(lsb_str)
                    if msb >= lsb:
                        rng = range(msb, lsb - 1, -1)
                    else:
                        rng = range(msb, lsb + 1)
                    for i in rng:
                        bit_name = f"{base}[{i}]"
                        if bit_name not in seen:
                            seen.add(bit_name)
                            signals.append(bit_name)
                else:
                    if leaf not in seen:
                        seen.add(leaf)
                        signals.append(leaf)

    except OSError as e:
        print(
            f"Error: cannot open GTKWave save file '{gtkw_path}': {e}",
            file=sys.stderr,
        )
        return []

    return signals


def parse_time_with_units(spec: Optional[str], opt_name: str) -> Optional[float]:
    """
    @brief Parse time specification string like '10ns', '2.5us', '1e-6'.
    
    @param spec Time specification string
    @param opt_name Option name for error messages
    @return Time in seconds or None if spec is None
    @note Exits program on error with informative message
    """
    if spec is None:
        return None
    m = RE_TSPEC.match(spec)
    if not m:
        print(
            f"Error: invalid time specification '{spec}' for {opt_name}. "
            f"Use <value>[unit] where unit is one of fs,ps,ns,us,ms,s.",
            file=sys.stderr,
        )
        sys.exit(1)
    val_str, unit = m.groups()
    value = float(val_str)
    if not unit:
        # No units — seconds.
        return value
    unit = unit.lower()
    if unit not in UNIT_TO_PS:
        print(
            f"Error: invalid time unit '{unit}' in {opt_name}. "
            f"Use one of fs,ps,ns,us,ms,s.",
            file=sys.stderr,
        )
        sys.exit(1)
    # UNIT_TO_PS is in picoseconds → convert to seconds.
    seconds = value * UNIT_TO_PS[unit] * 1e-12
    return seconds


def vcd_to_csv(
    path_in: str,
    path_out: str,
    wanted_signals: Optional[List[str]] = None,
    tmin: Optional[float] = None,
    tmax: Optional[float] = None,
    ignore_missing: bool = False,
    uniform_step: Optional[float] = None,  # seconds
) -> None:
    """
    @brief Main VCD -> CSV conversion.
    
    @param path_in Input VCD file path
    @param path_out Output CSV file path
    @param wanted_signals List of signals to export (None = all scalars)
    @param tmin Minimum time to include (seconds)
    @param tmax Maximum time to include (seconds)
    @param ignore_missing If True, don't fail on missing signals
    @param uniform_step Uniform sampling step (seconds) or None for event mode
    """
    try:
        with open(path_in, 'r') as f:
            lines = f.read().splitlines()
    except OSError as e:
        print(f"Error: cannot open VCD file '{path_in}': {e}", file=sys.stderr)
        sys.exit(1)

    # timescale -> seconds per tick
    ts_ps = parse_timescale(lines)
    ts_sec = ts_ps * 1e-12  # 1 ps = 1e-12 s

    # ---------- Parse VCD header ----------
    scalar_name2id: Dict[str, str] = {}  # name -> id
    bus_defs: Dict[str, Tuple[str, str, int, int, int]] = {}

    for line in lines:
        if '$enddefinitions' in line:
            break
        parsed = parse_var_line(line)
        if not parsed:
            continue
        width, sid, ref, rng = parsed
        if width == 1:
            # IMPORTANT: build name -> id mapping, considering all aliases
            scalar_name2id.setdefault(ref, sid)
        else:
            if rng:
                m = re.match(r'\[(\d+):(\d+)\]', rng)
                if m:
                    msb, lsb = map(int, m.groups())
                else:
                    msb, lsb = width - 1, 0
            else:
                msb, lsb = width - 1, 0
            base = ref
            bus_defs[sid] = (ref, base, msb, lsb, width)

    if not scalar_name2id and not bus_defs:
        print(
            "Error: no signals (scalar or bus) found in VCD.",
            file=sys.stderr,
        )
        sys.exit(1)

    # ---------- Select signals based on wanted_signals ----------
    busid_to_bits: Dict[str, List[Tuple[str, int, int]]] = {}
    # sid -> [(bit_name, offset_from_MSB, width)]
    missing: List[str] = []
    scalar_selected_names: List[str] = []

    if wanted_signals:
        for n in wanted_signals:
            # Scalar?
            if n in scalar_name2id:
                scalar_selected_names.append(n)
                continue

            # Bus bit?
            m_bit = RE_BUSBIT.match(n)
            if m_bit:
                base, idx_str = m_bit.groups()
                idx = int(idx_str)
                found = False
                for sid, (_, bus_base, msb, lsb, width) in bus_defs.items():
                    if bus_base != base:
                        continue
                    if (msb >= lsb and lsb <= idx <= msb) or (msb < lsb and msb <= idx <= lsb):
                        # Position in b<...> string, assuming string always MSB..LSB
                        if msb >= lsb:
                            bit_offset = msb - idx
                        else:
                            bit_offset = idx - msb
                        busid_to_bits.setdefault(sid, []).append((n, bit_offset, width))
                        found = True
                        break
                if not found:
                    missing.append(n)
            else:
                missing.append(n)

        if missing:
            msg = "Warning" if ignore_missing else "Error"
            print(
                f"{msg}: signals not found in VCD: " + ", ".join(missing),
                file=sys.stderr,
            )
        if not ignore_missing and missing:
            sys.exit(1)

        # Final list of names that actually exist (scalars and bus bits)        
        effective_signals: List[str] = []
        for n in wanted_signals:
            if n in scalar_selected_names:
                effective_signals.append(n)
            else:
                if any(
                    n == bit_name
                    for lst in busid_to_bits.values()
                    for (bit_name, _, _) in lst
                ):
                    effective_signals.append(n)

        if not effective_signals:
            print(
                "Error: none of the requested signals are present in VCD.",
                file=sys.stderr,
            )
            sys.exit(1)

        signals = effective_signals
    else:
        # If neither --gtkw nor --signal specified — take all scalars
        signals = sorted(scalar_name2id.keys())
        scalar_selected_names = signals

    # id -> list of scalar names we actually want
    scalar_sid_to_names: Dict[str, List[str]] = {}
    for name in scalar_selected_names:
        sid = scalar_name2id.get(name)
        if sid is None:
            continue
        scalar_sid_to_names.setdefault(sid, []).append(name)

    # Current value of each selected signal (idle = 1)
    cur_vals: Dict[str, str] = {name: '1' for name in signals}

    try:
        out = open(path_out, 'w')
    except OSError as e:
        print(
            f"Error: cannot open output CSV file '{path_out}' for writing: {e}",
            file=sys.stderr,
        )
        sys.exit(1)

    with out:
        # CSV header
        out.write("Time[s]," + ",".join(signals) + "\n")

        # ---------------------------------------------------------
        # MODE 1: UNIFORM TIME GRID (--uniform-step)
        # ---------------------------------------------------------
        if uniform_step is not None:
            cur_time_ticks: Optional[int] = None
            last_time_sec: Optional[float] = None
            next_sample_time: Optional[float] = None

            def emit_uniform_between(t_from: float, t_to: float):
                """Emit rows with uniform_step on interval [t_from; t_to)."""
                nonlocal next_sample_time
                if tmax is not None and t_from > tmax:
                    return
                if next_sample_time is None:
                    start = t_from
                    if tmin is not None and tmin > start:
                        start = tmin
                    next_sample_time = start
                while (next_sample_time is not None and
                       next_sample_time < t_to and
                       (tmax is None or next_sample_time <= tmax)):
                    row = [f"{next_sample_time:.12f}"] + [cur_vals[n] for n in signals]
                    out.write(",".join(row) + "\n")
                    next_sample_time += uniform_step

            header_done = False
            for raw_line in lines:
                line = raw_line.rstrip()

                # Skip VCD header until $enddefinitions                
                if not header_done:
                    if '$enddefinitions' in line:
                        header_done = True
                    continue
                if not line:
                    continue

                # Time marker
                m_t = RE_TIME.match(line)
                if m_t:
                    new_ticks = int(m_t.group(1))
                    new_sec = new_ticks * ts_sec
                    if cur_time_ticks is None:
                        cur_time_ticks = new_ticks
                        last_time_sec = new_sec
                    else:
                        # First output samples on previous time interval
                        # (state cur_vals refers to [last_time_sec; new_sec) after
                        # applying all changes from previous block).
                        emit_uniform_between(last_time_sec, new_sec)
                        cur_time_ticks = new_ticks
                        last_time_sec = new_sec
                    continue

                if line[0] in '$#':
                    continue

                # Scalar
                m_s = RE_SCALAR.match(line)
                if m_s:
                    val, sid = m_s.groups()
                    if sid not in scalar_sid_to_names:
                        continue
                    for name in scalar_sid_to_names[sid]:
                        prev = cur_vals[name]
                        new = sanitize_bit(val, prev)
                        if new != prev:
                            cur_vals[name] = new
                    continue

                # Vector (bus)
                m_v = RE_VECTOR.match(line)
                if m_v:
                    bits, sid = m_v.groups()
                    if sid not in busid_to_bits:
                        continue
                    for bit_name, offset, width in busid_to_bits[sid]:
                        pad_char = bits[0] if bits[0].lower() in ('x', 'z') else '0'
                        bits_p = bits.rjust(width, pad_char)
                        if offset >= len(bits_p):
                            raw_bit = 'x'
                        else:
                            raw_bit = bits_p[offset]
                        prev = cur_vals.get(bit_name, '1')
                        new = sanitize_bit(raw_bit, prev)
                        if new != prev:
                            cur_vals[bit_name] = new
                    # Rest not interested
                    continue

            if cur_time_ticks is not None and last_time_sec is not None:
                end_sec = last_time_sec
                if tmax is not None and tmax > end_sec:
                    end_sec = tmax
                emit_uniform_between(last_time_sec, end_sec)

            return  # uniform mode finished

        # ---------------------------------------------------------
        # MODE 2: EVENT-BASED — row for each change
        # ---------------------------------------------------------

        cur_time_ticks: Optional[int] = None
        changed_at_time = False

        def flush_if_needed():
            """Flush current time row if changes occurred."""
            nonlocal changed_at_time
            if cur_time_ticks is None or not changed_at_time:
                return False
            t_sec = cur_time_ticks * ts_sec
            if tmin is not None and t_sec < tmin:
                changed_at_time = False
                return False
            if tmax is not None and t_sec > tmax:
                return True
            row = [f"{t_sec:.12f}"] + [cur_vals[n] for n in signals]
            out.write(",".join(row) + "\n")
            changed_at_time = False
            return False

        header_done = False
        stop = False

        for raw_line in lines:
            if stop:
                break
            line = raw_line.rstrip()

            # Skip VCD header until $enddefinitions
            if not header_done:
                if '$enddefinitions' in line:
                    header_done = True
                continue
            if not line:
                continue

            # Time marker
            m_t = RE_TIME.match(line)
            if m_t:
                if flush_if_needed():
                    stop = True
                    break
                cur_time_ticks = int(m_t.group(1))
                continue

            if line[0] in '$#':
                continue

            # Scalar
            m_s = RE_SCALAR.match(line)
            if m_s:
                val, sid = m_s.groups()
                if sid not in scalar_sid_to_names:
                    continue
                for name in scalar_sid_to_names[sid]:
                    prev = cur_vals[name]
                    new = sanitize_bit(val, prev)
                    if new != prev:
                        cur_vals[name] = new
                        changed_at_time = True
                continue

            # Vector (bus)
            m_v = RE_VECTOR.match(line)
            if m_v:
                bits, sid = m_v.groups()
                if sid not in busid_to_bits:
                    continue
                for bit_name, offset, width in busid_to_bits[sid]:
                    pad_char = bits[0] if bits[0].lower() in ('x', 'z') else '0'
                    bits_p = bits.rjust(width, pad_char)
                    if offset >= len(bits_p):
                        raw_bit = 'x'
                    else:
                        raw_bit = bits_p[offset]
                    prev = cur_vals.get(bit_name, '1')
                    new = sanitize_bit(raw_bit, prev)
                    if new != prev:
                        cur_vals[bit_name] = new
                        changed_at_time = True
                # Ignore rest
                continue

        if not stop:
            flush_if_needed()


def main(argv=None):
    """Main entry point for command-line execution."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Convert VCD to PulseView-friendly CSV (with X/Z cleanup and bus support)."
    )
    parser.add_argument("vcd", help="input VCD file")
    parser.add_argument("csv", help="output CSV file")
    parser.add_argument(
        "--gtkw",
        help="GTKWave .gtkw file to take signal list from "
             "(hierarchical names will be reduced to leaf names; "
             "buses like state_o[2:0] will be expanded into bits).",
        default=None,
    )
    parser.add_argument(
        "--signal",
        "-s",
        action="append",
        help=(
            "signal name to export (can be used multiple times). "
            "Use bit names for buses, e.g. state_o[2], state_o[1]. "
            "If omitted and --gtkw is not given, all scalar signals are exported."
        ),
    )
    parser.add_argument(
        "--tmin",
        type=str,
        default=None,
        help=(
            "minimum time to include (events earlier are skipped). "
            "Format: <value>[unit], unit∈{fs,ps,ns,us,ms,s}. "
            "Without unit value is in seconds, e.g. 10ns, 2.5us, 1e-6."
        ),
    )
    parser.add_argument(
        "--tmax",
        type=str,
        default=None,
        help=(
            "maximum time to include (processing stops after this time). "
            "Format: <value>[unit], unit∈{fs,ps,ns,us,ms,s}. "
            "Without unit value is in seconds."
        ),
    )
    parser.add_argument(
        "--ignore-missing",
        action="store_true",
        help=(
            "do not fail if some requested signals are missing in VCD; "
            "print a warning and continue with the existing ones."
        ),
    )
    parser.add_argument(
        "--uniform-step",
        type=str,
        default=None,
        help=(
            "output rows on a uniform time grid with given step. "
            "Format: <value>[unit], unit∈{fs,ps,ns,us,ms,s}. "
            "Without unit value is in seconds, e.g. 5ns, 10ns, 1e-8. "
            "In PulseView, set Samplerate = 1/step when importing CSV."
        ),
    )

    args = parser.parse_args(argv)

    signals: List[str] = []

    if args.gtkw:
        signals = parse_gtkw_signals(args.gtkw)
        if not signals:
            print(
                "Warning: no signals parsed from GTKW file, "
                "falling back to --signal or all scalar signals.",
                file=sys.stderr,
            )

    if not signals and args.signal:
        signals = args.signal[:]

    tmin = parse_time_with_units(args.tmin, "--tmin") if args.tmin else None
    tmax = parse_time_with_units(args.tmax, "--tmax") if args.tmax else None
    uniform_step = (
        parse_time_with_units(args.uniform_step, "--uniform-step")
        if args.uniform_step
        else None
    )

    vcd_to_csv(
        args.vcd,
        args.csv,
        wanted_signals=signals if signals else None,
        tmin=tmin,
        tmax=tmax,
        ignore_missing=args.ignore_missing,
        uniform_step=uniform_step,
    )


if __name__ == "__main__":
    main()
