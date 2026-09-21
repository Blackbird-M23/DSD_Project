`timescale 1ns / 1ps
//=============================================================================
// Module  : full_adder
// Purpose : 1-bit full adder built from two half adders (structural)
// Inputs  : a, b, cin
// Outputs : sum, cout
//=============================================================================
module full_adder (
    input  a,
    input  b,
    input  cin,
    output sum,
    output cout
);
    wire s1, c1, c2;

    // First half adder computes partial sum and carry from a, b
    half_adder ha1 (.a(a),  .b(b),   .sum(s1),  .carry(c1));
    // Second half adder adds partial sum with carry-in
    half_adder ha2 (.a(s1), .b(cin), .sum(sum), .carry(c2));

    // Final carry is OR of both intermediate carries
    assign cout = c1 | c2;
endmodule
