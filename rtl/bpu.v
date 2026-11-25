// ---------------------------------------------------------------------------
// bpu.v -- BIJOY-64 dynamic branch predictor (Phase 1/2a)
//
// 64-entry direct-mapped BTB with 2-bit saturating counters.
//   lookup : IF stage, per fetched PC -> (pred_taken, pred_target)
//   update : EX stage, when a control-flow insn resolves
// Entries are indexed by pc[7:2] (word-aligned). Saturating counters start
// weakly-taken on allocation, so backward loop branches are picked up after
// their first iteration.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module bpu (
    input  wire        clk,
    input  wire        rst_n,

    // IF-stage lookup
    input  wire [63:0] lookup_pc,
    output wire        pred_taken,
    output wire [63:0] pred_target,

    // EX-stage update
    input  wire        update_valid,
    input  wire [63:0] update_pc,
    input  wire        update_taken,
    input  wire [63:0] update_target
);

    parameter ENTRIES = 64;

    reg [63:0]  btb_target [0:ENTRIES-1];
    reg [1:0]   pht        [0:ENTRIES-1];
    reg [63:0]  valid;

    // lookup: index = pc[7:2]
    wire [5:0] lidx = lookup_pc[7:2];
    assign pred_taken  = valid[lidx] && pht[lidx][1];
    assign pred_target = btb_target[lidx];

    // update
    wire [5:0] uidx = update_pc[7:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 64'd0;
        end else if (update_valid) begin
            valid[uidx] <= 1'b1;
            btb_target[uidx] <= update_target;
            if (update_taken)
                pht[uidx] <= (pht[uidx] == 2'b11) ? 2'b11 : pht[uidx] + 2'd1;
            else
                pht[uidx] <= (pht[uidx] == 2'b00) ? 2'b00 : pht[uidx] - 2'd1;
        end
    end

endmodule
