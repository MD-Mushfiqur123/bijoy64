// ---------------------------------------------------------------------------
// bijoy64_core.v -- BIJOY-64 5-stage pipelined core (IF ID EX MEM WB)
//
//   * full EX/MEM->EX and MEM/WB->EX forwarding
//   * load-use hazard: 1-cycle bubble (IF/ID stalls, ID/EX flushed)
//   * branches/JAL/JALR resolved in EX; taken -> flush IF/ID & ID/EX,
//     IF redirected (static predict-not-taken, 2-cycle mispredict penalty)
//   * HLT stops fetch, drains the pipe, raises `halted`
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module bijoy64_core (
    input  wire        clk,
    input  wire        rst_n,

    output wire [63:0] imem_addr,
    input  wire [31:0] imem_rdata,

    output wire [63:0] dmem_addr,
    output wire        dmem_re,
    output wire        dmem_we,
    output wire [63:0] dmem_wdata,
    input  wire [63:0] dmem_rdata,

    output wire        halted
);

    // forward declarations of stage registers used across stages
    reg         id_ex_valid;
    reg  [63:0] id_ex_pc;
    reg  [63:0] id_ex_rs1val, id_ex_rs2val;
    reg  [63:0] id_ex_imm18, id_ex_imm_s, id_ex_imm_b, id_ex_imm_j;
    reg  [3:0]  id_ex_rd, id_ex_rs1, id_ex_rs2;
    reg  [3:0]  id_ex_aluop;
    reg         id_ex_a_zero, id_ex_b_imm, id_ex_b_s12, id_ex_rd_wren;
    reg         id_ex_mem_re, id_ex_mem_we;
    reg         id_ex_is_br, id_ex_is_jal, id_ex_is_jalr, id_ex_is_link, id_ex_is_halt;
    reg  [2:0]  id_ex_cmp_op;

    reg         ex_mem_valid;
    reg  [63:0] ex_mem_val;       // result value (alu result or pc+4 link)
    reg  [63:0] ex_mem_addr;      // dmem address
    reg  [63:0] ex_mem_stdata;    // store data
    reg  [3:0]  ex_mem_rd;
    reg         ex_mem_rd_wren, ex_mem_mem_re, ex_mem_mem_we;

    reg         mem_wb_valid;
    reg  [63:0] mem_wb_val;
    reg  [3:0]  mem_wb_rd;
    reg         mem_wb_rd_wren;

    // =====================================================================
    // IF
    // =====================================================================
    reg         halted_q;
    reg  [63:0] pc_q;

    wire        ex_taken;
    wire [63:0] ex_target;

    wire        if_stall;
    wire        fetch_en = !halted_q && !if_stall;

    assign imem_addr = pc_q;

    // =====================================================================
    // IF/ID + decode
    // =====================================================================
    reg         if_id_valid;
    reg  [63:0] if_id_pc;
    reg  [31:0] if_id_ins;

    wire [3:0]  id_rd, id_rs1, id_rs2;
    wire [63:0] id_imm18, id_imm_s, id_imm_b, id_imm_j;
    wire [3:0]  id_aluop;
    wire        id_a_zero, id_b_imm, id_b_s12, id_rd_wren;
    wire        id_mem_re, id_mem_we, id_is_br, id_is_jal, id_is_jalr, id_is_link, id_is_halt;
    wire [2:0]  id_cmp_op;
    wire        id_uses_rs1, id_uses_rs2;

    decoder u_dec (
        .ins       (if_id_ins),
        .rd        (id_rd),
        .rs1       (id_rs1),
        .rs2       (id_rs2),
        .imm18     (id_imm18),
        .imm_s     (id_imm_s),
        .imm_b     (id_imm_b),
        .imm_j     (id_imm_j),
        .aluop     (id_aluop),
        .a_zero    (id_a_zero),
        .b_imm     (id_b_imm),
        .b_s12     (id_b_s12),
        .rd_wren   (id_rd_wren),
        .mem_re    (id_mem_re),
        .mem_we    (id_mem_we),
        .is_branch (id_is_br),
        .cmp_op    (id_cmp_op),
        .is_jal    (id_is_jal),
        .is_jalr   (id_is_jalr),
        .is_link   (id_is_link),
        .is_halt   (id_is_halt),
        .uses_rs1  (id_uses_rs1),
        .uses_rs2  (id_uses_rs2)
    );

    wire        rf_wren;
    wire [3:0]  rf_waddr;
    wire [63:0] rf_wdata;
    wire [63:0] id_rs1val, id_rs2val;

    regfile16x64 u_rf (
        .clk    (clk),
        .rst_n  (rst_n),
        .raddr1 (id_rs1),
        .rdata1 (id_rs1val),
        .raddr2 (id_rs2),
        .rdata2 (id_rs2val),
        .wren   (rf_wren),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata)
    );

    // load-use stall: instruction in EX is a load whose rd is a source here
    assign if_stall = id_ex_valid && id_ex_mem_re && (id_ex_rd != 4'd0) && if_id_valid &&
                      ((id_uses_rs1 && (id_ex_rd == id_rs1)) ||
                       (id_uses_rs2 && (id_ex_rd == id_rs2)));

    // =====================================================================
    // EX: forwarding + execute
    // =====================================================================
    wire        ex_fwdA_ex = ex_mem_valid && ex_mem_rd_wren && !ex_mem_mem_re &&
                             (ex_mem_rd != 4'd0) && (ex_mem_rd == id_ex_rs1);
    wire        ex_fwdA_wb = mem_wb_valid && mem_wb_rd_wren && (mem_wb_rd != 4'd0) &&
                             (mem_wb_rd == id_ex_rs1) && !ex_fwdA_ex;
    wire        ex_fwdB_ex = ex_mem_valid && ex_mem_rd_wren && !ex_mem_mem_re &&
                             (ex_mem_rd != 4'd0) && (ex_mem_rd == id_ex_rs2);
    wire        ex_fwdB_wb = mem_wb_valid && mem_wb_rd_wren && (mem_wb_rd != 4'd0) &&
                             (mem_wb_rd == id_ex_rs2) && !ex_fwdB_ex;

    wire [63:0] opr_a = id_ex_a_zero ? 64'd0 :
                        ex_fwdA_ex  ? ex_mem_val :
                        ex_fwdA_wb  ? mem_wb_val :
                                      id_ex_rs1val;
    wire [63:0] opr_b = ex_fwdB_ex  ? ex_mem_val :
                        ex_fwdB_wb  ? mem_wb_val :
                                      id_ex_rs2val;

    wire [63:0] alu_b = id_ex_b_imm ? (id_ex_b_s12 ? id_ex_imm_s : id_ex_imm18) : opr_b;

    wire [63:0] alu_res;

    alu64 u_alu (
        .op (id_ex_aluop),
        .a  (opr_a),
        .b  (alu_b),
        .y  (alu_res)
    );

    // branch condition against forwarded operands
    wire br_eq  = (opr_a == opr_b);
    wire br_lt  = ($signed(opr_a) < $signed(opr_b));
    wire br_ltu = (opr_a < opr_b);

    reg br_taken;
    always @* begin
        case (id_ex_cmp_op)
            3'd0:    br_taken = br_eq;
            3'd1:    br_taken = !br_eq;
            3'd2:    br_taken = br_lt;
            3'd3:    br_taken = !br_lt;
            3'd4:    br_taken = br_ltu;
            default: br_taken = !br_ltu;
        endcase
    end

    wire [63:0] br_target   = id_ex_pc + id_ex_imm_b;
    wire [63:0] jal_target  = id_ex_pc + id_ex_imm_j;
    wire [63:0] jalr_target = opr_a + id_ex_imm18;

    wire        id_ex_is_ct = id_ex_is_br || id_ex_is_jal || id_ex_is_jalr;
    assign      ex_taken = id_ex_valid && id_ex_is_ct &&
                           (id_ex_is_jal || id_ex_is_jalr || br_taken);
    assign      ex_target = id_ex_is_jal  ? jal_target  :
                            id_ex_is_jalr ? jalr_target :
                                            br_target;

    wire        halt_fetch = id_ex_valid && id_ex_is_halt;

    // =====================================================================
    // MEM
    // =====================================================================
    assign dmem_addr  = ex_mem_addr;
    assign dmem_re    = ex_mem_valid && ex_mem_mem_re;
    assign dmem_we    = ex_mem_valid && ex_mem_mem_we;
    assign dmem_wdata = ex_mem_stdata;

    // =====================================================================
    // WB
    // =====================================================================
    assign rf_wren  = mem_wb_valid && mem_wb_rd_wren;
    assign rf_waddr = mem_wb_rd;
    assign rf_wdata = mem_wb_val;

    // =====================================================================
    // pipeline control
    // =====================================================================
    wire flush = ex_taken;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q        <= 64'd0;
            halted_q    <= 1'b0;
            if_id_valid <= 1'b0;
            if_id_pc    <= 64'd0;
            if_id_ins   <= 32'd0;
        end else begin
            if (halt_fetch)
                halted_q <= 1'b1;

            if (!halted_q) begin
                if (ex_taken)
                    pc_q <= ex_target;
                else if (fetch_en)
                    pc_q <= pc_q + 64'd4;

                // IF/ID
                if (ex_taken || halt_fetch) begin
                    if_id_valid <= 1'b0;
                end else if (!if_stall) begin
                    if_id_valid <= 1'b1;
                    if_id_pc    <= pc_q;
                    if_id_ins   <= imem_rdata;
                end
            end
        end
    end

    // ID/EX
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_valid   <= 1'b0;
            id_ex_pc      <= 64'd0;
            id_ex_rs1val  <= 64'd0;
            id_ex_rs2val  <= 64'd0;
            id_ex_imm18   <= 64'd0;
            id_ex_imm_s   <= 64'd0;
            id_ex_imm_b   <= 64'd0;
            id_ex_imm_j   <= 64'd0;
            id_ex_rd      <= 4'd0;
            id_ex_rs1     <= 4'd0;
            id_ex_rs2     <= 4'd0;
            id_ex_aluop   <= 4'd0;
            id_ex_a_zero  <= 1'b0;
            id_ex_b_imm   <= 1'b0;
            id_ex_b_s12   <= 1'b0;
            id_ex_rd_wren <= 1'b0;
            id_ex_mem_re  <= 1'b0;
            id_ex_mem_we  <= 1'b0;
            id_ex_is_br   <= 1'b0;
            id_ex_is_jal  <= 1'b0;
            id_ex_is_jalr <= 1'b0;
            id_ex_is_link <= 1'b0;
            id_ex_is_halt <= 1'b0;
            id_ex_cmp_op  <= 3'd0;
        end else if (flush || if_stall || halted_q || halt_fetch) begin
            id_ex_valid   <= 1'b0;
            id_ex_rd_wren <= 1'b0;
            id_ex_mem_re  <= 1'b0;
            id_ex_mem_we  <= 1'b0;
            id_ex_is_br   <= 1'b0;
            id_ex_is_jal  <= 1'b0;
            id_ex_is_jalr <= 1'b0;
            id_ex_is_link <= 1'b0;
            id_ex_is_halt <= 1'b0;
        end else begin
            id_ex_valid   <= if_id_valid;
            id_ex_pc      <= if_id_pc;
            id_ex_rs1val  <= id_rs1val;
            id_ex_rs2val  <= id_rs2val;
            id_ex_imm18   <= id_imm18;
            id_ex_imm_s   <= id_imm_s;
            id_ex_imm_b   <= id_imm_b;
            id_ex_imm_j   <= id_imm_j;
            id_ex_rd      <= id_rd;
            id_ex_rs1     <= id_rs1;
            id_ex_rs2     <= id_rs2;
            id_ex_aluop   <= id_aluop;
            id_ex_a_zero  <= id_a_zero;
            id_ex_b_imm   <= id_b_imm;
            id_ex_b_s12   <= id_b_s12;
            id_ex_rd_wren <= id_rd_wren;
            id_ex_mem_re  <= id_mem_re;
            id_ex_mem_we  <= id_mem_we;
            id_ex_is_br   <= id_is_br;
            id_ex_is_jal  <= id_is_jal;
            id_ex_is_jalr <= id_is_jalr;
            id_ex_is_link <= id_is_link;
            id_ex_is_halt <= id_is_halt;
            id_ex_cmp_op  <= id_cmp_op;
        end
    end

    // EX/MEM + MEM/WB
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_valid   <= 1'b0;
            ex_mem_val     <= 64'd0;
            ex_mem_addr    <= 64'd0;
            ex_mem_stdata  <= 64'd0;
            ex_mem_rd      <= 4'd0;
            ex_mem_rd_wren <= 1'b0;
            ex_mem_mem_re  <= 1'b0;
            ex_mem_mem_we  <= 1'b0;
            mem_wb_valid   <= 1'b0;
            mem_wb_val     <= 64'd0;
            mem_wb_rd      <= 4'd0;
            mem_wb_rd_wren <= 1'b0;
        end else begin
            // ---- EX -> MEM ----
            if (!id_ex_valid) begin
                ex_mem_valid   <= 1'b0;
                ex_mem_rd_wren <= 1'b0;
                ex_mem_mem_re  <= 1'b0;
                ex_mem_mem_we  <= 1'b0;
            end else begin
                ex_mem_valid   <= 1'b1;
                ex_mem_val     <= id_ex_is_link ? (id_ex_pc + 64'd4) : alu_res;
                ex_mem_addr    <= alu_res;
                ex_mem_stdata  <= opr_b;
                ex_mem_rd      <= id_ex_rd;
                ex_mem_rd_wren <= id_ex_rd_wren;
                ex_mem_mem_re  <= id_ex_mem_re;
                ex_mem_mem_we  <= id_ex_mem_we;
            end

            // ---- MEM -> WB ----
            if (!ex_mem_valid) begin
                mem_wb_valid   <= 1'b0;
                mem_wb_rd_wren <= 1'b0;
            end else begin
                mem_wb_valid   <= 1'b1;
                mem_wb_rd      <= ex_mem_rd;
                mem_wb_rd_wren <= ex_mem_rd_wren;
                mem_wb_val     <= ex_mem_mem_re ? dmem_rdata : ex_mem_val;
            end
        end
    end

    assign halted = halted_q && !id_ex_valid && !ex_mem_valid && !mem_wb_valid;

endmodule
