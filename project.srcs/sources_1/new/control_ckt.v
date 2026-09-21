`timescale 1ns / 1ps
//=============================================================================
// Module  : control_circuit
// Purpose : Conditions one bit of the B operand for the ALU.
//           Truth table (S1, S0):
//             00 -> Y = 0          (Force zero / pass A)
//             01 -> Y = B          (Addition:    A + B)
//             10 -> Y = NOT B      (Subtraction: A + ~B + Cin=1 = A - B)
//             11 -> Y = 1          (Force one)
// Inputs  : B_i (1 bit of B), S1, S0 (operation select)
// Output  : Y_i (conditioned B bit sent to full adder)
//=============================================================================
module control_circuit (
    input  B_i,
    input  S1,
    input  S0,
    output Y_i
);
    wire b_not, and1, and2;

    not (b_not, B_i);           // ~B_i
    and (and1, B_i,   S0);      // B_i  AND S0  (selects B  when S0=1)
    and (and2, b_not, S1);      // ~B_i AND S1  (selects ~B when S1=1)
    or  (Y_i,  and1,  and2);    // Y_i = (B & S0) | (~B & S1)
endmodule
