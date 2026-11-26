// ---------------------------------------------------------------------------
// mx_hpi_1_top.v -- MX-Hpi-1 top level: core + instruction/data memories
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module mx_hpi_1_top (
    input  wire clk,
    input  wire rst_n,
    output wire halted
);

    wire [63:0] imem_addr;
    wire [31:0] imem_rdata;
    wire [63:0] dmem_addr;
    wire        dmem_re, dmem_we;
    wire [63:0] dmem_wdata, dmem_rdata;

    mx_hpi_1_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_re    (dmem_re),
        .dmem_we    (dmem_we),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .halted     (halted)
    );

    imem u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    dmem u_dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .re    (dmem_re),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .wdata (dmem_wdata)
    );

endmodule
