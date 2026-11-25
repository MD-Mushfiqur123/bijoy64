// ---------------------------------------------------------------------------
// fpga_imem.v -- 16 KB instruction memory for FPGA builds (4096 x 32-bit)
// Unlike rtl/imem.v the $readmemh init is NOT wrapped in translate_off, so
// synthesis tools init the inferred BRAM with the assembled program.
// Place the built imem.hex next to the synthesis project / run from its cwd.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module fpga_imem (
    input  wire [63:0] addr,
    output wire [31:0] rdata
);
    parameter WORDS = 4096;   // bytes = WORDS * 4

    reg [31:0] mem [0:WORDS-1];

    initial begin
        $readmemh("imem.hex", mem);
    end

    assign rdata = mem[addr[13:2]];
endmodule
