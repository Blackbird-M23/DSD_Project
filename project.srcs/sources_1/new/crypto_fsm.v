`timescale 1ns / 1ps
//=============================================================================
// Module  : crypto_fsm
// Purpose : Core FSM for the Hybrid Cryptographic Processor.
//           Orchestrates:
//             Phase 1 (Encryption)
//               - Key entry via switches + btn_enter
//               - UART receive + Caesar encrypt via custom ALU
//               - 4x4 columnar transposition of the 16-byte matrix
//             Phase 2 (Decryption / Output)
//               - Decryption key entry
//               - On-the-fly: inverse transpose index + Caesar decrypt
//               - UART transmit decrypted bytes
//
//   The 16-byte matrix is declared here and ONLY here (single source).
//
// ALU usage:
//   Add (Encrypt) : S1=0, S0=1, Cin=0  -> F = A + B
//   Sub (Decrypt) : S1=1, S0=0, Cin=1  -> F = A - B
//
// Columnar Transposition (4x4):
//   Matrix layout (row-major, index 0..15):
//     [0]  [1]  [2]  [3]
//     [4]  [5]  [6]  [7]
//     [8]  [9]  [10] [11]
//     [12] [13] [14] [15]
//   sw[3:0] provides the column order key: col[3]=sw[3:2], col[2]=sw[3:2]...
//   Implementation uses sw[3:0] as a 4-bit key where each 2-bit pair
//   selects a column priority (see column permutation logic below).
//=============================================================================
module crypto_fsm (
    input        clk,
    input        reset,

    // Switch & button inputs (already debounced pulses from top)
    input [15:0] sw,
    input        btn_enter_pulse,   // single-cycle pulse from debouncer
    input        btn_show_pulse,    // single-cycle pulse from debouncer

    // UART RX
    input        rx_dv,             // Data valid from uart_rx
    input  [7:0] rx_byte,           // Received byte from uart_rx

    // UART TX
    output reg [7:0] tx_byte,       // Byte to send
    output reg       tx_dv,         // Trigger transmit (1-cycle pulse)
    input            tx_active,     // Transmitter busy flag

    // Display mode (0=Enc, 1=dEc) to seg7_driver
    output reg       disp_mode,

    // Status LEDs (optional, map to Basys 3 LEDs for debug)
    output reg [3:0] status_leds
);

    //=========================================================================
    // FSM State Encoding
    //=========================================================================
    localparam [3:0]
        S_ENC_CAESAR_KEY    = 4'd0,  // Wait for Caesar key (sw + btn_enter)
        S_ENC_TRANSPOSE_KEY = 4'd1,  // Wait for transpose key (sw + btn_enter)
        S_RX_AND_CAESAR     = 4'd2,  // Receive 16 UART bytes + Caesar encrypt
        S_ENC_TRANSPOSE     = 4'd3,  // Apply 4x4 columnar transposition
        S_DEC_CAESAR_KEY    = 4'd4,  // Wait for decrypt Caesar key
        S_DEC_TRANSPOSE_KEY = 4'd5,  // Wait for decrypt transpose key
        S_DEC_WAIT_SHOW     = 4'd6,  // Wait for btn_show
        S_TX_SETUP          = 4'd7,  // Compute on-the-fly decrypt index
        S_TX_LOAD           = 4'd8,  // Load ALU result into tx_byte, pulse tx_dv
        S_TX_WAIT           = 4'd9,  // Wait for tx_active to drop
        S_DONE              = 4'd10; // All bytes sent, idle

    reg [3:0] state;

    //=========================================================================
    // Single 16-byte memory (DO NOT DUPLICATE)
    //=========================================================================
    reg [7:0] matrix [0:15];

    //=========================================================================
    // Key registers
    //=========================================================================
    reg [7:0] enc_caesar_key;   // Caesar shift for encryption
    reg [3:0] enc_trans_key;    // Transposition column order for encryption
    reg [7:0] dec_caesar_key;   // Caesar shift for decryption
    reg [3:0] dec_trans_key;    // Transposition column order for decryption

    //=========================================================================
    // Counters
    //=========================================================================
    reg [3:0] rx_count;         // Counts received bytes 0..15
    reg [3:0] tx_count;         // Counts transmitted bytes 0..15
    reg [4:0] trans_step;       // Step counter for transposition state

    //=========================================================================
    // ALU interface wires (combinatorial)
    //=========================================================================
    reg  [7:0] alu_A;
    reg  [7:0] alu_B;
    reg        alu_S1;
    reg        alu_S0;
    reg        alu_Cin;
    wire [7:0] alu_F;
    wire       alu_Cout;

    arithmetic_circuit_8bit ALU (
        .A   (alu_A),
        .B   (alu_B),
        .S1  (alu_S1),
        .S0  (alu_S0),
        .Cin (alu_Cin),
        .F   (alu_F),
        .Cout(alu_Cout)
    );

    //=========================================================================
    // Transposition helper
    // Column permutation derived from enc_trans_key / dec_trans_key.
    // The 4-bit key is interpreted as a priority order for 4 columns:
    //   col_order[0..3] = { key[3:2]+1 mod 4, key[1:0]+0 mod 4, ... }
    // Simple approach: the 4-bit key directly gives the column permutation:
    //   bit[1:0] -> which physical column goes to output column 0
    //   bit[3:2] -> which physical column goes to output column 1
    //   columns 2 and 3 fill remaining slots in ascending order.
    // For transmission the permuted index maps back to matrix read address.
    //=========================================================================

    // Derive a 4-element permutation array from a 4-bit key.
    // Returns: perm[output_col] = source_col
    // Encoding: key[1:0] = first output col source, key[3:2] = second.
    // The two remaining columns fill perm[2] and perm[3] in order.
    function [7:0] make_perm;  // returns 8 bits = 4 x 2-bit fields
        input [3:0] key;
        reg [1:0] p0, p1, p2, p3;
        reg [3:0] used;
        integer k;
        begin
            p0   = key[1:0];            // Column for output position 0
            p1   = key[3:2];            // Column for output position 1
            used = 4'b0000;
            used[p0] = 1'b1;
            used[p1] = 1'b1;
            // Fill p2, p3 with unused columns in ascending order
            p2 = 2'd0; p3 = 2'd0;
            k = 0;
            begin : fill_loop
                integer j;
                integer filled;
                filled = 0;
                for (j = 0; j < 4; j = j + 1) begin
                    if (!used[j] && filled == 0) begin
                        p2     = j[1:0];
                        filled = 1;
                    end else if (!used[j] && filled == 1) begin
                        p3     = j[1:0];
                        filled = 2;
                    end
                end
            end
            make_perm = {p3, p2, p1, p0}; // Pack: bits[1:0]=p0 bits[3:2]=p1 etc.
        end
    endfunction

    // Transpose permutation during encryption phase (writes new matrix)
    reg [7:0] enc_perm_packed;
    reg [7:0] dec_perm_packed;

    // Unpack permutation: perm_col(n) returns the 2-bit column index for output slot n
    function [1:0] perm_col;
        input [7:0] packed;
        input [1:0] slot;
        begin
            case (slot)
                2'd0: perm_col = packed[1:0];
                2'd1: perm_col = packed[3:2];
                2'd2: perm_col = packed[5:4];
                2'd3: perm_col = packed[7:6];
            endcase
        end
    endfunction

    // Compute matrix read address for TX:
    // Output byte tx_count is at position (tx_count) in the transposed matrix.
    // In column-major transposition, output byte n = matrix[col*4 + row]
    // where col = n % 4, row = n / 4 under the original order, but here
    // we send row-major of the transposed result.
    // Transposed byte at (out_row, out_col): source = matrix[out_row*4 + perm_col(out_col)]
    function [3:0] tx_matrix_index;
        input [3:0]  tx_cnt;
        input [7:0]  perm;
        reg   [1:0]  out_row, out_col;
        reg   [1:0]  src_col;
        begin
            out_row = tx_cnt[3:2];   // tx_cnt / 4
            out_col = tx_cnt[1:0];   // tx_cnt % 4
            src_col = perm_col(perm, out_col);
            tx_matrix_index = {out_row, src_col}; // out_row*4 + src_col
        end
    endfunction

    //=========================================================================
    // Transposition scratch buffer (used during S_ENC_TRANSPOSE)
    //=========================================================================
    reg [7:0] trans_buf [0:15];
    reg [3:0] trans_write_ptr;

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state           <= S_ENC_CAESAR_KEY;
            rx_count        <= 4'd0;
            tx_count        <= 4'd0;
            trans_step      <= 5'd0;
            trans_write_ptr <= 4'd0;
            tx_dv           <= 1'b0;
            tx_byte         <= 8'h00;
            disp_mode       <= 1'b0; // Show "Enc"
            status_leds     <= 4'b0000;
            enc_caesar_key  <= 8'd0;
            enc_trans_key   <= 4'd0;
            dec_caesar_key  <= 8'd0;
            dec_trans_key   <= 4'd0;
            enc_perm_packed <= 8'd0;
            dec_perm_packed <= 8'd0;
        end else begin
            // Default: no TX trigger
            tx_dv <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // Phase 1: Encryption Key Entry
                //-------------------------------------------------------------

                // STATE 0: Wait for user to set Caesar key on sw[7:0], press btn_enter
                S_ENC_CAESAR_KEY: begin
                    disp_mode   <= 1'b0;        // Display "Enc"
                    status_leds <= 4'b0001;
                    if (btn_enter_pulse) begin
                        enc_caesar_key <= sw[7:0];  // Latch lower 8 switch bits
                        state          <= S_ENC_TRANSPOSE_KEY;
                    end
                end

                // STATE 1: Wait for transposition key on sw[3:0], press btn_enter
                S_ENC_TRANSPOSE_KEY: begin
                    status_leds <= 4'b0011;
                    if (btn_enter_pulse) begin
                        enc_trans_key   <= sw[3:0];
                        enc_perm_packed <= make_perm(sw[3:0]);
                        rx_count        <= 4'd0;
                        state           <= S_RX_AND_CAESAR;
                    end
                end

                //-------------------------------------------------------------
                // STATE 2: Receive 16 UART bytes, Caesar-encrypt via ALU, store
                //-------------------------------------------------------------
                S_RX_AND_CAESAR: begin
                    status_leds <= 4'b0111;
                    if (rx_dv) begin
                        // ALU wired combinatorially; result available immediately.
                        // Capture alu_F into matrix at current rx_count index.
                        matrix[rx_count] <= alu_F;  // alu_F = rx_byte + enc_caesar_key
                        rx_count         <= rx_count + 1;
                        if (rx_count == 4'd15)
                            state <= S_ENC_TRANSPOSE;
                    end
                end

                //-------------------------------------------------------------
                // STATE 3: Columnar transposition (1 output byte per clock)
                // Reads matrix in column-major order defined by enc_perm,
                // writes result into trans_buf, then copies back to matrix.
                //-------------------------------------------------------------
                S_ENC_TRANSPOSE: begin
                    status_leds <= 4'b1111;
                    if (trans_step < 5'd16) begin
                        // Each trans_step corresponds to one output byte:
                        //   output slot n -> src matrix[row*4 + perm_col(col)]
                        trans_buf[trans_step[3:0]] <=
                            matrix[tx_matrix_index(trans_step[3:0], enc_perm_packed)];
                        trans_step <= trans_step + 1;
                    end else if (trans_step < 5'd17) begin
                        // Copy trans_buf back to matrix (can take 16 more cycles)
                        // Using a second pass with the same step counter offset
                        trans_step <= trans_step + 1;
                    end else if (trans_step <= 5'd31) begin
                        matrix[trans_step - 5'd17] <= trans_buf[trans_step - 5'd17];
                        if (trans_step == 5'd31) begin
                            trans_step  <= 5'd0;
                            state       <= S_DEC_CAESAR_KEY;
                        end else
                            trans_step <= trans_step + 1;
                    end
                end

                //-------------------------------------------------------------
                // Phase 2: Decryption Key Entry
                //-------------------------------------------------------------

                // STATE 4: Wait for decryption Caesar key on sw[7:0], btn_enter
                S_DEC_CAESAR_KEY: begin
                    disp_mode   <= 1'b1;        // Display "dEc"
                    status_leds <= 4'b1000;
                    if (btn_enter_pulse) begin
                        dec_caesar_key <= sw[7:0];
                        state          <= S_DEC_TRANSPOSE_KEY;
                    end
                end

                // STATE 5: Wait for decryption transposition key on sw[3:0], btn_enter
                S_DEC_TRANSPOSE_KEY: begin
                    status_leds <= 4'b1100;
                    if (btn_enter_pulse) begin
                        dec_trans_key   <= sw[3:0];
                        dec_perm_packed <= make_perm(sw[3:0]);
                        state           <= S_DEC_WAIT_SHOW;
                    end
                end

                // STATE 6: Wait for btn_show press
                S_DEC_WAIT_SHOW: begin
                    status_leds <= 4'b1110;
                    if (btn_show_pulse) begin
                        tx_count <= 4'd0;
                        state    <= S_TX_SETUP;
                    end
                end

                //-------------------------------------------------------------
                // STATE 7: Compute which matrix byte to read for tx_count
                //-------------------------------------------------------------
                S_TX_SETUP: begin
                    // Combinatorial: alu_A is assigned in the always @(*) block
                    // below using tx_matrix_index(tx_count, dec_perm_packed).
                    // ALU performs subtraction: F = matrix[idx] - dec_caesar_key
                    // Just move to S_TX_LOAD on the next clock (ALU stable).
                    state <= S_TX_LOAD;
                end

                // STATE 8: Load ALU output, trigger TX
                S_TX_LOAD: begin
                    if (!tx_active) begin
                        tx_byte <= alu_F;   // Decrypted byte from ALU
                        tx_dv   <= 1'b1;    // Pulse to start UART TX
                        state   <= S_TX_WAIT;
                    end
                end

                // STATE 9: Wait for TX to complete
                S_TX_WAIT: begin
                    tx_dv <= 1'b0;
                    if (!tx_active) begin
                        if (tx_count == 4'd15)
                            state <= S_DONE;
                        else begin
                            tx_count <= tx_count + 1;
                            state    <= S_TX_SETUP;
                        end
                    end
                end

                S_DONE: begin
                    status_leds <= 4'b0000;
                    // Remain idle until reset
                end

                default: state <= S_ENC_CAESAR_KEY;
            endcase
        end
    end

    //=========================================================================
    // Combinatorial ALU input mux
    // During RX phase: ALU adds rx_byte + enc_caesar_key
    // During TX phase: ALU subtracts matrix[idx] - dec_caesar_key
    //=========================================================================
    always @(*) begin
        // Defaults
        alu_A   = 8'h00;
        alu_B   = 8'h00;
        alu_S1  = 1'b0;
        alu_S0  = 1'b0;
        alu_Cin = 1'b0;

        case (state)
            //------------------------------------------------------------------
            // Encryption: F = A + B  (S1=0, S0=1, Cin=0)
            //------------------------------------------------------------------
            S_RX_AND_CAESAR: begin
                alu_A   = rx_byte;
                alu_B   = enc_caesar_key;
                alu_S1  = 1'b0;  // S1=0
                alu_S0  = 1'b1;  // S0=1 -> Y = B (pass B through)
                alu_Cin = 1'b0;  // No extra carry
            end

            //------------------------------------------------------------------
            // Decryption: F = A - B  (S1=1, S0=0, Cin=1  -> A + ~B + 1)
            //------------------------------------------------------------------
            S_TX_SETUP,
            S_TX_LOAD,
            S_TX_WAIT: begin
                // Read the correct transposition index for this tx_count
                alu_A   = matrix[tx_matrix_index(tx_count, dec_perm_packed)];
                alu_B   = dec_caesar_key;
                alu_S1  = 1'b1;  // S1=1 -> Y = ~B
                alu_S0  = 1'b0;  // S0=0
                alu_Cin = 1'b1;  // Cin=1 -> 2's complement subtraction
            end

            default: begin
                alu_A   = 8'h00;
                alu_B   = 8'h00;
                alu_S1  = 1'b0;
                alu_S0  = 1'b0;
                alu_Cin = 1'b0;
            end
        endcase
    end

endmodule
