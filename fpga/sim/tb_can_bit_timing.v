`timescale 1ns/1ps

module tb_can_bit_timing;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg hard_sync = 1'b0;
    reg resync = 1'b0;
    wire tq_tick;
    wire bit_start;
    wire sample_point;
    wire bit_end;
    wire [7:0] tq_index;
    integer clock_count = 0;
    integer last_tq_clock = 0;
    integer tq_count = 0;
    integer start_count = 0;
    integer sample_count = 0;
    integer end_count = 0;

    // Small integer parameters keep simulation fast while preserving ratios:
    // one TQ every 5 clocks, 8 TQ per bit, sample at the sixth TQ.
    can_bit_timing #(
        .CLOCK_HZ(40), .BIT_RATE(1), .TQ_PER_BIT(8), .SAMPLE_TQ(6)
    ) dut (
        .clk(clk), .rst(rst), .hard_sync(hard_sync), .resync(resync),
        .tq_tick(tq_tick), .bit_start(bit_start),
        .sample_point(sample_point), .bit_end(bit_end), .tq_index(tq_index)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst) begin
            clock_count = clock_count + 1;
            if (tq_tick) begin
                tq_count = tq_count + 1;
                if ((tq_count > 1) && ((clock_count - last_tq_clock) != 5)) begin
                    $display("FAIL: TQ interval was %0d clocks", clock_count - last_tq_clock);
                    $fatal(1);
                end
                last_tq_clock = clock_count;
            end
            if (bit_start) start_count = start_count + 1;
            if (sample_point) sample_count = sample_count + 1;
            if (bit_end) end_count = end_count + 1;
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        wait (end_count == 3);
        @(posedge clk);

        if ((start_count != 3) || (sample_count != 3) || (end_count != 3)) begin
            $display("FAIL: pulse counts start=%0d sample=%0d end=%0d",
                     start_count, sample_count, end_count);
            $fatal(1);
        end

        @(negedge clk); hard_sync = 1;
        @(posedge clk);
        #1;
        if (tq_index != 0 || !bit_start) begin
            $display("FAIL: hard synchronization did not establish bit start");
            $fatal(1);
        end
        @(negedge clk); hard_sync = 0;

        repeat (18) @(posedge clk);
        @(negedge clk); resync = 1;
        @(posedge clk);
        @(negedge clk); resync = 0;

        $display("PASS: nominal timing, hard synchronization, and resynchronization");
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL: timeout");
        $fatal(1);
    end
endmodule
