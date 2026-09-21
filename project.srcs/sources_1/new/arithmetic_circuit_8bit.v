`timescale 1ns / 1ps
//=============================================================================
// Module  : arithmetic_circuit_8bit
// Purpose : Custom 8-bit ALU built from structural full adders and control
//           circuits. Supports addition and 2's-complement subtraction.
//
//  Operation encoding (S1, S0, Cin):
//    Add  : S1=0, S0=1, Cin=0  -> F = A + B
//    Sub  : S1=1, S0=0, Cin=1  -> F = A - B  (A + ~B + 1)
//
// Inputs  : A[7:0]  - data operand (plaintext / ciphertext byte)
//           B[7:0]  - key operand  (Caesar shift key)
//           S1, S0  - operation select (drives control_circuit)
//           Cin     - carry-in (must be 1 for subtraction)
// Outputs : F[7:0]  - result
//           Cout    - carry out (overflow indicator)
//=============================================================================
module arithmetic_circuit_8bit (
    input  [7:0] A,
    input  [7:0] B,
    input        S1,
    input        S0,
    input        Cin,
    output [7:0] F,
    output       Cout
);
    wire [7:0] Y;       // Conditioned B bits
    wire [8:0] C;       // Carry chain: C[0]=Cin ... C[8]=Cout

    assign C[0] = Cin;  // Feed carry-in to bit-0 slice

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : alu_slice
            // Step 1: condition the i-th bit of B through the control circuit
            control_circuit ic (
                .B_i(B[i]),
                .S1 (S1),
                .S0 (S0),
                .Y_i(Y[i])
            );
            // Step 2: full adder accumulates A[i], conditioned B[i], and carry
            full_adder fa (
                .a   (A[i]),
                .b   (Y[i]),
                .cin (C[i]),
                .sum (F[i]),
                .cout(C[i+1])
            );
        end
    endgenerate

    assign Cout = C[8]; // Propagate final carry out
endmodule
