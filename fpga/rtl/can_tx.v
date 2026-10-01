`timescale 1ns/1ps

// Classical CAN 2.0A standard data-frame transmitter. bit_tick advances one
// physical bit. bus_bit is the resolved wired-AND bus level for arbitration,
// ACK, and bit-error monitoring.
module can_tx (
    input  wire        clk,
    input  wire        rst,
    input  wire        bit_tick,
    input  wire        start,
    input  wire [10:0] frame_id,
    input  wire [3:0]  frame_dlc,
    input  wire [63:0] frame_data,
    input  wire        bus_bit,
    output reg         tx_bit,
    output reg         busy,
    output reg         tx_done,
    output reg         arbitration_lost,
    output reg         ack_error,
    output reg         bit_error
);
    localparam [3:0] P_IDLE      = 4'd0;
    localparam [3:0] P_RAW       = 4'd1;
    localparam [3:0] P_CRC       = 4'd2;
    localparam [3:0] P_CRC_DELIM = 4'd3;
    localparam [3:0] P_ACK       = 4'd4;
    localparam [3:0] P_ACK_DELIM = 4'd5;
    localparam [3:0] P_EOF       = 4'd6;
    localparam [3:0] P_INTERM    = 4'd7;

    reg [3:0] phase;
    reg [6:0] raw_index;
    reg [6:0] raw_last;
    reg [4:0] crc_index;
    reg [3:0] eof_index;
    reg [2:0] interm_index;
    reg [10:0] id_latched;
    reg [3:0] dlc_latched;
    reg [63:0] data_latched;
    reg [14:0] crc_latched;
    reg [2:0] run_length;
    reg last_output;
    reg current_is_stuff;

    function [14:0] crc_step;
        input [14:0] current;
        input bit_value;
        reg feedback;
        begin
            feedback = bit_value ^ current[14];
            crc_step = {current[13:0], 1'b0};
            if (feedback) crc_step = crc_step ^ 15'h4599;
        end
    endfunction

    function [14:0] frame_crc;
        input [10:0] identifier;
        input [3:0] length;
        input [63:0] payload;
        integer i;
        integer byte_number;
        integer bit_number;
        reg [14:0] value;
        begin
            value = crc_step(15'd0, 1'b0);
            for (i = 10; i >= 0; i = i - 1)
                value = crc_step(value, identifier[i]);
            value = crc_step(value, 1'b0); // RTR
            value = crc_step(value, 1'b0); // IDE
            value = crc_step(value, 1'b0); // r0
            for (i = 3; i >= 0; i = i - 1)
                value = crc_step(value, length[i]);
            for (byte_number = 0; byte_number < 8; byte_number = byte_number + 1)
                if (byte_number < length)
                    for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1)
                        value = crc_step(value, payload[byte_number*8 + bit_number]);
            frame_crc = value;
        end
    endfunction

    function raw_bit_at;
        input [6:0] index;
        integer data_offset;
        integer byte_number;
        integer bit_number;
        begin
            if (index == 0)
                raw_bit_at = 1'b0;
            else if (index <= 11)
                raw_bit_at = id_latched[11-index];
            else if (index <= 14)
                raw_bit_at = 1'b0;
            else if (index <= 18)
                raw_bit_at = dlc_latched[18-index];
            else begin
                data_offset = index - 19;
                byte_number = data_offset / 8;
                bit_number  = 7 - (data_offset % 8);
                raw_bit_at  = data_latched[byte_number*8 + bit_number];
            end
        end
    endfunction

    function current_logical_bit;
        begin
            case (phase)
                P_RAW:       current_logical_bit = raw_bit_at(raw_index);
                P_CRC:       current_logical_bit = crc_latched[crc_index];
                default:     current_logical_bit = 1'b1;
            endcase
        end
    endfunction

    function next_logical_bit;
        begin
            case (phase)
                P_RAW: begin
                    if (raw_index == raw_last)
                        next_logical_bit = crc_latched[14];
                    else
                        next_logical_bit = raw_bit_at(raw_index + 1'b1);
                end
                P_CRC: begin
                    if (crc_index == 0)
                        next_logical_bit = 1'b1;
                    else
                        next_logical_bit = crc_latched[crc_index - 1'b1];
                end
                default: next_logical_bit = 1'b1;
            endcase
        end
    endfunction

    task abort_transmission;
        begin
            phase            <= P_IDLE;
            busy             <= 1'b0;
            tx_bit           <= 1'b1;
            current_is_stuff <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        tx_done          <= 1'b0;
        arbitration_lost <= 1'b0;
        ack_error        <= 1'b0;
        bit_error        <= 1'b0;

        if (rst) begin
            phase            <= P_IDLE;
            tx_bit           <= 1'b1;
            busy             <= 1'b0;
            raw_index        <= 7'd0;
            raw_last         <= 7'd18;
            crc_index        <= 5'd14;
            eof_index        <= 4'd0;
            interm_index     <= 3'd0;
            id_latched       <= 11'd0;
            dlc_latched      <= 4'd0;
            data_latched     <= 64'd0;
            crc_latched      <= 15'd0;
            run_length       <= 3'd0;
            last_output      <= 1'b1;
            current_is_stuff <= 1'b0;
        end else begin
            if ((phase == P_IDLE) && start && (frame_dlc <= 8)) begin
                phase            <= P_RAW;
                busy             <= 1'b1;
                id_latched       <= frame_id;
                dlc_latched      <= frame_dlc;
                data_latched     <= frame_data;
                crc_latched      <= frame_crc(frame_id, frame_dlc, frame_data);
                raw_index        <= 7'd0;
                raw_last         <= 7'd18 + frame_dlc * 8;
                crc_index        <= 5'd14;
                tx_bit           <= 1'b0;
                run_length       <= 3'd0;
                last_output      <= 1'b1;
                current_is_stuff <= 1'b0;
            end else if (bit_tick && busy) begin
                if ((phase == P_RAW) && (raw_index >= 1) && (raw_index <= 12) &&
                    tx_bit && !bus_bit) begin
                    arbitration_lost <= 1'b1;
                    abort_transmission();
                end else if ((phase == P_ACK) && bus_bit) begin
                    ack_error <= 1'b1;
                    abort_transmission();
                end else if ((phase != P_ACK) && (phase != P_INTERM) &&
                             (tx_bit != bus_bit)) begin
                    bit_error <= 1'b1;
                    abort_transmission();
                end else if ((phase == P_RAW) || (phase == P_CRC)) begin
                    if (current_is_stuff) begin
                        current_is_stuff <= 1'b0;
                        last_output      <= tx_bit;
                        run_length       <= 3'd1;
                        tx_bit           <= current_logical_bit();
                    end else begin
                        if (phase == P_RAW) begin
                            if (raw_index == raw_last) begin
                                phase     <= P_CRC;
                                crc_index <= 5'd14;
                            end else raw_index <= raw_index + 1'b1;
                        end else begin
                            if (crc_index == 0)
                                phase <= P_CRC_DELIM;
                            else crc_index <= crc_index - 1'b1;
                        end

                        if ((tx_bit == last_output) && (run_length == 3'd5)) begin
                            // Defensive reset: this should be unreachable.
                            bit_error <= 1'b1;
                            abort_transmission();
                        end else if ((tx_bit == last_output) && (run_length == 3'd4)) begin
                            tx_bit           <= ~tx_bit;
                            current_is_stuff <= 1'b1;
                            run_length       <= 3'd5;
                        end else begin
                            if (tx_bit == last_output)
                                run_length <= run_length + 1'b1;
                            else begin
                                run_length  <= 3'd1;
                                last_output <= tx_bit;
                            end
                            tx_bit <= next_logical_bit();
                        end
                    end
                end else begin
                    case (phase)
                        P_CRC_DELIM: begin phase <= P_ACK; tx_bit <= 1'b1; end
                        P_ACK:       begin phase <= P_ACK_DELIM; tx_bit <= 1'b1; end
                        P_ACK_DELIM: begin phase <= P_EOF; eof_index <= 0; tx_bit <= 1'b1; end
                        P_EOF: begin
                            tx_bit <= 1'b1;
                            if (eof_index == 6) begin
                                phase <= P_INTERM;
                                interm_index <= 0;
                            end else eof_index <= eof_index + 1'b1;
                        end
                        P_INTERM: begin
                            tx_bit <= 1'b1;
                            if (interm_index == 2) begin
                                phase <= P_IDLE;
                                busy <= 1'b0;
                                tx_done <= 1'b1;
                            end else interm_index <= interm_index + 1'b1;
                        end
                        default: abort_transmission();
                    endcase
                end
            end
        end
    end
endmodule
