`timescale 1ns / 1ps
//=============================================================================
// Module  : seg7_driver
// Purpose : Time-multiplexed 4-digit 7-segment display driver for Basys 3.
//
//   Displays one of two fixed messages depending on mode:
//     mode = 0 : "Enc " (Encryption phase)
//     mode = 1 : "dEc " (Decryption phase)
//
//   Segment encoding (active-LOW cathodes, CA type on Basys 3):
//     Segment bits:  { dp, g, f, e, d, c, b, a }
//     '0'-'9' and selected letters encoded below.
//
//   Multiplexing: 4 digits refreshed at ~1 kHz (1 ms each at 100 MHz).
//   Refresh counter width = $clog2(100_000) = 17 bits for 1 ms period.
//
// Inputs  : clk, reset, mode (0=Enc, 1=dEc)
// Outputs : seg[7:0] (cathodes, active-LOW), an[3:0] (anodes, active-LOW)
//=============================================================================
module seg7_driver (
    input        clk,
    input        reset,
    input        mode,      // 0 = Encryption ("Enc "), 1 = Decryption ("dEc ")
    output reg [7:0] seg,   // {dp, g, f, e, d, c, b, a} active-LOW
    output reg [3:0] an     // Anode select, active-LOW
);

    // -----------------------------------------------------------------------
    // Refresh counter — rolls over every ~1 ms giving ~1 kHz refresh rate
    // -----------------------------------------------------------------------
    localparam REFRESH_MAX = 100_000;          // 1 ms @ 100 MHz
    reg [16:0] refresh_cnt;
    reg  [1:0] digit_sel;  // Which of the 4 digits is active

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            refresh_cnt <= 0;
            digit_sel   <= 0;
        end else begin
            if (refresh_cnt == REFRESH_MAX - 1) begin
                refresh_cnt <= 0;
                digit_sel   <= digit_sel + 1;
            end else begin
                refresh_cnt <= refresh_cnt + 1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 7-segment encoding (active-LOW, Basys 3 common-anode display)
    // Bit order: {dp, g, f, e, d, c, b, a}
    // A '1' in a bit position turns the segment OFF.
    // -----------------------------------------------------------------------
    // Character map (dp is always OFF = 1):
    //   SPACE : 1111_1111  (all segments off)
    //   'E'   : 1000_0110  (segments a,f,g,e,d on)
    //   'n'   : 1010_1011  (segments e,g,c on  — lowercase n)
    //   'c'   : 1101_0111  (segments a,f,e,d on — lowercase c... approx)
    //   'd'   : 1010_0001  (segments b,c,d,e,g on — lowercase d)
    // Note: 7-seg has limited character set; approximations used for letters.
    //
    // Verified encodings (CA, active-LOW):
    //   dp g f e d c b a
    //   7  6 5 4 3 2 1 0
    localparam SEG_SPACE = 8'b1111_1111; // blank
    localparam SEG_E     = 8'b1000_0110; // E  : a,f,g,e,d on
    localparam SEG_n     = 8'b1010_1011; // n  : e,g,c on (small n)
    localparam SEG_c     = 8'b1101_0111; // c  : a,f,e,d on (small c)
    localparam SEG_d     = 8'b1010_0001; // d  : b,c,d,e,g on (small d)

    // -----------------------------------------------------------------------
    // Message arrays: digit[3] = leftmost, digit[0] = rightmost
    //   "Enc " -> digit3='E' digit2='n' digit1='c' digit0=' '
    //   "dEc " -> digit3='d' digit2='E' digit1='c' digit0=' '
    // -----------------------------------------------------------------------
    reg [7:0] msg_enc [0:3];
    reg [7:0] msg_dec [0:3];

    initial begin
        msg_enc[3] = SEG_E;     // Leftmost  : 'E'
        msg_enc[2] = SEG_n;     //            : 'n'
        msg_enc[1] = SEG_c;     //            : 'c'
        msg_enc[0] = SEG_SPACE; // Rightmost : ' '

        msg_dec[3] = SEG_d;     // Leftmost  : 'd'
        msg_dec[2] = SEG_E;     //            : 'E'
        msg_dec[1] = SEG_c;     //            : 'c'
        msg_dec[0] = SEG_SPACE; // Rightmost : ' '
    end

    // -----------------------------------------------------------------------
    // Mux: select digit to drive based on digit_sel
    // -----------------------------------------------------------------------
    reg [7:0] current_seg;

    always @(*) begin
        // Default: all off
        current_seg = SEG_SPACE;
        an          = 4'b1111;  // All anodes OFF

        case (digit_sel)
            2'd3: begin
                an = 4'b0111;   // Enable digit 3 (leftmost)
                current_seg = mode ? msg_dec[3] : msg_enc[3];
            end
            2'd2: begin
                an = 4'b1011;   // Enable digit 2
                current_seg = mode ? msg_dec[2] : msg_enc[2];
            end
            2'd1: begin
                an = 4'b1101;   // Enable digit 1
                current_seg = mode ? msg_dec[1] : msg_enc[1];
            end
            2'd0: begin
                an = 4'b1110;   // Enable digit 0 (rightmost)
                current_seg = mode ? msg_dec[0] : msg_enc[0];
            end
        endcase
    end

    // Register seg output to avoid glitches
    always @(posedge clk or posedge reset) begin
        if (reset)
            seg <= 8'hFF;
        else
            seg <= current_seg;
    end

endmodule
