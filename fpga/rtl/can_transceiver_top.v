`timescale 1ns/1ps

// Board-independent physical wrapper. Connect can_txd/can_rxd to a 3.3 V CAN
// transceiver (for example SN65HVD230). Board clock/reset pin constraints are
// intentionally deferred until a board is selected.
module can_transceiver_top #(
    parameter integer CLOCK_HZ   = 40000000,
    parameter integer BIT_RATE   = 500000,
    parameter integer TQ_PER_BIT = 16,
    parameter integer SAMPLE_TQ  = 13,
    parameter [10:0] ACCEPTANCE_ID   = 11'h000,
    parameter [10:0] ACCEPTANCE_MASK = 11'h000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        can_rxd,
    output wire        can_txd,
    input  wire        tx_request,
    input  wire [10:0] tx_id,
    input  wire [3:0]  tx_dlc,
    input  wire [63:0] tx_data,
    output wire        tx_busy,
    output wire        tx_success,
    output wire        tx_failed,
    output wire        rx_valid,
    output wire [10:0] rx_id,
    output wire [3:0]  rx_dlc,
    output wire [63:0] rx_data,
    output wire        error_warning,
    output wire        error_passive,
    output wire        bus_off
);
    reg rx_meta;
    reg rx_sync;
    reg rx_previous;
    reg [3:0] idle_recessive_bits;
    wire sample_point;
    wire unused_tq_tick;
    wire unused_bit_start;
    wire unused_bit_end;
    wire [7:0] unused_tq_index;
    wire falling_edge = rx_previous && !rx_sync;
    wire hard_sync = falling_edge && (idle_recessive_bits >= 11);
    wire resync = falling_edge && (idle_recessive_bits < 11);
    wire unused_arbitration_lost;
    wire unused_crc_error;
    wire unused_stuff_error;
    wire unused_form_error;
    wire [8:0] unused_tec;
    wire [7:0] unused_rec;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_previous <= 1'b1;
            idle_recessive_bits <= 4'd11;
        end else begin
            rx_meta <= can_rxd;
            rx_sync <= rx_meta;
            rx_previous <= rx_sync;
            if (sample_point) begin
                if (rx_sync) begin
                    if (idle_recessive_bits < 11)
                        idle_recessive_bits <= idle_recessive_bits + 1'b1;
                end else begin
                    idle_recessive_bits <= 0;
                end
            end
        end
    end

    can_bit_timing #(
        .CLOCK_HZ(CLOCK_HZ), .BIT_RATE(BIT_RATE),
        .TQ_PER_BIT(TQ_PER_BIT), .SAMPLE_TQ(SAMPLE_TQ)
    ) timing (
        .clk(clk), .rst(rst), .hard_sync(hard_sync), .resync(resync),
        .tq_tick(unused_tq_tick),
        .bit_start(unused_bit_start), .sample_point(sample_point),
        .bit_end(unused_bit_end), .tq_index(unused_tq_index)
    );

    can_controller_core #(
        .ACCEPTANCE_ID(ACCEPTANCE_ID), .ACCEPTANCE_MASK(ACCEPTANCE_MASK)
    ) core (
        .clk(clk), .rst(rst), .bit_tick(sample_point), .can_rx(rx_sync),
        .can_tx(can_txd), .tx_request(tx_request), .tx_id(tx_id),
        .tx_dlc(tx_dlc), .tx_data(tx_data), .tx_busy(tx_busy),
        .tx_success(tx_success), .tx_failed(tx_failed),
        .arbitration_lost(unused_arbitration_lost), .rx_valid(rx_valid),
        .rx_id(rx_id), .rx_dlc(rx_dlc), .rx_data(rx_data),
        .crc_error(unused_crc_error), .stuff_error(unused_stuff_error),
        .form_error(unused_form_error), .tx_error_count(unused_tec),
        .rx_error_count(unused_rec), .error_warning(error_warning),
        .error_passive(error_passive), .bus_off(bus_off)
    );
endmodule
