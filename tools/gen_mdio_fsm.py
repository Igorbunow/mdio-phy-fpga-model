#!/usr/bin/env python3
"""
@file gen_mdio_fsm.py
@brief MDIO FSM DOT Graph Generator

This script parses a SystemVerilog file containing an MDIO PHY state machine
and generates a DOT graph representation for visualization.

The script performs the following steps:
1. Extracts state enumeration values from typedef enum state_t declarations
2. Analyzes case(state) blocks in always_ff processes to find state transitions
3. Generates a DOT format graph showing the state machine structure

@usage
    python3 gen_mdio_fsm.py <mdio_phy_combined_model.sv>

@note Requires a SystemVerilog file with:
      - typedef enum declaration for state_t
      - always_ff blocks with case(state) statements

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
from pathlib import Path

def main():
    """@brief Main entry point for the script"""
    
    # Check command line arguments
    if len(sys.argv) != 2:
        script_name = Path(sys.argv[0]).name
        print(f"Usage: {script_name} <mdio_phy_combined_model.sv>", 
              file=sys.stderr)
        sys.exit(1)

    sv_path = Path(sys.argv[1])
    
    # Read and preprocess the SystemVerilog file
    text = sv_path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()

    # ---- 1. Extract state enumeration values from typedef enum state_t ----
    states = []
    in_enum = False

    for line in lines:
        if not in_enum:
            # Look for typedef enum ... state_t; pattern
            if re.search(r'\btypedef\s+enum\b', line) and "state_t" in line:
                in_enum = True
            continue

        # Inside enum until closing '}'
        if "}" in line:
            in_enum = False
            continue

        # Extract the first identifier in the line (S_IDLE, S_ST, ...)
        m = re.search(r'\b([A-Za-z_]\w*)\b', line)
        if m:
            states.append(m.group(1))

    # ---- 2. Analyze case(state) blocks in always_ff processes ----
    edges = set()
    in_case = False
    current_state = None

    for line in lines:
        stripped = line.strip()

        if not in_case:
            # Look for case (state) statements
            if re.search(r'\bcase\s*\(\s*state\s*\)', line):
                in_case = True
            continue

        # Inside case (state) block
        if re.match(r'endcase', stripped):
            in_case = False
            current_state = None
            continue

        # State label: S_IDLE:, S_ST:, etc.
        m_state = re.match(r'([A-Za-z_]\w*)\s*:', stripped)
        if m_state:
            current_state = m_state.group(1)
            continue

        # State assignment: state <= S_XXX;
        m_assign = re.search(r'\bstate\s*<=\s*([A-Za-z_]\w*)', line)
        if m_assign and current_state:
            target = m_assign.group(1)
            edges.add((current_state, target))

    # ---- 3. Generate DOT format output ----
    print("digraph MDIO_FSM_AUTO {")
    print("  rankdir=TB;")
    print("  node [shape=ellipse];")
    print("  label=\"MDIO State Machine\";")
    print("  labelloc=\"top\";")
    print("  fontsize=16;")
    print()
    
    # Print all state nodes
    for s in states:
        print(f"  {s};")

    print()
    
    # Print all state transitions
    for src, dst in sorted(edges):
        print(f"  {src} -> {dst};")

    print("}")

if __name__ == '__main__':
    main()
