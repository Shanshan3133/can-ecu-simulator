`timescale 1ns/1ps

// Vendor-neutral nominal bit-time pulse generator.
// This first-stage block deliberately excludes edge resynchronization; that is
// added with the RX synchronizer when the receive path is implemented.
module can_bit_timing #(
    parameter integer CLOCK_HZ   = 40000000,
    parameter integer BIT_RATE   = 500000,
    parameter integer TQ_PER_BIT = 16,
    parameter integer SAMPLE_TQ  = 13,
    parameter integer SJW_TQ     = 2
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       hard_sync,
    input  wire       resync,
    output reg        tq_tick,
    output reg        bit_start,
    output reg        sample_point,
    output reg        bit_end,
    output reg  [7:0] tq_index
);
    localparam integer TQ_DIV = CLOCK_HZ / (BIT_RATE * TQ_PER_BIT);
    reg [31:0] divider_count;

`ifndef SYNTHESIS
    initial begin
        if (TQ_DIV < 1) begin
            $display("ERROR: clock is too slow for the requested CAN timing");
            $finish;
        end
        if ((CLOCK_HZ % (BIT_RATE * TQ_PER_BIT)) != 0) begin
            $display("ERROR: CLOCK_HZ must divide exactly into time quanta");
            $finish;
        end
        if ((SAMPLE_TQ < 1) || (SAMPLE_TQ >= TQ_PER_BIT)) begin
            $display("ERROR: SAMPLE_TQ must be inside the nominal bit time");
            $finish;
        end
    end
`endif

    always @(posedge clk) begin
        tq_tick      <= 1'b0;
        bit_start    <= 1'b0;
        sample_point <= 1'b0;
        bit_end      <= 1'b0;

        if (rst) begin
            divider_count <= 32'd0;
            tq_index      <= 8'd0;
        end else if (hard_sync) begin
            // A recessive-to-dominant SOF edge establishes a new bit boundary.
            divider_count <= 32'd0;
            tq_index      <= 8'd0;
            bit_start     <= 1'b1;
        end else if (resync) begin
            // Bound phase correction to SJW. Edges before the sample point
            // lengthen the current bit; edges after it shorten the bit.
            divider_count <= 32'd0;
            if (tq_index < SAMPLE_TQ) begin
                if (tq_index <= SJW_TQ)
                    tq_index <= 8'd0;
                else
                    tq_index <= tq_index - SJW_TQ;
            end else begin
                if ((TQ_PER_BIT - tq_index) <= SJW_TQ)
                    tq_index <= 8'd0;
                else
                    tq_index <= tq_index + SJW_TQ;
            end
        end else if (divider_count == TQ_DIV - 1) begin
            divider_count <= 32'd0;
            tq_tick       <= 1'b1;
            bit_start     <= (tq_index == 0);
            sample_point  <= (tq_index == SAMPLE_TQ - 1);
            bit_end       <= (tq_index == TQ_PER_BIT - 1);

            if (tq_index == TQ_PER_BIT - 1)
                tq_index <= 8'd0;
            else
                tq_index <= tq_index + 1'b1;
        end else begin
            divider_count <= divider_count + 1'b1;
        end
    end
endmodule
