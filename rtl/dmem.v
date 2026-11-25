// ---------------------------------------------------------------------------
// dmem.v -- 4 KB data memory (512 x 64-bit), byte-addressed / word aligned
// Combinational read for same-cycle load data, synchronous write.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module dmem (
    input  wire        clk,
    input  wire [63:0] addr,
    input  wire        re,
    output wire [63:0] rdata,
    input  wire        we,
    input  wire [63:0] wdata
);
    parameter WORDS = 512;    // bytes = WORDS * 8

    reg [63:0] mem [0:WORDS-1];

    // synthesis translate_off
    initial begin
        $readmemh("dmem.hex", mem);
    end
    // synthesis translate_on

    assign rdata = mem[addr[11:3]];

    always @(posedge clk) begin
        if (we)
            mem[addr[11:3]] <= wdata;
    end
endmodule
