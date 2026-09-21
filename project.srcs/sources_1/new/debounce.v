`timescale 1ns / 1ps
//=============================================================================
// Module  : debounce
// Purpose : Removes mechanical bounce from push-buttons.
//           Waits for the raw input to stay stable for DEBOUNCE_CYCLES
//           consecutive clock cycles before toggling the clean output.
//           Also generates a single-cycle pulse (o_pulse) on every
//           rising edge of the debounced signal — use this pulse in the FSM
//           so one button press = one event.
//
// Parameters:
//   DEBOUNCE_CYCLES : Number of clocks input must be stable (default 5 ms
//                     at 100 MHz -> 500_000 cycles)
//
// Inputs  : clk, reset, i_raw (bouncy button input, active-HIGH)
// Outputs : o_clean (debounced level), o_pulse (single-cycle rising-edge)
//=============================================================================
module debounce #(
    parameter DEBOUNCE_CYCLES = 500_000  // 5 ms @ 100 MHz
)(
    input  clk,
    input  reset,
    input  i_raw,
    output o_clean,
    output o_pulse
);
    // -----------------------------------------------------------------------
    // Counter: reset whenever input changes; assert clean when it saturates
    // -----------------------------------------------------------------------
    reg [$clog2(DEBOUNCE_CYCLES)-1 : 0] cnt;
    reg clean_r;
    reg prev_clean;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cnt       <= 0;
            clean_r   <= 0;
            prev_clean <= 0;
        end else begin
            prev_clean <= clean_r;          // For edge detection
            if (i_raw == clean_r) begin
                // Input matches current stable value — reset counter
                cnt <= 0;
            end else begin
                if (cnt == DEBOUNCE_CYCLES - 1) begin
                    // Input has been different long enough → latch new value
                    clean_r <= i_raw;
                    cnt     <= 0;
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end

    assign o_clean = clean_r;
    // Rising-edge pulse: high for exactly one clock cycle
    assign o_pulse = clean_r & ~prev_clean;

endmodule
