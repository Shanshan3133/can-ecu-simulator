`timescale 1ns/1ps

// Generates the CAN error flag, error delimiter, and intermission sequence.
// Error-active nodes drive six dominant bits; error-passive nodes transmit a
// passive (recessive) flag. Bus-off nodes remain recessive.
module can_error_flag (
    input  wire clk,
    input  wire rst,
    input  wire bit_tick,
    input  wire trigger,
    input  wire error_passive,
    input  wire bus_off,
    output reg  error_bit,
    output reg  busy
);
    localparam [1:0] E_IDLE   = 2'd0;
    localparam [1:0] E_FLAG   = 2'd1;
    localparam [1:0] E_DELIM  = 2'd2;
    localparam [1:0] E_INTERM = 2'd3;

    reg [1:0] state;
    reg [3:0] bit_count;

    always @(posedge clk) begin
        if (rst) begin
            state <= E_IDLE;
            bit_count <= 0;
            error_bit <= 1'b1;
            busy <= 1'b0;
        end else if (bus_off) begin
            state <= E_IDLE;
            bit_count <= 0;
            error_bit <= 1'b1;
            busy <= 1'b0;
        end else if ((state == E_IDLE) && trigger) begin
            state <= E_FLAG;
            bit_count <= 0;
            error_bit <= error_passive ? 1'b1 : 1'b0;
            busy <= 1'b1;
        end else if (bit_tick && busy) begin
            case (state)
                E_FLAG: begin
                    if (bit_count == 5) begin
                        state <= E_DELIM;
                        bit_count <= 0;
                        error_bit <= 1'b1;
                    end else bit_count <= bit_count + 1'b1;
                end
                E_DELIM: begin
                    error_bit <= 1'b1;
                    if (bit_count == 7) begin
                        state <= E_INTERM;
                        bit_count <= 0;
                    end else bit_count <= bit_count + 1'b1;
                end
                E_INTERM: begin
                    error_bit <= 1'b1;
                    if (bit_count == 2) begin
                        state <= E_IDLE;
                        bit_count <= 0;
                        busy <= 1'b0;
                    end else bit_count <= bit_count + 1'b1;
                end
                default: begin
                    state <= E_IDLE;
                    error_bit <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
