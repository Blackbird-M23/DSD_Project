`timescale 1ns / 1ps
//=============================================================================
// Module  : half_adder
// Purpose : Computes 1-bit sum and carry (structural, no behavioral operators)
// Inputs  : a, b
// Outputs : sum (a XOR b), carry (a AND b)
//=============================================================================
module half_adder (
    input  a,
    input  b,
    output sum,
    output carry
);
    assign sum   = a ^ b;   // XOR  -> partial sum
    assign carry = a & b;   // AND  -> carry out
endmodule
