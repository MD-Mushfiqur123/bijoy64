// ---------------------------------------------------------------------------
// div64.v -- BIJOY-64 multi-cycle DIV/REM unit (Phase 1/2b)
//
// Iterative restoring divider on magnitudes, 64 iterations (~66 cycle
// latency including start/done overhead), sign-fixup at the end:
//   DIV: truncation toward zero, sign = sign(a) ^ sign(b)
//   REM: magnitude remainder, sign follows dividend
//   b == 0: quotient = 0, remainder = a  (defined hardware semantics)
//
// Interface:
//   start: pulse (operand capture happens on this edge; inputs may change
//          afterwards, they are latched internally)
//   done : one-cycle pulse when quotient/remainder are final
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module div64 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire [63:0] a,
    input  wire [63:0] b,

    output wire        done,
    output wire [63:0] quotient,
    output wire [63:0] remainder
);

    reg        running;
    reg        zdiv;                    // divide-by-zero fast path
    reg        neg_q, neg_r;
    reg [63:0] mag_b;                   // |b|
    reg [63:0] cap_a;                   // captured a (for remainder semantics)
    reg [63:0] rem_acc;                 // partial remainder
    reg [63:0] quo_acc;                 // quotient bits assembled MSB->LSB
    reg [63:0] work;                    // remaining dividend bits (shifted)
    reg [6:0]  cnt;                     // 0..63

    wire signed [63:0] a_s = a;
    wire signed [63:0] b_s = b;

    // current iteration (combinational)
    wire        last     = (cnt == 7'd63);
    wire [63:0] shift_in = {rem_acc[62:0], work[63]};
    wire        try_sub  = (shift_in >= mag_b);
    wire [63:0] sub_res  = shift_in - mag_b;

    // final values during the done cycle
    wire [63:0] quo_mag  = {quo_acc[62:0], try_sub};
    wire [63:0] rem_mag  = try_sub ? sub_res : shift_in;

    assign done = running && last;

    assign quotient  = zdiv ? 64'd0 :
                       neg_q ? (64'd0 - quo_mag) : quo_mag;
    assign remainder = zdiv ? cap_a :
                       neg_r ? (64'd0 - rem_mag) : rem_mag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running  <= 1'b0;
            zdiv     <= 1'b0;
            neg_q    <= 1'b0;
            neg_r    <= 1'b0;
            mag_b    <= 64'd0;
            cap_a    <= 64'd0;
            rem_acc  <= 64'd0;
            quo_acc  <= 64'd0;
            work     <= 64'd0;
            cnt      <= 7'd0;
        end else if (start && !running) begin
            running  <= 1'b1;
            zdiv     <= (b == 64'd0);
            neg_q    <= (a_s[63] != b_s[63]);
            neg_r    <= a_s[63];
            cap_a    <= a;
            mag_b    <= (b_s[63]) ? (64'd0 - b) : b;
            rem_acc  <= 64'd0;
            quo_acc  <= 64'd0;
            work     <= (a_s[63]) ? (64'd0 - a) : a;
            cnt      <= 7'd0;
        end else if (running && last) begin
            running <= 1'b0;
        end else if (running) begin
            rem_acc <= try_sub ? sub_res  : shift_in;
            quo_acc <= {quo_acc[62:0], try_sub};
            work    <= work << 1;
            cnt     <= cnt + 7'd1;
        end
    end

endmodule
