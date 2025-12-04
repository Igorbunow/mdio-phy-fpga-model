**MDIO PHY Combined Model (Clause 22 + Clause 45)  
Application Note for Driver Development and Verification**

## 1. Overview

This application note describes the usage, integration, and verification methodology for the **MDIO PHY Combined Model**, a synthesizable SystemVerilog module implementing both IEEE 802.3 Clause-22 (C22) and Clause-45 (C45) PHY behavior.  
The model is intended as a high-fidelity reference for:

- FPGA-based MDIO interface bring-up  
- Driver development and debugging  
- MPSSE/FTDI-based MDIO host implementations  
- C22/C45 feature validation  
- Regression and stress testing of MDIO masters

The model has been validated in:

- iverilog simulation  
- Vivado simulation  
- Real FPGA hardware  
- FT2232H MPSSE fast-backend (1–2 MHz MDC)

All functional tests, including negative and stress tests, pass both in simulation and on hardware.

---

## 2. Features

### 2.1 Clause-22 Support

- BMCR/BMSR registers  
- PHYID1/PHYID2  
- Auto-Negotiation Advertisement (ANAR)  
- Link Partner Ability (LPAR)  
- Extended Status (ESR)  
- 10/100/1000 Mb/s speed advertisement  
- Duplex settings  
- Link state reflection  
- Negative tests:
  - Incorrect PHY address  
  - Invalid ST field  
  - Short preamble  

### 2.2 Clause-45 Support

- Full support for:
  - DEV 1 — PMA/PMD  
  - DEV 3 — PCS  
  - DEV 7 — AN  
  - DEV 31 — Vendor-specific (4 banks × 256 registers)
- Standard registers implemented:
  - ID1/ID2  
  - PMA Control 1  
  - PMA Status 1  
  - AN Advertisement  
  - EEE Capability and LP Ability  
- Negative tests:
  - Wrong DEVAD  
  - Wrong PHY address  
  - Invalid ST  

### 2.3 Timing Model

- MDC edge detection fully synchronized to `clk_sys`
- Output data (`mdio_o`) updated on MDC falling edge
- MDIO driven (`mdio_oe`) only during read transactions
- TA phase implemented as Z + 0 (per IEEE 802.3)

---

## 3. Module Interface

### 3.1 Ports

| Signal          | Dir  | Description                                   |
|-----------------|------|-----------------------------------------------|
| `clk_sys`       | in   | System clock (must be faster than MDC × 4)    |
| `rst_n`         | in   | Asynchronous active-low reset                 |
| `mdc`           | in   | MDIO clock from master                        |
| `mdio_i`        | in   | MDIO input (from master)                      |
| `mdio_o`        | out  | MDIO output (to master)                       |
| `mdio_oe`       | out  | Output enable for MDIO line                   |
| `link_up_i`     | in   | Initial link state (1/0)                      |
| `link_speed_i`  | in   | Initial speed: {00=10M, 01=100M, 10=1G}       |

### 3.2 Output Behavior

- During C22 or C45 **read**:
  - TA phase: Z → 0  
  - 16-bit data shifted MSB first
- During write or invalid frame:
  - PHY keeps MDIO in high-impedance

---

## 4. Integration Guidelines

### 4.1 Clocking Requirements

To ensure correct edge detection:

```text
clk_sys ≥ 4 × MDC frequency
````

Recommended:

* MDC ≤ 2.5 MHz
* clk_sys = 50–200 MHz (typical FPGA clock)

### 4.2 Connecting to a Master (FPGA Testbench)

Example tri-state wiring:

```systemverilog
wire mdio;

assign mdio = master_oe ? master_o : 1'bz;
assign mdio = phy_oe    ? phy_o    : 1'bz;

assign phy_i    = mdio;
assign master_i = mdio;
```

### 4.3 Connecting to MPSSE/FTDI

Typical pin mapping (FT2232H):

| FTDI pin | MDIO signal         |
| -------- | ------------------- |
| ADBUS0   | MDC                 |
| ADBUS1   | MDIO bidirectional  |
| Optional | Short ADBUS2 & MDIO |

Backend-independent code (fast/slow) supports this mapping.

---

## 5. Using the Model for Driver Development

### 5.1 Basic Bring-Up Procedure

1. Read C22 ID registers (2, 3):
   Expect:

   * ID1 = 0x2000
   * ID2 = 0x5C90

2. Validate C22 reads of BMCR, BMSR.

3. Validate C45 access:

   * Write address via `C45-ADDR` frame
   * Write/read data via `C45-WR` / `C45-RD`

4. Test link and speed control:

   * Modify BMCR (C22)
   * Modify PMA Control1 (C45)
   * Modify DEV31 control register

### 5.2 Negative Test Scenarios (Driver Error Paths)

| Scenario          | Expected behavior                        |
| ----------------- | ---------------------------------------- |
| Wrong PHY address | PHY does not drive MDIO (TA remains Z/Z) |
| Wrong DEVAD       | No response, TA = 1/1                    |
| Invalid ST        | Frame ignored                            |
| Short preamble    | Frame ignored                            |
| Random noise      | No spurious responses                    |

The reference software test tools demonstrate these cases:

* `manual_mdio_fast_c22`
* `manual_mdio_fast_c45`

---

## 6. Testbench Overview

The bundled testbench performs:

### 6.1 Sanity Tests

* C22 register map
* C45 PMA/PCS/AN ID consistency
* Vendor DEV31 accessibility
* Extended status verification

### 6.2 Link/Speed Tests

* BMCR speed control
* PMA Control1 speed control
* DEV31 control of link/speed

### 6.3 Negative Tests

* Wrong PHY
* Wrong DEVAD
* Short preamble
* Invalid ST

### 6.4 Stress Tests

* Random C22/C45 transactions
* Noise/stability testing
* FSM state coverage monitoring
* Link-race conditions

All tests pass in:

* iverilog
* Vivado
* Real FPGA hardware
* FT2232H fast backend

---

## 7. Timing Details

### 7.1 MDC Processing

Rising edge (`mdc_rise`):

* FSM transitions
* Bit counters increment

Falling edge (`mdc_fall`):

* MDIO output bit updated:

```text
mdio_o <= tx_shift[15 - bit_cnt];
```

### 7.2 TA Phase

* First bit: `Z`
* Second bit: `0`
* Correctly detected by MPSSE backend (`TA0=1, TA1=0` in debug logs)

---

### 7.3 ASCII Timing Diagram – Clause-22 Read

The following ASCII timing diagram illustrates a typical Clause-22 read transaction:

```text
Time →
MDC  :  _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
        ^   ^   ^   ^   ^   ^   ^   ^   ^   ^   ^   ^
        |   |   |   |   |   |   |   |   |   |   |   |
        |   |   |   |   |   |   |   |   |   |   |   +-- rising edges
        |   |   |   |   |   |   |   |   |   |   +------ falling edges
        ...
MDIO
(master): 11111111111111111111111111111111  01 10 AAAAA RRRRR  Z  Z
          <-------- preamble (32 x '1') ----------> ST OP PHYAD REGAD TA
                                                          
MDIO
(PHY)  : --------------------------------------------- Z  0 D15 D14 ... D0 ---
                                                         ^  ^   ^        ^
                                                         |  |   |        |
                                                         |  |   |        +-- last data bit
                                                         |  |   +----------- first data bit (MSB)
                                                         |  +--------------- 2nd TA bit driven by PHY ('0')
                                                         +------------------ 1st TA bit (high-Z from PHY)

Legend:
- ST  = 01 for Clause-22 operation
- OP  = 10 for read
- AAAAA = PHY address (5 bits)
- RRRRR = register address (5 bits)
- TA  = Z (master release) then 0 (PHY drives)
- D15..D0 = data bits (MSB first), driven by PHY on MDC falling edges
```

Key points:

* The **master** drives preamble, ST, OP, PHYAD, REGAD and the first TA bit (by releasing the line to 'Z').
* The **PHY** drives the second TA bit (`0`) and all data bits D15..D0.
* The model ensures `mdio_oe` is asserted only during the second TA bit and data phase.

---

### 7.4 ASCII Timing Diagram – Clause-45 Address Phase

Clause-45 transactions consist of two frames: an **address phase** followed by a **data phase**.
The address phase programs the target device (DEVAD) and register address.

```text
Time →
MDC  :  _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
MDIO
(master): 11111111111111111111111111111111  00 00 AAAAA DDDDD 10 A15 ... A0 Z
          <-------- preamble ------------->  ST OP  PHYAD DEVAD TA  ADDRESS  TA

Where:
- ST    = 00 (Clause-45)
- OP    = 00 (address)
- AAAAA = PHY address
- DDDDD = DEVAD (5-bit device address)
- TA    = 10 (master drives both bits for address op)
- A15..A0 = 16-bit register address
- Final TA/Z: line released back to idle (high-Z)
```

In the model:

* Address and DEVAD are latched during this frame.
* No data is driven by the PHY in the address phase.
* Subsequent read/write operations will use the latched address.

---

### 7.5 ASCII Timing Diagram – Clause-45 Read Data Phase

After the address phase, a Clause-45 read uses a second frame with `OP=11` and a TA phase similar to Clause-22:

```text
Time →
MDC  :  _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
MDIO
(master): 11111111111111111111111111111111  00 11 AAAAA DDDDD  Z  Z
          <------------- preamble -------->  ST OP  PHYAD DEVAD TA

MDIO
(PHY)  : -------------------------------------- Z  0  D15 D14 ... D0 ----
                                              ^  ^   ^            ^
                                              |  |   |            |
                                              |  |   |            +-- last data bit
                                              |  |   +--------------- first data bit
                                              |  +------------------- 2nd TA bit = 0 (PHY)
                                              +---------------------- 1st TA bit (high-Z from PHY)

Where:
- ST    = 00 (Clause-45)
- OP    = 11 (read)
- AAAAA = PHY address
- DDDDD = DEVAD
- TA    = Z0 (same as Clause-22 read)
- D15..D0 = data bits driven by PHY
```

The model behavior:

* TA phase is implemented as Z, then 0, identical to Clause-22 read.
* Data is driven on MDC falling edges from an internal shift register.
* If `PHY` or `DEVAD` are invalid, the PHY will not drive the line (TA reads as 1/1 in the MPSSE backend).

---

## 8. Recommended Driver Tests (Checklist)

### 8.1 Clause-22

* Read BMCR/BMSR
* Write BMCR speed bits
* Read/verify PHYID
* AN advertisement read
* ESR capabilities read

### 8.2 Clause-45

* C45 Address → Data write/read
* PCS Status1 (link_up toggle)
* PMA Control1 speed manipulation
* AN negotiation sequence:

  * Write AN_ADV
  * Trigger autoneg
  * Read AN_STATUS1

### 8.3 Negative Tests

* Randomized PHY address
* DEVAD outside allowed set
* ST=01/11 tests
* Preamble=8/16 bits
* Stall/timeout handling

---

## 9. Notes on Real Hardware Behavior

The model has been validated on an FPGA and behaves identically to simulation in:

* C22/C45 read/write timing
* TA phase generation
* MDIO tristate behavior (`mdio_oe`)
* Link/speed change propagation

Debug logs confirm exact functional match:

```text
TA0=1, TA1=0    (C22/C45 read)
C22 reg dump matches expected values
C45 multi-register scan correct
Negative tests return -5 (no response)
```

---

## 10. Known Limitations

These are not bugs but design constraints to be aware of:

1. The model expects:

   ```text
   clk_sys ≥ 4 × MDC
   ```

   Otherwise MDC edge synchronization may degrade.

2. DEV1/DEV3/DEV7/DEV31 memory is fixed to 256 registers per device.

3. Vendor-specific behavior is minimal (DEV31 only).

4. Auto-negotiation is simplified (instant resolve).

---

## 11. Revision Control and Extensibility

Recommended extension points:

* Adding new Clause-45 devices (DEVAD 2/4/8, etc.)
* Extending DEV31 vendor-specific logic
* Enabling EEE negotiation automation
* Making link-up/AN completion timing more realistic
* Adding RX/TX error injection modes

The architecture cleanly separates:

* FSM
* C22/C45 register event logic
* Link/speed control
* Vendor registers

So maintaining or extending the model is straightforward.

---

## 12. Conclusion

The **MDIO PHY Combined Model** serves as a reliable, production-grade reference PHY for verification and driver development.
It has been validated against both simulation and real FTDI-MPSSE hardware, including all negative and stress scenarios.

This model is suitable as:

* a standalone test platform for MDIO masters,
* an FPGA-based behavioral PHY,
* a golden reference for driver bring-up,
* a teaching/reference implementation of IEEE 802.3 C22/C45 protocols.
