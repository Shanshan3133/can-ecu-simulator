`timescale 1ns/1ps

// Classical CAN link-layer CRC-15 generator.
// Polynomial: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1
// Feed the destuffed frame bits MSB first, from SOF through the data field.
module can_crc15 (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,
    input  wire        enable,
    input  wire        bit_in,
    output reg  [14:0] crc
);
    wire feedback = bit_in ^ crc[14];

    always @(posedge clk) begin
        if (rst || clear) begin
            crc <= 15'h0000;
        end else if (enable) begin
            if (feedback)
                crc <= {crc[13:0], 1'b0} ^ 15'h4599;
            else
                crc <= {crc[13:0], 1'b0};
        end
    end
endmodule
