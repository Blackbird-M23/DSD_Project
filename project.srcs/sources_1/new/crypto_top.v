`timescale 1ns / 1ps
//=============================================================================
// Module  : crypto_top  (TOP-LEVEL)
// Project : Hybrid Cryptographic Processor (Caesar + 4x4 Columnar Transposition)
// Target  : Digilent Basys 3 (Artix-7 XC7A35T, 100 MHz)
//
// I/O Summary (Basys 3 headers match XDC constraint file):
//   clk       -> W5  (100 MHz oscillator)
//   reset     -> T18 (BTNC - center button, active-HIGH)
//   sw[15:0]  -> V17..R2 (slide switches)
//   btn_enter -> U18 (BTNU - up button)
//   btn_show  -> T17 (BTNL - left button)
//   RsRx      -> B18 (USB-UART RX)
//   RsTx      -> A18 (USB-UART TX)
//   seg[7:0]  -> W7..U7 (7-segment cathodes)
//   an[3:0]   -> U2..W4 (7-segment anodes)
//   led[3:0]  -> U16..V14 (debug LEDs, optional)
//
// Module hierarchy:
//   crypto_top
//   ├── debounce        (btn_enter)
//   ├── debounce        (btn_show)
//   ├── uart_rx
//   ├── uart_tx
//   ├── seg7_driver
//   └── crypto_fsm
//       └── arithmetic_circuit_8bit  (×1 shared ALU)
//           ├── control_circuit      (×8, generated)
//           └── full_adder           (×8, generated)
//               └── half_adder       (×2 each)
//=============================================================================
module crypto_top (
    input        clk,       // 100 MHz system clock
    input        reset,     // Asynchronous reset (BTNC, active-HIGH)

    input [15:0] sw,        // Slide switches

    input        btn_enter, // BTNU — lock in key from switches
    input        btn_show,  // BTNL — trigger UART output of memory

    input        RsRx,      // UART receive (from PC)
    output       RsTx,      // UART transmit (to PC)

    output [7:0] seg,       // 7-segment cathodes (active-LOW)
    output [3:0] an,        // 7-segment anodes   (active-LOW)

    output [3:0] led        // Debug status LEDs
);

    //=========================================================================
    // Parameter
    //=========================================================================
    // Baud rate: 115200 @ 100 MHz -> CLKS_PER_BIT = 100_000_000 / 115200 = 868
    localparam CLKS_PER_BIT = 868;

    //=========================================================================
    // Internal wires
    //=========================================================================

    // Debounced button signals
    wire btn_enter_pulse;
    wire btn_show_pulse;

    // UART RX outputs
    wire       rx_dv;
    wire [7:0] rx_byte;

    // UART TX inputs/outputs
    wire [7:0] tx_byte;
    wire       tx_dv;
    wire       tx_active;
    wire       tx_done;
    wire       tx_serial;

    // Display mode (from FSM)
    wire       disp_mode;

    // Status LEDs (from FSM)
    wire [3:0] status_leds;

    //=========================================================================
    // Button Debouncers
    // Uses 5 ms debounce window (500_000 cycles at 100 MHz).
    // o_pulse is a single-cycle rising-edge pulse — safe for FSM transitions.
    //=========================================================================
    debounce #(.DEBOUNCE_CYCLES(500_000)) db_enter (
        .clk     (clk),
        .reset   (reset),
        .i_raw   (btn_enter),
        .o_clean (/* unused level */),
        .o_pulse (btn_enter_pulse)
    );

    debounce #(.DEBOUNCE_CYCLES(500_000)) db_show (
        .clk     (clk),
        .reset   (reset),
        .i_raw   (btn_show),
        .o_clean (/* unused level */),
        .o_pulse (btn_show_pulse)
    );

    //=========================================================================
    // UART Receiver
    //=========================================================================
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx_inst (
        .i_Clock     (clk),
        .i_Rx_Serial (RsRx),
        .o_Rx_DV     (rx_dv),
        .o_Rx_Byte   (rx_byte)
    );

    //=========================================================================
    // UART Transmitter
    //=========================================================================
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx_inst (
        .i_Clock     (clk),
        .i_Tx_DV     (tx_dv),
        .i_Tx_Byte   (tx_byte),
        .o_Tx_Active (tx_active),
        .o_Tx_Serial (tx_serial),
        .o_Tx_Done   (tx_done)
    );

    // Connect TX serial output to physical pin
    assign RsTx = tx_serial;

    //=========================================================================
    // 7-Segment Display Driver
    //=========================================================================
    seg7_driver display (
        .clk      (clk),
        .reset    (reset),
        .mode     (disp_mode),  // 0 = "Enc ", 1 = "dEc "
        .seg      (seg),
        .an       (an)
    );

    //=========================================================================
    // Cryptographic FSM (contains the single matrix and the ALU)
    //=========================================================================
    crypto_fsm fsm (
        .clk             (clk),
        .reset           (reset),
        .sw              (sw),
        .btn_enter_pulse (btn_enter_pulse),
        .btn_show_pulse  (btn_show_pulse),
        .rx_dv           (rx_dv),
        .rx_byte         (rx_byte),
        .tx_byte         (tx_byte),
        .tx_dv           (tx_dv),
        .tx_active       (tx_active),
        .disp_mode       (disp_mode),
        .status_leds     (status_leds)
    );

    //=========================================================================
    // LED Output
    //=========================================================================
    assign led = status_leds;

endmodule
