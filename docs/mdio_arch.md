\page mdio_arch MDIO PHY Internal Architecture
\ingroup mdio_model

# MDIO PHY Internal Architecture {#mdio_arch}

This page provides an overview of the internal architecture of the
`mdio_phy_combined_model` and the testbench tasks that interact with it.

## High-level block diagram

\dot
digraph MDIO_ARCH {
  rankdir=LR;
  node [shape=box, fontsize=10];
  graph [ranksep=0.7, nodesep=0.6];

  subgraph cluster_tb {
    label="Testbench";
    style=rounded;
    color=lightgrey;

    TB_TOP          [label="mdio_phy_combined_model_tb"];
    TB_C22_READ     [label="task mdio_c22_read"];
    TB_C22_WRITE    [label="task mdio_c22_write"];
    TB_C45_ADDR     [label="task mdio_c45_addr"];
    TB_C45_READ     [label="task mdio_c45_read"];
    TB_C45_WRITE    [label="task mdio_c45_write"];
    TB_SUMMARY      [label="task display_test_summary"];
  }

  subgraph cluster_dut {
    label="DUT: mdio_phy_combined_model";
    style=rounded;
    color=lightblue;

    DUT_TOP         [label="module mdio_phy_combined_model"];
    DUT_FSM         [label="FSM\n(state_t / always_ff)"];
    DUT_GET_C22     [label="function get_c22_reg"];
    DUT_GET_C45     [label="function get_c45_reg"];
    DUT_REGMAP_C22  [label="Clause 22\nregister map"];
    DUT_REGMAP_C45  [label="Clause 45\nregister map"];
    DUT_STATS       [label="Error counters\n& statistics"];
  }

  // Testbench flow
  TB_TOP      -> TB_C22_READ;
  TB_TOP      -> TB_C22_WRITE;
  TB_TOP      -> TB_C45_ADDR;
  TB_TOP      -> TB_C45_READ;
  TB_TOP      -> TB_C45_WRITE;
  TB_TOP      -> TB_SUMMARY;

  // TB ↔ DUT interaction (MDIO bus)
  TB_C22_READ  -> DUT_TOP  [label="C22 read frame"];
  TB_C22_WRITE -> DUT_TOP  [label="C22 write frame"];
  TB_C45_ADDR  -> DUT_TOP  [label="C45 addr frame"];
  TB_C45_READ  -> DUT_TOP  [label="C45 read frame"];
  TB_C45_WRITE -> DUT_TOP  [label="C45 write frame"];

  // DUT internals
  DUT_TOP     -> DUT_FSM        [label="decode ST/OP/ADDR"];
  DUT_FSM     -> DUT_GET_C22    [label="C22 access"];
  DUT_FSM     -> DUT_GET_C45    [label="C45 access"];

  DUT_GET_C22 -> DUT_REGMAP_C22;
  DUT_GET_C45 -> DUT_REGMAP_C45;

  DUT_FSM     -> DUT_STATS      [label="update\ncounters"];
  DUT_STATS   -> TB_SUMMARY     [label="report\nstatistics"];
}
\enddot
