// ---------------------------------------------------------------------------
// fpga_dmem.v -- 4 KB data memory for FPGA builds (512 x 64-bit)
// Like fpga_imem: .data section (dmem.hex) is loaded at synthesis time, so
// programs can keep their strings/tables in it. BRAM with sync write.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module fpga_dmem (
    input  wire        clk,
    input  wire [63:0] addr,
    input  wire        re,
    output wire [63:0] rdata,
    input  wire        we,
    input  wire [63:0] wdata
);
    parameter WORDS = 512;    // bytes = WORDS * 8

    reg [63:0] mem [0:WORDS-1];

    initial begin
        $readmemh("dmem.hex", mem);
    end

    assign rdata = mem[addr[11:3]];

    always @(posedge clk) begin
        if (we)
            mem[addr[11:3]] <= wdata;
    end
endmodule
