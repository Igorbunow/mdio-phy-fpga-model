// mdio_phy_combined_model.sv
/**
 * @file mdio_phy_combined_model.sv
 * @brief MDIO PHY Behavioral Model with Clause 22 and Clause 45 Support
 * @author Igor Gorbunov <igor@gorbunov.tel>
 * @details
 * This module implements a comprehensive MDIO PHY behavioral model that supports
 * both Clause 22 and Clause 45 management frames. It includes advanced features
 * such as Energy Efficient Ethernet (EEE), auto-negotiation, and extensive
 * register maps for PMA/PMD, PCS, and Auto-Negotiation components.
 *
 * Key Features:
 * - Configurable PHY addresses and capabilities
 * - Support for 10M/100M/1G/2.5G/5G/10G speeds
 * - Energy Efficient Ethernet (EEE) support
 * - Auto-negotiation with configurable timeout
 * - Vendor-specific device (DEV31) support
 * - Comprehensive error tracking and statistics
 * - Strict IEEE 802.3 compliance option
 *
 * @note Designed for use with Icarus Verilog (-g2012)
 * @version 1.1
 * @date 2025
 * 
 * @copyright
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
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`timescale 1ns/1ps

/**
 * @defgroup mdio_model MDIO PHY Behavioral Model
 * @brief Behavioral MDIO PHY model with Clause 22 and Clause 45 support.
 *
 * This group contains the behavioral PHY model, its parameters,
 * register maps, and internal helper tasks/functions.
 * @{
 */

/**
 * @brief MDIO PHY Combined Model
 * @details
 * Comprehensive MDIO PHY model supporting Clause 22 and Clause 45 operations
 * with configurable features and extensive register mapping.
 */
module mdio_phy_combined_model #(
    // PHY Configuration
    parameter logic [4:0] PHY_ADDR0 = 5'd3,     ///< First valid PHY address
    parameter logic [4:0] PHY_ADDR1 = 5'd5,     ///< Second valid PHY address  
    parameter logic [4:0] PHY_ADDR2 = 5'd7,     ///< Third valid PHY address

    // Feature Enable Parameters
    parameter bit ENABLE_C45        = 1,        ///< Enable Clause 45 functionality
    parameter bit ENABLE_C22        = 1,        ///< Enable Clause 22 functionality
    parameter bit ENABLE_VENDOR_DEV = 1,        ///< Enable vendor-specific device (DEV31)

    // Speed Capability Profile
    parameter bit SUPPORT_10M       = 1,        ///< Support 10Mbps operation
    parameter bit SUPPORT_100M      = 1,        ///< Support 100Mbps operation  
    parameter bit SUPPORT_1G        = 1,        ///< Support 1Gbps operation
    parameter bit SUPPORT_2P5G      = 1,        ///< Support 2.5Gbps operation (Clause 45)
    parameter bit SUPPORT_5G        = 1,        ///< Support 5Gbps operation (Clause 45)
    parameter bit SUPPORT_10G       = 1,        ///< Support 10Gbps operation (Clause 45)

    // Compliance and Advanced Features
    parameter bit STRICT_802_3      = 1,        ///< Enforce strict IEEE 802.3 compliance
    parameter bit SUPPORT_EEE       = 1,        ///< Support Energy Efficient Ethernet

    // MDIO Frame Configuration
    parameter int unsigned MAX_PREAMBLE_LENGTH = 32,  ///< Minimum preamble length requirement
    parameter int unsigned AN_TIMEOUT_CYCLES   = 64   ///< Auto-negotiation timeout in MDC cycles
)(
    // System Interface
    input  logic       clk_sys,        ///< System clock
    input  logic       rst_n,          ///< Active-low reset
    input  logic       mdc,            ///< Management Data Clock
    
    // MDIO Tristate Interface
    input  logic       mdio_i,         ///< MDIO input from bus
    output logic       mdio_o,         ///< MDIO output to bus  
    output logic       mdio_oe,        ///< MDIO output enable
    
    // Link Status Configuration
    input  logic       link_up_i,      ///< Initial link status
    input  logic [1:0] link_speed_i    ///< Initial link speed: 00=10M, 01=100M, 10=1G
);

    
/*
`ifdef SIM
    assign mdio_com_o = (mdio_oe === 1'b1) ? mdio_o :
                            (mdio_oe === 1'b0) ? mdio_i :
                                                 1'bx;
`else
    assign mdio_com_o = mdio_oe ? mdio_o : mdio_i;
`endif
*/
    // --------------------------------------------------------------------
    // State Machine Definitions
    // --------------------------------------------------------------------
    
    /**
     * @page mdio_fsm MDIO Frame Processing State Machine
     * @brief State transitions for MDIO Clause 22/45 frame parsing.
     *
     * @details
     * This diagram shows the high-level state transitions inside
     * the MDIO frame processing FSM of @ref mdio_phy_combined_model.
     *
     * @dot
     * digraph MDIO_FSM {
     *   rankdir=LR;
     *   node [shape=ellipse];

     *   S_IDLE      [label="S_IDLE\nIdle"];
     *   S_ST        [label="S_ST\nStart bits"];
     *   S_OP        [label="S_OP\nOpcode"];
     *   S_PHYAD     [label="S_PHYAD\nPHY address"];
     *   S_REG_DEVAD [label="S_REG_DEVAD\nREG/DEVAD"];
     *   S_TA        [label="S_TA\nTurnaround"];
     *   S_DATA      [label="S_DATA\nData (16 bits)"];

     *   S_IDLE      -> S_ST        [label="preamble OK"];
     *   S_ST        -> S_OP        [label="ST == 01"];
     *   S_OP        -> S_PHYAD     [label="valid OP"];
     *   S_PHYAD     -> S_REG_DEVAD [label="PHY in {3,5,7}"];
     *   S_REG_DEVAD -> S_TA;
     *   S_TA        -> S_DATA;
     *   S_DATA      -> S_IDLE      [label="frame done"];
     * }
     * @enddot
     */
    
    /**
     * @brief MDIO Frame Processing States
     * @details States for parsing MDIO management frames according to IEEE 802.3
     */
    typedef enum logic [2:0] {
        S_IDLE,         ///< Idle state, waiting for frame start
        S_ST,           ///< Start frame detection
        S_OP,           ///< Operation code decoding  
        S_PHYAD,        ///< PHY address field
        S_REG_DEVAD,    ///< Register address (C22) or Device address (C45)
        S_TA,           ///< Turnaround field
        S_DATA          ///< Data field (16 bits)
    } state_t;

    /**
     * @brief MDIO Operation Types
     * @details Supported MDIO operations for both Clause 22 and Clause 45
     */
    typedef enum logic [2:0] {
        OP_NONE,        ///< No operation/invalid
        OP_C22_WRITE,   ///< Clause 22 write operation
        OP_C22_READ,    ///< Clause 22 read operation
        OP_C45_ADDR,    ///< Clause 45 address operation
        OP_C45_WRITE,   ///< Clause 45 write operation  
        OP_C45_READ     ///< Clause 45 read operation
    } op_kind_t;
    
    
    // Operation execution flags
    logic respond_read;               ///< Execute read operation
    logic c22_do_write;               ///< Execute Clause 22 write
    logic c45_do_addr;                ///< Execute Clause 45 address
    logic c45_do_write;               ///< Execute Clause 45 write
    logic cxx_do_read;                ///< Execute Clause 22 read
    logic cxx_do_read_first;          ///< Execute Clause 22 read
    logic cxx_do_read_last;           ///< Execute Clause 22 read


    // --------------------------------------------------------------------
    // Clause 45 Device Address Constants
    // --------------------------------------------------------------------
    
    /** @brief Clause 45 Device Address Constants */
    localparam logic [4:0] DEV_PMA    = 5'd1;   ///< PMA/PMD Device
    localparam logic [4:0] DEV_AN     = 5'd7;   ///< Auto-Negotiation Device
    localparam logic [4:0] DEV_VENDOR = 5'd31;  ///< Vendor-specific Device
    localparam logic [4:0] DEV_PCS    = 5'd3;   ///< PCS Device

    // --------------------------------------------------------------------
    // Internal State Variables
    // --------------------------------------------------------------------
    
    state_t    state;                  ///< Current FSM state
    op_kind_t  op_kind;               ///< Current operation type
    
    logic      frame_is_c45;          ///< Current frame is Clause 45
    logic      frame_preamble_ok;     ///< Preamble validation passed

    // Bit counters for frame parsing
    logic [4:0] bit_cnt;              ///< Bit counter within field
    logic [5:0] preamble_cnt;         ///< Preamble '1' counter

    // Frame field storage
    logic [1:0] st_bits;              ///< Start frame bits
    logic [1:0] op_bits;              ///< Operation code bits
    
    logic [4:0] phy_addr;             ///< Received PHY address
    logic [4:0] phy_addr_shift;       ///< PHY address shift register
    logic [4:0] reg_addr;             ///< Clause 22 register address
    logic [4:0] devad;                ///< Clause 45 device address  
    logic [4:0] reg_dev_shift;        ///< Register/device shift register

    // Address validation flags
    logic       phy_ok;               ///< PHY address is valid
    logic       dev_ok;               ///< Device address is valid

    // Turnaround field
    logic [1:0] ta_bits;              ///< Turnaround bits

    // Data shift registers
    logic [15:0] rx_shift;            ///< Receive data shift register
    logic [15:0] tx_shift;            ///< Transmit data shift register

    // Read data pipeline
    logic [15:0] read_data_preview;   ///< Pre-computed read data
    logic        read_data_is_c45;    ///< Read data is from Clause 45
    
    

    // --------------------------------------------------------------------
    // Link Status Management
    // --------------------------------------------------------------------
    
    /**
     * @brief Link Speed Enumeration
     * @details Supported link speeds for internal management
     */
    typedef enum logic [1:0] {
        LINK_SPEED_10M   = 2'b00,     ///< 10 Mbps operation
        LINK_SPEED_100M  = 2'b01,     ///< 100 Mbps operation  
        LINK_SPEED_1000M = 2'b10      ///< 1000 Mbps operation
    } link_speed_e;

    logic         link_up;            ///< Current link status
    link_speed_e  link_speed;         ///< Current link speed

    // Link status update control signals
    logic         update_link_up;     ///< Strobe to update link_up register
    logic         update_link_speed;  ///< Strobe to update link_speed register
    logic         new_link_up;        ///< New link status value
    link_speed_e  new_link_speed;     ///< New link speed value

    // --------------------------------------------------------------------
    // Clause 22 Register Map and Constants
    // --------------------------------------------------------------------
    
    /**
     * @brief Clause 22 Register Addresses
     * @details Standard register addresses defined in IEEE 802.3 Clause 22
     */
    localparam int C22_REG_BMCR   = 0;   ///< Basic Mode Control Register
    localparam int C22_REG_BMSR   = 1;   ///< Basic Mode Status Register
    localparam int C22_REG_PHYID1 = 2;   ///< PHY Identifier 1
    localparam int C22_REG_PHYID2 = 3;   ///< PHY Identifier 2
    localparam int C22_REG_ANAR   = 4;   ///< Auto-Negotiation Advertisement
    localparam int C22_REG_ANLPAR = 5;   ///< Auto-Negotiation Link Partner Ability
    localparam int C22_REG_ANER   = 6;   ///< Auto-Negotiation Expansion
    localparam int C22_REG_ANNPT  = 7;   ///< Auto-Negotiation Next Page
    localparam int C22_REG_GBCR   = 9;   ///< 1000BASE-T Control Register
    localparam int C22_REG_GBSR   = 10;  ///< 1000BASE-T Status Register  
    localparam int C22_REG_ESR    = 15;  ///< Extended Status Register

    
    //------------------------------------------------------------------------------
    /// \name BMCR (Basic Mode Control Register) bit definitions (Clause 22)
    /// \details
    /// Standard Clause 22 bit assignment:
    ///   - [15] RESET          : Software reset (self-clearing)
    ///   - [14] LOOPBACK       : MII loopback enable
    ///   - [13] SPEED_SELECT   : Speed selection (0 = 10 Mbit/s, 1 = 100 Mbit/s)
    ///   - [12] AN_ENABLE      : Auto-negotiation enable
    ///   - [11] POWER_DOWN     : Power-down mode
    ///   - [10] ISOLATE        : Electrically isolate PHY from MAC
    ///   - [ 9] RESTART_AN     : Restart auto-negotiation (self-clearing)
    ///   - [ 8] DUPLEX_MODE    : Duplex mode (0 = Half, 1 = Full)
    ///   - [ 7] COLLISION_TEST : Collision test mode
    ///   - [ 6:0] Reserved in pure Clause 22 (write as 0, ignore on read)
    ///
    /// Extension for 10/100/1000 PHY emulation:
    ///   - Bit [6] is used as SPEED_SELECT_MSB:
    ///       SPEED[1:0] = { BMCR_SPEED_1000, BMCR_SPEED_SELECT }
    ///         2'b00 -> 10 Mbit/s
    ///         2'b01 -> 100 Mbit/s
    ///         2'b10 -> 1000 Mbit/s
    ///         2'b11 -> reserved / treated as invalid speed combination.
    ///------------------------------------------------------------------------------

    localparam logic [15:0] BMCR_RESET       = 16'h8000; ///< [15] Software reset (self-clearing)
    localparam logic [15:0] BMCR_LOOPBACK    = 16'h4000; ///< [14] Loopback mode enable

    // Clause 22 SPEED_SELECT bit:
    localparam logic [15:0] BMCR_SPEED_SELECT = 16'h2000; ///< [13] SPEED_SELECT (0 = 10 Mbit/s, 1 = 100 Mbit/s)
    localparam logic [15:0] BMCR_SPEED_100    = BMCR_SPEED_SELECT; ///< Alias for SPEED_SELECT = 1 (100 Mbit/s in pure Clause 22)

    localparam logic [15:0] BMCR_AN_ENABLE   = 16'h1000; ///< [12] Auto-negotiation enable
    localparam logic [15:0] BMCR_POWER_DOWN  = 16'h0800; ///< [11] Power-down mode
    localparam logic [15:0] BMCR_ISOLATE     = 16'h0400; ///< [10] Electrical isolate (disconnect PHY from MAC)
    localparam logic [15:0] BMCR_RESTART_AN  = 16'h0200; ///< [ 9] Restart auto-negotiation (self-clearing)
    localparam logic [15:0] BMCR_FULL_DUPLEX = 16'h0100; ///< [ 8] Duplex mode: 1 = Full-duplex
    localparam logic [15:0] BMCR_COLL_TEST   = 16'h0080; ///< [ 7] Collision test mode

    // Extension: bit [6] as SPEED_SELECT_MSB for 1000BASE-T
    localparam logic [15:0] BMCR_SPEED_1000  = 16'h0040; ///< [ 6] SPEED_SELECT_MSB (used with BMCR_SPEED_SELECT to encode 1000 Mbit/s)

    // Reserved bits in pure Clause 22: must be written as 0 and ignored on read.
    localparam logic [15:0] BMCR_RESERVED_5  = 16'h0020; ///< [ 5] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_4  = 16'h0010; ///< [ 4] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_3  = 16'h0008; ///< [ 3] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_2  = 16'h0004; ///< [ 2] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_1  = 16'h0002; ///< [ 1] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_0  = 16'h0001; ///< [ 0] Reserved (write as 0, ignore on read)

    //------------------------------------------------------------------------------
    /// \name BMCR convenience configurations for forced speed/duplex
    /// \details
    /// The SPEED field is interpreted as:
    ///   SPEED[1:0] = { BMCR_SPEED_1000 ? 1 : 0 , BMCR_SPEED_SELECT ? 1 : 0 }
    ///   Valid combinations in this model:
    ///     - 2'b00 -> 10 Mbit/s
    ///     - 2'b01 -> 100 Mbit/s
    ///     - 2'b10 -> 1000 Mbit/s
    ///   2'b11 is reserved and should not be used; if encountered, it may be
    ///   treated as an invalid / implementation-defined speed.
    ///------------------------------------------------------------------------------

    localparam logic [15:0] BMCR_SPEED_10 = 16'h0000; ///< SPEED[1:0] = 2'b00 -> 10 Mbit/s

    localparam logic [15:0] BMCR_10HALF   = BMCR_SPEED_10;                    ///< 10 Mbit/s, Half-duplex
    localparam logic [15:0] BMCR_10FULL   = BMCR_SPEED_10  | BMCR_FULL_DUPLEX;///< 10 Mbit/s, Full-duplex
    localparam logic [15:0] BMCR_100HALF  = BMCR_SPEED_100;                   ///< 100 Mbit/s, Half-duplex
    localparam logic [15:0] BMCR_100FULL  = BMCR_SPEED_100 | BMCR_FULL_DUPLEX;///< 100 Mbit/s, Full-duplex

    // 1000BASE-T mode: SPEED[1:0] = 2'b10 (BMCR_SPEED_1000=1, BMCR_SPEED_SELECT=0)
    localparam logic [15:0] BMCR_1000FULL = BMCR_SPEED_1000 | BMCR_FULL_DUPLEX;///< 1000 Mbit/s, Full-duplex (10/100/1000 extension)


    // BMCR Bit Positions
    localparam int BMCR_BIT_RESET       = 15;
    localparam int BMCR_BIT_LOOPBACK    = 14;
    localparam int BMCR_BIT_SPEED_100   = 13;
    localparam int BMCR_BIT_AN_ENABLE   = 12;
    localparam int BMCR_BIT_POWER_DOWN  = 11;
    localparam int BMCR_BIT_ISOLATE     = 10;
    localparam int BMCR_BIT_RESTART_AN  = 9;
    localparam int BMCR_BIT_FULL_DUPLEX = 8;
    localparam int BMCR_BIT_COLL_TEST   = 7;
    localparam int BMCR_BIT_SPEED_1000  = 6;


    // BMSR Bit Positions
    localparam int BMSR_BIT_LINK_STATUS   = 2;
    localparam int BMSR_BIT_AN_COMPLETE   = 5;
    
    // Capability bits (static profile)
    localparam int BMSR_EXTENDED_STATUS_BIT  = 8;  ///< Extended status capability (ESR at reg 0x0F)
    localparam int BMSR_AN_ABILITY_BIT       = 3;  ///< Auto-negotiation ability
    localparam int BMSR_10BASE_T_FD_BIT      = 12; ///< 10BASE-T full duplex capability
    localparam int BMSR_10BASE_T_HD_BIT      = 11; ///< 10BASE-T half duplex capability
    localparam int BMSR_100BASE_TX_FD_BIT    = 14; ///< 100BASE-TX full duplex capability
    localparam int BMSR_100BASE_TX_HD_BIT    = 13; ///< 100BASE-TX half duplex capability


    /**
     * @brief BMSR Ability Mask
     * @details
     * Statically configured based on PHY capability parameters:
     *   - SUPPORT_10M  -> 10BASE-T FD/HD capability bits
     *   - SUPPORT_100M -> 100BASE-TX FD/HD capability bits
     *   - SUPPORT_1G   -> Extended status bit (ESR present)
     *   - Auto-negotiation ability bit is always set for this model.
     */
    localparam logic [15:0] BMSR_ABILITY_MASK =
        // 10BASE-T capabilities
        (SUPPORT_10M  ? ((16'h1 << BMSR_10BASE_T_FD_BIT) |
                         (16'h1 << BMSR_10BASE_T_HD_BIT)) : 16'h0000) |
        // 100BASE-TX capabilities
        (SUPPORT_100M ? ((16'h1 << BMSR_100BASE_TX_FD_BIT) |
                         (16'h1 << BMSR_100BASE_TX_HD_BIT)) : 16'h0000) |
        // Extended status (ESR) present if 1G supported
        (SUPPORT_1G   ?  (16'h1 << BMSR_EXTENDED_STATUS_BIT) : 16'h0000) |
        // Auto-negotiation ability (always 1 for this model)
        (16'h1 << BMSR_AN_ABILITY_BIT);

    // Extended Status Register Bit Definitions
    localparam logic [15:0] ESR_1000BASE_X_FD = 16'h8000; ///< 1000BASE-X FD ability
    localparam logic [15:0] ESR_1000BASE_X_HD = 16'h4000; ///< 1000BASE-X HD ability  
    localparam logic [15:0] ESR_1000BASE_T_FD = 16'h2000; ///< 1000BASE-T FD ability
    localparam logic [15:0] ESR_1000BASE_T_HD = 16'h1000; ///< 1000BASE-T HD ability

    // 1000BASE-T Control Register Bit Definitions
    localparam logic [15:0] GBCR_ADV_1000BASE_T_FD = 16'h0200; ///< Advertise 1000BASE-T FD
    localparam logic [15:0] GBCR_ADV_1000BASE_T_HD = 16'h0100; ///< Advertise 1000BASE-T HD

    // GBSR Bit Positions
    localparam int GBSR_BIT_LP_1000BASE_T_FD = 9;
    localparam int GBSR_BIT_LP_1000BASE_T_HD = 8;
    localparam int GBSR_BIT_LOCAL_RX_STATUS  = 11;
    localparam int GBSR_BIT_REMOTE_RX_STATUS = 10;

    // Auto-Negotiation Advertisement Register Bit Definitions
    localparam logic [15:0] ANAR_10BASE_T_HD   = 16'h0020; ///< 10BASE-T HD ability
    localparam logic [15:0] ANAR_10BASE_T_FD   = 16'h0040; ///< 10BASE-T FD ability
    localparam logic [15:0] ANAR_100BASE_TX_HD = 16'h0080; ///< 100BASE-TX HD ability
    localparam logic [15:0] ANAR_100BASE_TX_FD = 16'h0100; ///< 100BASE-TX FD ability
    localparam logic [15:0] ANAR_PAUSE_SYM     = 16'h0400; ///< Pause ability
    localparam logic [15:0] ANAR_SELECTOR_IEEE = 16'h0001; ///< IEEE selector field

    // Energy Efficient Ethernet Bit Definitions
    localparam logic [15:0] EEE_ADV_100TX = 16'h0002; ///< 100BASE-TX EEE capability
    localparam logic [15:0] EEE_ADV_1000T = 16'h0004; ///< 1000BASE-T EEE capability

    // Clause 22 register file
    logic [15:0] c22_regs [0:31];

    // --------------------------------------------------------------------
    // Clause 45 Register Maps and Constants
    // --------------------------------------------------------------------
    
    /**
     * @brief PMA/PMD Register Addresses (DEV1)
     * @details PMA/PMD register addresses from IEEE 802.3 Clause 45
     */
    localparam logic [7:0] PMA_REG_CTRL1       = 8'h00; ///< PMA Control 1
    localparam logic [7:0] PMA_REG_STATUS1     = 8'h01; ///< PMA Status 1  
    localparam logic [7:0] PMA_REG_ID1         = 8'h03; ///< PMA Identifier 1
    localparam logic [7:0] PMA_REG_ID2         = 8'h04; ///< PMA Identifier 2
    localparam logic [7:0] PMA_REG_STATUS2     = 8'h08; ///< PMA Status 2
    localparam logic [7:0] PMA_REG_EXT_ABIL    = 8'h0B; ///< PMA Extended Abilities

    // PMA Status 1 Bit Definitions
    localparam logic [15:0] PMA_STATUS1_LINK = 16'h0004; ///< PMA link status
    
    // PMA Status 1 Bit Positions
    localparam int PMA_STATUS1_BIT_LINK = 2;

    // PMA Status 2 Bit Definitions
    localparam logic [15:0] PMA_STATUS2_USE_EXT_ABIL = 16'h0200; ///< Use extended abilities

    // PMA Extended Abilities Bit Definitions
    localparam logic [15:0] PMA_EXT_10BT      = 16'h0100; ///< 10BASE-T ability
    localparam logic [15:0] PMA_EXT_100BTX    = 16'h0080; ///< 100BASE-TX ability
    localparam logic [15:0] PMA_EXT_1000BT    = 16'h0020; ///< 1000BASE-T ability
    localparam logic [15:0] PMA_EXT_10GBT     = 16'h0004; ///< 10GBASE-T ability
    localparam logic [15:0] PMA_EXT_NBT_25_5G = 16'h4000; ///< 2.5G/5G NBT ability

    /**
     * @brief PMA Extended Abilities Profile
     * @details Statically configured based on PHY speed capabilities
     */
    localparam logic [15:0] PMA_EXT_ABIL_PROFILE =
          (SUPPORT_10M   ? PMA_EXT_10BT      : 16'h0000) |
          (SUPPORT_100M  ? PMA_EXT_100BTX    : 16'h0000) |
          (SUPPORT_1G    ? PMA_EXT_1000BT    : 16'h0000) |
          (SUPPORT_10G   ? PMA_EXT_10GBT     : 16'h0000) |
          ((SUPPORT_2P5G || SUPPORT_5G) ? PMA_EXT_NBT_25_5G : 16'h0000);

    // Auto-Negotiation Device Register Addresses
    localparam logic [7:0] AN_REG_CTRL1        = 8'h00; ///< AN Control 1
    localparam logic [7:0] AN_REG_STATUS1      = 8'h01; ///< AN Status 1
    localparam logic [7:0] AN_REG_ADV          = 8'h10; ///< AN Advertisement
    localparam logic [7:0] AN_REG_LP_ADV       = 8'h13; ///< AN Link Partner Advertisement
    localparam logic [7:0] AN_REG_EEE_ADV      = 8'h3C; ///< EEE Advertisement
    localparam logic [7:0] AN_REG_EEE_LP_ADV   = 8'h3D; ///< EEE Link Partner Advertisement

    // Auto-Negotiation Status Register Bit Definitions (DEV7)
    localparam logic [15:0] AN_STATUS1_LP_AN_ABILITY = 16'h0080; ///< Link partner AN ability
    localparam logic [15:0] AN_STATUS1_AN_STATUS     = 16'h0040; ///< Auto-negotiation status
    localparam logic [15:0] AN_STATUS1_AN_ABILITY    = 16'h0020; ///< Local AN ability
    localparam logic [15:0] AN_STATUS1_AN_COMPLETE   = 16'h0004; ///< AN process complete
    localparam logic [15:0] AN_STATUS1_PAGE_RX       = 16'h0002; ///< Page received

    // AN Status 1 Bit Positions
    localparam int AN_STATUS1_BIT_LP_AN_ABILITY = 7;
    localparam int AN_STATUS1_BIT_AN_STATUS     = 6;
    localparam int AN_STATUS1_BIT_AN_ABILITY    = 5;
    localparam int AN_STATUS1_BIT_AN_COMPLETE   = 2;
    localparam int AN_STATUS1_BIT_PAGE_RX       = 1;

    // Vendor Device Register Addresses
    localparam logic [7:0] VENDOR_REG_STATUS   = 8'h01; ///< Vendor Status Register
    localparam logic [7:0] VENDOR_REG_CTRL     = 8'h02; ///< Vendor Control Register

    // Vendor Status Register Bit Positions
    localparam int VENDOR_STATUS_BIT_LINK      = 0;
    localparam int VENDOR_STATUS_BIT_SPEED_MSB = 1;
    localparam int VENDOR_STATUS_BIT_SPEED_LSB = 2;

    // Clause 45 memory blocks with block RAM synthesis guidance (* ram_style = "block" *)
    logic [15:0] c45_dev1   [0:255]; ///< PMA/PMD device memory
    logic [15:0] c45_dev7   [0:255]; ///< AN device memory  
    logic [15:0] c45_dev31  [0:255]; ///< Vendor device memory
    logic [15:0] c45_dev3   [0:255]; ///< PCS device memory

    // Last addressed registers for Clause 45 address phase
    logic [15:0] c45_addr1;           ///< Last PMA/PMD register address
    logic [15:0] c45_addr7;           ///< Last AN register address
    logic [15:0] c45_addr31;          ///< Last vendor register address  
    logic [15:0] c45_addr3;           ///< Last PCS register address

    // --------------------------------------------------------------------
    // Auto-Negotiation Control
    // --------------------------------------------------------------------
    
    logic [15:0] an_timer;            ///< Auto-negotiation timeout counter
    logic        an_in_progress;      ///< Auto-negotiation in progress flag

    // --------------------------------------------------------------------
    // Statistics Counters
    // --------------------------------------------------------------------
    
    logic [31:0] cnt_c22_read_ok;     ///< Successful Clause 22 read operations
    logic [31:0] cnt_c22_write_ok;    ///< Successful Clause 22 write operations
    logic [31:0] cnt_c45_read_ok;     ///< Successful Clause 45 read operations  
    logic [31:0] cnt_c45_write_ok;    ///< Successful Clause 45 write operations
    logic [31:0] cnt_err_short_preamble;  ///< Short preamble errors
    logic [31:0] cnt_err_invalid_st;  ///< Invalid start frame errors
    logic [31:0] cnt_err_bad_phy;     ///< Invalid PHY address errors
    logic [31:0] cnt_err_bad_dev;     ///< Invalid device address errors

    // --------------------------------------------------------------------
    // Field Length Constants
    // --------------------------------------------------------------------
    
    localparam int PREAMBLE_CNT_MAX   = 63;     ///< Maximum preamble counter value
    localparam int PHY_ADDR_WIDTH     = 5;      ///< PHY address field width in bits
    localparam int REG_ADDR_WIDTH     = 5;      ///< Register address field width in bits
    localparam int DEV_ADDR_WIDTH     = 5;      ///< Device address field width in bits
    localparam int TA_FIELD_WIDTH     = 2;      ///< Turnaround field width in bits
    localparam int DATA_FIELD_WIDTH   = 16;     ///< Data field width in bits

    // --------------------------------------------------------------------
    // Operation Code Constants
    // --------------------------------------------------------------------
    
    localparam logic [1:0] OP_C22_WRITE_CODE = 2'b01; ///< Clause 22 write operation code
    localparam logic [1:0] OP_C22_READ_CODE  = 2'b10; ///< Clause 22 read operation code
    localparam logic [1:0] OP_C45_ADDR_CODE  = 2'b00; ///< Clause 45 address operation code
    localparam logic [1:0] OP_C45_WRITE_CODE = 2'b01; ///< Clause 45 write operation code
    localparam logic [1:0] OP_C45_READ_CODE  = 2'b11; ///< Clause 45 read operation code

    // --------------------------------------------------------------------
    // Start Frame Constants
    // --------------------------------------------------------------------
    
    localparam logic [1:0] ST_C22_FRAME = 2'b01; ///< Clause 22 start frame pattern
    localparam logic [1:0] ST_C45_FRAME = 2'b00; ///< Clause 45 start frame pattern

    // --------------------------------------------------------------------
    // Default Register Values
    // --------------------------------------------------------------------
    
    localparam logic [15:0] DEFAULT_PHYID1     = 16'h2000; ///< Default PHY Identifier 1
    localparam logic [15:0] DEFAULT_PHYID2     = 16'h5C90; ///< Default PHY Identifier 2
    localparam logic [15:0] DEFAULT_ANAR       = 16'h01E1; ///< Default AN Advertisement
    localparam logic [15:0] DEFAULT_ANER       = 16'h0001; ///< Default AN Expansion

    // --------------------------------------------------------------------
    // Helper Functions
    // --------------------------------------------------------------------
    
    /**
     * @brief Validate PHY Address
     * @param a PHY address to validate
     * @return 1 if address is valid, 0 otherwise
     * @details Checks if the provided PHY address matches any of the configured valid addresses
     */
    function automatic logic is_valid_phy(input logic [4:0] a);
        begin
            is_valid_phy = (a == PHY_ADDR0) || (a == PHY_ADDR1) || (a == PHY_ADDR2);
        end
    endfunction

    /**
     * @brief Validate Clause 45 Device Address
     * @param d Device address to validate
     * @return 1 if device address is valid and enabled, 0 otherwise
     * @details Checks device address against supported devices and feature enables
     */
    function automatic logic is_valid_c45_dev(input logic [4:0] d);
        begin
            if (!ENABLE_C45) begin
                is_valid_c45_dev = 1'b0;
            end else begin
                unique case (d)
                    DEV_PMA   : is_valid_c45_dev = 1'b1;
                    DEV_PCS   : is_valid_c45_dev = 1'b1;
                    DEV_AN    : is_valid_c45_dev = 1'b1;
                    DEV_VENDOR: is_valid_c45_dev = ENABLE_VENDOR_DEV ? 1'b1 : 1'b0;
                    default   : is_valid_c45_dev = 1'b0;
                endcase
            end
        end
    endfunction

    /**
     * @brief Get Clause 22 Register Value with Dynamic Bits
     * @param addr Register address (0-31)
     * @return Register value with dynamic bits (link status, etc.)
     * @details Handles dynamic bits in BMSR, GBSR that depend on current link status
     * and auto-negotiation state. This ensures status registers reflect actual PHY state.
     */
    function automatic logic [15:0] get_c22_reg(input logic [4:0] addr);
        logic [15:0] r;
        begin
            r = c22_regs[addr];

            // Handle BMSR dynamic bits
            if (addr == C22_REG_BMSR[4:0]) begin
                r |= BMSR_ABILITY_MASK;           // Static capabilities
                r[BMSR_BIT_LINK_STATUS] = link_up; // LINK_STATUS bit
                if (link_up) r[BMSR_BIT_AN_COMPLETE] = 1'b1; // AN complete when link up
            end
            // Handle GBSR dynamic bits
            else if (addr == C22_REG_GBSR[4:0]) begin
                if (SUPPORT_1G) begin
                    r = c22_regs[C22_REG_GBSR];   // Start with stored value
                    // When link is up, assume link partner supports 1000BASE-T FD/HD
                    r[GBSR_BIT_LP_1000BASE_T_FD:GBSR_BIT_LP_1000BASE_T_HD] = link_up ? 2'b11 : 2'b00;
                    r[GBSR_BIT_LOCAL_RX_STATUS]  = link_up; // Local receiver status
                    r[GBSR_BIT_REMOTE_RX_STATUS] = link_up; // Remote receiver status
                end
            end
            get_c22_reg = r;
        end
    endfunction

    /**
     * @brief Get Clause 45 Register Value with Dynamic Bits
     * @param dev Device address
     * @return Register value with dynamic status bits
     * @details Handles dynamic status bits in PMA, PCS, AN, and vendor devices
     * based on current link status and auto-negotiation state.
     */
    function automatic logic [15:0] get_c45_reg(input logic [4:0] dev);
        logic [15:0] r;
        logic [15:0] adv_and_lp;
        begin
            if (!ENABLE_C45) begin
                get_c45_reg = 16'hFFFF;           // Return all ones if C45 disabled
            end else begin
                unique case (dev)
                    DEV_PMA: begin
                        r = c45_dev1[c45_addr1[7:0]];
                        // PMA Status1: dynamic link status
                        if (c45_addr1[7:0] == PMA_REG_STATUS1) begin
                            r = 16'h0000;
                            if (link_up) r[PMA_STATUS1_BIT_LINK] = 1'b1;
                        end
                        get_c45_reg = r;
                    end

                    DEV_PCS: begin
                        r = c45_dev3[c45_addr3[7:0]];
                        // PCS Status1: dynamic link status
                        if (c45_addr3[7:0] == PMA_REG_STATUS1) begin
                            r = 16'h0000;
                            if (link_up) r[PMA_STATUS1_BIT_LINK] = 1'b1; // Link status bit
                        end
                        get_c45_reg = r;
                    end

                    DEV_AN: begin
                        r = c45_dev7[c45_addr7[7:0]];
                        // AN Status1: dynamic auto-negotiation status
                        if (c45_addr7[7:0] == AN_REG_STATUS1) begin
                            r = 16'h0000;
                            r[AN_STATUS1_BIT_AN_ABILITY]    = 1'b1;      // Local AN ability
                            r[AN_STATUS1_BIT_LP_AN_ABILITY] = 1'b1;   // Assume LP AN ability

                            // Check for matching advertised and link partner abilities
                            adv_and_lp = c45_dev7[AN_REG_ADV] & c45_dev7[AN_REG_LP_ADV];

                            if (link_up && (adv_and_lp != 16'h0000)) begin
                                r[AN_STATUS1_BIT_AN_STATUS]   = 1'b1;   // AN successful
                                r[AN_STATUS1_BIT_AN_COMPLETE] = 1'b1; // AN complete
                                r[AN_STATUS1_BIT_PAGE_RX]     = 1'b1;     // Page received
                            end
                        end
                        get_c45_reg = r;
                    end

                    DEV_VENDOR: begin
                        r = c45_dev31[c45_addr31[7:0]];
                        // Vendor status register: dynamic link info
                        if (c45_addr31[7:0] == VENDOR_REG_STATUS) begin
                            r = 16'h0000;
                            r[VENDOR_STATUS_BIT_LINK]    = link_up;           // Link status
                            r[VENDOR_STATUS_BIT_SPEED_LSB:VENDOR_STATUS_BIT_SPEED_MSB] = link_speed; // Link speed
                        end
                        get_c45_reg = r;
                    end

                    default: begin
                        get_c45_reg = 16'hFFFF;           // Invalid device
                    end
                endcase
            end
        end
    endfunction
    
    // --------------------------------------------------------------------
    // Clock Domain Crossing and Input Synchronization
    // --------------------------------------------------------------------
    
    logic [1:0] mdc_sync;             ///< Synchronizer for MDC
    logic [1:0] mdio_i_sync;          ///< Synchronizer for MDIO input
    logic       mdc_rise;             ///< Single-cycle pulse on MDC rising edge in clk_sys domain
    logic       mdio_sample;          ///< Synchronized MDIO input sampled in clk_sys domain
    wire        mdc_fail;
    

    /**
     * @brief Synchronize MDC and MDIO inputs
     * @details Two-stage synchronizer for metastability protection
     */
    always_ff @(posedge clk_sys) begin
        if (!rst_n) begin
            mdc_sync    <= 2'b00;
            mdio_i_sync <= 2'b00;
        end else begin
            mdc_sync    <= {mdc_sync[0], mdc};
            mdio_i_sync <= {mdio_i_sync[0], mdio_i};
        end
    end

    // Detect MDC rising edge and provide stable MDIO sample
    assign mdc_rise    = (mdc_sync == 2'b01); ///< MDC rising edge detection
    assign mdio_sample = mdio_i_sync[1];      ///< Stable MDIO input sample
    assign mdc_fail    = ~mdc_sync[0] & mdc_sync[1]; ///< MDC sync error detection


    wire   mdc_pulse;   ///< MDC pulse signal
    
    reg    mdc_rise_D;  ///< Delayed mdc_rise for edge detection
    assign mdc_pulse   = ~mdc_rise &  mdc_rise_D; ///< MDC pulse generation
    
    
    /**
     * @brief Delay mdc_rise for pulse generation
     */
    always_ff @(posedge clk_sys) begin
        if (!rst_n) begin
            mdc_rise_D    <= 1'b0;
        end else begin
            mdc_rise_D    <= mdc_rise;
        end
    end

    logic mdio_oe_d1; ///< Delayed mdio_oe signal
    
    assign mdio_oe = cxx_do_read; ///< MDIO output enable during read operations

    // --------------------------------------------------------------------
    // Link Status Register Process
    // --------------------------------------------------------------------
    
    /**
     * @brief Link Status Register Update Process
     * @details Separate process for link_up and link_speed registers to avoid
     * Vivado warning 8-7137 about multiple set/reset with same priority.
     * This process provides clear reset priority over update strobes.
     */
    always_ff @(posedge clk_sys) begin
        if (!rst_n) begin
            // Reset has highest priority
            link_up <= link_up_i;
            case (link_speed_i)
                2'b00: link_speed <= LINK_SPEED_10M;
                2'b01: link_speed <= LINK_SPEED_100M;
                default: link_speed <= LINK_SPEED_1000M;
            endcase
        end else begin
            // Update strobes have lower priority than reset
            if (update_link_up) begin
                link_up <= new_link_up;
            end
            if (update_link_speed) begin
                link_speed <= new_link_speed;
            end
        end
    end

    // --------------------------------------------------------------------
    // Main Sequential Logic
    // --------------------------------------------------------------------
    // Includes MDIO FSM, register file management, auto-negotiation timer, and statistics
    
    integer i; ///< Loop variable for initialization

    /**
     * @brief Main sequential process
     * @details Implements MDIO frame processing FSM, register updates,
     * auto-negotiation timer, and statistics collection
     */
    always_ff @(posedge clk_sys) begin
        if (!rst_n) begin
            // Reset all state variables
            state            <= S_IDLE;
            op_kind          <= OP_NONE;
            frame_is_c45     <= 1'b0;
            frame_preamble_ok<= 1'b0;

            bit_cnt          <= 5'd0;
            preamble_cnt     <= 6'd0;

            st_bits          <= 2'b00;
            op_bits          <= 2'b00;

            phy_addr         <= 5'd0;
            phy_addr_shift   <= 5'd0;
            reg_addr         <= 5'd0;
            devad            <= 5'd0;
            reg_dev_shift    <= 5'd0;

            phy_ok           <= 1'b0;
            dev_ok           <= 1'b0;

            ta_bits          <= 2'b00;
            rx_shift         <= 16'h0000;
            tx_shift         <= 16'h0000;

            read_data_preview<= 16'hFFFF;
            read_data_is_c45 <= 1'b0;

            respond_read     <= 1'b0;
            c22_do_write     <= 1'b0;
            c45_do_addr      <= 1'b0;
            c45_do_write     <= 1'b0;
            cxx_do_read      <= 1'b0;
            cxx_do_read_last <= 1'b0;
            cxx_do_read_first<= 1'b0;
            
            

            mdio_o           <= 1'b0;

            c45_addr1        <= 16'h0000;
            c45_addr7        <= 16'h0000;
            c45_addr31       <= 16'h0000;
            c45_addr3        <= 16'h0000;

            // Link status initialization moved to separate process
            update_link_up   <= 1'b0;
            update_link_speed<= 1'b0;
            new_link_up      <= 1'b0;
            new_link_speed   <= LINK_SPEED_10M;

            // Initialize Clause 22 registers
            for (i = 0; i < 32; i = i + 1)
                c22_regs[i] <= 16'h0000;

            // Set Clause 22 register default values
            c22_regs[C22_REG_BMCR]   <= BMCR_AN_ENABLE | BMCR_FULL_DUPLEX | BMCR_SPEED_100;
            c22_regs[C22_REG_BMSR]   <= BMSR_ABILITY_MASK;
            c22_regs[C22_REG_PHYID1] <= DEFAULT_PHYID1;
            c22_regs[C22_REG_PHYID2] <= DEFAULT_PHYID2;
            c22_regs[C22_REG_ANAR]   <= DEFAULT_ANAR;
            c22_regs[C22_REG_ANLPAR] <= 16'h0000;
            c22_regs[C22_REG_ANER]   <= DEFAULT_ANER;
            c22_regs[C22_REG_ANNPT]  <= 16'h0000;
            c22_regs[C22_REG_GBCR]   <= SUPPORT_1G ? (GBCR_ADV_1000BASE_T_FD | GBCR_ADV_1000BASE_T_HD) : 16'h0000;
            c22_regs[C22_REG_GBSR]   <= 16'h0000;
            c22_regs[C22_REG_ESR]    <= SUPPORT_1G ? (ESR_1000BASE_T_FD | ESR_1000BASE_T_HD) : 16'h0000;

            // Initialize Clause 45 memories
            for (i = 0; i < 256; i = i + 1) begin
                c45_dev1[i]   <= 16'h0000;
                c45_dev7[i]   <= 16'h0000;
                c45_dev31[i]  <= 16'h0000;
                c45_dev3[i]   <= 16'h0000;
            end

            // Set PMA/PMD (DEV1) default values
            c45_dev1[PMA_REG_CTRL1]    <= 16'h0000;
            c45_dev1[PMA_REG_STATUS1]  <= 16'h0000;
            c45_dev1[PMA_REG_ID1]      <= DEFAULT_PHYID1;
            c45_dev1[PMA_REG_ID2]      <= DEFAULT_PHYID2;
            c45_dev1[PMA_REG_STATUS2]  <= PMA_STATUS2_USE_EXT_ABIL;
            c45_dev1[PMA_REG_EXT_ABIL] <= PMA_EXT_ABIL_PROFILE;

            // Set PCS (DEV3) default values
            c45_dev3[PMA_REG_ID1]      <= DEFAULT_PHYID1;
            c45_dev3[PMA_REG_ID2]      <= DEFAULT_PHYID2;
            c45_dev3[PMA_REG_CTRL1]    <= 16'h0000;
            c45_dev3[PMA_REG_STATUS1]  <= 16'h0000;

            // Set AN (DEV7) default values
            c45_dev7[AN_REG_CTRL1]     <= 16'h0000;
            c45_dev7[AN_REG_STATUS1]   <= 16'h0000;
            c45_dev7[AN_REG_ADV]       <= DEFAULT_ANAR; // AN Advertisement
            c45_dev7[AN_REG_LP_ADV]    <= 16'h0000;     // AN Link Partner

            // Set EEE registers if supported
            if (SUPPORT_EEE) begin
                c45_dev7[AN_REG_EEE_ADV]    <= EEE_ADV_100TX | EEE_ADV_1000T; // EEE Advertisement
                c45_dev7[AN_REG_EEE_LP_ADV] <= 16'h0000;                      // EEE LP Ability
            end

            // Set Vendor (DEV31) default values
            c45_dev31[VENDOR_REG_CTRL] <= 16'h0000; // Control register

            // Initialize auto-negotiation
            an_timer       <= 16'h0000;
            an_in_progress <= 1'b0;

            // Initialize statistics counters
            cnt_c22_read_ok        <= 32'd0;
            cnt_c22_write_ok       <= 32'd0;
            cnt_c45_read_ok        <= 32'd0;
            cnt_c45_write_ok       <= 32'd0;
            cnt_err_short_preamble <= 32'd0;
            cnt_err_invalid_st     <= 32'd0;
            cnt_err_bad_phy        <= 32'd0;
            cnt_err_bad_dev        <= 32'd0;

        end else begin
            // Default values for update strobes
            update_link_up   <= 1'b0;
            update_link_speed<= 1'b0;
            
            if (mdc_fail) begin
                if (cxx_do_read) begin
                    // Read operation - drive data MSB first
                    mdio_o <= tx_shift[15 - bit_cnt];
                end
                if (cxx_do_read_last) begin
                    cxx_do_read       <= 1'b0;
                    cxx_do_read_last  <= 1'b0;
                    mdio_o            <= 1'b0;
                end
                if (cxx_do_read_first) begin
                    cxx_do_read       <= 1'b1;
                    cxx_do_read_first <= 1'b0;
                end
            end
            if (mdc_rise) begin
                // -------------------------- FSM Implementation --------------------------
                unique case (state)
                    // ----------------------------------------------------
                    // S_IDLE: Preamble Detection
                    // ----------------------------------------------------
                    S_IDLE: begin
                        op_kind          <= OP_NONE;
                        phy_ok           <= 1'b0;
                        dev_ok           <= 1'b0;
                        respond_read     <= 1'b0;
                        c22_do_write     <= 1'b0;
                        c45_do_addr      <= 1'b0;
                        c45_do_write     <= 1'b0;
                        read_data_preview<= 16'hFFFF;
                        read_data_is_c45 <= 1'b0;

                        // Count consecutive '1's as preamble
                        if (mdio_sample == 1'b1) begin
                            if (preamble_cnt != PREAMBLE_CNT_MAX)
                                preamble_cnt <= preamble_cnt + 6'd1;
                        end else begin
                            // Falling edge detected - check preamble length
                            if (preamble_cnt >= MAX_PREAMBLE_LENGTH) begin
                                // Valid preamble detected
                                frame_preamble_ok <= 1'b1;
                                st_bits[1]        <= 1'b0; // First ST bit is 0
                                state             <= S_ST;
                                bit_cnt           <= 5'd0;
                                preamble_cnt      <= 6'd0;
                            end else begin
                                // Short preamble - count as error
                                if (preamble_cnt != 6'd0)
                                    cnt_err_short_preamble <= cnt_err_short_preamble + 32'd1;
                                preamble_cnt      <= 6'd0;
                            end
                        end
                    end

                    // ----------------------------------------------------
                    // S_ST: Start Frame Detection
                    // ----------------------------------------------------
                    S_ST: begin
                        st_bits[0] <= mdio_sample;
                        // Determine frame type based on ST bits
                        if ({st_bits[1], mdio_sample} == ST_C22_FRAME && ENABLE_C22) begin
                            // Clause 22 frame
                            frame_is_c45 <= 1'b0;
                            state        <= S_OP;
                            bit_cnt      <= 5'd0;
                        end else if ({st_bits[1], mdio_sample} == ST_C45_FRAME && ENABLE_C45) begin
                            // Clause 45 frame
                            frame_is_c45 <= 1'b1;
                            state        <= S_OP;
                            bit_cnt      <= 5'd0;
                        end else begin
                            // Invalid ST pattern
                            cnt_err_invalid_st <= cnt_err_invalid_st + 32'd1;
                            state            <= S_IDLE;
                            frame_preamble_ok<= 1'b0;
                            preamble_cnt     <= (mdio_sample == 1'b1) ? 6'd1 : 6'd0;
                        end
                    end

                    // ----------------------------------------------------
                    // S_OP: Operation Code Decoding
                    // ----------------------------------------------------
                    S_OP: begin
                        if (bit_cnt == 5'd0) begin
                            // First OP bit
                            op_bits[1] <= mdio_sample;
                            bit_cnt    <= 5'd1;
                        end else begin
                            // Second OP bit - decode operation
                            logic [1:0] op_tmp;
                            op_kind_t   op_kind_next;
                            op_bits[0]  <= mdio_sample;
                            op_tmp      = {op_bits[1], mdio_sample};
                            op_kind_next = OP_NONE;
                            
                            // Decode operation based on frame type
                            if (!frame_is_c45 && ENABLE_C22) begin
                                // Clause 22: 01=write, 10=read
                                if (op_tmp == OP_C22_WRITE_CODE)
                                    op_kind_next = OP_C22_WRITE;
                                else if (op_tmp == OP_C22_READ_CODE)
                                    op_kind_next = OP_C22_READ;
                            end else if (frame_is_c45 && ENABLE_C45) begin
                                // Clause 45: 00=address, 01=write, 11=read
                                if (op_tmp == OP_C45_ADDR_CODE)
                                    op_kind_next = OP_C45_ADDR;
                                else if (op_tmp == OP_C45_WRITE_CODE)
                                    op_kind_next = OP_C45_WRITE;
                                else if (op_tmp == OP_C45_READ_CODE)
                                    op_kind_next = OP_C45_READ;
                            end

                            op_kind <= op_kind_next;

                            if (op_kind_next == OP_NONE) begin
                                // Invalid operation code
                                state            <= S_IDLE;
                                frame_preamble_ok<= 1'b0;
                                preamble_cnt     <= (mdio_sample == 1'b1) ? 6'd1 : 6'd0;
                            end else begin
                                // Valid operation - proceed to PHY address
                                state   <= S_PHYAD;
                                bit_cnt <= 5'd0;
                                phy_addr_shift <= 5'd0;
                            end
                        end
                    end

                    // ----------------------------------------------------
                    // S_PHYAD: PHY Address Field (5 bits)
                    // ----------------------------------------------------
                    S_PHYAD: begin
                        phy_addr_shift <= {phy_addr_shift[3:0], mdio_sample};
                        if (bit_cnt == (PHY_ADDR_WIDTH - 1)) begin
                            // Complete PHY address received
                            phy_addr <= {phy_addr_shift[3:0], mdio_sample};
                            phy_ok   <= is_valid_phy({phy_addr_shift[3:0], mdio_sample});
                            if (!is_valid_phy({phy_addr_shift[3:0], mdio_sample}) && frame_preamble_ok)
                                cnt_err_bad_phy <= cnt_err_bad_phy + 32'd1;
                            state    <= S_REG_DEVAD;
                            bit_cnt  <= 5'd0;
                            reg_dev_shift <= 5'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    // ----------------------------------------------------
                    // S_REG_DEVAD: Register Address (C22) or Device Address (C45)
                    // ----------------------------------------------------
                    S_REG_DEVAD: begin
                        reg_dev_shift <= {reg_dev_shift[3:0], mdio_sample};
                        if (bit_cnt == (REG_ADDR_WIDTH - 1)) begin                            
                            if (!frame_is_c45) begin
                                // Clause 22: Register Address
                                reg_addr <= {reg_dev_shift[3:0], mdio_sample};
                                devad    <= 5'd0;
                                dev_ok   <= 1'b0;

                                // Set operation flags for Clause 22
                                c22_do_write <= frame_preamble_ok && phy_ok && (op_kind == OP_C22_WRITE);
                                respond_read <= frame_preamble_ok && phy_ok && (op_kind == OP_C22_READ);
                                c45_do_addr  <= 1'b0;
                                c45_do_write <= 1'b0;                                

                                // Pipeline: prepare read data for Clause 22
                                if (frame_preamble_ok && phy_ok && (op_kind == OP_C22_READ) && ENABLE_C22) begin
                                    read_data_preview <= get_c22_reg({reg_dev_shift[3:0], mdio_sample});
                                end else begin
                                    read_data_preview <= 16'hFFFF;
                                end
                                read_data_is_c45 <= 1'b0;

                            end else begin
                                // Clause 45: Device Address
                                logic [4:0] devad_next;
                                logic       dev_ok_next;

                                devad_next  = {reg_dev_shift[3:0], mdio_sample};
                                dev_ok_next = is_valid_c45_dev(devad_next);

                                devad       <= devad_next;
                                dev_ok      <= dev_ok_next;
                                if (!dev_ok_next && frame_preamble_ok)
                                    cnt_err_bad_dev <= cnt_err_bad_dev + 32'd1;

                                // Set operation flags for Clause 45
                                c22_do_write<= 1'b0;
                                c45_do_addr  <= frame_preamble_ok && phy_ok && dev_ok_next && (op_kind == OP_C45_ADDR);
                                c45_do_write <= frame_preamble_ok && phy_ok && dev_ok_next && (op_kind == OP_C45_WRITE);
                                respond_read <= frame_preamble_ok && phy_ok && dev_ok_next && (op_kind == OP_C45_READ);

                                // Pipeline: prepare read data for Clause 45
                                if (frame_preamble_ok && phy_ok && dev_ok_next &&
                                    (op_kind == OP_C45_READ) && ENABLE_C45) begin
                                    read_data_preview <= get_c45_reg(devad_next);
                                end else begin
                                    read_data_preview <= 16'hFFFF;
                                end
                                read_data_is_c45 <= 1'b1;
                            end

                            state   <= S_TA;
                            bit_cnt <= 5'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                        end
                    end

                    // ----------------------------------------------------
                    // S_TA: Turnaround Field (2 bits)
                    // ----------------------------------------------------
                    S_TA: begin
                        if (bit_cnt == 5'd0) begin
                            ta_bits[1] <= mdio_sample; // First TA bit
                            bit_cnt    <= 5'd1;
                            cxx_do_read_first <= respond_read;
                        end else begin
                            ta_bits[0] <= mdio_sample; // Second TA bit
                            if (respond_read) begin
                                // Prepare for read operation - drive MDIO
                                mdio_o  <= 1'b0; // Second TA bit driven as 0 by PHY

                                // Load pre-computed read data
                                tx_shift <= read_data_preview;
                            end

                            state   <= S_DATA;
                            bit_cnt <= 5'd0;
                            rx_shift<= 16'h0000;
                        end
                    end

                    // ----------------------------------------------------
                    // S_DATA: Data Field (16 bits)
                    // ----------------------------------------------------
                    S_DATA: begin
                        if (respond_read) begin
                            // Read operation - drive data MSB first
                            //mdio_o <= tx_shift[15 - bit_cnt];

                            if (bit_cnt == (DATA_FIELD_WIDTH - 1)) begin
                                // Read operation complete - update statistics
                                if (!frame_is_c45) begin
                                    if (phy_ok && frame_preamble_ok)
                                        cnt_c22_read_ok <= cnt_c22_read_ok + 32'd1;
                                end else begin
                                    if (phy_ok && dev_ok && frame_preamble_ok)
                                        cnt_c45_read_ok <= cnt_c45_read_ok + 32'd1;
                                end

                                // Note: mdio_oe remains asserted until returning to IDLE
                                state            <= S_IDLE;
                                frame_preamble_ok<= 1'b0;
                                preamble_cnt     <= 6'd0;
                                bit_cnt          <= 5'd0;
                                cxx_do_read_last <= 1'b1;
                            end else begin
                                bit_cnt <= bit_cnt + 5'd1;
                            end

                        end else begin
                            // Write or Address operation - shift in data
                            rx_shift <= {rx_shift[14:0], mdio_sample};

                            if (bit_cnt == (DATA_FIELD_WIDTH - 1)) begin
                                logic [15:0] full_word;
                                full_word = {rx_shift[14:0], mdio_sample};

                                if (!frame_is_c45) begin
                                    // Clause 22 write operation
                                    if (c22_do_write && phy_ok && frame_preamble_ok && ENABLE_C22) begin
                                        c22_regs[reg_addr] <= full_word;

                                        // Handle BMCR writes that affect link speed - use strobes
                                        if (reg_addr == C22_REG_BMCR[4:0]) begin
                                            update_link_speed <= 1'b1;
                                            unique case ({full_word[BMCR_BIT_SPEED_1000], full_word[BMCR_BIT_SPEED_100]})
                                                2'b00: new_link_speed <= LINK_SPEED_10M;
                                                2'b01: new_link_speed <= LINK_SPEED_100M;
                                                default: new_link_speed <= LINK_SPEED_1000M;
                                            endcase
                                        end

                                        cnt_c22_write_ok <= cnt_c22_write_ok + 32'd1;
                                    end
                                end else begin
                                    // Clause 45 address or write operation
                                    if (phy_ok && dev_ok && frame_preamble_ok && ENABLE_C45) begin
                                        if (c45_do_addr) begin
                                            // Address phase - store register address
                                            unique case (devad)
                                                DEV_PMA   : c45_addr1  <= full_word;
                                                DEV_PCS   : c45_addr3  <= full_word;
                                                DEV_AN    : c45_addr7  <= full_word;
                                                DEV_VENDOR: c45_addr31 <= full_word;
                                                default   : ;
                                            endcase
                                        end else if (c45_do_write) begin
                                            // Write phase - write to register
                                            unique case (devad)
                                                DEV_PMA: begin
                                                    c45_dev1[c45_addr1[7:0]] <= full_word;
                                                    // PMA Control1 can affect link speed - use strobes
                                                    if (c45_addr1[7:0] == PMA_REG_CTRL1) begin
                                                        update_link_speed <= 1'b1;
                                                        unique case ({full_word[BMCR_BIT_SPEED_1000], full_word[BMCR_BIT_SPEED_100]})
                                                            2'b00: new_link_speed <= LINK_SPEED_10M;
                                                            2'b01: new_link_speed <= LINK_SPEED_100M;
                                                            default: new_link_speed <= LINK_SPEED_1000M;
                                                        endcase
                                                    end
                                                end
                                                DEV_AN: begin
                                                    c45_dev7[c45_addr7[7:0]] <= full_word;
                                                    // AN Control register can start auto-negotiation
                                                    if (c45_addr7[7:0] == AN_REG_CTRL1) begin
                                                        if (full_word[9] || full_word[12]) begin
                                                            an_in_progress <= 1'b1;
                                                            an_timer       <= AN_TIMEOUT_CYCLES[15:0];
                                                        end
                                                    end
                                                end
                                                DEV_PCS: begin
                                                    c45_dev3[c45_addr3[7:0]] <= full_word;
                                                end
                                                DEV_VENDOR: begin
                                                    if (ENABLE_VENDOR_DEV) begin
                                                        // Vendor control register can affect link status - use strobes
                                                        if (c45_addr31[7:0] == VENDOR_REG_CTRL) begin
                                                            c45_dev31[VENDOR_REG_CTRL] <= full_word;
                                                            update_link_up   <= 1'b1;
                                                            new_link_up     <= full_word[VENDOR_STATUS_BIT_LINK];
                                                            update_link_speed<= 1'b1;
                                                            unique case (full_word[VENDOR_STATUS_BIT_SPEED_LSB:VENDOR_STATUS_BIT_SPEED_MSB])
                                                                2'b00: new_link_speed <= LINK_SPEED_10M;
                                                                2'b01: new_link_speed <= LINK_SPEED_100M;
                                                                default: new_link_speed <= LINK_SPEED_1000M;
                                                            endcase
                                                        end else begin
                                                            c45_dev31[c45_addr31[7:0]] <= full_word;
                                                        end
                                                    end
                                                end
                                                default: ;
                                            endcase
                                            cnt_c45_write_ok <= cnt_c45_write_ok + 32'd1;
                                        end
                                    end
                                end

                                state            <= S_IDLE;
                                frame_preamble_ok<= 1'b0;
                                preamble_cnt     <= 6'd0;
                                bit_cnt          <= 5'd0;

                            end else begin
                                bit_cnt <= bit_cnt + 5'd1;
                            end
                        end
                    end

                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end //if (mdc_rise) begin
            // -------------------------- Auto-Negotiation Timer --------------------------
            if (an_in_progress) begin
                if (an_timer != 16'h0000) begin
                    an_timer <= an_timer - 16'h0001;
                end else begin
                    // Auto-negotiation complete
                    // Copy advertised abilities to link partner abilities
                    c45_dev7[AN_REG_LP_ADV] <= c45_dev7[AN_REG_ADV];
                    // Copy EEE advertisement to EEE link partner ability if supported
                    if (SUPPORT_EEE) begin
                        c45_dev7[AN_REG_EEE_LP_ADV] <= c45_dev7[AN_REG_EEE_ADV];
                    end
                    an_in_progress  <= 1'b0;
                end
            end
        end
    end
/**
 * @}
 */
endmodule

/** @} */ // end of mdio_model group
`default_nettype none
