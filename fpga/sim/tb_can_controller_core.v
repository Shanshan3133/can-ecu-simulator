`timescale 1ns/1ps

module tb_can_controller_core;
    reg clk = 0;
    reg rst = 1;
    reg bit_tick = 0;
    wire bus_bit;

    reg a_request = 0;
    reg [10:0] a_id = 0;
    reg [3:0] a_dlc = 0;
    reg [63:0] a_data = 0;
    wire a_tx;
    wire a_busy;
    wire a_success;
    wire a_failed;
    wire a_lost;
    wire a_rx_valid;
    wire [10:0] a_rx_id;
    wire [3:0] a_rx_dlc;
    wire [63:0] a_rx_data;

    reg b_request = 0;
    reg [10:0] b_id = 0;
    reg [3:0] b_dlc = 0;
    reg [63:0] b_data = 0;
    wire b_tx;
    wire b_busy;
    wire b_success;
    wire b_failed;
    wire b_lost;
    wire b_rx_valid;
    wire [10:0] b_rx_id;
    wire [3:0] b_rx_dlc;
    wire [63:0] b_rx_data;

    reg first_received = 0;
    reg [10:0] first_id = 0;
    reg a_lost_seen = 0;
    reg a_success_seen = 0;
    reg b_success_seen = 0;
    integer timeout;

    assign bus_bit = a_tx & b_tx;
    always #5 clk = ~clk;
    always @(negedge clk) bit_tick = ~bit_tick;

    always @(posedge clk) begin
        if (a_lost) a_lost_seen <= 1;
        if (a_success) a_success_seen <= 1;
        if (b_success) b_success_seen <= 1;
        if (a_rx_valid && !first_received) begin
            first_received <= 1;
            first_id <= a_rx_id;
        end
    end

    can_controller_core node_a (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .can_rx(bus_bit), .can_tx(a_tx),
        .tx_request(a_request), .tx_id(a_id), .tx_dlc(a_dlc), .tx_data(a_data),
        .tx_busy(a_busy), .tx_success(a_success), .tx_failed(a_failed),
        .arbitration_lost(a_lost), .rx_valid(a_rx_valid), .rx_id(a_rx_id),
        .rx_dlc(a_rx_dlc), .rx_data(a_rx_data), .crc_error(), .stuff_error(),
        .form_error(), .tx_error_count(), .rx_error_count(), .error_warning(),
        .error_passive(), .bus_off()
    );

    can_controller_core node_b (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .can_rx(bus_bit), .can_tx(b_tx),
        .tx_request(b_request), .tx_id(b_id), .tx_dlc(b_dlc), .tx_data(b_data),
        .tx_busy(b_busy), .tx_success(b_success), .tx_failed(b_failed),
        .arbitration_lost(b_lost), .rx_valid(b_rx_valid), .rx_id(b_rx_id),
        .rx_dlc(b_rx_dlc), .rx_data(b_rx_data), .crc_error(), .stuff_error(),
        .form_error(), .tx_error_count(), .rx_error_count(), .error_warning(),
        .error_passive(), .bus_off()
    );

    task request_a;
        input [10:0] identifier;
        input [3:0] length;
        input [63:0] payload;
        begin
            @(negedge clk);
            a_id = identifier; a_dlc = length; a_data = payload; a_request = 1;
            @(negedge clk); a_request = 0;
        end
    endtask

    task request_b;
        input [10:0] identifier;
        input [3:0] length;
        input [63:0] payload;
        begin
            @(negedge clk);
            b_id = identifier; b_dlc = length; b_data = payload; b_request = 1;
            @(negedge clk); b_request = 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 0;

        request_a(11'h123, 4'd2, 64'h0000000000003ca5);
        timeout = 0;
        while (!b_rx_valid && timeout < 1000) begin @(posedge clk); timeout = timeout + 1; end
        if (!b_rx_valid || (b_rx_id != 11'h123) || (b_rx_dlc != 2) ||
            (b_rx_data[15:0] != 16'h3ca5)) begin
            $display("FAIL: end-to-end RX id=%h dlc=%0d data=%h", b_rx_id, b_rx_dlc, b_rx_data[15:0]);
            $fatal(1);
        end
        timeout = 0;
        while (!a_success && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
        if (a_failed) begin
            $display("FAIL: acknowledged transmission reported failure");
            $fatal(1);
        end

        repeat (4) @(posedge clk);

        // Simultaneous requests: lower identifier 0x100 must win, while 0x300
        // observes arbitration loss and retries after the winning frame.
        first_received = 0;
        first_id = 0;
        a_lost_seen = 0;
        a_success_seen = 0;
        b_success_seen = 0;
        fork
            request_a(11'h300, 4'd1, 64'h55);
            request_b(11'h100, 4'd1, 64'haa);
        join

        timeout = 0;
        while ((!a_success_seen || !b_success_seen) && timeout < 3000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        if (!a_lost_seen || !a_success_seen || !b_success_seen ||
            !first_received || (first_id != 11'h100) || a_failed || b_failed) begin
            $display("FAIL: arbitration lost=%b Aok=%b Bok=%b first=%h",
                     a_lost_seen, a_success_seen, b_success_seen, first_id);
            $fatal(1);
        end

        $display("PASS: frame TX/RX, ACK, CRC, stuffing, arbitration, and retry");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: global timeout");
        $fatal(1);
    end
endmodule
