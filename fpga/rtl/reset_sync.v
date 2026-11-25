// ---------------------------------------------------------------------------
// reset_sync.v -- asynchronous assert / synchronous release reset
// Board reset buttons are asynchronous; the core must leave reset on a clean
// clk edge so all pipeline registers come out of reset in lockstep.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module reset_sync (
    input  wire clk,
    input  wire arst_n_in,
    output wire rst_n
);
    reg [1:0] sync;

    always @(posedge clk or negedge arst_n_in) begin
        if (!arst_n_in)
            sync <= 2'b00;
        else
            sync <= {sync[0], 1'b1};
    end

    assign rst_n = sync[1];
endmodule
