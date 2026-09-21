# Hybrid Cryptographic Hardware Processor

> **Course Project:** CSE 4224 — Digital System Design Laboratory  
> **Target Hardware:** Digilent Basys 3 FPGA (Xilinx Artix-7 `xc7a35tcpg236-1`)  
> **HDL:** Verilog HDL  

---

## 📌 Project Overview

This repository contains the complete Verilog HDL implementation of a **Hybrid Cryptographic Hardware Processor** built on the **Digilent Basys 3 FPGA board**. The processor encrypts and decrypts **16-byte blocks** of ASCII text using a two-tier layered cipher scheme:

1. **Caesar Cipher (Byte Shift):** Shift value configurable via onboard switches `sw[7:0]` (0–255 shift range).
2. **4×4 Columnar Transposition:** Key permutation configurable via onboard switches `sw[3:0]`.

### ⚡ Key Technical Highlight: Custom Structural ALU
All arithmetic addition and subtraction for encryption and decryption are executed strictly by a **custom 8-bit structural ALU** (`arithmetic_circuit_8bit`) constructed from low-level gate logic — building blocks include 1-bit half adders, full adders, and control conditioning circuits. **No Verilog arithmetic operators (`+` or `-`) are used in the cipher data path.**

---

## ✨ Features

- **Layered Cryptography:** Combines substitution (Caesar Cipher) and transposition (4×4 Columnar Matrix) for enhanced hardware security.
- **Pure Structural ALU:** Built from 16 half-adders, 8 full-adders, and 8 control circuits with a ripple-carry chain. Supports addition ($F = A + B$) for encryption and 2's complement subtraction ($F = A - B = A + \sim B + 1$) for decryption.
- **10-State FSM Controller:** Robust Finite State Machine driving key input latching, byte receiving, matrix transposition, inverse transposition, and UART transmission.
- **Full-Duplex UART Communication:** 115200 baud rate (8N1 configuration) over the micro-USB FTDI bridge for sending plaintext files and receiving decrypted outputs via serial terminal (Tera Term).
- **Real-Time Visual Feedback:**
  - **7-Segment Display:** Displays `Enc ` during encryption phase and `dEc ` during decryption phase.
  - **LED Status Indicators:** `led[3:0]` display exact FSM state codes to guide the user step-by-step.
- **Hardware Debouncing:** Parameterized 5ms debouncing modules on all physical input buttons (`BTNU`, `BTNL`).

---

## 🏗️ Hardware Architecture & Module Hierarchy

```
crypto_top (Top Level Module)
├── debounce (btn_enter - BTNU)       ── Parameterized button debouncer
├── debounce (btn_show - BTNL)        ── Parameterized button debouncer
├── uart_rx                           ── 115200 Baud 8N1 UART Receiver
├── uart_tx                           ── 115200 Baud 8N1 UART Transmitter
├── seg7_driver                       ── 4-Digit Time-Multiplexed 7-Seg Display Driver
└── crypto_fsm                        ── Main FSM & 16-Byte Transposition Matrix
    └── arithmetic_circuit_8bit       ── Shared Structural 8-bit ALU
        ├── control_circuit × 8       ── Gate-level bit conditioning (S1, S0 logic)
        └── full_adder × 8            ── 8-bit Ripple-Carry Adder Chain
            └── half_adder × 2        ── Basic XOR/AND Gate Building Blocks
```

---

## 📋 System Requirements & Setup

### Hardware Required
- Digilent Basys 3 FPGA Board
- Micro-USB cable (for FPGA programming & UART serial communication)

### Software Required
- **Xilinx Vivado** (2020.1 or newer recommended)
- **Tera Term** (or any serial terminal supporting binary file transfer)

---

## 🎮 Board Control Mapping

| Hardware Control | Board Label | Function / Description |
|---|---|---|
| **Center Button** | `BTNC` | Global System Reset (`reset`) |
| **Up Button** | `BTNU` | Latch Key Input (`btn_enter`) |
| **Left Button** | `BTNL` | Transmit Decrypted Output (`btn_show`) |
| **Switches `sw[7:0]`** | `sw[7:0]` | Caesar Cipher 8-bit Key Value (0–255) |
| **Switches `sw[3:0]`** | `sw[3:0]` | Transposition Matrix Column Permutation Key |
| **7-Segment Display** | `an[3:0]`, `seg[6:0]` | Displays current mode (`Enc ` or `dEc `) |
| **LEDs `led[3:0]`** | `led[3:0]` | Displays current FSM state hex indicator |

---

## 🚀 How to Run the Project

### 1. Program the FPGA
1. Open Vivado and load the project file (`project.xpr`).
2. Open **Hardware Manager** and connect your Basys 3 board via USB.
3. Click **Program Device** and select `crypto_top.bit` (located in `project.runs/impl_1/` or root repository).

### 2. Configure Tera Term
1. Launch Tera Term and select the **COM Port** corresponding to your Basys 3 USB Serial Port.
2. Navigate to **Setup → Serial Port...** and apply the following settings:
   - **Baud Rate:** `115200`
   - **Data:** `8 bit`
   - **Parity:** `None`
   - **Stop bits:** `1 bit`
   - **Flow control:** `None`

---

## 🕹️ Step-by-Step Operating Guide

The processor operates in two main phases across 10 internal FSM states:

### 🔹 PHASE 1: Encryption Phase (Display: `Enc `)

1. **Set Encryption Caesar Key:**
   - Set `sw[7:0]` to your desired Caesar shift value (e.g., `00000011` for shift of 3).
   - Press **BTNU** (`btn_enter`). *(LEDs: `0001` → `0011`)*
2. **Set Encryption Transposition Key:**
   - Set `sw[3:0]` to your column permutation order.
   - Press **BTNU** (`btn_enter`). *(LEDs: `0011` → `0111`)*
3. **Transmit 16-Byte Plaintext:**
   - In Tera Term: **File → Send File...**
   - Select your 16-byte input text file (⚠️ **Check Binary mode** to avoid extra line-ending bytes).
   - The FPGA automatically processes all 16 bytes through the structural ALU ($F = \text{byte} + \text{key}$) into the internal 4×4 matrix. *(LEDs: `0111`)*
4. **Automatic Transposition:**
   - The FPGA automatically performs the 4×4 matrix transposition in ~33 clock cycles (~330 ns).
   - The display switches to `dEc `. *(LEDs: `1111` → `1000`)*

---

### 🔸 PHASE 2: Decryption Phase (Display: `dEc `)

5. **Set Decryption Caesar Key:**
   - Set `sw[7:0]` to the **same Caesar key** used in Step 1.
   - Press **BTNU** (`btn_enter`). *(LEDs: `1000` → `1100`)*
6. **Set Decryption Transposition Key:**
   - Set `sw[3:0]` to the **same Transposition key** used in Step 2.
   - Press **BTNU** (`btn_enter`). *(LEDs: `1100` → `1110`)*
7. **Transmit Decrypted Output:**
   - Press **BTNL** (`btn_show`).
   - The FPGA computes the inverse transposition and feeds each byte through the ALU subtractor ($F = \text{byte} - \text{key}$).
   - The original 16-byte decrypted plaintext stream will appear directly on your Tera Term terminal window! *(LEDs: `1110` → `0000`)*
8. **Reset:** Press **BTNC** (`reset`) to process a new message.

---

## 📊 LED State Reference Table

| LED Pattern | Hex | FSM State | Description |
|:---:|:---:|:---|:---|
| `0001` | `1` | `S_ENC_CAESAR_KEY` | Waiting for Caesar Enc key (`sw[7:0]`) + `BTNU` |
| `0011` | `3` | `S_ENC_TRANSPOSE_KEY` | Waiting for Transposition Enc key (`sw[3:0]`) + `BTNU` |
| `0111` | `7` | `S_RX_AND_CAESAR` | Receiving 16 UART bytes and performing Caesar shift |
| `1111` | `F` | `S_ENC_TRANSPOSE` | Executing 4×4 matrix columnar transposition |
| `1000` | `8` | `S_DEC_CAESAR_KEY` | Waiting for Caesar Dec key (`sw[7:0]`) + `BTNU` |
| `1100` | `C` | `S_DEC_TRANSPOSE_KEY` | Waiting for Transposition Dec key (`sw[3:0]`) + `BTNU` |
| `1110` | `E` | `S_DEC_WAIT_SHOW` | Encryption complete. Waiting for `BTNL` (`btn_show`) |
| `0000` | `0` | `S_DONE` | Decryption & UART transmission finished |

---

## 🛠️ Repository Structure

```
.
├── basys3_crypto.xdc           # Basys 3 Master FPGA Pin Constraints File
├── crypto_top.bit              # Pre-compiled FPGA Bitstream File
├── project.xpr                 # Vivado Project File
├── README.md                   # Project Documentation
└── project.srcs/
    └── sources_1/
        └── new/                # Verilog HDL Source Files
            ├── half_adder.v             # Structural 1-bit Half Adder
            ├── full_adder.v             # Structural 1-bit Full Adder
            ├── control_ckt.v            # ALU Operand B Control Circuit
            ├── arithmetic_circuit_8bit.v# Custom Structural 8-bit ALU
            ├── debounce.v               # Button Edge & Pulse Debouncer
            ├── uart_rx.v                # 115200 Baud UART Receiver
            ├── uart_tx.v                # 115200 Baud UART Transmitter
            ├── seg7_driver.v            # 4-Digit 7-Segment Multiplexed Driver
            ├── crypto_fsm.v             # Central Crypto State Machine & Storage
            └── crypto_top.v             # Top-Level Structural Interconnect
```


---

## 👨‍💻 Author


**Farhan Miraz Shihab**  
Department of Computer Science & Engineering (CSE)  
Khulna University of Engineering & Technology (KUET)  
- GitHub: [@Blackbird-M23](https://github.com/Blackbird-M23)  
- LinkedIn: [Farhan Miraz Shihab](https://www.linkedin.com/in/farhanmirazshihab/)