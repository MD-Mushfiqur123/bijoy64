// ---------------------------------------------------------------------------
// alu64.v -- MX-Hpi-1 64-bit ALU (combinational)
// op coding matches tools/assembler.py R-type opcode minus 1:
//   0 ADD, 1 SUB, 2 AND, 3 OR, 4 XOR, 5 SLL, 6 SRL, 7 SRA,
//   8 SLT, 9 SLTU, 10 MUL, 11 DIV, 12 REM (DIV/REM are multi-cycle:
//   handled by div64.v in the core; the ALU ties those ops to 0)
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module alu64 (
    input  wire [3:0]  op,
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] y
);

    wire signed [63:0] a_s = a;
    wire signed [63:0] b_s = b;

    always @* begin
        case (op)
            4'd0:  y = a + b;                                  // ADD
            4'd1:  y = a - b;                                  // SUB
            4'd2:  y = a & b;                                  // AND
            4'd3:  y = a | b;                                  // OR
            4'd4:  y = a ^ b;                                  // XOR
            4'd5:  y = a << b[5:0];                            // SLL
            4'd6:  y = a >> b[5:0];                            // SRL
            4'd7:  y = a_s >>> b[5:0];                         // SRA
            4'd8:  y = (a_s < b_s) ? 64'd1 : 64'd0;            // SLT
            4'd9:  y = (a   < b  ) ? 64'd1 : 64'd0;            // SLTU
            4'd10: y = a_s * b_s;                              // MUL (low 64)
                                                          // DIV/REM: div64.v
            default: y = 64'd0;
        endcase
    end

endmodule
