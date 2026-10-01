`timescale 1ns/1ps

module tb_can_fault_paths;
    reg clk = 0;
    reg rst = 1;
    reg bit_tick = 0;
    reg start = 0;
    reg [10:0] frame_id = 11'h321;
    reg [3:0] frame_dlc = 2;
    reg [63:0] frame_data = 64'h0000000000005aa5;
    wire tx_bit;
    wire busy;
    wire tx_done;
    wire ack_error;
    wire bit_error;
    wire ack_drive;
    wire rx_valid;
    wire crc_error;
    wire stuff_error;
    wire form_error;
    wire bus_bit = tx_bit & ~ack_drive;
    reg crc_seen = 0;
    reg ack_error_seen = 0;
    integer timeout;

    always #5 clk = ~clk;
    always @(negedge clk) bit_tick = ~bit_tick;
    always @(posedge clk) begin
        if (crc_error) crc_seen <= 1;
        if (ack_error) ack_error_seen <= 1;
    end

    can_tx transmitter (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .start(start),
        .frame_id(frame_id), .frame_dlc(frame_dlc), .frame_data(frame_data),
        .bus_bit(bus_bit), .tx_bit(tx_bit), .busy(busy), .tx_done(tx_done),
        .arbitration_lost(), .ack_error(ack_error), .bit_error(bit_error)
    );

    can_rx receiver (
        .clk(clk), .rst(rst), .bit_valid(bit_tick), .bus_bit(bus_bit),
        .ack_drive(ack_drive), .frame_valid(rx_valid), .frame_id(), .frame_dlc(),
        .frame_data(), .crc_error(crc_error), .stuff_error(stuff_error),
        .form_error(form_error)
    );

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 0;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        wait (busy);
        // Deliberately corrupt the generated CRC before the CRC field begins.
        transmitter.crc_latched[0] = ~transmitter.crc_latched[0];

        timeout = 0;
        while ((!crc_seen || !ack_error_seen) && timeout < 1000) begin
            @(posedge clk); timeout = timeout + 1;
        end

        if (!crc_seen || !ack_error_seen || rx_valid || stuff_error ||
            form_error || bit_error) begin
            $display("FAIL: CRC reject=%b ACK error=%b rx_valid=%b stuff=%b form=%b bit=%b",
                     crc_seen, ack_error_seen, rx_valid, stuff_error, form_error, bit_error);
            $fatal(1);
        end

        $display("PASS: invalid CRC rejected and missing ACK reported");
        $finish;
    end

    initial begin
        #30000;
        $display("FAIL: fault-path timeout");
        $fatal(1);
    end
endmodule
