// ---------------------------------------------------------------------------
// tb_core.v -- BIJOY-64 simulation testbench (for Icarus Verilog)
//
// Loads imem.hex / dmem.hex, runs until the core reports `halted`, then
// prints the architectural register file and non-zero data memory.
//
//   iverilog -o sim rtl/*.v tb/tb_core.v && ./sim
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_core;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire halted;

    bijoy64_top dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .halted (halted)
    );

    always #5 clk = ~clk;

    integer i;
    integer j;

    initial begin
        // uncomment for waveform debugging:
        // $dumpfile("tb_core.vcd");
        // $dumpvars(0, tb_core);

        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;

        @(posedge halted);
        for (j = 0; j < 4; j = j + 1)
            @(posedge clk);

        $display("=== BIJOY-64 halted: architectural register file ===");
        for (i = 1; i < 16; i = i + 1)
            $display("r%0d = 0x%016h", i, dut.u_core.u_rf.regs[i]);

        $display("=== non-zero data memory ===");
        for (j = 0; j < 512; j = j + 1)
            if (dut.u_dmem.mem[j] !== 64'h0)
                $display("mem[0x%04h] = 0x%016h", j * 8, dut.u_dmem.mem[j]);

        $display("=== done ===");
        $finish;
    end

    // safety timeout
    initial begin
        #200000;
        $display("TIMEOUT: core never halted");
        $finish;
    end

endmodule
