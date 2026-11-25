// ---------------------------------------------------------------------------
// regfile16x64.v -- MX-Hpi-1 register file: 16 x 64-bit, r0 hardwired to zero.
// Combinational read, synchronous write.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module regfile16x64 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  raddr1,
    output wire [63:0] rdata1,
    input  wire [3:0]  raddr2,
    output wire [63:0] rdata2,
    input  wire        wren,
    input  wire [3:0]  waddr,
    input  wire [63:0] wdata
);

    reg [63:0] regs [1:15];

    assign rdata1 = (raddr1 == 4'd0) ? 64'd0 : regs[raddr1];
    assign rdata2 = (raddr2 == 4'd0) ? 64'd0 : regs[raddr2];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 16; i = i + 1)
                regs[i] <= 64'd0;
        end else if (wren && waddr != 4'd0) begin
            regs[waddr] <= wdata;
        end
    end

endmodule
