\page mdio_fsm MDIO PHY Frame Processing State Machine
\ingroup mdio_model

# MDIO PHY Frame Processing State Machine {#mdio_fsm}

This page describes the high-level FSM of the MDIO PHY model.

## FSM State Transitions (auto-generated)

\dotfile mdio_fsm_auto.dot

## FSM (UML / PlantUML)

\startuml
[*] --> IDLE
IDLE --> ST       : preamble OK
ST   --> OP       : ST == 01
OP   --> PHYAD    : valid opcode
PHYAD --> REG_DEV : valid PHY address
REG_DEV --> TA
TA --> DATA
DATA --> IDLE     : frame complete
\enduml
