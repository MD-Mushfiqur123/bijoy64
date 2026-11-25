// ---------------------------------------------------------------------------
// imem.v -- 16 KB instruction memory (4096 x 32-bit), $readmemh loaded
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module imem (
    input  wire [63:0] addr,
    output wire [31:0] rdata
);
    parameter WORDS = 4096;   // bytes = WORDS * 4

    reg [31:0] mem [0:WORDS-1];

    // synthesis translate_off
    initial begin
        $readmemh("imem.hex", mem);
    end
    // synthesis translate_on

    assign rdata = mem[addr[13:2]];
endmodule
