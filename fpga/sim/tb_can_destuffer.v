`timescale 1ns/1ps

module tb_can_destuffer;
    reg clk = 0;
    reg rst = 1;
    reg clear = 0;
    reg enable = 1;
    reg bit_valid = 0;
    reg raw_bit = 1;
    wire logical_valid;
    wire logical_bit;
    wire stuff_error;
    wire stuff_pending;
    reg [15:0] captured = 0;
    integer captured_count = 0;
    integer errors = 0;

    can_destuffer dut (
        .clk(clk), .rst(rst), .clear(clear), .enable(enable),
        .bit_valid(bit_valid), .raw_bit(raw_bit),
        .logical_valid(logical_valid), .logical_bit(logical_bit),
        .stuff_error(stuff_error), .stuff_pending(stuff_pending)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (logical_valid) begin
            captured = {captured[14:0], logical_bit};
            captured_count = captured_count + 1;
        end
        if (stuff_error) errors = errors + 1;
    end

    task send_bit;
        input value;
        begin
            @(negedge clk); raw_bit = value; bit_valid = 1;
            @(negedge clk); bit_valid = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;

        // Logical 00000 11111 is transmitted as 00000[1]1111[0]1.
        send_bit(0); send_bit(0); send_bit(0); send_bit(0); send_bit(0);
        send_bit(1);
        send_bit(1); send_bit(1); send_bit(1); send_bit(1);
        send_bit(0);
        send_bit(1);

        if ((captured_count != 10) || (captured[9:0] !== 10'b0000011111)) begin
            $display("FAIL: destuffed count=%0d bits=%b", captured_count, captured[9:0]);
            $fatal(1);
        end

        @(negedge clk); clear = 1;
        @(negedge clk); clear = 0;
        send_bit(0); send_bit(0); send_bit(0); send_bit(0); send_bit(0);
        send_bit(0); // Invalid: sixth dominant bit instead of recessive stuff bit.
        if (errors != 1) begin
            $display("FAIL: expected one stuffing error, got %0d", errors);
            $fatal(1);
        end

        $display("PASS: destuffing and stuffing-error detection");
        $finish;
    end
endmodule
