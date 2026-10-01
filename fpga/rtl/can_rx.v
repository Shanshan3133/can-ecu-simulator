`timescale 1ns/1ps

// Receive path for Classical CAN 2.0A standard data frames. bit_valid must
// pulse once per sampled nominal bit. Data byte 0 is stored in data[7:0].
module can_rx #(
    parameter [10:0] ACCEPTANCE_ID   = 11'h000,
    parameter [10:0] ACCEPTANCE_MASK = 11'h000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        bit_valid,
    input  wire        bus_bit,
    output reg         ack_drive,
    output reg         frame_valid,
    output reg  [10:0] frame_id,
    output reg  [3:0]  frame_dlc,
    output reg  [63:0] frame_data,
    output reg         crc_error,
    output reg         stuff_error,
    output reg         form_error
);
    localparam [3:0] S_IDLE      = 4'd0;
    localparam [3:0] S_ID        = 4'd1;
    localparam [3:0] S_RTR       = 4'd2;
    localparam [3:0] S_IDE       = 4'd3;
    localparam [3:0] S_R0        = 4'd4;
    localparam [3:0] S_DLC       = 4'd5;
    localparam [3:0] S_DATA      = 4'd6;
    localparam [3:0] S_CRC       = 4'd7;
    localparam [3:0] S_CRC_TAIL  = 4'd8;
    localparam [3:0] S_ACK       = 4'd9;
    localparam [3:0] S_ACK_DELIM = 4'd10;
    localparam [3:0] S_EOF       = 4'd11;
    localparam [3:0] S_ERROR     = 4'd12;

    reg [3:0] state;
    reg [6:0] field_index;
    reg [3:0] dlc_work;
    reg [14:0] crc_calc;
    reg [14:0] crc_received;
    reg crc_matches;
    reg frame_eligible;
    reg [3:0] recessive_count;

    wire sof_start = (state == S_IDLE) && bit_valid && (bus_bit == 1'b0);
    wire stuffed_region = sof_start || (state >= S_ID && state <= S_CRC) ||
                          ((state == S_CRC_TAIL) && destuff_pending);
    wire destuff_clear = (state == S_IDLE) && !sof_start;
    wire logical_valid;
    wire logical_bit;
    wire destuff_error;
    wire destuff_pending;

    can_destuffer destuffer (
        .clk(clk), .rst(rst), .clear(destuff_clear),
        .enable(stuffed_region), .bit_valid(bit_valid), .raw_bit(bus_bit),
        .logical_valid(logical_valid), .logical_bit(logical_bit),
        .stuff_error(destuff_error), .stuff_pending(destuff_pending)
    );

    function [14:0] crc_step;
        input [14:0] current;
        input bit_value;
        reg feedback;
        begin
            feedback = bit_value ^ current[14];
            crc_step = {current[13:0], 1'b0};
            if (feedback)
                crc_step = crc_step ^ 15'h4599;
        end
    endfunction

    function accepted;
        input [10:0] identifier;
        begin
            accepted = ((identifier & ACCEPTANCE_MASK) ==
                        (ACCEPTANCE_ID & ACCEPTANCE_MASK));
        end
    endfunction

    task reject_frame;
        begin
            state           <= S_ERROR;
            ack_drive       <= 1'b0;
            frame_eligible  <= 1'b0;
            recessive_count <= 4'd0;
        end
    endtask

    always @(posedge clk) begin
        frame_valid <= 1'b0;
        crc_error   <= 1'b0;
        stuff_error <= 1'b0;
        form_error  <= 1'b0;

        if (rst) begin
            state            <= S_IDLE;
            ack_drive        <= 1'b0;
            frame_id         <= 11'd0;
            frame_dlc        <= 4'd0;
            frame_data       <= 64'd0;
            field_index      <= 7'd0;
            dlc_work         <= 4'd0;
            crc_calc         <= 15'd0;
            crc_received     <= 15'd0;
            crc_matches      <= 1'b0;
            frame_eligible   <= 1'b0;
            recessive_count  <= 4'd0;
        end else if (bit_valid) begin
            if (destuff_error) begin
                stuff_error <= 1'b1;
                reject_frame();
            end else begin
                case (state)
                    S_IDLE: begin
                        ack_drive <= 1'b0;
                        if (bus_bit == 1'b0) begin
                            state          <= S_ID;
                            field_index    <= 7'd0;
                            frame_id       <= 11'd0;
                            frame_dlc      <= 4'd0;
                            frame_data     <= 64'd0;
                            dlc_work       <= 4'd0;
                            crc_calc       <= crc_step(15'd0, 1'b0);
                            crc_received   <= 15'd0;
                            crc_matches    <= 1'b0;
                            frame_eligible <= 1'b1;
                        end
                    end

                    S_ID: if (logical_valid) begin
                        frame_id  <= {frame_id[9:0], logical_bit};
                        crc_calc  <= crc_step(crc_calc, logical_bit);
                        if (field_index == 7'd10) begin
                            state       <= S_RTR;
                            field_index <= 7'd0;
                        end else field_index <= field_index + 1'b1;
                    end

                    S_RTR: if (logical_valid) begin
                        crc_calc <= crc_step(crc_calc, logical_bit);
                        if (logical_bit) frame_eligible <= 1'b0;
                        state <= S_IDE;
                    end

                    S_IDE: if (logical_valid) begin
                        crc_calc <= crc_step(crc_calc, logical_bit);
                        if (logical_bit) frame_eligible <= 1'b0;
                        state <= S_R0;
                    end

                    S_R0: if (logical_valid) begin
                        crc_calc <= crc_step(crc_calc, logical_bit);
                        if (logical_bit) begin
                            form_error <= 1'b1;
                            reject_frame();
                        end else begin
                            state       <= S_DLC;
                            field_index <= 7'd0;
                        end
                    end

                    S_DLC: if (logical_valid) begin
                        dlc_work <= {dlc_work[2:0], logical_bit};
                        crc_calc <= crc_step(crc_calc, logical_bit);
                        if (field_index == 7'd3) begin
                            frame_dlc <= {dlc_work[2:0], logical_bit};
                            field_index <= 7'd0;
                            if ({dlc_work[2:0], logical_bit} > 4'd8) begin
                                form_error <= 1'b1;
                                reject_frame();
                            end else if ({dlc_work[2:0], logical_bit} == 0) begin
                                state <= S_CRC;
                            end else begin
                                state <= S_DATA;
                            end
                        end else field_index <= field_index + 1'b1;
                    end

                    S_DATA: if (logical_valid) begin
                        frame_data[(field_index / 8) * 8 +
                                   (7 - (field_index % 8))] <= logical_bit;
                        crc_calc <= crc_step(crc_calc, logical_bit);
                        if (field_index == (frame_dlc * 8 - 1)) begin
                            state       <= S_CRC;
                            field_index <= 7'd0;
                        end else field_index <= field_index + 1'b1;
                    end

                    S_CRC: if (logical_valid) begin
                        crc_received <= {crc_received[13:0], logical_bit};
                        if (field_index == 7'd14) begin
                            crc_matches <= ({crc_received[13:0], logical_bit} == crc_calc);
                            state       <= S_CRC_TAIL;
                            field_index <= 7'd0;
                        end else field_index <= field_index + 1'b1;
                    end

                    S_CRC_TAIL: begin
                        // If the CRC ended with a run of five, consume its final
                        // stuff bit first. Otherwise this is the CRC delimiter.
                        if (!destuff_pending) begin
                            if (bus_bit != 1'b1) begin
                                form_error <= 1'b1;
                                reject_frame();
                            end else if (!crc_matches) begin
                                crc_error <= 1'b1;
                                reject_frame();
                            end else begin
                                ack_drive <= frame_eligible;
                                state <= S_ACK;
                            end
                        end
                    end

                    S_ACK: begin
                        ack_drive <= 1'b0;
                        state <= S_ACK_DELIM;
                    end

                    S_ACK_DELIM: begin
                        if (bus_bit != 1'b1) begin
                            form_error <= 1'b1;
                            reject_frame();
                        end else begin
                            state       <= S_EOF;
                            field_index <= 7'd0;
                        end
                    end

                    S_EOF: begin
                        if (bus_bit != 1'b1) begin
                            form_error <= 1'b1;
                            reject_frame();
                        end else if (field_index == 7'd6) begin
                            frame_valid <= frame_eligible && accepted(frame_id);
                            state <= S_IDLE;
                        end else field_index <= field_index + 1'b1;
                    end

                    S_ERROR: begin
                        ack_drive <= 1'b0;
                        if (bus_bit) begin
                            if (recessive_count == 4'd10) begin
                                state <= S_IDLE;
                                recessive_count <= 4'd0;
                            end else recessive_count <= recessive_count + 1'b1;
                        end else recessive_count <= 4'd0;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
