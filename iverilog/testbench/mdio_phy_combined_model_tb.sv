// mdio_phy_combined_model_tb.sv
/**
 * @file mdio_phy_combined_model_tb.sv
 * @brief Comprehensive Testbench for MDIO PHY Combined Model
 * @author Igor Gorbunov <igor@gorbunov.tel>
 * @details
 * This testbench verifies the MDIO PHY behavioral model with extensive testing
 * of both Clause 22 and Clause 45 functionality, including advanced features
 * like Energy Efficient Ethernet (EEE), auto-negotiation, and speed control.
 *
 * Test Categories:
 * - Basic register map sanity
 * - PHY capability profiling
 * - Clause 22/45 read/write operations
 * - Speed control via BMCR and PMA
 * - Auto-negotiation simulation
 * - Negative testing (invalid frames, addresses)
 * - Stress testing (random operations, link races)
 * - FSM state and transition coverage
 *
 * @note Designed for Icarus Verilog with SystemVerilog 2012 support (-g2012)
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
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`timescale 1ns/1ps

/**
 * @defgroup mdio_testbench MDIO PHY Testbench
 * @brief Self-checking testbench for the MDIO PHY Combined Model.
 *
 * This group contains the self-checking testbench, MDIO master tasks,
 * randomized and directed tests, statistics and coverage reporting.
 * @{
 */

/**
 * @brief MDIO PHY Combined Model Testbench
 * @details
 * Comprehensive testbench for MDIO PHY model with extensive test coverage
 * including positive, negative, and stress testing scenarios.
 */
module mdio_phy_combined_model_tb;

    // --------------------------------------------------------------------
    // Testbench Signals and Parameters
    // --------------------------------------------------------------------
    
    logic clk_sys;                  ///< System clock for DUT (>100MHz)
    logic rst_n;                    ///< Active-low reset
    logic mdc;                      ///< Management Data Clock (100MHz)

    // Tri-state MDIO bus signals
    wire  mdio;                     ///< Bidirectional MDIO data line
    logic mdio_master_o;            ///< Master MDIO output
    logic mdio_master_oe;           ///< Master MDIO output enable
    logic mdio_phy_o;               ///< PHY MDIO output
    logic mdio_phy_oe;              ///< PHY MDIO output enable

    // Link status configuration
    logic       link_up;            ///< Link status input to DUT */
    logic [1:0] link_speed;         ///< Link speed input to DUT (00=10M, 01=100M, 10=1G) */

    integer errors;                 ///< Global error counter */

    // --------------------------------------------------------------------
    // FSM Coverage Monitoring
    // --------------------------------------------------------------------
    
    logic [2:0] fsm_prev_state;     ///< Previous FSM state for transition tracking
    int         fsm_state_hits [0:7];       ///< Hit counters for each FSM state
    int         fsm_state_trans[0:7][0:7];  ///< Transition counters between states
    int         cov_i, cov_j;               ///< Loop variables for coverage reporting

    // --------------------------------------------------------------------
    // Test Configuration Constants
    // --------------------------------------------------------------------
    
    /** @brief Auto-negotiation timeout cycles (must be >= AN_TIMEOUT_CYCLES in DUT) */
    localparam int AN_TIMEOUT_CYCLES_TB = 80;
    
    /** @brief MDC clock period in nanoseconds */
    localparam real MDC_CLOCK_PERIOD_NS = 10.0;
    
    /** @brief System clock period in nanoseconds */
    localparam real CLK_SYS_PERIOD_NS = 1.0;
    
    /** @brief Reset duration in nanoseconds */
    localparam real RESET_DURATION_NS = 100.0;
    
    /** @brief Test interval between operations in nanoseconds */
    localparam real TEST_INTERVAL_NS = 100.0;
    
    /** @brief Test pack interval in nanoseconds */
    localparam real TEST_PACK_INTERVAL_NS = 100.0;

    // --------------------------------------------------------------------
    // Auto-Negotiation Configuration Constants
    // --------------------------------------------------------------------
    
    localparam logic [15:0] C45_AN_CTRL_ENABLE_RESTART = 16'h1200; ///< AN enable + restart
    localparam logic [15:0] C45_AN_AR_DEFAULT          = 16'h01E1; ///< Default AN Advertisement
    localparam logic [15:0] C45_AN_LPAR_CLEAR          = 16'h0000; ///< Clear Link Partner Ability

    // --------------------------------------------------------------------
    // Device and Register Selection Constants
    // --------------------------------------------------------------------
    
    localparam int MAX_ITERATIONS_RANDOM      = 200;  ///< Maximum iterations for random tests
    localparam int MAX_ITERATIONS_VALID       = 300;  ///< Maximum iterations for valid ops tests
    localparam int MAX_ITERATIONS_LINK_RACE   = 100;  ///< Maximum iterations for link race tests
    localparam int MAX_ITERATIONS_MDIO_READ   = 200;  ///< Maximum iterations for MDIO read tests

    // --------------------------------------------------------------------
    // Stress Test Constants
    // --------------------------------------------------------------------
    
    localparam int STRESS_RANDOM_ITERATIONS  = 200;   ///< Random stress test iterations
    localparam int STRESS_VALID_ITERATIONS   = 300;   ///< Valid operations stress iterations
    localparam int STRESS_LINK_RACE_ITERATIONS = 100; ///< Link race stress iterations
    localparam int STRESS_MONITOR_CYCLES     = 200;   ///< Cycles to monitor for drive activity
    localparam int SHORT_PREAMBLE_LENGTH     = 16;    ///< Short preamble length for negative tests
    localparam int MONITOR_CYCLES_SHORT      = 200;   ///< Monitor cycles for short tests

    // --------------------------------------------------------------------
    // Field Width Constants
    // --------------------------------------------------------------------
    
    localparam int PHY_ADDR_WIDTH     = 5;      ///< PHY address field width in bits
    localparam int REG_ADDR_WIDTH     = 5;      ///< Register address field width in bits
    localparam int DEV_ADDR_WIDTH     = 5;      ///< Device address field width in bits
    localparam int DATA_FIELD_WIDTH   = 16;     ///< Data field width in bits
    localparam int PREAMBLE_LENGTH    = 32;     ///< Standard preamble length

    // --------------------------------------------------------------------
    // PHY Address Constants
    // --------------------------------------------------------------------
    
    localparam logic [4:0] PHY_ADDR_VALID_0   = 5'd3; ///< First valid PHY address
    localparam logic [4:0] PHY_ADDR_VALID_1   = 5'd5; ///< Second valid PHY address
    localparam logic [4:0] PHY_ADDR_VALID_2   = 5'd7; ///< Third valid PHY address
    localparam logic [4:0] PHY_ADDR_INVALID   = 5'd1; ///< Invalid PHY address for negative tests

    // --------------------------------------------------------------------
    // Device Address Constants
    // --------------------------------------------------------------------
    
    localparam logic [4:0] DEV_PMA    = 5'd1;   ///< PMA/PMD Device
    localparam logic [4:0] DEV_AN     = 5'd7;   ///< Auto-Negotiation Device
    localparam logic [4:0] DEV_VENDOR = 5'd31;  ///< Vendor-specific Device
    localparam logic [4:0] DEV_PCS    = 5'd3;   ///< PCS Device

    // --------------------------------------------------------------------
    // Register Address Constants
    // --------------------------------------------------------------------
    
    // Clause 22 Register Addresses
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
    localparam int C22_REG_SCRATCH= 16;  ///< Scratch register for testing

    // Clause 45 Register Addresses
    localparam logic [15:0] C45_REG_PMA_CTRL1    = 16'h0000; ///< PMA Control 1
    localparam logic [15:0] C45_REG_PMA_STATUS1  = 16'h0001; ///< PMA Status 1
    localparam logic [15:0] C45_REG_PMA_ID1      = 16'h0003; ///< PMA Identifier 1
    localparam logic [15:0] C45_REG_PMA_ID2      = 16'h0004; ///< PMA Identifier 2
    localparam logic [15:0] C45_REG_PMA_EXT_ABIL = 16'h000B; ///< PMA Extended Abilities
    localparam logic [15:0] C45_REG_AN_CTRL1     = 16'h0000; ///< AN Control 1
    localparam logic [15:0] C45_REG_AN_STATUS1   = 16'h0001; ///< AN Status 1
    localparam logic [15:0] C45_REG_AN_ADV       = 16'h0010; ///< AN Advertisement
    localparam logic [15:0] C45_REG_AN_LP_ADV    = 16'h0013; ///< AN Link Partner Advertisement
    localparam logic [15:0] C45_REG_EEE_ADV      = 16'h003C; ///< EEE Advertisement
    localparam logic [15:0] C45_REG_EEE_LP_ADV   = 16'h003D; ///< EEE Link Partner Advertisement
    localparam logic [15:0] C45_REG_VENDOR_CTRL  = 16'h0002; ///< Vendor Control Register
    localparam logic [15:0] C45_REG_VENDOR_STATUS= 16'h0001; ///< Vendor Status Register
    localparam logic [15:0] C45_REG_VENDOR_SCRATCH=16'h0000; ///< Vendor Scratch Register

    // --------------------------------------------------------------------
    // Operation Code Constants
    // --------------------------------------------------------------------
    
    localparam logic [1:0] ST_C22_FRAME = 2'b01; ///< Clause 22 start frame pattern
    localparam logic [1:0] ST_C45_FRAME = 2'b00; ///< Clause 45 start frame pattern
    localparam logic [1:0] OP_C22_WRITE_CODE = 2'b01; ///< Clause 22 write operation code
    localparam logic [1:0] OP_C22_READ_CODE  = 2'b10; ///< Clause 22 read operation code
    localparam logic [1:0] OP_C45_ADDR_CODE  = 2'b00; ///< Clause 45 address operation code
    localparam logic [1:0] OP_C45_WRITE_CODE = 2'b01; ///< Clause 45 write operation code
    localparam logic [1:0] OP_C45_READ_CODE  = 2'b11; ///< Clause 45 read operation code

    // --------------------------------------------------------------------
    // Default Register Values
    // --------------------------------------------------------------------
    
    localparam logic [15:0] DEFAULT_PHYID1     = 16'h2000; ///< Default PHY Identifier 1
    localparam logic [15:0] DEFAULT_PHYID2     = 16'h5C90; ///< Default PHY Identifier 2
    localparam logic [15:0] DEFAULT_ANAR       = 16'h01E1; ///< Default AN Advertisement
    localparam logic [15:0] DEFAULT_ANER       = 16'h0001; ///< Default AN Expansion

    // --------------------------------------------------------------------
    // Test Pattern Constants
    // --------------------------------------------------------------------
    
    localparam logic [15:0] TEST_PATTERN_1     = 16'h1234; ///< Test pattern for write/read verification
    localparam logic [15:0] TEST_PATTERN_2     = 16'h55AA; ///< Alternate test pattern
    localparam logic [15:0] TEST_PATTERN_3     = 16'hAA55; ///< Another test pattern
    localparam logic [15:0] TEST_PATTERN_4     = 16'h55AA; ///< Vendor scratch test pattern

    // --------------------------------------------------------------------
    // Link Speed Constants
    // --------------------------------------------------------------------
    
    localparam logic [1:0] LINK_SPEED_10M   = 2'b00; ///< 10 Mbps operation
    localparam logic [1:0] LINK_SPEED_100M  = 2'b01; ///< 100 Mbps operation
    localparam logic [1:0] LINK_SPEED_1000M = 2'b10; ///< 1000 Mbps operation

    // --------------------------------------------------------------------
    // Control Register Bit Masks
    // --------------------------------------------------------------------
    
    localparam logic [15:0] CTRL_LINK_UP     = 16'h0001; ///< Link up control bit
    localparam logic [15:0] CTRL_SPEED_10M   = 16'h0000; ///< 10M speed control
    localparam logic [15:0] CTRL_SPEED_100M  = 16'h0002; ///< 100M speed control
    localparam logic [15:0] CTRL_SPEED_1G    = 16'h0004; ///< 1G speed control
    localparam logic [15:0] CTRL_LINK_1G     = 16'h0005; ///< Link up + 1G speed

    // --------------------------------------------------------------------
    // Status Register Bit Field Constants
    // --------------------------------------------------------------------
    
    // BMSR (Basic Mode Status Register) Bit Definitions
    localparam logic [15:0] BMCR_RESET       = 16'h8000; ///< Software reset
    localparam logic [15:0] BMCR_LOOPBACK    = 16'h4000; ///< Loopback mode
    localparam logic [15:0] BMCR_SPEED_100   = 16'h2000; ///< Speed selection (0=10M, 1=100M)
    localparam logic [15:0] BMCR_AN_ENABLE   = 16'h1000; ///< Auto-negotiation enable
    localparam logic [15:0] BMCR_POWER_DOWN  = 16'h0800; ///< Power down mode
    localparam logic [15:0] BMCR_ISOLATE     = 16'h0400; ///< Electrical isolate
    localparam logic [15:0] BMCR_RESTART_AN  = 16'h0200; ///< Restart auto-negotiation
    localparam logic [15:0] BMCR_FULL_DUPLEX = 16'h0100; ///< Duplex mode (1=Full)
    localparam logic [15:0] BMCR_COLL_TEST   = 16'h0080; ///< Collision test
    localparam logic [15:0] BMCR_SPEED_1000  = 16'h0040; ///< Speed selection for 1G
    localparam logic [15:0] BMCR_RESERVED_5  = 16'h0020; ///< [5] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_4  = 16'h0010; ///< [4] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_3  = 16'h0008; ///< [3] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_2  = 16'h0004; ///< [2] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_1  = 16'h0002; ///< [1] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_RESERVED_0  = 16'h0001; ///< [0] Reserved (write as 0, ignore on read)
    localparam logic [15:0] BMCR_SPEED_10    = 16'h0000; ///< 10Mbps speed (BMCR_SPEED_100=0, BMCR_SPEED_1000=0)
    
    // Common configuration combinations
    localparam logic [15:0] BMCR_10HALF      = BMCR_SPEED_10;                    ///< 10Mbps Half-duplex
    localparam logic [15:0] BMCR_10FULL      = BMCR_SPEED_10 | BMCR_FULL_DUPLEX; ///< 10Mbps Full-duplex
    localparam logic [15:0] BMCR_100HALF     = BMCR_SPEED_100;                   ///< 100Mbps Half-duplex
    localparam logic [15:0] BMCR_100FULL     = BMCR_SPEED_100 | BMCR_FULL_DUPLEX;///< 100Mbps Full-duplex
    localparam logic [15:0] BMCR_1000FULL    = BMCR_SPEED_1000 | BMCR_FULL_DUPLEX;///< 1000Mbps Full-duplex
    
    // BMSR (Basic Mode Status Register) bit positions
    localparam int BMSR_EXTENDED_STATUS_BIT  = 8;  ///< Extended status capability
    localparam int BMSR_AN_ABILITY_BIT       = 3;  ///< Auto-negotiation ability
    localparam int BMSR_LINK_STATUS_BIT      = 2;  ///< Link status
    localparam int BMSR_AN_COMPLETE_BIT      = 5;  ///< Auto-negotiation complete
    
    // BMSR capability bit fields
    localparam int BMSR_10BASE_T_FD_BIT      = 12; ///< 10BASE-T full duplex capability
    localparam int BMSR_10BASE_T_HD_BIT      = 11; ///< 10BASE-T half duplex capability
    localparam int BMSR_100BASE_TX_FD_BIT    = 14; ///< 100BASE-TX full duplex capability
    localparam int BMSR_100BASE_TX_HD_BIT    = 13; ///< 100BASE-TX half duplex capability
    
    // ESR (Extended Status Register) bit fields
    localparam int ESR_1000BASE_T_FD_BIT     = 13; ///< 1000BASE-T full duplex capability
    localparam int ESR_1000BASE_T_HD_BIT     = 12; ///< 1000BASE-T half duplex capability
    
    // GBCR (1000BASE-T Control Register) bit fields
    localparam int GBCR_1000BASE_T_FD_BIT    = 9;  ///< Advertise 1000BASE-T full duplex
    localparam int GBCR_1000BASE_T_HD_BIT    = 8;  ///< Advertise 1000BASE-T half duplex
    
    // GBSR (1000BASE-T Status Register) bit fields
    localparam int GBSR_LP_1000BASE_T_FD_BIT = 9;  ///< Link partner 1000BASE-T FD capability
    localparam int GBSR_LP_1000BASE_T_HD_BIT = 8;  ///< Link partner 1000BASE-T HD capability
    localparam int GBSR_LOCAL_RX_STATUS_BIT  = 11; ///< Local receiver status
    localparam int GBSR_LP_RX_STATUS_BIT     = 10; ///< Link partner receiver status
    
    // PMA Extended Abilities bit fields
    localparam int PMA_EXT_10G_BIT           = 8;  ///< 10G capability
    localparam int PMA_EXT_5G_BIT            = 7;  ///< 5G capability
    localparam int PMA_EXT_2_5G_BIT          = 6;  ///< 2.5G capability
    localparam int PMA_EXT_1000BASE_T_BIT    = 5;  ///< 1000BASE-T capability
    localparam int PMA_EXT_100BASE_TX_BIT    = 2;  ///< 100BASE-TX capability
    localparam int PMA_EXT_NBT_2_5G_5G_BIT   = 14; ///< NBT 2.5G/5G capability
    
    // AN Status Register bit fields
    localparam int AN_STATUS_AN_ABILITY_BIT  = 6;  ///< Auto-negotiation ability
    localparam int AN_STATUS_LINK_PARTNER_ABILITY_BIT = 5; ///< Link partner ability
    localparam int AN_STATUS_AN_COMPLETE_BIT = 2;  ///< Auto-negotiation complete
    localparam int AN_STATUS_PAGE_RECEIVED_BIT = 7; ///< Page received

    // --------------------------------------------------------------------
    // MDIO Bus Wiring
    // --------------------------------------------------------------------
    
    assign mdio = mdio_master_oe ? mdio_master_o : 1'bz;
    assign mdio = mdio_phy_oe    ? mdio_phy_o    : 1'bz;

    // --------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // --------------------------------------------------------------------
    
    mdio_phy_combined_model dut (
        .clk_sys      (clk_sys),
        .rst_n        (rst_n),
        .mdc          (mdc),
        .mdio_i       (mdio),
        .mdio_o       (mdio_phy_o),
        .mdio_oe      (mdio_phy_oe),
        .link_up_i    (link_up),
        .link_speed_i (link_speed)
    );

    // --------------------------------------------------------------------
    // Clock Generation
    // --------------------------------------------------------------------
    
    // System clock generator (>100MHz)
    initial begin
        clk_sys = 1'b0;
        forever #(CLK_SYS_PERIOD_NS/2) clk_sys = ~clk_sys;
    end
    
    /**
     * @brief Generate MDC clock signal
     * @details Creates 100MHz management data clock with 50% duty cycle
     */
    initial begin
        mdc = 1'b0;
        forever #(MDC_CLOCK_PERIOD_NS/2) mdc = ~mdc;
    end

    // --------------------------------------------------------------------
    // MDIO Master Helper Tasks
    // --------------------------------------------------------------------
    
    /**
     * @brief Drive single MDIO bit from master
     * @param val Bit value to drive (0 or 1)
     * @details Data is valid around positive edge of MDC
     */
    task automatic mdio_drive_bit(input logic val);
    begin
        @(negedge mdc);
        mdio_master_o  = val;
        mdio_master_oe = 1'b1;
        @(posedge mdc);
    end
    endtask

    /**
     * @brief Release MDIO line for one bit time
     * @details Tri-states the master output to allow PHY to drive
     */
    task automatic mdio_release_bit();
    begin
        @(negedge mdc);
        mdio_master_oe = 1'b0;
        @(posedge mdc);
    end
    endtask

    /**
     * @brief Send preamble sequence
     * @param n Number of '1' bits to send
     * @details Generates preamble pattern to synchronize PHY
     */
    task automatic mdio_preamble(input int n);
        int i;
    begin
        #(TEST_PACK_INTERVAL_NS)
        for (i = 0; i < n; i++)
            mdio_drive_bit(1'b1);
    end
    endtask

    // --------------------------------------------------------------------
    // Clause 22 Frame Tasks
    // --------------------------------------------------------------------
    
    /**
     * @brief Clause 22 Write Operation
     * @param phy PHY address (5 bits)
     * @param regad Register address (5 bits)  
     * @param data Data to write (16 bits)
     * @details Sends: ST=01, OP=01, PHYAD, REGAD, TA=10, DATA
     */
    task automatic mdio_c22_write(
        input logic [4:0] phy,
        input logic [4:0] regad,
        input logic [15:0] data
    );
        int i;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // ST = 01
        mdio_drive_bit(ST_C22_FRAME[1]);
        mdio_drive_bit(ST_C22_FRAME[0]);

        // OP = 01 (write)
        mdio_drive_bit(OP_C22_WRITE_CODE[1]);
        mdio_drive_bit(OP_C22_WRITE_CODE[0]);

        // PHYAD (5 bits, MSB first)
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // REGAD (5 bits, MSB first)
        for (i = REG_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(regad[i]);

        // TA = 10
        mdio_drive_bit(1'b1);
        mdio_drive_bit(1'b0);

        // DATA (16 bits, MSB first)
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) mdio_drive_bit(data[i]);

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    /**
     * @brief Clause 22 Read Operation
     * @param phy PHY address (5 bits)
     * @param regad Register address (5 bits)
     * @param data Output data read from PHY (16 bits)
     * @details Sends: ST=01, OP=10, PHYAD, REGAD, releases for TA, reads DATA
     */
    task automatic mdio_c22_read(
        input  logic [4:0] phy,
        input  logic [4:0] regad,
        output logic [15:0] data
    );
        int i;
        logic [15:0] tmp;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // ST = 01
        mdio_drive_bit(ST_C22_FRAME[1]);
        mdio_drive_bit(ST_C22_FRAME[0]);

        // OP = 10 (read)
        mdio_drive_bit(OP_C22_READ_CODE[1]);
        mdio_drive_bit(OP_C22_READ_CODE[0]);

        // PHYAD (5 bits, MSB first)
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // REGAD (5 bits, MSB first)
        for (i = REG_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(regad[i]);

        // TA - release for turnaround
        mdio_release_bit();
        mdio_release_bit();

        // DATA from PHY - sample on positive edge after data update at negative edge
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) begin
            @(negedge mdc);
            @(posedge mdc);
            tmp[i] = mdio;
        end

        data = tmp;

        // Master keeps line released
        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    /**
     * @brief Clause 22 Read with Short Preamble (Negative Test)
     * @param phy PHY address (5 bits)
     * @param regad Register address (5 bits) 
     * @param data Output data (should not be driven by PHY)
     * @details Tests PHY behavior with insufficient preamble
     */
    task automatic mdio_c22_read_short_preamble(
        input  logic [4:0] phy,
        input  logic [4:0] regad,
        output logic [15:0] data
    );
        int i;
        logic [15:0] tmp;
    begin
        // Short preamble: only 16 ones (should trigger error)
        mdio_preamble(SHORT_PREAMBLE_LENGTH);

        // ST = 01
        mdio_drive_bit(ST_C22_FRAME[1]);
        mdio_drive_bit(ST_C22_FRAME[0]);

        // OP = 10 (read)
        mdio_drive_bit(OP_C22_READ_CODE[1]);
        mdio_drive_bit(OP_C22_READ_CODE[0]);

        // PHYAD
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // REGAD
        for (i = REG_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(regad[i]);

        // TA
        mdio_release_bit();
        mdio_release_bit();

        // DATA from PHY (expected: no drive due to short preamble)
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) begin
            @(negedge mdc);
            @(posedge mdc);
            tmp[i] = mdio;
        end

        data = tmp;

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    /**
     * @brief Clause 22 Frame with Invalid ST (Negative Test)
     * @param phy PHY address (5 bits)
     * @param regad Register address (5 bits)
     * @param data Output data (should not be driven by PHY)
     * @details Tests PHY behavior with invalid start frame pattern
     */
    task automatic mdio_c22_read_invalid_st(
        input  logic [4:0] phy,
        input  logic [4:0] regad,
        output logic [15:0] data
    );
        int i;
        logic [15:0] tmp;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // INVALID ST = 11 (should trigger error)
        mdio_drive_bit(1'b1);
        mdio_drive_bit(1'b1);

        // OP = 10 (read) - but ST already invalid
        mdio_drive_bit(OP_C22_READ_CODE[1]);
        mdio_drive_bit(OP_C22_READ_CODE[0]);

        // PHYAD
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // REGAD
        for (i = REG_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(regad[i]);

        // TA (still follow protocol on master side)
        mdio_release_bit();
        mdio_release_bit();

        // DATA from PHY (expected: no drive due to invalid ST)
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) begin
            @(negedge mdc);
            @(posedge mdc);
            tmp[i] = mdio;
        end

        data = tmp;

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    // --------------------------------------------------------------------
    // Clause 45 Frame Tasks
    // --------------------------------------------------------------------
    
    /**
     * @brief Clause 45 Address Phase
     * @param phy PHY address (5 bits)
     * @param devad Device address (5 bits)
     * @param addr Register address (16 bits)
     * @details Sends: ST=00, OP=00, PHYAD, DEVAD, TA=10, ADDR
     */
    task automatic mdio_c45_addr(
        input logic [4:0] phy,
        input logic [4:0] devad,
        input logic [15:0] addr
    );
        int i;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // ST = 00
        mdio_drive_bit(ST_C45_FRAME[1]);
        mdio_drive_bit(ST_C45_FRAME[0]);

        // OP = 00 (address)
        mdio_drive_bit(OP_C45_ADDR_CODE[1]);
        mdio_drive_bit(OP_C45_ADDR_CODE[0]);

        // PHYAD (5 bits, MSB first)
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // DEVAD (5 bits, MSB first)
        for (i = DEV_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(devad[i]);

        // TA = 10
        mdio_drive_bit(1'b1);
        mdio_drive_bit(1'b0);

        // Address (16 bits, MSB first)
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) mdio_drive_bit(addr[i]);

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    /**
     * @brief Clause 45 Write Operation
     * @param phy PHY address (5 bits)
     * @param devad Device address (5 bits)
     * @param data Data to write (16 bits)
     * @details Sends: ST=00, OP=01, PHYAD, DEVAD, TA=10, DATA
     */
    task automatic mdio_c45_write(
        input logic [4:0] phy,
        input logic [4:0] devad,
        input logic [15:0] data
    );
        int i;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // ST = 00
        mdio_drive_bit(ST_C45_FRAME[1]);
        mdio_drive_bit(ST_C45_FRAME[0]);

        // OP = 01 (write)
        mdio_drive_bit(OP_C45_WRITE_CODE[1]);
        mdio_drive_bit(OP_C45_WRITE_CODE[0]);

        // PHYAD (5 bits, MSB first)
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // DEVAD (5 bits, MSB first)
        for (i = DEV_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(devad[i]);

        // TA = 10
        mdio_drive_bit(1'b1);
        mdio_drive_bit(1'b0);

        // DATA (16 bits, MSB first)
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) mdio_drive_bit(data[i]);

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    /**
     * @brief Clause 45 Read Operation
     * @param phy PHY address (5 bits)
     * @param devad Device address (5 bits)
     * @param data Output data read from PHY (16 bits)
     * @details Sends: ST=00, OP=11, PHYAD, DEVAD, releases for TA, reads DATA
     */
    task automatic mdio_c45_read(
        input  logic [4:0] phy,
        input  logic [4:0] devad,
        output logic [15:0] data
    );
        int i;
        logic [15:0] tmp;
    begin
        mdio_preamble(PREAMBLE_LENGTH);

        // ST = 00
        mdio_drive_bit(ST_C45_FRAME[1]);
        mdio_drive_bit(ST_C45_FRAME[0]);

        // OP = 11 (read)
        mdio_drive_bit(OP_C45_READ_CODE[1]);
        mdio_drive_bit(OP_C45_READ_CODE[0]);

        // PHYAD (5 bits, MSB first)
        for (i = PHY_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(phy[i]);

        // DEVAD (5 bits, MSB first)
        for (i = DEV_ADDR_WIDTH-1; i >= 0; i--) mdio_drive_bit(devad[i]);

        // TA - release for turnaround
        mdio_release_bit();
        mdio_release_bit();

        // DATA from PHY - sample on positive edge after data update at negative edge
        for (i = DATA_FIELD_WIDTH-1; i >= 0; i--) begin
            @(negedge mdc);
            @(posedge mdc);
            tmp[i] = mdio;
        end

        data = tmp;

        @(negedge mdc);
        mdio_master_oe = 1'b0;
    end
    endtask

    // --------------------------------------------------------------------
    // Test Functions
    // --------------------------------------------------------------------
    
    /**
     * @brief Basic Register Map Sanity Test
     * @details Verifies fundamental C22 and C45 register accessibility and default values
     * Tests: PHY IDs, AN registers, BMSR capabilities, ESR, GBCR
     */
    task automatic test_register_maps_sanity();
        logic [15:0] rd;
        logic [15:0] rd_c45;
    begin
        $display("========== REGISTER MAP SANITY TEST ==========");

        // C22 PHYID1 verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID1, rd);
        if (rd !== DEFAULT_PHYID1) begin
            $display("FAIL: C22 PHYID1: expected 0x%04h, got 0x%04h", DEFAULT_PHYID1, rd);
            errors++;
        end else
            $display("PASS: C22 PHYID1 0x%04h", rd);

        // C22 PHYID2 verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID2, rd);
        if (rd !== DEFAULT_PHYID2) begin
            $display("FAIL: C22 PHYID2: expected 0x%04h, got 0x%04h", DEFAULT_PHYID2, rd);
            errors++;
        end else
            $display("PASS: C22 PHYID2 0x%04h", rd);

        // C22 ANAR verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_ANAR, rd);
        if (rd !== DEFAULT_ANAR) begin
            $display("FAIL: C22 ANAR: expected 0x%04h, got 0x%04h", DEFAULT_ANAR, rd);
            errors++;
        end else
            $display("PASS: C22 ANAR");

        // C22 BMSR capability bits verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
        if (rd[BMSR_EXTENDED_STATUS_BIT] !== 1'b1 || rd[BMSR_AN_ABILITY_BIT] !== 1'b1) begin
            $display("FAIL: C22 BMSR caps: expected ext_status=1, an_ability=1, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: C22 BMSR caps (ext_status & an_ability)");

        // C22 ESR 1000BASE-T capability verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_ESR, rd);
        if (rd[ESR_1000BASE_T_FD_BIT:ESR_1000BASE_T_HD_BIT] !== 2'b11) begin
            $display("FAIL: C22 ESR: expected 1000BASE-T FD/HD bits=2'b11, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: C22 ESR 1000BASE-T FD/HD");

        // C22 GBCR 1000BASE-T advertisement verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_GBCR, rd);
        if (rd[GBCR_1000BASE_T_FD_BIT:GBCR_1000BASE_T_HD_BIT] !== 2'b11) begin
            $display("FAIL: C22 GBCR: expected advertise 1000BASE-T FD/HD (bits[9:8]=2'b11), got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: C22 GBCR advertise 1000BASE-T FD/HD");

        // C45 PMA ID1 verification
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_PMA, rd);
        if (rd !== DEFAULT_PHYID1) begin
            $display("FAIL: C45 PMA ID1: expected 0x%04h, got 0x%04h", DEFAULT_PHYID1, rd);
            errors++;
        end else
            $display("PASS: C45 PMA ID1");

        // C45 PMA ID2 verification
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID2);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_PMA, rd);
        if (rd !== DEFAULT_PHYID2) begin
            $display("FAIL: C45 PMA ID2: expected 0x%04h, got 0x%04h", DEFAULT_PHYID2, rd);
            errors++;
        end else
            $display("PASS: C45 PMA ID2");

        // C45 AN Advertisement consistency with C22 ANAR
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_AN, rd_c45);
        if (rd_c45 !== DEFAULT_ANAR) begin
            $display("FAIL: C45 AN Advertised: expected 0x%04h (match C22 ANAR), got 0x%04h", DEFAULT_ANAR, rd_c45);
            errors++;
        end else
            $display("PASS: C45 AN Advertised matches C22 ANAR");
    end
    endtask

    /**
     * @brief PCS Status Test
     * @details Verifies PCS (DEV3) status register reflects link status changes
     */
    task automatic test_pcs_status();
        logic [15:0] rd;
    begin
        $display("========== C45 PCS STATUS TEST ==========");

        // Set link_up=1 via DEV31 control register
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G); // link_up=1, speed=1G

        // Verify PCS Status1 reflects link_up
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PCS, C45_REG_PMA_STATUS1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_PCS, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b1) begin
            $display("FAIL: PCS Status1[2] expected 1 (link_up), got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: PCS Status1 link_up=1");

        // Test link_down scenario
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, 16'h0000); // link_up=0
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PCS, C45_REG_PMA_STATUS1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_PCS, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b0) begin
            $display("FAIL: PCS Status1[2] after link_down expected 0, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: PCS Status1 link_up=0");

        // Restore link for subsequent tests
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G); // link_up=1, speed=1G
    end
    endtask

    /**
     * @brief Energy Efficient Ethernet (EEE) Capability Test
     * @details Verifies EEE advertisement and link partner ability synchronization
     */
    task automatic test_eee_caps();
        logic [15:0] rd_adv;
        logic [15:0] rd_lp;
    begin
        $display("========== C45 EEE CAPABILITY TEST ==========");

        // Read EEE Advertisement (DEV7, 0x3C)
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_EEE_ADV);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_AN, rd_adv);
        if (rd_adv[2:1] !== 2'b11) begin
            $display("FAIL: EEE Advertisement bits[2:1] expected 2'b11 (100TX+1000T), got 0x%04h", rd_adv);
            errors++;
        end else
            $display("PASS: EEE Advertisement 100TX+1000T");

        // Configure auto-negotiation
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_AR_DEFAULT); // ANAR
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_LP_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_LPAR_CLEAR); // ANLPAR=0 before autoneg

        // Start auto-negotiation
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_CTRL1);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_CTRL_ENABLE_RESTART); // AN enable + restart

        // Wait for auto-negotiation completion
        repeat (AN_TIMEOUT_CYCLES_TB) @(posedge mdc);

        // Verify EEE LP Ability matches Advertisement after autoneg
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_EEE_LP_ADV);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_AN, rd_lp);
        if (rd_lp !== rd_adv) begin
            $display("FAIL: EEE LP Ability expected 0x%04h, got 0x%04h", rd_adv, rd_lp);
            errors++;
        end else
            $display("PASS: EEE LP Ability matches EEE Advertisement after autoneg");
    end
    endtask

    /**
     * @brief PHY Capability Bits Profile Test
     * @details Verifies BMSR, ESR, GBCR, GBSR, and PMA Extended Abilities reflect configured capabilities
     */
    task automatic test_capability_bits_profile();
        logic [15:0] rd;
    begin
        $display("========== PHY CAPABILITY BITS PROFILE TEST ==========");

        // BMSR 10BASE-T capability verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
        if (rd[BMSR_10BASE_T_FD_BIT] !== 1'b1 || rd[BMSR_10BASE_T_HD_BIT] !== 1'b1) begin
            $display("FAIL: BMSR 10BASE-T FD/HD bits expected 1, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: BMSR 10BASE-T FD/HD capability");

        // BMSR 100BASE-X capability verification
        if (rd[BMSR_100BASE_TX_FD_BIT] !== 1'b1 || rd[BMSR_100BASE_TX_HD_BIT] !== 1'b1) begin
            $display("FAIL: BMSR 100BASE-X FD/HD bits expected 1, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: BMSR 100BASE-X FD/HD capability");

        // BMSR extended status and auto-negotiation capability
        if (rd[BMSR_EXTENDED_STATUS_BIT] !== 1'b1 || rd[BMSR_AN_ABILITY_BIT] !== 1'b1) begin
            $display("FAIL: BMSR ext_status/an_able expected 1, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: BMSR ext_status & an_able bits");

        // ESR 1000BASE-T capability verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_ESR, rd);
        if (rd[ESR_1000BASE_T_FD_BIT:ESR_1000BASE_T_HD_BIT] !== 2'b11) begin
            $display("FAIL: ESR 1000BASE-T FD/HD bits expected 2'b11, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: ESR 1000BASE-T FD/HD capability");

        // GBCR 1000BASE-T advertisement verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_GBCR, rd);
        if (rd[GBCR_1000BASE_T_FD_BIT:GBCR_1000BASE_T_HD_BIT] !== 2'b11) begin
            $display("FAIL: GBCR advertise 1000BASE-T FD/HD (bits[9:8]=2'b11), got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: GBCR advertise 1000BASE-T FD/HD");

        // GBSR 1000BASE-T status verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_GBSR, rd);
        if (rd[GBSR_LP_1000BASE_T_FD_BIT:GBSR_LP_1000BASE_T_HD_BIT] !== 2'b11 || 
            rd[GBSR_LOCAL_RX_STATUS_BIT] !== 1'b1 || rd[GBSR_LP_RX_STATUS_BIT] !== 1'b1) begin
            $display("FAIL: GBSR 1000BASE-T status (LP cap & RX OK) expected bits[11:8]=4'b1111, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: GBSR 1000BASE-T status (LP cap & RX OK)");

        // PMA Extended Abilities verification
        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_EXT_ABIL);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, rd);
        if (rd[PMA_EXT_10G_BIT] !== 1'b1 || rd[PMA_EXT_5G_BIT] !== 1'b1 || 
            rd[PMA_EXT_1000BASE_T_BIT] !== 1'b1 || rd[PMA_EXT_100BASE_TX_BIT] !== 1'b1) begin
            $display("FAIL: PMA ExtAbil (1.11) 10/100/1000/10G bits mismatch, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: PMA ExtAbil (1.11) 10/100/1000/10G ability bits");

        // 2.5G/5G NBT ability verification
        if (rd[PMA_EXT_NBT_2_5G_5G_BIT] !== 1'b1) begin
            $display("FAIL: PMA ExtAbil (1.11.14) NBT 2.5/5G ability bit expected 1, got 0x%04h", rd);
            errors++;
        end else
            $display("PASS: PMA ExtAbil (1.11.14) NBT 2.5/5G ability bit");
    end
    endtask

    /**
     * @brief Clause 22 BMCR/BMSR Read/Write Test
     * @details Tests BMCR register accessibility and BMSR status reflection
     */
    task automatic test_c22_bmcr_bmsr();
        logic [15:0] rd;
    begin
        $display("========== C22 BMCR/BMSR TEST ==========");

        // BMCR read/write test
        mdio_c22_write(PHY_ADDR_VALID_0, C22_REG_BMCR, TEST_PATTERN_1);
        mdio_c22_read (PHY_ADDR_VALID_0, C22_REG_BMCR, rd);
        if (rd !== TEST_PATTERN_1) begin
            $display("FAIL: C22 BMCR R/W: expected 0x%04h, got 0x%04h", TEST_PATTERN_1, rd);
            errors++;
        end else
            $display("PASS: C22 BMCR R/W");

        // BMSR link and auto-negotiation status verification
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b1 || rd[BMSR_AN_COMPLETE_BIT] !== 1'b1) begin
            $display("FAIL: C22 BMSR status: expected link_up=1, AN_COMPLETE=1, got link=%0d, an_comp=%0d",
                     rd[BMSR_LINK_STATUS_BIT], rd[BMSR_AN_COMPLETE_BIT]);
            errors++;
        end else
            $display("PASS: C22 BMSR link/an_complete");
    end
    endtask

    /**
     * @brief Clause 45 DEV31 Read/Write Test
     * @details Tests vendor-specific device register accessibility
     */
    task automatic test_c45_dev31_rw();
        logic [15:0] rd;
    begin
        $display("========== C45 DEV31 R/W TEST ==========");

        mdio_c45_addr (PHY_ADDR_VALID_1, DEV_VENDOR, C45_REG_VENDOR_SCRATCH);
        mdio_c45_write(PHY_ADDR_VALID_1, DEV_VENDOR, TEST_PATTERN_4);

        mdio_c45_addr (PHY_ADDR_VALID_1, DEV_VENDOR, C45_REG_VENDOR_SCRATCH);
        mdio_c45_read (PHY_ADDR_VALID_1, DEV_VENDOR, rd);
        if (rd !== TEST_PATTERN_4) begin
            $display("FAIL: C45 DEV31[0x0000] R/W: expected 0x%04h, got 0x%04h", TEST_PATTERN_4, rd);
            errors++;
        end else
            $display("PASS: C45 DEV31[0x0000] R/W");
    end
    endtask

    /**
     * @brief Link Status and Speed Control via DEV31 Test
     * @details Tests link status and speed control through vendor device registers
     */
    task automatic test_link_status_speed_via_dev31();
        logic [15:0] rd;
    begin
        $display("========== C45 DEV31 LINK STATUS/SPEED CONTROL TEST ==========");

        // Set link_up=1, speed=1G via DEV31 control register
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_2, DEV_VENDOR, CTRL_LINK_1G);

        // Verify BMSR reflects the changes
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b1 || rd[BMSR_AN_COMPLETE_BIT] !== 1'b1) begin
            $display("FAIL: DEV31 ctrl -> BMSR: expected link=1, AN_COMPLETE=1, got link=%0d an_comp=%0d",
                     rd[BMSR_LINK_STATUS_BIT], rd[BMSR_AN_COMPLETE_BIT]);
            errors++;
        end else
            $display("PASS: DEV31 ctrl -> BMSR");

        // Verify DEV31 status register
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[0] !== 1'b1 || rd[2:1] !== 2'b10) begin
            $display("FAIL: DEV31[1]: expected link_up=1 speed=10b, got link_up=%0d speed=%0d",
                     rd[0], rd[2:1]);
            errors++;
        end else
            $display("PASS: DEV31[1] after ctrl");

        // Test link_down scenario
        mdio_c45_addr (PHY_ADDR_VALID_1, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_1, DEV_VENDOR, 16'h0000);

        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b0) begin
            $display("FAIL: DEV31 ctrl -> BMSR: link should be 0, got %0d", rd[BMSR_LINK_STATUS_BIT]);
            errors++;
        end else
            $display("PASS: DEV31 ctrl -> BMSR link_down");

        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[0] !== 1'b0 || rd[2:1] !== 2'b00) begin
            $display("FAIL: DEV31[1] after ctrl=0: expected link_down 10M, got link_up=%0d speed=%0d",
                     rd[0], rd[2:1]);
            errors++;
        end else
            $display("PASS: DEV31[1] after ctrl=0");
    end
    endtask

    /**
     * @brief Speed Control via C22 BMCR Test
     * @details Tests speed configuration through Clause 22 BMCR register
     */
    task automatic test_speed_control_bmcr();
        logic [15:0] rd;
    begin
        $display("========== SPEED CONTROL VIA C22 BMCR ==========");

        // Set baseline: link_up=1, 1G
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G);

        // Test 10M speed configuration
        mdio_c22_write(PHY_ADDR_VALID_0, C22_REG_BMCR, BMCR_SPEED_10);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_10M) begin
            $display("FAIL: BMCR speed 10M: expected 00, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: BMCR speed -> 10M");

        // Test 100M speed configuration
        mdio_c22_write(PHY_ADDR_VALID_0, C22_REG_BMCR, BMCR_SPEED_100);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_100M) begin
            $display("FAIL: BMCR speed 100M: expected 01, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: BMCR speed -> 100M");

        // Test 1G speed configuration
        mdio_c22_write(PHY_ADDR_VALID_0, C22_REG_BMCR, BMCR_SPEED_1000);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_1000M) begin
            $display("FAIL: BMCR speed 1G: expected 10, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: BMCR speed -> 1G");
    end
    endtask

    /**
     * @brief Speed Control via C45 PMA Control Test
     * @details Tests speed configuration through Clause 45 PMA Control register
     */
    task automatic test_speed_control_pma();
        logic [15:0] rd;
    begin
        $display("========== SPEED CONTROL VIA C45 PMA CONTROL1 ==========");

        // Set baseline: link_up=1, 1G
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G);

        // Test 10M speed configuration
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_CTRL1);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_PMA, BMCR_SPEED_10);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_10M) begin
            $display("FAIL: PMA speed 10M: expected 00, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: PMA speed -> 10M");

        // Test 100M speed configuration
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_CTRL1);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_PMA, BMCR_SPEED_100);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_100M) begin
            $display("FAIL: PMA speed 100M: expected 01, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: PMA speed -> 100M");

        // Test 1G speed configuration
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_CTRL1);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_PMA, BMCR_SPEED_1000);
        mdio_c45_addr (PHY_ADDR_VALID_2, DEV_VENDOR, C45_REG_VENDOR_STATUS);
        mdio_c45_read (PHY_ADDR_VALID_2, DEV_VENDOR, rd);
        if (rd[2:1] !== LINK_SPEED_1000M) begin
            $display("FAIL: PMA speed 1G: expected 10, got %0d", rd[2:1]);
            errors++;
        end else
            $display("PASS: PMA speed -> 1G");
    end
    endtask

    /**
     * @brief Clause 45 PMA and AN Status Test
     * @details Verifies PMA and Auto-Negotiation status register behavior
     */
    task automatic test_c45_pma_an_status();
        logic [15:0] rd;
    begin
        $display("========== C45 PMA/AN STATUS TEST ==========");

        // Set baseline: link_up=1, speed=1G
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G);

        // Verify PMA Status1 link status
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_STATUS1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_PMA, rd);
        if (rd[BMSR_LINK_STATUS_BIT] !== 1'b1) begin
            $display("FAIL: PMA Status1[2] expected 1, got %0d", rd[BMSR_LINK_STATUS_BIT]);
            errors++;
        end else
            $display("PASS: PMA Status1 link_up=1");

        // Configure matching ANAR and ANLPAR
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_AR_DEFAULT);
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_LP_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_AR_DEFAULT);

        // Verify AN Status1 reflects matched abilities
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_STATUS1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_AN, rd);
        if (rd[AN_STATUS_AN_ABILITY_BIT] !== 1'b1 || rd[AN_STATUS_LINK_PARTNER_ABILITY_BIT] !== 1'b1 || 
            rd[AN_STATUS_PAGE_RECEIVED_BIT] !== 1'b1 || rd[AN_STATUS_AN_COMPLETE_BIT] !== 1'b1) begin
            $display("FAIL: AN Status1: expected AN_STATUS=1, AN_ABILITY=1, LP_ABILITY=1, AN_COMPLETE=1, got [%b]",
                     rd);
            errors++;
        end else
            $display("PASS: AN Status1 link & ability matched");
    end
    endtask

    /**
     * @brief Clause 45 Auto-Negotiation Simulation Test
     * @details Tests complete auto-negotiation process with timeout
     */
    task automatic test_c45_an_autoneg();
        logic [15:0] rd;
    begin
        $display("========== C45 AN AUTONEG SIMULATION TEST ==========");

        // Set baseline: link_up=1, speed=1G
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_VENDOR, C45_REG_VENDOR_CTRL);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_VENDOR, CTRL_LINK_1G);

        // Configure AN Advertisement and clear Link Partner Ability
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_AR_DEFAULT);
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_LP_ADV);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_LPAR_CLEAR);

        // Start auto-negotiation
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_CTRL1);
        mdio_c45_write(PHY_ADDR_VALID_0, DEV_AN, C45_AN_CTRL_ENABLE_RESTART); // AN enable + restart

        // Wait for auto-negotiation completion
        repeat (AN_TIMEOUT_CYCLES_TB) @(posedge mdc);

        // Verify AN Status1 after auto-negotiation
        mdio_c45_addr (PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_STATUS1);
        mdio_c45_read (PHY_ADDR_VALID_0, DEV_AN, rd);
        if (rd[AN_STATUS_AN_ABILITY_BIT] !== 1'b1 || rd[AN_STATUS_AN_COMPLETE_BIT] !== 1'b1) begin
            $display("FAIL: AN Status1 after autoneg: expected AN_STATUS=1, AN_COMPLETE=1, got [%b]", rd);
            errors++;
        end else
            $display("PASS: AN Status1 after autoneg");
    end
    endtask

    // --------------------------------------------------------------------
    // Stress and Negative Test Functions
    // --------------------------------------------------------------------
    
    /**
     * @brief Random Noise Stress Test
     * @details Tests PHY resilience to random bus noise and invalid frames
     */
    task automatic test_random_stress();
        int iter;
        logic saw_drive;
        int k;
        logic [15:0] snap_c22_id1_before, snap_c22_id1_after;
        logic [15:0] snap_c22_id2_before, snap_c22_id2_after;
        logic [15:0] snap_esr_before,     snap_esr_after;
        logic [15:0] snap_pma_id1_before, snap_pma_id1_after;
        logic [15:0] snap_pma_id2_before, snap_pma_id2_after;
        logic [15:0] snap_ext_before,     snap_ext_after;
        logic [15:0] snap_anadv_before,   snap_anadv_after;
    begin
        $display("========== RANDOM/NOISE STRESS TEST ==========");

        // Take pre-stress snapshots of critical registers
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID1,  snap_c22_id1_before);
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID2,  snap_c22_id2_before);
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_ESR,     snap_esr_before);

        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID1);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_pma_id1_before);
        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID2);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_pma_id2_before);
        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_EXT_ABIL);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_ext_before);

        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_AN, snap_anadv_before);

        // Generate random noise frames
        for (iter = 0; iter < STRESS_RANDOM_ITERATIONS; iter++) begin
            int noise_len = $urandom_range(32, 256);
            saw_drive = 1'b0;

            fork
                // Monitor PHY drive activity
                begin
                    for (k = 0; k < noise_len*2; k++) begin
                        @(posedge mdc);
                        if (mdio_phy_oe)
                            saw_drive = 1'b1;
                    end
                end

                // Generate random bus noise
                begin
                    int j;
                    for (j = 0; j < noise_len; j++) begin
                        @(negedge mdc);

                        case ($urandom_range(0,2))
                            0: begin
                                // Release bus
                                mdio_master_oe = 1'b0;
                            end

                            1: begin
                                // Drive random bit
                                mdio_master_oe = 1'b1;
                                mdio_master_o  = $urandom_range(0,1);
                            end

                            2: begin
                                // Generate glitch (2-3 bits)
                                mdio_master_oe = 1'b1;
                                mdio_master_o  = $urandom;
                                @(negedge mdc);
                                mdio_master_o  = $urandom;
                                @(negedge mdc);
                                mdio_master_oe = 1'b0;
                            end
                        endcase
                    end
                    mdio_master_oe = 1'b0;
                end
            join

            // Verify PHY never drives during noise
            if (saw_drive) begin
                $display("FAIL: RANDOM: PHY drove MDIO line during noise frame %0d", iter);
                errors++;
            end
        end

        // Take post-stress snapshots
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID1,  snap_c22_id1_after);
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_PHYID2,  snap_c22_id2_after);
        mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_ESR,     snap_esr_after);

        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID1);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_pma_id1_after);
        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_ID2);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_pma_id2_after);
        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_EXT_ABIL);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, snap_ext_after);

        mdio_c45_addr(PHY_ADDR_VALID_0, DEV_AN, C45_REG_AN_ADV);
        mdio_c45_read(PHY_ADDR_VALID_0, DEV_AN, snap_anadv_after);

        // Verify register integrity after stress
        if (snap_c22_id1_after !== snap_c22_id1_before ||
            snap_c22_id2_after !== snap_c22_id2_before ||
            snap_esr_after     !== snap_esr_before) begin
            $display("FAIL: RANDOM: C22 ID/ESR registers corrupted");
            errors++;
        end else
            $display("PASS: RANDOM: C22 ID/ESR registers intact");

        if (snap_pma_id1_after !== snap_pma_id1_before ||
            snap_pma_id2_after !== snap_pma_id2_before ||
            snap_ext_after     !== snap_ext_before) begin
            $display("FAIL: RANDOM: C45 PMA ID/ExtAbil registers corrupted");
            errors++;
        end else
            $display("PASS: RANDOM: C45 PMA ID/ExtAbil registers intact");

        if (snap_anadv_after !== snap_anadv_before) begin
            $display("FAIL: RANDOM: C45 AN Advertisement corrupted");
            errors++;
        end else
            $display("PASS: RANDOM: C45 AN Advertisement intact");
    end
    endtask

    /**
     * @brief Random Valid Operations Stress Test
     * @details Tests PHY with random but valid C22/C45 read/write operations
     */
    task automatic test_random_valid_ops();
        int          iter;
        int          kind;
        int          err_before;
        logic [15:0] rd;
        logic [15:0] wr_val;
        logic [4:0]  phy;
        logic [4:0]  dev;
        logic [15:0] addr;
        logic [4:0]  regad;
    begin
        $display("========== RANDOM VALID C22/C45 STRESS TEST ==========");
        err_before = errors;

        for (iter = 0; iter < STRESS_VALID_ITERATIONS; iter++) begin
            kind   = $urandom_range(0,3); // 0: C22-R, 1: C22-W, 2: C45-R, 3: C45-W

            // Select valid PHY address
            case ($urandom_range(0,2))
                0: phy = PHY_ADDR_VALID_0;
                1: phy = PHY_ADDR_VALID_1;
                default: phy = PHY_ADDR_VALID_2;
            endcase

            wr_val = $urandom;

            unique case (kind)
                // Clause-22 READ
                0: begin
                    regad = $urandom_range(0,31);
                    mdio_c22_read(phy, regad, rd);
                    // Check for X propagation
                    if (^rd === 1'bx) begin
                        $display("FAIL: RANDOM-V: C22 READ got Xs, phy=%0d reg=%0d rd=%h", phy, regad, rd);
                        errors++;
                    end
                end

                // Clause-22 WRITE (safe registers only)
                1: begin
                    case ($urandom_range(0,2))
                        0: regad = C22_REG_BMCR;
                        1: regad = C22_REG_ANAR;
                        default: regad = C22_REG_SCRATCH;
                    endcase
                    mdio_c22_write(phy, regad, wr_val);
                end

                // Clause-45 READ
                2: begin
                    case ($urandom_range(0,3))
                        0: dev = DEV_PMA;
                        1: dev = DEV_PCS;
                        2: dev = DEV_AN;
                        default: dev = DEV_VENDOR;
                    endcase
                    addr = $urandom;
                    mdio_c45_addr(phy, dev, addr);
                    mdio_c45_read(phy, dev, rd);
                    if (^rd === 1'bx) begin
                        $display("FAIL: RANDOM-V: C45 READ got Xs, phy=%0d dev=%0d addr=%h rd=%h", phy, dev, addr, rd);
                        errors++;
                    end
                end

                // Clause-45 WRITE (safe registers only)
                3: begin
                    case ($urandom_range(0,2))
                        0: begin dev = DEV_PMA;  addr = C45_REG_PMA_CTRL1; end
                        1: begin dev = DEV_AN;   addr = C45_REG_AN_ADV; end
                        default: begin dev = DEV_VENDOR; addr = C45_REG_VENDOR_SCRATCH; end
                    endcase
                    mdio_c45_addr(phy, dev, addr);
                    mdio_c45_write(phy, dev, wr_val);
                end
            endcase
        end

        if (errors == err_before)
            $display("PASS: RANDOM-V: valid C22/C45 R/W stress (no X)");
        else
            $display("FAIL: RANDOM-V: errors detected in valid R/W stress");
    end
    endtask

    /**
     * @brief Link Status Race Condition Stress Test
     * @details Tests PHY under rapidly changing link status conditions
     */
    task automatic test_link_race_stress();
        int          i;
        int          err_before;
        logic [15:0] rd;
    begin
        $display("========== LINK RACE STRESS TEST ==========");
        err_before = errors;

        fork
            // Thread 1: Randomly toggle link status and speed
            begin : link_toggler
                for (i = 0; i < STRESS_LINK_RACE_ITERATIONS; i++) begin
                    int d = $urandom_range(1,10);
                    repeat (d) @(negedge mdc);
                    link_up    = $urandom_range(0,1);
                    link_speed = $urandom_range(0,2); // 0/1/2 -> 10/100/1000
                end
            end

            // Thread 2: Continuously read status registers
            begin : mdio_reader
                for (i = 0; i < MAX_ITERATIONS_MDIO_READ; i++) begin
                    // C22 BMSR
                    mdio_c22_read(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
                    if (^rd === 1'bx) begin
                        $display("FAIL: RACE: BMSR has X under link toggle, rd=%h", rd);
                        errors++;
                    end

                    // C45 PMA Status1
                    mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PMA, C45_REG_PMA_STATUS1);
                    mdio_c45_read(PHY_ADDR_VALID_0, DEV_PMA, rd);
                    if (^rd === 1'bx) begin
                        $display("FAIL: RACE: PMA Status1 has X under link toggle, rd=%h", rd);
                        errors++;
                    end

                    // C45 PCS Status1
                    mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PCS, C45_REG_PMA_STATUS1);
                    mdio_c45_read(PHY_ADDR_VALID_0, DEV_PCS, rd);
                    if (^rd === 1'bx) begin
                        $display("FAIL: RACE: PCS Status1 has X under link toggle, rd=%h", rd);
                        errors++;
                    end
                end
            end
        join

        if (errors == err_before)
            $display("PASS: LINK RACE STRESS (no X in status reads)");
        else
            $display("FAIL: LINK RACE STRESS (errors were detected)");
    end
    endtask
    
    /**
     * @brief Wrong PHY Address Negative Test
     * @details Tests PHY behavior with invalid PHY addresses
     */
    task automatic test_wrong_phy_address();
        logic [15:0] rd;
        logic        oe_seen;
        int          k;
    begin
        $display("========== NEGATIVE: WRONG PHY ADDRESS ==========");

        oe_seen = 1'b0;

        // Monitor PHY drive during frame with invalid PHY address
        fork
            begin
                for (k = 0; k < STRESS_MONITOR_CYCLES; k++) begin
                    @(posedge mdc);
                    if (mdio_phy_oe) oe_seen = 1'b1;
                end
            end
            begin
                mdio_c22_read(PHY_ADDR_INVALID, C22_REG_BMCR, rd); // PHY 1 is invalid
            end
        join

        if (oe_seen) begin
            $display("FAIL: PHY drove MDIO line for wrong PHY address");
            errors++;
        end else
            $display("PASS: Wrong PHY address -> PHY did not drive line");
    end
    endtask

    /**
     * @brief Short Preamble Negative Test
     * @details Tests PHY behavior with insufficient preamble length
     */
    task automatic test_short_preamble();
        logic [15:0] rd;
        logic        oe_seen;
        int          k;
    begin
        $display("========== NEGATIVE: SHORT PREAMBLE ==========");

        oe_seen = 1'b0;

        fork
            begin
                for (k = 0; k < MONITOR_CYCLES_SHORT; k++) begin
                    @(posedge mdc);
                    if (mdio_phy_oe) oe_seen = 1'b1;
                end
            end
            begin
                mdio_c22_read_short_preamble(PHY_ADDR_VALID_0, C22_REG_BMCR, rd);
            end
        join

        if (oe_seen) begin
            $display("FAIL: PHY drove MDIO line for short preamble");
            errors++;
        end else
            $display("PASS: Short preamble -> PHY did not drive line");
    end
    endtask

    /**
     * @brief Invalid ST Negative Test
     * @details Tests PHY behavior with invalid start frame pattern
     */
    task automatic test_invalid_st();
        logic [15:0] rd;
        logic        oe_seen;
        int          k;
    begin
        $display("========== NEGATIVE: INVALID ST ==========");

        oe_seen = 1'b0;

        fork
            begin
                for (k = 0; k < MONITOR_CYCLES_SHORT; k++) begin
                    @(posedge mdc);
                    if (mdio_phy_oe) oe_seen = 1'b1;
                end
            end
            begin
                mdio_c22_read_invalid_st(PHY_ADDR_VALID_0, C22_REG_BMSR, rd);
            end
        join

        if (oe_seen) begin
            $display("FAIL: PHY drove MDIO line for invalid ST");
            errors++;
        end else
            $display("PASS: Invalid ST -> PHY did not drive line");
    end
    endtask

    /**
     * @brief Register 0-5 Read Debug Test
     * @details Reads and displays C22 registers 0-5 and C45 DEV_PCS registers 0-5 for debugging
     */
    task automatic test_register_0_5_read();
        logic [15:0] rd;
        logic [15:0] rd_c45;
        int   k;
    begin
        $display("========== REGISTERS C22 phy[%d] ==========", PHY_ADDR_VALID_0);
        for (k = 0; k <= 5; k++) begin
            // C22 register read
            mdio_c22_read(PHY_ADDR_VALID_0, k, rd);
            $display("C22 [%d] 0x%04h", k, rd);
        end
        $display("========== REGISTER C45 phy[%d] dev[%d] ==========", PHY_ADDR_VALID_0, DEV_PCS);
        for (k = 0; k <= 5; k++) begin
            // C45 register read
            mdio_c45_addr(PHY_ADDR_VALID_0, DEV_PCS, k);
            mdio_c45_read(PHY_ADDR_VALID_0, DEV_PCS, rd_c45);
            $display("C45 [%d] 0x%04h", k, rd_c45);
        end
    end
    endtask

    // --------------------------------------------------------------------
    // FSM Coverage Monitoring
    // --------------------------------------------------------------------
    
    /**
     * @brief Initialize FSM coverage arrays
     * @details Sets all state hit counters and transition counters to zero
     */
    initial begin
        for (cov_i = 0; cov_i < 8; cov_i++) begin
            fsm_state_hits[cov_i] = 0;
            for (cov_j = 0; cov_j < 8; cov_j++)
                fsm_state_trans[cov_i][cov_j] = 0;
        end
        fsm_prev_state = 3'd0;
    end

    /**
     * @brief Monitor FSM state transitions for coverage analysis
     * @details Tracks state visits and transitions between states during simulation
     */
    always @(posedge mdc) begin
        if (!rst_n) begin
            fsm_prev_state <= 3'd0;
        end else begin
            logic [2:0] current_state;
            current_state = dut.state; // Access DUT's internal state
            if (current_state <= 3'd7) begin
                fsm_state_hits[current_state] <= fsm_state_hits[current_state] + 1;
                fsm_state_trans[fsm_prev_state][current_state] <= fsm_state_trans[fsm_prev_state][current_state] + 1;
                fsm_prev_state <= current_state;
            end
        end
    end

    // --------------------------------------------------------------------
    // Final Test Result and Statistics
    // --------------------------------------------------------------------
    
    /**
     * @brief Display comprehensive test summary
     * @details Shows error count, operation statistics, and coverage information
     */
    task automatic display_test_summary();
    begin
        $display("\n========== COMPREHENSIVE TEST SUMMARY ==========");
        $display("Total Errors Detected: %0d", errors);
        $display("Test Completion Time: %0t ns", $time);
        
        // DUT operation statistics
        $display("----- DUT OPERATION STATISTICS -----");
        $display("Clause 22 Read Operations : %0d", dut.cnt_c22_read_ok);
        $display("Clause 22 Write Operations: %0d", dut.cnt_c22_write_ok);
        $display("Clause 45 Read Operations : %0d", dut.cnt_c45_read_ok);
        $display("Clause 45 Write Operations: %0d", dut.cnt_c45_write_ok);
        
        // Error statistics
        $display("----- ERROR STATISTICS -----");
        $display("Short Preamble Errors : %0d", dut.cnt_err_short_preamble);
        $display("Invalid ST Errors     : %0d", dut.cnt_err_invalid_st);
        $display("Bad PHY Address Errors: %0d", dut.cnt_err_bad_phy);
        $display("Bad Device Address Errors: %0d", dut.cnt_err_bad_dev);
        
        // Coverage summary
        $display("----- COVERAGE SUMMARY -----");
        $display("FSM States Covered: %0d/8", get_covered_states_count());
        $display("FSM Transitions Covered: %0d/64", get_covered_transitions_count());
    end
    endtask
    
    /**
     * @brief Count number of covered FSM states
     * @return Number of states with at least one hit
     */
    function automatic int get_covered_states_count();
        int count = 0;
        for (cov_i = 0; cov_i < 8; cov_i++) begin
            if (fsm_state_hits[cov_i] > 0) count++;
        end
        return count;
    endfunction
    
    /**
     * @brief Count number of covered FSM transitions
     * @return Number of transitions with at least one occurrence
     */
    function automatic int get_covered_transitions_count();
        int count = 0;
        for (cov_i = 0; cov_i < 8; cov_i++) begin
            for (cov_j = 0; cov_j < 8; cov_j++) begin
                if (fsm_state_trans[cov_i][cov_j] > 0) count++;
            end
        end
        return count;
    endfunction

    // --------------------------------------------------------------------
    // Final Cleanup and Result Reporting
    // --------------------------------------------------------------------
    
    /**
     * @brief Main testbench execution block
     * @details Initializes signals, runs all tests, and reports results
     */
    initial begin
        // Setup waveform dumping
        $dumpfile("mdio_phy_combined_model.vcd");
        $dumpvars(0, mdio_phy_combined_model_tb);

//    $dumpvars(0, dut.clk_sys);
//    $dumpvars(0, dut.rst_n);
//    $dumpvars(0, dut.mdc);
//    $dumpvars(0, dut.mdio_oe);
//    $dumpvars(0, dut.mdio_o);
//    $dumpvars(0, dut.mdio_i);

        // Initialize testbench signals
        errors         = 0;
        rst_n          = 0;
        mdio_master_o  = 1'b1;
        mdio_master_oe = 1'b0;

        // Initial link state (used during reset)
        link_up    = 1'b1;
        link_speed = LINK_SPEED_1000M;

        // Release reset after initialization
        #(RESET_DURATION_NS);
        rst_n = 1'b1;
        #(RESET_DURATION_NS);

        $display("========== MDIO PHY COMBINED MODEL TESTBENCH STARTED ==========");
        $display("Simulation Time: %0t ns", $time);

        // Execute test sequence
        test_register_0_5_read();
        
        test_register_maps_sanity();    #(TEST_INTERVAL_NS);
        test_capability_bits_profile(); #(TEST_INTERVAL_NS);
        test_pcs_status();              #(TEST_INTERVAL_NS);
        test_eee_caps();                #(TEST_INTERVAL_NS);
        test_c22_bmcr_bmsr();           #(TEST_INTERVAL_NS);
        test_c45_dev31_rw();            #(TEST_INTERVAL_NS);
        test_link_status_speed_via_dev31(); #(TEST_INTERVAL_NS);
        test_speed_control_bmcr();      #(TEST_INTERVAL_NS);
        test_speed_control_pma();       #(TEST_INTERVAL_NS);
        test_c45_pma_an_status();       #(TEST_INTERVAL_NS);
        test_c45_an_autoneg();          #(TEST_INTERVAL_NS);
        test_wrong_phy_address();       #(TEST_INTERVAL_NS);
        test_short_preamble();          #(TEST_INTERVAL_NS);
        test_invalid_st();              #(TEST_INTERVAL_NS);
        test_random_stress();           #(TEST_INTERVAL_NS);
        test_random_valid_ops();        #(TEST_INTERVAL_NS);
        test_link_race_stress();        #(TEST_INTERVAL_NS);

        // Final delay for any pending operations
        #(TEST_INTERVAL_NS * 4);
        
        // Display comprehensive results
        display_test_summary();

        // Detailed FSM coverage reporting
        $display("\n========== DETAILED FSM STATE COVERAGE ==========");
        for (cov_i = 0; cov_i < 8; cov_i++) begin
            $display("STATE %0d: %0d hits", cov_i, fsm_state_hits[cov_i]);
        end

        $display("\n========== DETAILED FSM TRANSITION COVERAGE ==========");
        for (cov_i = 0; cov_i < 8; cov_i++) begin
            for (cov_j = 0; cov_j < 8; cov_j++) begin
                if (fsm_state_trans[cov_i][cov_j] != 0) begin
                    $display("  TRANSITION %0d -> %0d : %0d occurrences", 
                            cov_i, cov_j, fsm_state_trans[cov_i][cov_j]);
                end
            end
        end

        // Final test result
        $display("\n========== FINAL TEST RESULT ==========");
        if (errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("The MDIO PHY Combined Model has been successfully verified.");
            $display("All functional, stress, and negative tests completed without errors.");
        end else begin
            $display("*** TESTS FAILED: %0d error(s) detected ***", errors);
            $display("Please review the error messages above for details.");
        end
        
        $display("\nSimulation completed at time: %0t ns", $time);
        $display("=================================================");

        // Allow some time for final signal stabilization
        #(TEST_INTERVAL_NS);
        $finish;
    end

endmodule

/** @} */ // end of mdio_testbench group
