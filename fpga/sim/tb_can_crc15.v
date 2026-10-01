`timescale 1ns/1ps

module tb_can_crc15;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg clear = 1'b0;
    reg enable = 1'b0;
    reg bit_in = 1'b0;
    wire [14:0] crc;
    integer i;

    can_crc15 dut (
        .clk(clk), .rst(rst), .clear(clear), .enable(enable),
        .bit_in(bit_in), .crc(crc)
    );

    always #5 clk = ~clk;

    task feed_byte;
        input [7:0] value;
        integer bit_number;
        begin
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                @(negedge clk);
                bit_in = value[bit_number];
                enable = 1'b1;
                @(posedge clk);
            end
            @(negedge clk);
            enable = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // CRC-15/CAN standard check string, processed MSB first.
        feed_byte(8'h31); feed_byte(8'h32); feed_byte(8'h33);
        feed_byte(8'h34); feed_byte(8'h35); feed_byte(8'h36);
        feed_byte(8'h37); feed_byte(8'h38); feed_byte(8'h39);

        if (crc !== 15'h059e) begin
            $display("FAIL: expected CRC 059e, got %04h", crc);
            $fatal(1);
        end

        @(negedge clk);
        clear = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear = 1'b0;
        if (crc !== 15'h0000) begin
            $display("FAIL: clear did not reset CRC, got %04h", crc);
            $fatal(1);
        end

        $display("PASS: CAN CRC-15 check vector = %04h", crc | 15'h059e);
        $finish;
    end
endmodule
