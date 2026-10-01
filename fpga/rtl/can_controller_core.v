`timescale 1ns/1ps

// One-entry register/FIFO wrapper around the RX, TX, ACK, retry, acceptance,
// and fault-confinement blocks. can_rx and can_tx use logical CAN polarity:
// 0 is dominant, 1 is recessive.
module can_controller_core #(
    parameter [10:0] ACCEPTANCE_ID   = 11'h000,
    parameter [10:0] ACCEPTANCE_MASK = 11'h000,
    parameter integer MAX_RETRIES    = 3
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        bit_tick,
    input  wire        can_rx,
    output wire        can_tx,

    input  wire        tx_request,
    input  wire [10:0] tx_id,
    input  wire [3:0]  tx_dlc,
    input  wire [63:0] tx_data,
    output wire        tx_busy,
    output reg         tx_success,
    output reg         tx_failed,
    output wire        arbitration_lost,

    output wire        rx_valid,
    output wire [10:0] rx_id,
    output wire [3:0]  rx_dlc,
    output wire [63:0] rx_data,
    output wire        crc_error,
    output wire        stuff_error,
    output wire        form_error,

    output wire [8:0]  tx_error_count,
    output wire [7:0]  rx_error_count,
    output wire        error_warning,
    output wire        error_passive,
    output wire        bus_off
);
    reg pending;
    reg start_tx;
    reg [10:0] pending_id;
    reg [3:0] pending_dlc;
    reg [63:0] pending_data;
    reg [3:0] retry_count;
    reg [3:0] recessive_wait;

    wire tx_serial_bit;
    wire tx_engine_busy;
    wire tx_engine_done;
    wire tx_ack_error;
    wire tx_bit_error;
    wire rx_ack_drive;
    wire any_rx_error = crc_error || stuff_error || form_error;
    wire any_tx_error = tx_ack_error || tx_bit_error;
    wire error_flag_bit;
    wire error_flag_busy;

    assign can_tx = tx_serial_bit & ~(rx_ack_drive && !tx_engine_busy) &
                    error_flag_bit;
    assign tx_busy = pending || tx_engine_busy || error_flag_busy;

    can_tx transmitter (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .start(start_tx),
        .frame_id(pending_id), .frame_dlc(pending_dlc),
        .frame_data(pending_data), .bus_bit(can_rx),
        .tx_bit(tx_serial_bit), .busy(tx_engine_busy), .tx_done(tx_engine_done),
        .arbitration_lost(arbitration_lost), .ack_error(tx_ack_error),
        .bit_error(tx_bit_error)
    );

    can_rx #(
        .ACCEPTANCE_ID(ACCEPTANCE_ID), .ACCEPTANCE_MASK(ACCEPTANCE_MASK)
    ) receiver (
        .clk(clk), .rst(rst), .bit_valid(bit_tick), .bus_bit(can_rx),
        .ack_drive(rx_ack_drive), .frame_valid(rx_valid), .frame_id(rx_id),
        .frame_dlc(rx_dlc), .frame_data(rx_data), .crc_error(crc_error),
        .stuff_error(stuff_error), .form_error(form_error)
    );

    can_error_state confinement (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .bus_recessive(can_rx),
        .tx_error(any_tx_error), .rx_error(any_rx_error),
        .tx_success(tx_engine_done), .rx_success(rx_valid),
        .tx_error_count(tx_error_count), .rx_error_count(rx_error_count),
        .error_warning(error_warning), .error_passive(error_passive),
        .bus_off(bus_off)
    );

    can_error_flag error_signalling (
        .clk(clk), .rst(rst), .bit_tick(bit_tick),
        .trigger(any_rx_error || any_tx_error),
        .error_passive(error_passive), .bus_off(bus_off),
        .error_bit(error_flag_bit), .busy(error_flag_busy)
    );

    always @(posedge clk) begin
        start_tx   <= 1'b0;
        tx_success <= 1'b0;
        tx_failed  <= 1'b0;

        if (rst) begin
            pending       <= 1'b0;
            start_tx      <= 1'b0;
            pending_id    <= 11'd0;
            pending_dlc   <= 4'd0;
            pending_data  <= 64'd0;
            retry_count   <= 4'd0;
            recessive_wait <= 3'd0;
        end else begin
            if (tx_request && !pending && !tx_engine_busy && !bus_off &&
                (tx_dlc <= 8)) begin
                pending      <= 1'b1;
                pending_id   <= tx_id;
                pending_dlc  <= tx_dlc;
                pending_data <= tx_data;
                retry_count  <= 0;
                recessive_wait <= 0;
            end

            if (pending && !tx_engine_busy && !error_flag_busy && !bus_off) begin
                if (bit_tick && can_rx) begin
                    // Eleven consecutive recessive bits qualify the bus as
                    // idle. Waiting for only the three intermission bits can
                    // falsely restart inside another node's stuffed frame.
                    if (recessive_wait == 10) begin
                        start_tx <= 1'b1;
                        recessive_wait <= 0;
                    end else recessive_wait <= recessive_wait + 1'b1;
                end else if (bit_tick) recessive_wait <= 0;
            end

            if (tx_engine_done) begin
                pending <= 1'b0;
                retry_count <= 0;
                tx_success <= 1'b1;
            end

            if (arbitration_lost || any_tx_error) begin
                recessive_wait <= 0;
                if (retry_count < MAX_RETRIES)
                    retry_count <= retry_count + 1'b1;
                else begin
                    pending <= 1'b0;
                    tx_failed <= 1'b1;
                end
            end

            if (bus_off) begin
                pending <= 1'b0;
                tx_failed <= tx_busy;
                retry_count <= 0;
                recessive_wait <= 0;
            end
        end
    end
endmodule
