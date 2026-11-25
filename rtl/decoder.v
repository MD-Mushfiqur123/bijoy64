// ---------------------------------------------------------------------------
// decoder.v -- BIJOY-64 instruction decoder (combinational, ID stage)
// Field geometry (docs/ISA.md):
//   op  = ins[31:26]   rd = ins[25:22]   rs1 = ins[21:18]   rs2 = ins[17:14]
//   I-type: imm18 = ins[17:0]                    (signed, except LODI / ORI -> zero ext)
//   S-type: imm12 = ins[13:2]                    (signed)
//   B-type: imm12 = ins[13:2], target = pc + imm12<<2
//   J-type: off22 = ins[21:0], target = pc + off22<<2
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module decoder (
    input  wire [31:0] ins,

    output wire [3:0]  rd,
    output wire [3:0]  rs1,
    output wire [3:0]  rs2,

    output reg  [63:0] imm18,     // sext(ins[17:0])     (I-type ops)
    output wire [63:0] imm_s,     // sext(ins[13:2])     (ST address)
    output wire [63:0] imm_b,     // sext(ins[13:2])<<2  (branch target)
    output wire [63:0] imm_j,     // sext(ins[21:0])<<2  (JAL target)

    output reg  [3:0]  aluop,     // matches alu64.v coding
    output reg         a_zero,    // EX: alu operand A forced to 0 (LODI)
    output reg         b_imm,     // EX: alu operand B from immediate
    output reg         b_s12,     // EX: ... use imm_s (ST) instead of imm18
    output reg         rd_wren,
    output reg         mem_re,
    output reg         mem_we,
    output reg         is_branch, // conditional branch
    output reg  [2:0]  cmp_op,    // 0 EQ, 1 NE, 2 LT, 3 GE, 4 LTU, 5 GEU
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_link,   // write pc+4 into rd (JAL / JALR)
    output reg         is_halt,
    output reg         uses_rs1,  // needed for load-use stall detection
    output reg         uses_rs2
);

    wire [5:0] op = ins[31:26];

    assign rd   = ins[25:22];
    assign rs1  = ins[21:18];
    assign rs2  = ins[17:14];

    wire [63:0] i18 = {{46{ins[17]}}, ins[17:0]};
    wire [63:0] i12 = {{52{ins[13]}}, ins[13:2]};
    wire [63:0] i22 = {{42{ins[21]}}, ins[21:0]};

    assign imm18 = i18;
    assign imm_s = i12;
    assign imm_b = {i12[61:0], 2'b00};
    assign imm_j = {i22[61:0], 2'b00};

    // ALU op coding == assembler R-type opcode minus 1 (branch-free decode)
    wire [3:0] alu_of_rtype = op[3:0] - 4'd1;

    // I-type ALU ops need an explicit mapping into the alu64 coding
    reg [3:0] alu_of_itype;
    always @* begin
        case (op)
            6'h10:    alu_of_itype = 4'd0;  // ADDI -> ADD
            6'h11:    alu_of_itype = 4'd2;  // ANDI -> AND
            6'h12:    alu_of_itype = 4'd3;  // ORI  -> OR
            6'h13:    alu_of_itype = 4'd4;  // XORI -> XOR
            6'h14:    alu_of_itype = 4'd5;  // SLLI -> SLL
            6'h15:    alu_of_itype = 4'd6;  // SRLI -> SRL
            6'h16:    alu_of_itype = 4'd7;  // SRAI -> SRA
            6'h17:    alu_of_itype = 4'd8;  // SLTI -> SLT
            default:  alu_of_itype = 4'd9;  // SLTIU -> SLTU
        endcase
    end

    always @* begin
        // defaults: bubble
        aluop     = 4'd0;
        a_zero    = 1'b0;
        b_imm     = 1'b0;
        b_s12     = 1'b0;
        rd_wren   = 1'b0;
        mem_re    = 1'b0;
        mem_we    = 1'b0;
        is_branch = 1'b0;
        cmp_op    = 3'd0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        is_link   = 1'b0;
        is_halt   = 1'b0;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;

        case (op)
            // ---- R-type: 0x01..0x0D ----
            6'h01, 6'h02, 6'h03, 6'h04, 6'h05, 6'h06, 6'h07,
            6'h08, 6'h09, 6'h0A, 6'h0B, 6'h0C, 6'h0D: begin
                aluop    = alu_of_rtype;
                rd_wren  = 1'b1;
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end

            // ---- I-type ALU (ADDI ANDI ORI XORI, shifts, SLTI SLTIU) ----
            6'h10, 6'h11, 6'h12, 6'h13, 6'h14, 6'h15, 6'h16, 6'h17, 6'h18: begin
                aluop    = alu_of_itype;
                b_imm    = 1'b1;
                rd_wren  = 1'b1;
                uses_rs1 = 1'b1;
            end

            6'h19: begin                            // LODI (zero-extended, rs1 ignored)
                aluop    = 4'd0;                    // ADD
                a_zero   = 1'b1;
                b_imm    = 1'b1;
                rd_wren  = 1'b1;
            end

            6'h1A: begin                            // LD
                aluop    = 4'd0;                    // ADD (address)
                b_imm    = 1'b1;
                rd_wren  = 1'b1;
                mem_re   = 1'b1;
                uses_rs1 = 1'b1;
            end

            6'h20: begin                            // ST
                aluop    = 4'd0;                    // ADD (address)
                b_imm    = 1'b1;
                b_s12    = 1'b1;
                mem_we   = 1'b1;
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end

            // ---- B-type: 0x30..0x35 ----
            6'h30, 6'h31, 6'h32, 6'h33, 6'h34, 6'h35: begin
                is_branch = 1'b1;
                cmp_op    = op - 6'h30;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
            end

            6'h3D: begin                            // JALR
                is_jalr   = 1'b1;
                is_link   = 1'b1;
                rd_wren   = 1'b1;
                uses_rs1  = 1'b1;
            end

            6'h3E: begin                            // JAL
                is_jal    = 1'b1;
                is_link   = 1'b1;
                rd_wren   = 1'b1;
            end

            6'h00: begin                            // HLT
                is_halt = 1'b1;
            end

            default: ;                              // reserved: behaves as NOP
        endcase
    end

endmodule
