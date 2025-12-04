#!/bin/bash

plantuml mdio_phy_architecture.puml
plantuml mdio_c22_read_sequence.puml
plantuml mdio_c22_write_sequence.puml
plantuml mdio_c45_read_sequence.puml
plantuml mdio_c45_write_sequence.puml
dot -Tsvg mdio_phy_fsm.dot -o mdio_phy_fsm.svg
