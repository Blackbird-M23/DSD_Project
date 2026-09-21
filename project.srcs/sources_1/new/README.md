# Hybrid Cryptographic Processor — User Manual
### Basys 3 FPGA | Caesar Cipher + 4×4 Columnar Transposition

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [Hardware Architecture](#2-hardware-architecture)
3. [File Inventory](#3-file-inventory)
4. [ALU Operation Reference](#4-alu-operation-reference)
5. [Hardware Setup](#5-hardware-setup)
6. [Tera Term Configuration](#6-tera-term-configuration)
7. [Step-by-Step Operating Guide](#7-step-by-step-operating-guide)
8. [LED Status Reference](#8-led-status-reference)
9. [7-Segment Display Reference](#9-7-segment-display-reference)
10. [Vivado Build Instructions](#10-vivado-build-instructions)
11. [Cryptography Reference](#11-cryptography-reference)
12. [Troubleshooting](#12-troubleshooting)
13. [Module Hierarchy](#13-module-hierarchy)

---

## 1. Project Overview

This project implements a **Hybrid Cryptographic Processor** on the Digilent Basys 3 FPGA board. It encrypts exactly **16 bytes** of ASCII text using two layered techniques:

| Layer | Algorithm | Key Source |
|-------|-----------|------------|
| 1st   | Caesar Cipher (byte-shift) | `sw[7:0]` — 8-bit shift value |
| 2nd   | 4×4 Columnar Transposition | `sw[3:0]` — 4-bit column order |

**Arithmetic is performed entirely by a custom structural ALU** (`arithmetic_circuit_8bit`) built from half adders, full adders, and control circuits — no Verilog `+` or `-` operators are used for cryptographic computation.

**Data flow:**

```
PC (Tera Term) ──UART──► FPGA RX
                          │
                          ▼
                   Caesar Encrypt (ALU Add)
                          │
                          ▼
                   4×4 Transposition
                          │
                   16-byte matrix stored
                          │
                   Inverse Transpose (on-the-fly)
                          │
                          ▼
                   Caesar Decrypt (ALU Subtract)
                          │
                          ▼
FPGA TX ──UART──► PC (Tera Term) shows plaintext
```

---

## 2. Hardware Architecture

### Module Hierarchy

```
crypto_top  (top level)
├── debounce            × 2  (btn_enter, btn_show)
├── uart_rx                  (serial receive, 115200 baud)
├── uart_tx                  (serial transmit, 115200 baud)
├── seg7_driver              (4-digit time-multiplexed display)
└── crypto_fsm               (main state machine + single matrix)
    └── arithmetic_circuit_8bit  (shared 8-bit structural ALU)
        ├── control_circuit  × 8  (generated, conditions B bits)
        └── full_adder       × 8  (generated, ripple-carry chain)
            └── half_adder   × 2 per full_adder
```

### ALU Data Path (Structural)

```
 A[7:0] ──────────────────────────────── full_adder[7:0].a
 B[7:0] ──► control_circuit[7:0] ──Y──► full_adder[7:0].b
                 ▲                             │
              S1, S0                      carry chain
                                              │
 Cin ──────────────────────────────────► C[0]
                                              │
                                        F[7:0], Cout
```

---

## 3. File Inventory

| File | Description |
|------|-------------|
| `half_adder.v` | 1-bit half adder (XOR + AND, structural) |
| `full_adder.v` | 1-bit full adder from two half adders |
| `control_ckt.v` | 1-bit B conditioning logic (S1/S0 select) |
| `arithmetic_circuit_8bit.v` | 8-bit custom ALU (ripple-carry, generated) |
| `debounce.v` | Parameterised button debouncer with edge pulse |
| `uart_rx.v` | 8N1 UART receiver (115200 baud) |
| `uart_tx.v` | 8N1 UART transmitter (115200 baud) |
| `seg7_driver.v` | Time-multiplexed 4-digit 7-seg driver |
| `crypto_fsm.v` | Main FSM, 16-byte matrix, ALU mux |
| `crypto_top.v` | Top-level wiring module |
| `basys3_crypto.xdc` | Basys 3 pin constraint file |
| `README.md` | This document |

---

## 4. ALU Operation Reference

The custom `arithmetic_circuit_8bit` is driven with specific control signals for each operation:

| Operation | S1 | S0 | Cin | Result |
|-----------|----|----|-----|--------|
| **Encrypt** (Add) | 0 | 1 | 0 | `F = A + B` |
| **Decrypt** (Sub) | 1 | 0 | 1 | `F = A − B` (2's complement: A + ~B + 1) |

> `A` = data byte (plaintext or ciphertext)  
> `B` = Caesar key byte (sw[7:0] latched at key entry)

**Control circuit truth table** (per bit):

| S1 | S0 | Y_i (fed to full adder) |
|----|----|--------------------------|
| 0  | 0  | 0 (force zero) |
| 0  | 1  | B_i (pass B — **addition**) |
| 1  | 0  | ~B_i (invert B — **subtraction**) |
| 1  | 1  | 1 (force one) |

---

## 5. Hardware Setup

### Required Equipment

- Digilent Basys 3 FPGA board
- USB-A to Micro-USB cable
- PC with Tera Term installed

### Physical Connections

1. Connect the Basys 3 to your PC via the **Micro-USB** programming port.
2. The same USB connection provides the UART bridge — **no additional cable needed**.
3. Ensure the **PROG** jumper (JP2) is set to USB (default factory position).

### Button Assignments

| Function | Button | Basys 3 Label |
|----------|--------|---------------|
| Lock in key from switches | **BTNU** (Up) | `btn_enter` |
| Transmit decrypted output | **BTNL** (Left) | `btn_show` |
| Global reset | **BTNC** (Centre) | `reset` |

### Switch Usage

| Switches | Used For |
|----------|----------|
| `sw[7:0]` (right 8) | Caesar key value (0–255) |
| `sw[3:0]` (right 4) | Transposition column order key (0–15) |

---

## 6. Tera Term Configuration

Tera Term is the recommended terminal. Configure it **before** programming the FPGA.

### Serial Port Settings

1. Open Tera Term → **Setup → Serial Port**
2. Select the **COM port** that corresponds to the Basys 3 (check Device Manager)
3. Apply these settings:

| Setting | Value |
|---------|-------|
| Baud Rate | **115200** |
| Data | **8 bit** |
| Parity | **None** |
| Stop | **1 bit** |
| Flow Control | **None** |

4. Click **OK**.

### Sending Data (Encryption)

1. Go to **File → Send File...**
2. Select a plain-text file containing **exactly 16 ASCII characters** (no newline at end, or account for it — see Tip below).
3. Check **Binary** mode to prevent Tera Term from adding CR/LF.
4. Click **Open** — Tera Term will send bytes one at a time.

> **Tip:** Create your 16-byte file with a hex editor or use Python:
> ```python
> with open("plaintext.bin", "wb") as f:
>     f.write(b"HelloFPGAWorld!!")   # exactly 16 bytes
> ```

### Receiving Data (Decryption Output)

The decrypted bytes will appear in the Tera Term terminal window after you press `btn_show`.  
To capture to a file: **File → Log...** before pressing `btn_show`.

---

## 7. Step-by-Step Operating Guide

The processor cycles through **10 FSM states** grouped into two phases. Follow the steps in order. The LED pattern and 7-segment display tell you the current state.

---

### PHASE 1 — Encryption

---

#### Step 1 — Set Encryption Caesar Key
**Display:** `Enc_` | **LEDs:** `0001`

1. Set `sw[7:0]` (the right 8 switches) to your desired Caesar shift value.
   - Example: shift of 3 → binary `00000011` → sw1 and sw0 ON, rest OFF.
   - The shift can be any value 0–255. A shift of 0 means no Caesar encryption.
2. Press **BTNU** (btn_enter) once.
   - The key is latched. The FPGA moves to Step 2.

> **Note:** There is a 5 ms hardware debounce — a single firm press is enough.

---

#### Step 2 — Set Encryption Transposition Key
**Display:** `Enc_` | **LEDs:** `0011`

1. Set `sw[3:0]` (the rightmost 4 switches) to the transposition column key.
   - `sw[1:0]` = first output column source (0–3)
   - `sw[3:2]` = second output column source (0–3)
   - The remaining two columns are assigned automatically.
   - Example: key `0110` (sw3=0, sw2=1, sw1=1, sw0=0) → columns [2,1,0,3] permutation.
2. Press **BTNU** (btn_enter) once.
   - The key is latched. The FPGA moves to Step 3.

---

#### Step 3 — Send 16 Bytes via Tera Term
**Display:** `Enc_` | **LEDs:** `0111`

1. In Tera Term: **File → Send File...** → select your 16-byte binary file → check **Binary** → click **Open**.
2. The FPGA receives each byte, feeds it through the ALU (addition: `F = byte + caesar_key`), and stores the result in the internal matrix.
3. After all 16 bytes are received, the FPGA automatically proceeds to Step 4.

> The display stays on `Enc_` throughout. Watch the LEDs: they stay at `0111` until all 16 bytes arrive.

---

#### Step 4 — Automatic Transposition
**Display:** `Enc_` | **LEDs:** `1111`

- No user action required.
- The FPGA performs the 4×4 columnar transposition over ~33 clock cycles (~330 ns).
- The matrix is overwritten in-place with the final ciphertext.
- The FPGA automatically advances to Phase 2.

---

### PHASE 2 — Decryption & Output

---

#### Step 5 — Set Decryption Caesar Key
**Display:** `dEc_` | **LEDs:** `1000`

> The display switches from `Enc_` to `dEc_` — you are now in decryption phase.

1. Set `sw[7:0]` to the **same Caesar key** used in Step 1.
   - Must match exactly for correct decryption.
2. Press **BTNU** (btn_enter) once.

---

#### Step 6 — Set Decryption Transposition Key
**Display:** `dEc_` | **LEDs:** `1100`

1. Set `sw[3:0]` to the **same transposition key** used in Step 2.
2. Press **BTNU** (btn_enter) once.

---

#### Step 7 — Press btn_show to Transmit
**Display:** `dEc_` | **LEDs:** `1110`

1. Press **BTNL** (btn_show) once.
2. The FPGA begins transmitting 16 bytes via UART.

**For each byte, the FPGA does the following on-the-fly (no matrix modification):**
1. Computes the inverse-transposition index to find the correct matrix slot.
2. Reads `matrix[index]` and routes it to ALU input A.
3. Sets ALU for subtraction (`S1=1, S0=0, Cin=1`): `F = A − caesar_key`.
4. Sends `F` (the decrypted byte) via uart_tx.
5. Waits for TX to complete, then moves to the next byte.

3. Watch Tera Term — the original 16 bytes appear in sequence.

**LEDs:** `0000` when all 16 bytes have been sent (Step 8 / S_DONE).

---

#### Step 8 — Done
**Display:** `dEc_` | **LEDs:** `0000`

- Press **BTNC** (reset) to restart the entire process for a new message.

---

## 8. LED Status Reference

| LED Pattern | Hex | State | Waiting For |
|-------------|-----|-------|-------------|
| `0001` | 1 | S_ENC_CAESAR_KEY | sw[7:0] + btn_enter |
| `0011` | 3 | S_ENC_TRANSPOSE_KEY | sw[3:0] + btn_enter |
| `0111` | 7 | S_RX_AND_CAESAR | 16 UART bytes |
| `1111` | F | S_ENC_TRANSPOSE | Automatic (~33 cycles) |
| `1000` | 8 | S_DEC_CAESAR_KEY | sw[7:0] + btn_enter |
| `1100` | C | S_DEC_TRANSPOSE_KEY | sw[3:0] + btn_enter |
| `1110` | E | S_DEC_WAIT_SHOW | btn_show |
| `0000` | 0 | S_DONE | Reset |

---

## 9. 7-Segment Display Reference

| Display | Phase |
|---------|-------|
| `Enc ` | Encryption (Phases 1: steps 1–4) |
| `dEc ` | Decryption (Phase 2: steps 5–8) |

The display is time-multiplexed at ~1 kHz refresh rate (1 digit active per ~1 ms).

---

## 10. Vivado Build Instructions

### Create Project

1. Open **Vivado 2020.x** (or later).
2. **File → Project → New**
3. Choose **RTL Project**, uncheck *Do not specify sources*.
4. Add all `.v` files:
   - `half_adder.v`
   - `full_adder.v`
   - `control_ckt.v`
   - `arithmetic_circuit_8bit.v`
   - `debounce.v`
   - `uart_rx.v`
   - `uart_tx.v`
   - `seg7_driver.v`
   - `crypto_fsm.v`
   - `crypto_top.v`
5. Add `basys3_crypto.xdc` as a constraint file.
6. Set target board: **Basys3** (or part: `xc7a35tcpg236-1`).

### Set Top Module

- In the Sources panel, right-click `crypto_top` → **Set as Top**.

### Synthesise and Implement

1. **Flow → Run Synthesis** — fix any errors.
2. **Flow → Run Implementation**.
3. **Flow → Generate Bitstream**.

### Program the Board

1. Connect Basys 3 via USB.
2. **Flow → Open Hardware Manager → Open Target → Auto Connect**.
3. **Program Device** → select the generated `.bit` file → **Program**.

---

## 11. Cryptography Reference

### Caesar Cipher (Byte Shift)

Each byte of plaintext is shifted by the key value modulo 256:

```
Encrypt: ciphertext_byte = (plaintext_byte + key) mod 256
Decrypt: plaintext_byte  = (ciphertext_byte - key) mod 256
```

The ALU performs this with unsigned 8-bit arithmetic (natural mod-256 wrap).

### 4×4 Columnar Transposition

The 16 bytes are arranged as a 4×4 matrix (row-major):

```
 Index:  [0]  [1]  [2]  [3]     Row 0
         [4]  [5]  [6]  [7]     Row 1
         [8]  [9]  [10] [11]    Row 2
        [12]  [13] [14] [15]    Row 3
```

The transposition key `sw[3:0]` defines the column read order:
- `sw[1:0]` = which original column becomes output column 0
- `sw[3:2]` = which original column becomes output column 1
- Remaining columns fill positions 2 and 3 in ascending order.

**Example** — key `0b0110` (sw=6 → p0=2, p1=1, p2=0, p3=3):

```
Original column order:    Col0  Col1  Col2  Col3
Transposed column order:  Col2  Col1  Col0  Col3
```

Reading the transposed matrix **row-major** produces the ciphertext byte sequence.

**Decryption** uses the same key to reconstruct the original read order (inverse permutation).

### Why the Keys Must Match

The system does NOT store the keys. You must remember and re-enter them in Phase 2. Entering a wrong key produces garbled output — this is expected behaviour.

---

## 12. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Tera Term shows `COM port not found` | Wrong COM port selected | Check Device Manager for Basys 3 COM port |
| No bytes received by FPGA | Baud rate mismatch | Set Tera Term to 115200, 8N1, No flow control |
| FPGA stuck at LEDs `0111` | Fewer than 16 bytes sent | Re-send; ensure file is exactly 16 bytes (use Binary mode) |
| Tera Term receives garbage characters | Wrong decryption keys | Redo from reset with matching keys |
| Button press registers multiple times | Debouncer not working | Check synthesis; confirm DEBOUNCE_CYCLES=500_000 |
| Display shows all segments ON | Synthesis issue with seg7_driver | Check seg encoding constants; re-synthesise |
| Reset not working | Wrong button | BTNC (centre) is reset |
| `btn_show` not advancing to TX | Wrong button | BTNL (left button) is btn_show |

### Common Mistakes

- **Sending 17 bytes** (16 chars + newline): In Tera Term, use **Binary mode** in Send File, or trim your file to exactly 16 bytes.
- **Mismatched keys**: The Caesar key and Transposition key entered in Phase 2 **must exactly match** those used in Phase 1.
- **Switch 0 confusion**: `sw[0]` is the **rightmost** switch on the Basys 3.
- **Button debounce**: Press buttons firmly for at least 10 ms; do not hold them down across state transitions.

---

## 13. Module Hierarchy

```
crypto_top
│
├── debounce (btn_enter)           [debounce.v]
│     DEBOUNCE_CYCLES = 500_000
│
├── debounce (btn_show)            [debounce.v]
│     DEBOUNCE_CYCLES = 500_000
│
├── uart_rx                        [uart_rx.v]
│     CLKS_PER_BIT = 868
│
├── uart_tx                        [uart_tx.v]
│     CLKS_PER_BIT = 868
│
├── seg7_driver                    [seg7_driver.v]
│     Displays "Enc " or "dEc "
│
└── crypto_fsm                     [crypto_fsm.v]
      │  States: S_ENC_CAESAR_KEY → S_ENC_TRANSPOSE_KEY →
      │          S_RX_AND_CAESAR  → S_ENC_TRANSPOSE →
      │          S_DEC_CAESAR_KEY → S_DEC_TRANSPOSE_KEY →
      │          S_DEC_WAIT_SHOW  → S_TX_SETUP →
      │          S_TX_LOAD → S_TX_WAIT → S_DONE
      │
      └── arithmetic_circuit_8bit  [arithmetic_circuit_8bit.v]
            │  S1=0,S0=1,Cin=0 → ADD  (encrypt)
            │  S1=1,S0=0,Cin=1 → SUB  (decrypt)
            │
            ├── control_circuit × 8  [control_ckt.v]
            │     Conditions each bit of B operand
            │
            └── full_adder × 8       [full_adder.v]
                  │
                  └── half_adder × 2 per FA  [half_adder.v]
```

---

*End of User Manual*
