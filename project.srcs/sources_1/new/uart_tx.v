`timescale 1ns / 1ps
//=============================================================================
// Module  : uart_tx
// Purpose : Standard open-source UART transmitter.
//           Sends one 8N1 serial byte at CLKS_PER_BIT baud.
//
// Inputs  : i_Clock    - system clock
//           i_Tx_DV    - data valid (pulse high for 1 cycle to send i_Tx_Byte)
//           i_Tx_Byte  - byte to transmit
// Outputs : o_Tx_Active - high while transmission is in progress
//           o_Tx_Serial - UART TX pin (RsTx on Basys 3)
//           o_Tx_Done   - single-cycle pulse when byte has been sent
//=============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input        i_Clock,
    input        i_Tx_DV,
    input  [7:0] i_Tx_Byte,
    output reg   o_Tx_Active,
    output reg   o_Tx_Serial,
    output reg   o_Tx_Done
);
    localparam IDLE    = 2'd0;
    localparam START   = 2'd1;
    localparam DATA    = 2'd2;
    localparam STOP    = 2'd3;

    reg [1:0]  r_State       = IDLE;
    reg [15:0] r_Clock_Count = 0;
    reg [2:0]  r_Bit_Index   = 0;
    reg [7:0]  r_Tx_Data     = 0;

    always @(posedge i_Clock) begin
        o_Tx_Done <= 1'b0;

        case (r_State)
            IDLE: begin
                o_Tx_Serial  <= 1'b1;   // Line idle high
                o_Tx_Active  <= 1'b0;
                r_Clock_Count <= 0;
                r_Bit_Index   <= 0;
                if (i_Tx_DV == 1'b1) begin
                    r_Tx_Data <= i_Tx_Byte;
                    r_State   <= START;
                end
            end

            // Send start bit (line low)
            START: begin
                o_Tx_Serial <= 1'b0;
                o_Tx_Active <= 1'b1;
                if (r_Clock_Count < CLKS_PER_BIT - 1)
                    r_Clock_Count <= r_Clock_Count + 1;
                else begin
                    r_Clock_Count <= 0;
                    r_State       <= DATA;
                end
            end

            // Send each data bit LSB first
            DATA: begin
                o_Tx_Serial <= r_Tx_Data[r_Bit_Index];
                o_Tx_Active <= 1'b1;
                if (r_Clock_Count < CLKS_PER_BIT - 1)
                    r_Clock_Count <= r_Clock_Count + 1;
                else begin
                    r_Clock_Count <= 0;
                    if (r_Bit_Index < 7)
                        r_Bit_Index <= r_Bit_Index + 1;
                    else begin
                        r_Bit_Index <= 0;
                        r_State     <= STOP;
                    end
                end
            end

            // Send stop bit (line high)
            STOP: begin
                o_Tx_Serial <= 1'b1;
                o_Tx_Active <= 1'b1;
                if (r_Clock_Count < CLKS_PER_BIT - 1)
                    r_Clock_Count <= r_Clock_Count + 1;
                else begin
                    o_Tx_Done     <= 1'b1;
                    o_Tx_Active   <= 1'b0;
                    r_Clock_Count <= 0;
                    r_State       <= IDLE;
                end
            end

            default: r_State <= IDLE;
        endcase
    end

endmodule
