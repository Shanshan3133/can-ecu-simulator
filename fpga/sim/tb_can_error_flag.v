`timescale 1ns/1ps

module tb_can_error_flag;
    reg clk = 0;
    reg rst = 1;
    reg bit_tick = 0;
    reg trigger = 0;
    reg passive = 0;
    reg bus_off = 0;
    wire error_bit;
    wire busy;
    integer dominant_count = 0;
    integer total_count = 0;

    can_error_flag dut (
        .clk(clk), .rst(rst), .bit_tick(bit_tick), .trigger(trigger),
        .error_passive(passive), .bus_off(bus_off),
        .error_bit(error_bit), .busy(busy)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(negedge clk); bit_tick = 1;
            @(posedge clk);
            #1;
            if (busy) begin
                total_count = total_count + 1;
                if (!error_bit) dominant_count = dominant_count + 1;
            end
            @(negedge clk); bit_tick = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0; trigger = 1;
        @(posedge clk);
        @(negedge clk); trigger = 0;

        while (busy) tick();
        if (dominant_count != 5 || total_count != 16) begin
            $display("FAIL: active error flag sampled-dominant=%0d total=%0d",
                     dominant_count, total_count);
            $fatal(1);
        end

        dominant_count = 0; total_count = 0; passive = 1;
        @(negedge clk); trigger = 1;
        @(posedge clk);
        @(negedge clk); trigger = 0;
        while (busy) tick();
        if (dominant_count != 0 || total_count != 16) begin
            $display("FAIL: passive error flag dominant=%0d total=%0d",
                     dominant_count, total_count);
            $fatal(1);
        end

        $display("PASS: active and passive error signalling");
        $finish;
    end
endmodule
