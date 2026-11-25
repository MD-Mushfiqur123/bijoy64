// ---------------------------------------------------------------------------
// uart_rx.v -- 8N1 UART receiver, mid-bit sampling
// 2-FF input synchronizer, falling edge = start, samples the middle of every
// bit. After a valid stop bit the byte appears on `data` with `valid=1`;
// the consumer acknowledges with `ack` (one cycle) to clear `valid`.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module uart_rx #(
    parameter DIVISOR = 868
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    input  wire       ack,
    output reg  [7:0] data,
    output reg        valid
);
    localparam [15:0] DIV  = DIVISOR[15:0];
    localparam [15:0] HALF = DIVISOR[15:0] / 16'd2;

    reg [1:0]  sync;
    reg [15:0] baud_cnt;
    reg [3:0]  bit_cnt;               // 0=mid-start, 1..8=data, 9=mid-stop
    reg [7:0]  sh;
    reg        active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync     <= 2'b11;
            baud_cnt <= 16'd0;
            bit_cnt  <= 4'd0;
            sh       <= 8'd0;
            active   <= 1'b0;
            data     <= 8'd0;
            valid    <= 1'b0;
        end else begin
            sync <= {sync[0], rx};

            if (ack && valid)
                valid <= 1'b0;

            if (!active) begin
                if (sync[1] && !sync[0]) begin       // start falling edge
                    active   <= 1'b1;
                    baud_cnt <= HALF - 16'd1;
                    bit_cnt  <= 4'd0;
                end
            end else if (baud_cnt > 16'd0) begin
                baud_cnt <= baud_cnt - 16'd1;
            end else begin                           // sample point
                baud_cnt <= DIV;
                if (bit_cnt == 4'd0) begin           // mid-start
                    if (sync[1])                     // glitch, abort
                        active <= 1'b0;
                    else
                        bit_cnt <= 4'd1;
                end else if (bit_cnt <= 4'd8) begin  // data bits, LSB first
                    sh      <= {sync[1], sh[7:1]};
                    bit_cnt <= bit_cnt + 4'd1;
                end else begin                       // mid-stop
                    if (sync[1]) begin               // framing ok
                        data  <= sh;
                        valid <= 1'b1;
                    end
                    active <= 1'b0;
                end
            end
        end
    end
endmodule
