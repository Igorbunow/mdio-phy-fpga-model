#!/usr/bin/env python3
"""
@file vcd_sanitize_for_pulseview.py
@brief VCD sanitizer for PulseView compatibility

This script processes Value Change Dump (VCD) files to make them compatible
with Sigrok PulseView by:

1. Removing X/Z states:
   - Scalars: 0/1 remain as-is, Z becomes 1, X uses previous value (or 1)
   - Vectors: Same logic applied bitwise

2. Scaling timescale to 1ns and adjusting timestamps:
   - If original timescale < 1ns (e.g., 1ps), changes it to 1ns and divides
     all `#<time>` values by the scale factor
   - If already >= 1ns, keeps time format unchanged

@note This is particularly useful for MDIO protocol analysis in PulseView
      which has limited support for multi-state logic.

@usage
    python3 vcd_sanitize_for_pulseview.py input.vcd output.vcd

@author Igor Gorbunov <igor@gorbunov.tel>
@date Created: 2025
@version 1.0

@copyright
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright 2025 Igor Gorbunov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
"""

import re
import sys
from typing import Dict

# Regular expressions for parsing VCD syntax
RE_SCALAR = re.compile(r'^([01xXzZ])(\S+)\s*$')      # Scalar value changes
RE_VECTOR = re.compile(r'^[bBrR]([0-9a-fA-FxXzZ\.eE\+\-]+)\s+(\S+)\s*$')  # Vector/real changes
RE_TIME   = re.compile(r'^#(\d+)\s*$')               # Timestamp declarations
RE_TS     = re.compile(r'^(\s*)(\d+)\s*([fpnumk]s)\s*$', re.IGNORECASE)  # Timescale definitions

# Conversion factors to picoseconds
UNIT_TO_PS = {
    'fs': 1e-3,    # femtoseconds
    'ps': 1.0,     # picoseconds
    'ns': 1e3,     # nanoseconds
    'us': 1e6,     # microseconds
    'ms': 1e9,     # milliseconds
    's':  1e12,    # seconds
}


def sanitize_scalar(val: str, sig_id: str, last_values: Dict[str, str]) -> str:
    """
    @brief Sanitizes a scalar value by removing X/Z states
    
    @param val Input value character (0,1,x,X,z,Z)
    @param sig_id Signal identifier from VCD file
    @param last_values Dictionary tracking last known values for all signals
    @return Sanitized value (0 or 1)
    
    @details
    - 0/1 remain unchanged
    - Z becomes 1
    - X uses previous value (or defaults to 1 if no previous value)
    """
    v = val.lower()
    if v in ('0', '1'):
        last_values[sig_id] = v
        return v
    if v == 'z':
        last_values[sig_id] = '1'
        return '1'
    # x: use previous value or default to 1
    prev = last_values.get(sig_id, '1')
    if prev not in ('0', '1'):
        prev = '1'
    last_values[sig_id] = prev
    return prev


def sanitize_vector(bits: str, sig_id: str, last_values: Dict[str, str]) -> str:
    """
    @brief Sanitizes a vector value by removing X/Z states bitwise
    
    @param bits String of bits (may contain 0,1,x,X,z,Z)
    @param sig_id Signal identifier from VCD file
    @param last_values Dictionary tracking last known values for all signals
    @return Sanitized bit string (only 0s and 1s)
    
    @details
    Applies the same logic as sanitize_scalar() to each bit:
    - 0/1 remain unchanged
    - Z becomes 1
    - X uses previous bit value (or 1 if no previous value)
    """
    prev = last_values.get(sig_id)
    if prev is None or len(prev) != len(bits):
        prev = '1' * len(bits)

    out_bits = []
    for i, b in enumerate(bits):
        bl = b.lower()
        if bl in ('0', '1'):
            out_bits.append(bl)
        elif bl == 'z':
            out_bits.append('1')
        elif bl == 'x':
            out_bits.append(prev[i])
        else:
            out_bits.append('0')
    clean = ''.join(out_bits)
    last_values[sig_id] = clean
    return clean


def detect_timescale_scale(lines):
    """
    @brief Detects timescale in VCD header and calculates scaling factor
    
    @param lines List of lines from the VCD file
    @return Tuple (scale_factor, new_timescale_line)
            scale_factor = 1 if no scaling needed
            new_timescale_line = None if no change needed
    
    @details
    Searches for $timescale declaration and determines if scaling is needed
    to reach 1ns resolution for PulseView compatibility
    """
    scale = 1
    new_ts_line = None
    in_ts = False

    for i, line in enumerate(lines):
        if line.strip() == '$timescale':
            in_ts = True
            continue
        if in_ts:
            m = RE_TS.match(line)
            if not m:
                break
            indent, factor_str, unit = m.groups()
            factor = int(factor_str)
            unit = unit.lower()
            if unit not in UNIT_TO_PS:
                break

            orig_ps = factor * UNIT_TO_PS[unit]
            target_ps = 1e3  # 1ns in picoseconds

            if orig_ps < target_ps:
                # Need to scale up the timescale
                scale = int(round(target_ps / orig_ps))
                new_ts_line = f"{indent}1ns"
            # Exit after first timescale interpretation
            break
        if line.strip() == '$end':
            in_ts = False

    return scale, new_ts_line


def process_vcd(fin, fout):
    """
    @brief Main VCD processing function
    
    @param fin Input file object
    @param fout Output file object
    
    @details
    Processes the VCD file line by line:
    1. Adjusts timescale if necessary
    2. Scales timestamps according to timescale adjustment
    3. Sanitizes signal values (removes X/Z states)
    4. Preserves all other VCD structure and syntax
    """
    lines = fin.read().splitlines()

    # 1) Detect and adjust timescale
    scale, new_ts_line = detect_timescale_scale(lines)

    last_values: Dict[str, str] = {}
    in_header = True
    in_ts = False

    for line in lines:
        # Header processing (before $enddefinitions)
        if in_header:
            # Update timescale if needed
            if line.strip() == '$timescale':
                in_ts = True
                fout.write(line + '\n')
                continue
            if in_ts:
                if new_ts_line is not None and RE_TS.match(line):
                    fout.write(new_ts_line + '\n')
                else:
                    fout.write(line + '\n')
                if line.strip() == '$end':
                    in_ts = False
                # Continue header processing
                if '$enddefinitions' in line:
                    in_header = False
                continue

            fout.write(line + '\n')
            if '$enddefinitions' in line:
                in_header = False
            continue

        # After header: scale timestamps if needed
        m_t = RE_TIME.match(line)
        if m_t and scale != 1:
            t_old = int(m_t.group(1))
            t_new = t_old // scale
            fout.write(f"#{t_new}\n")
            continue

        # VCD commands ($dumpvars, $end, $comment, etc.)
        if line.startswith('$'):
            fout.write(line + '\n')
            continue

        # Timestamps without scaling
        if m_t and scale == 1:
            fout.write(line + '\n')
            continue

        # Scalar value change
        m_s = RE_SCALAR.match(line)
        if m_s:
            val, sig_id = m_s.groups()
            new_val = sanitize_scalar(val, sig_id, last_values)
            fout.write(f"{new_val}{sig_id}\n")
            continue

        # Vector / real value change
        m_v = RE_VECTOR.match(line)
        if m_v:
            bits, sig_id = m_v.groups()
            prefix = line[0]
            new_bits = sanitize_vector(bits, sig_id, last_values)
            if prefix.lower() == 'r':
                prefix = 'b'
            fout.write(f"{prefix}{new_bits} {sig_id}\n")
            continue

        # Everything else (comments, etc.)
        fout.write(line + '\n')


def main():
    """@brief Main entry point for the script"""
    if len(sys.argv) != 3:
        print("Usage: python3 vcd_sanitize_for_pulseview.py input.vcd output.vcd")
        sys.exit(1)

    in_path, out_path = sys.argv[1], sys.argv[2]

    with open(in_path, 'r') as fin, open(out_path, 'w') as fout:
        process_vcd(fin, fout)


if __name__ == '__main__':
    main()
