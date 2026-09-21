`timescale 1ns / 1ps
//=============================================================================
// Module  : uart_rx
// Purpose : Standard open-source UART receiver.
//           Receives one 8N1 serial byte at the baud rate defined by
//           CLKS_PER_BIT = (system clock Hz) / (baud rate).
//           For Basys 3 @ 100 MHz, 115200 baud: CLKS_PER_BIT = 868.
//
// Inputs  : i_Clock      - system clock
//           i_Rx_Serial  - UART RX pin (RsRx on Basys 3)
// Outputs : o_Rx_DV      - data valid pulse (1 clock wide, high when byte ready)
//           o_Rx_Byte    - received byte [7:0]
//
// NOTE: This is a standard, portable UART RX implementation.
//       Replace with your preferred uart_rx if you have one.
//=============================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input        i_Clock,
    input        i_Rx_Serial,
    output reg   o_Rx_DV,
    output reg [7:0] o_Rx_Byte
);
    // State encoding
    localparam IDLE    = 2'd0;
    localparam START   = 2'd1;
    localparam DATA    = 2'd2;
    localparam STOP    = 2'd3;

    reg [1:0]  r_State      = IDLE;
    reg [15:0] r_Clock_Count = 0;
    reg [2:0]  r_Bit_Index   = 0;
    reg [7:0]  r_Rx_Byte     = 0;
    reg        r_Rx_DV       = 0;
    reg        r_Rx_Data_R   = 1'b1; // Registered input (metastability)
    reg        r_Rx_Data_RR  = 1'b1;

    // Double-register for metastability
    always @(posedge i_Clock) begin
        r_Rx_Data_R  <= i_Rx_Serial;
        r_Rx_Data_RR <= r_Rx_Data_R;
    end

    always @(posedge i_Clock) begin
        o_Rx_DV <= 1'b0; // Default: pulse low every cycle

        case (r_State)
            IDLE: begin
                r_Clock_Count <= 0;
                r_Bit_Index   <= 0;
                if (r_Rx_Data_RR == 1'b0)   // Detected start bit (line low)
                    r_State <= START;
            end

            // Check mid-point of start bit to confirm it's valid
            START: begin
                if (r_Clock_Count == (CLKS_PER_BIT-1)/2) begin
                    if (r_Rx_Data_RR == 1'b0) begin
                        r_Clock_Count <= 0;
                        r_State       <= DATA;
                    end else
                        r_State <= IDLE;  // False start
                end else
                    r_Clock_Count <= r_Clock_Count + 1;
            end

            // Sample each data bit at center
            DATA: begin
                if (r_Clock_Count < CLKS_PER_BIT - 1)
                    r_Clock_Count <= r_Clock_Count + 1;
                else begin
                    r_Clock_Count             <= 0;
                    r_Rx_Byte[r_Bit_Index]    <= r_Rx_Data_RR;
                    if (r_Bit_Index < 7)
                        r_Bit_Index <= r_Bit_Index + 1;
                    else begin
                        r_Bit_Index <= 0;
                        r_State     <= STOP;
                    end
                end
            end

            // Wait for stop bit then signal data valid
            STOP: begin
                if (r_Clock_Count < CLKS_PER_BIT - 1)
                    r_Clock_Count <= r_Clock_Count + 1;
                else begin
                    o_Rx_DV       <= 1'b1;
                    o_Rx_Byte     <= r_Rx_Byte;
                    r_Clock_Count <= 0;
                    r_State       <= IDLE;
                end
            end

            default: r_State <= IDLE;
        endcase
    end

endmodule
