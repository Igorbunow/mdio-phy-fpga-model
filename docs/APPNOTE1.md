# **Application Note**

**AN-MDIO-PHY-001**
**MDIO PHY Behavioral Model (Clause 22 and Clause 45)
Reference Implementation for Driver Development and FPGA Verification**

**Revision:** 1.0
**Date:** 2025-12-03
**Author:** Internal Engineering Tools Group

---

## **Abstract**

This Application Note presents a synthesizable, feature-complete **MDIO PHY Behavioral Model** designed for use in FPGA verification environments, firmware driver bring-up, and hardware debug of MDIO masters such as SoC Ethernet MACs and FTDI MPSSE-based interfaces.
The model implements IEEE 802.3 **Clause 22 (C22)** and **Clause 45 (C45)** management protocols, including realistic timing, tri-state behavior, TA sequences, device addressing rules, and negative response conditions.

The model has been validated in simulation (Icarus Verilog, Vivado), FPGA hardware, and with an FT2232H operating up to 2 MHz MDC.

This AN describes the architecture, interface, operation, limitations, and recommended verification approach for system integrators and driver developers.

---

# **Table of Contents**

1. Introduction
2. Standards and Requirements
3. Architectural Overview
4. MDIO Protocol Operation

   * 4.1 Clause 22 Overview
   * 4.2 Clause 45 Overview
   * 4.3 TA Phase Behavior
   * 4.4 Timing Diagrams
5. Module Interface Description
6. Internal Architecture
7. Device Register Maps
8. Integration in FPGA and Simulation Environments
9. Driver Development Guidelines
10. Negative Test Scenarios
11. Hardware Validation Results
12. Known Limitations
13. Revision History
14. Legal Notices

---

# **1. Introduction**

Management Data Input/Output (MDIO) is a serial management interface defined in IEEE 802.3 used to configure Ethernet PHY devices and query status information.

During development of Ethernet MACs, MDIO controllers, or custom FPGA-based MDIO masters, a **behaviorally accurate PHY model** is essential for validating both protocol correctness and driver behavior.

This AN introduces a fully synthesizable **MDIO PHY Combined Model** supporting:

* Complete Clause-22 PHY functionality
* Complete Clause-45 device addressing
* PMA, PCS, AN, vendor devices
* EEE advertisement registers
* Link and speed control
* Full negative test coverage
* Realistic TA timing and tri-state MDIO behavior

This model provides deterministic and repeatable behavior identical between simulation and hardware test environments.

---

# **2. Standards and Requirements**

The model conforms to the following standards:

| Standard             | Description                           |
| -------------------- | ------------------------------------- |
| IEEE 802.3-2022      | Ethernet PHY Management: Clause 22/45 |
| IEEE 802.3.1         | YANG Data Models for C45 registers    |
| IEEE 802.3 Annex 45B | MDIO Transactions                     |

Design constraints:

* `clk_sys ≥ 4 × MDC` for safe synchronization
* MDC frequency validated up to 2.5 MHz
* Tri-state MDIO behavior matches IEEE timing
* All timing aligns to MDC rising/falling edges per standard

---

# **3. Architectural Overview**

The MDIO PHY Behavioral Model consists of:

```
+-----------------------------------------------------------+
|                   MDIO PHY Behavioral Model               |
|-----------------------------------------------------------|
|  Synchronizers       |  MDC Edge Detector                 |
|-----------------------------------------------------------|
|  Clause-22 Engine    |  Clause-45 Engine                  |
|-----------------------------------------------------------|
|  Register Files: C22 |  C45-PMA | C45-PCS | C45-AN       |
|                       |  C45-DEV31 Vendor Space (256x16) |
|-----------------------------------------------------------|
|  Link/Speed Core | Auto-Neg Simulation | EEE Logic       |
+-----------------------------------------------------------+
```

Key modules:

* **Frame decoder FSM** — shared for C22/C45
* **Register access layer** — handles read/write mapping
* **MDIO line driver unit** — controls TA, output timing, OE
* **Status/control layer** — speed, duplex, link state

---

# **4. MDIO Protocol Operation**

## **4.1 Clause-22 (C22) Overview**

A standard Clause-22 frame includes:

* 32-bit preamble
* ST = `01`
* OP = `01` write / `10` read
* 5-bit PHY address
* 5-bit register address
* 2-bit Turn-Around (TA)
* 16-bit data

The model implements:

* Complete 0x00–0x1F register map
* Full bidirectional timing correctness
* Z0 TA behavior on read
* No-drive behavior for invalid frames

---

## **4.2 Clause-45 (C45) Overview**

Clause-45 uses two frames:

1. **Address phase** — selects DEVAD + REG
2. **Data phase** — read or write

Supports:

* DEV1 (PMA/PMD)
* DEV3 (PCS)
* DEV7 (AN)
* DEV31 (Vendor device)

---

## **4.3 Turn-Around (TA) Phase Behavior**

Per IEEE:

* **Read TA**: `Z` then `0`
* **Write TA**: `1` then `0` (master-driven)

The model implements:

* First TA bit always high-Z
* Second TA bit driven `0` only when:

  * PHY address matches
  * DEVAD valid
  * Preamble >= 32 bits
  * ST valid

Otherwise, PHY remains tri-stated.

---

## **4.4 ASCII Timing Diagrams**

### **4.4.1 Clause-22 Read**

```
Time →
MDC  :  _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
MDIO (master):
        1111...1111  01 10 AAAAA RRRRR  Z  Z
        <---32x1---> ST OP PHYAD REGAD  TA

MDIO (PHY):
        --------------------------------  Z  0 D15 D14 ... D0 ----
```

---

### **4.4.2 Clause-45 Address Phase**

```
MDC               : _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_
MDIO (master)     : 1111...1111  00 00 AAAAA DDDDD 10 A15..A0 Z
```

---

### **4.4.3 Clause-45 Read Phase**

```
MDIO (master)     : 1111...1111  00 11 AAAAA DDDDD  Z  Z
MDIO (PHY)        : -------------------------------  Z  0 D15..D0 ---
```

---

# **5. Module Interface Description**

| Port           | Dir | Description        |
| -------------- | --- | ------------------ |
| `clk_sys`      | in  | System clock       |
| `rst_n`        | in  | Active-low reset   |
| `mdc`          | in  | MDIO clock         |
| `mdio_i`       | in  | MDIO input         |
| `mdio_o`       | out | MDIO output        |
| `mdio_oe`      | out | MDIO output enable |
| `link_up_i`    | in  | Initial link state |
| `link_speed_i` | in  | Initial speed      |

---

# **6. Internal Architecture**

The internal design consists of:

### **6.1 Clock Domain Crossing**

Two-flip-flop synchronizers for:

* MDC
* MDIO input

### **6.2 FSM**

Seven-state MDIO decoder:

| State | Description               |
| ----- | ------------------------- |
| S0    | Idle / preamble detection |
| S1    | ST decoding               |
| S2    | OP decoding               |
| S3    | PHY address               |
| S4    | Register/DEV address      |
| S5    | TA phase                  |
| S6    | Data phase                |

### **6.3 Register Engines**

Two independent engines handle C22 and C45 semantics:

* C22 — direct address
* C45 — latched DEVAD + REG from address phase

---

# **7. Device Register Maps**

### **7.1 Clause-22 Registers**

* BMCR (0x00)
* BMSR (0x01)
* PHYID1 (0x02)
* PHYID2 (0x03)
* ANAR / ANLPAR
* ESR (0x0F)
* GBCR / GBSR

### **7.2 Clause-45 Devices**

| DEVAD | Name    | Description                    |
| ----- | ------- | ------------------------------ |
| 1     | PMA/PMD | IDs, control, status           |
| 3     | PCS     | Status1, Fault, EEE            |
| 7     | AN      | Advertisement, Partner Ability |
| 31    | Vendor  | 256×16 storage                 |

---

# **8. Integration in FPGA and Simulation Environments**

## **8.1 Tri-State Wiring Example**

```systemverilog
assign mdio = phy_oe    ? phy_o    :
              master_oe ? master_o :
              1'bz;
```

## **8.2 Clocking Notes**

```
clk_sys ≥ 4 × MDC
```

Validated configurations:

| clk_sys | MDC   |
| ------- | ----- |
| 100 MHz | 2 MHz |
| 50 MHz  | 1 MHz |

---

# **9. Driver Development Guidelines**

### **9.1 Recommended Sequence**

1. Read C22 ID registers
2. Perform C45 address phase → read phase
3. Test link/speed control (BMCR / PMA Control1)
4. Validate EEE and AN Advertisement
5. Validate DEV31 vendor access

### **9.2 Error Path Testing**

| Condition      | Expected          |
| -------------- | ----------------- |
| Wrong PHY      | TA=1/1 (no drive) |
| Wrong DEVAD    | No TA0, no data   |
| Short preamble | Frame ignored     |
| Invalid ST     | Frame ignored     |

---

# **10. Negative Test Scenarios**

Model includes built-in detection counters:

* Short preamble
* Invalid ST
* Bad PHY address
* Bad DEVAD

These help validate robustness of driver implementations.

---

# **11. Hardware Validation Results**

The model was synthesized for FPGA and tested with:

* FT2232H MPSSE backend
* 1–2 MHz MDC
* manual_mdio_fast_c22
* manual_mdio_fast_c45

Results:

* All C22 and C45 operations pass
* TA already matches real PHY devices
* No metastability observed
* No incorrect drive observed on MDIO
* C45 DEV31 operations validated fully

---

# **12. Known Limitations**

* Auto-negotiation is simplified (instant resolve)
* EEE partner ability modeled statically
* DEV1/3/7/31 maps are simplified to 256 entries
* Requires `clk_sys >> MDC`

---

# **13. Revision History**

| Revision | Date       | Description     |
| -------- | ---------- | --------------- |
| 1.0      | 2025-12-03 | Initial release |

---

# **14. Legal Notices**

This application note and behavioral model are provided “as-is” without warranty of any kind.
It is intended for design verification, driver development, and educational use.
The implementer is responsible for ensuring compliance with IEEE standards and system requirements.

---
