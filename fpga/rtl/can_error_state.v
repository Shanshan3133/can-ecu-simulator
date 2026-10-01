`timescale 1ns/1ps

// CAN-style fault-confinement counters and bus-off recovery. Counter increments
// follow the principal ISO behavior needed by this core: transmit errors add 8,
// receive errors add 1, and successful traffic decrements the relevant counter.
module can_error_state (
    input  wire       clk,
    input  wire       rst,
    input  wire       bit_tick,
    input  wire       bus_recessive,
    input  wire       tx_error,
    input  wire       rx_error,
    input  wire       tx_success,
    input  wire       rx_success,
    output reg [8:0]  tx_error_count,
    output reg [7:0]  rx_error_count,
    output wire       error_warning,
    output wire       error_passive,
    output reg        bus_off
);
    reg [3:0] recessive_run;
    reg [7:0] recovery_sequences;

    assign error_warning = (tx_error_count >= 96) || (rx_error_count >= 96);
    assign error_passive = (tx_error_count >= 128) || (rx_error_count >= 128);

    always @(posedge clk) begin
        if (rst) begin
            tx_error_count   <= 9'd0;
            rx_error_count   <= 8'd0;
            bus_off          <= 1'b0;
            recessive_run    <= 4'd0;
            recovery_sequences <= 8'd0;
        end else begin
            if (!bus_off) begin
                if (tx_error) begin
                    if (tx_error_count >= 9'd248) begin
                        tx_error_count <= 9'd256;
                        bus_off <= 1'b1;
                    end else tx_error_count <= tx_error_count + 9'd8;
                end else if (tx_success && (tx_error_count != 0)) begin
                    tx_error_count <= tx_error_count - 1'b1;
                end

                if (rx_error) begin
                    if (rx_error_count != 8'hff)
                        rx_error_count <= rx_error_count + 1'b1;
                end else if (rx_success && (rx_error_count != 0)) begin
                    rx_error_count <= rx_error_count - 1'b1;
                end
            end else if (bit_tick) begin
                if (bus_recessive) begin
                    if (recessive_run == 10) begin
                        recessive_run <= 0;
                        if (recovery_sequences == 127) begin
                            bus_off <= 1'b0;
                            tx_error_count <= 0;
                            rx_error_count <= 0;
                            recovery_sequences <= 0;
                        end else recovery_sequences <= recovery_sequences + 1'b1;
                    end else recessive_run <= recessive_run + 1'b1;
                end else recessive_run <= 0;
            end
        end
    end
endmodule
