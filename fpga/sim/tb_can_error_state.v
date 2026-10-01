`timescale 1ns/1ps

module tb_can_error_state;
    reg clk = 0;
    reg rst = 1;
    reg bit_tick = 0;
    reg bus_recessive = 1;
    reg tx_error = 0;
    reg rx_error = 0;
    reg tx_success = 0;
    reg rx_success = 0;
    wire [8:0] tec;
    wire [7:0] rec;
    wire warning;
    wire passive;
    wire bus_off;
    integer i;

    can_error_state dut (
        .clk(clk), .rst(rst), .bit_tick(bit_tick),
        .bus_recessive(bus_recessive), .tx_error(tx_error),
        .rx_error(rx_error), .tx_success(tx_success), .rx_success(rx_success),
        .tx_error_count(tec), .rx_error_count(rec),
        .error_warning(warning), .error_passive(passive), .bus_off(bus_off)
    );

    always #5 clk = ~clk;

    task pulse_tx_error;
        begin
            @(negedge clk); tx_error = 1;
            @(negedge clk); tx_error = 0;
        end
    endtask

    task recovery_bit;
        begin
            @(negedge clk); bit_tick = 1;
            @(negedge clk); bit_tick = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;

        for (i = 0; i < 12; i = i + 1) pulse_tx_error();
        if (!warning || passive || (tec != 96)) begin
            $display("FAIL: warning threshold TEC=%0d warning=%b passive=%b", tec, warning, passive);
            $fatal(1);
        end

        for (i = 0; i < 4; i = i + 1) pulse_tx_error();
        if (!passive || (tec != 128)) begin
            $display("FAIL: passive threshold TEC=%0d", tec);
            $fatal(1);
        end

        for (i = 0; i < 16; i = i + 1) pulse_tx_error();
        if (!bus_off || (tec != 256)) begin
            $display("FAIL: bus-off threshold TEC=%0d bus_off=%b", tec, bus_off);
            $fatal(1);
        end

        // 128 occurrences of eleven consecutive recessive bits.
        for (i = 0; i < 1408; i = i + 1) recovery_bit();
        if (bus_off || (tec != 0)) begin
            $display("FAIL: bus-off recovery TEC=%0d bus_off=%b", tec, bus_off);
            $fatal(1);
        end

        $display("PASS: warning, passive, bus-off, and recovery thresholds");
        $finish;
    end
endmodule
