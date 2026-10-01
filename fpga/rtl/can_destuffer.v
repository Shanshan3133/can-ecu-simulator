`timescale 1ns/1ps

// Removes CAN bit stuffing from a sampled physical-bit stream. The caller
// enables the block from SOF through the CRC sequence. A logical bit appears
// combinationally with bit_valid; an expected stuff bit is consumed instead.
module can_destuffer (
    input  wire clk,
    input  wire rst,
    input  wire clear,
    input  wire enable,
    input  wire bit_valid,
    input  wire raw_bit,
    output wire logical_valid,
    output wire logical_bit,
    output wire stuff_error,
    output reg  stuff_pending
);
    reg last_bit;
    reg [2:0] run_length;
    reg have_history;

    assign logical_bit   = raw_bit;
    assign logical_valid = bit_valid && (!enable || !stuff_pending);
    assign stuff_error   = bit_valid && enable && stuff_pending &&
                           (raw_bit == last_bit);

    always @(posedge clk) begin
        if (rst || clear || !enable) begin
            last_bit     <= 1'b1;
            run_length   <= 3'd0;
            have_history <= 1'b0;
            stuff_pending <= 1'b0;
        end else if (bit_valid) begin
            if (stuff_pending) begin
                last_bit      <= raw_bit;
                run_length    <= 3'd1;
                have_history  <= 1'b1;
                stuff_pending <= 1'b0;
            end else if (!have_history || (raw_bit != last_bit)) begin
                last_bit      <= raw_bit;
                run_length    <= 3'd1;
                have_history  <= 1'b1;
                stuff_pending <= 1'b0;
            end else begin
                last_bit   <= raw_bit;
                run_length <= run_length + 1'b1;
                if (run_length == 3'd4)
                    stuff_pending <= 1'b1;
            end
        end
    end
endmodule
