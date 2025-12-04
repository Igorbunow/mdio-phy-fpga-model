# MDIO PHY Combined Model

This documentation describes a SystemVerilog behavioral model of an MDIO PHY
with support for IEEE 802.3 Clause 22 and Clause 45 management frames, together
with a self-checking testbench.

## Project structure

- **`mdio_phy_combined_model.sv`** – behavioral MDIO PHY model with C22/C45,
  EEE, auto-negotiation and extended register maps.
- **`iverilog/testbench/mdio_phy_combined_model_tb.sv`** – comprehensive,
  self-checking testbench for the PHY model.

## Documentation structure

- \subpage mdio_arch "MDIO PHY Internal Architecture"
- \subpage mdio_fsm  "MDIO PHY Frame Processing State Machine"
- @ref    mdio_model    "MDIO PHY Behavioral Model"
- @ref    mdio_testbench "MDIO PHY Testbench"

## Documentation map

- \subpage mdio_arch "MDIO PHY Internal Architecture"
- \subpage mdio_fsm  "MDIO PHY Frame Processing State Machine"
- @ref    mdio_model "MDIO PHY Behavioral Model API (group)"

## Simulation and verification

The testbench performs:

- register map sanity checks;
- Clause 22 and Clause 45 read/write operations;
- speed and link control through BMCR and PMA registers;
- auto-negotiation behavior;
- negative tests (invalid ST field, bad PHY address, bad DEVAD, short preamble);
- basic FSM coverage reporting.
