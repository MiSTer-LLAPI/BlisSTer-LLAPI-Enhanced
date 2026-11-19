`timescale 1ns/1ps
module raw_commands_tb #(parameter bit RAW_COMMANDS = 1);
    reg clk = 0, enable = 0, latch_in = 1, data_in = 1;
    reg request_valid = 0, raw = 0;
    reg [7:0] opcode = 0;
    reg [4:0] tx_length = 0;
    reg [3:0] rx_length = 0;
    reg [191:0] tx_data = 0;
    wire latch_out, data_out, ready, done, connected, status_update;
    wire [7:0] error, controller;
    wire [103:0] reply;
    wire [3:0] reply_length;
    wire modes_valid;
    wire [7:0] modes;

    always #10 clk = ~clk;

    LLAPI_Enhanced #(.COMMAND_INTERFACE(1), .RAW_COMMANDS(RAW_COMMANDS), .AUTO_MODES(0)) dut (
        .CLK_50M(clk), .ENABLE(enable), .LLAPI_SYNC(1'b0),
        .IO_LATCH_IN(latch_in), .IO_DATA_IN(data_in),
        .IO_LATCH_OUT(latch_out), .IO_DATA_OUT(data_out),
        .LLAPI_EN(connected), .LLAPI_TYPE(controller), .STATUS_UPDATE(status_update),
        .LLAPI_MODES(modes), .MODES_VALID(modes_valid),
        .CMD_VALID(request_valid), .CMD_READY(ready), .CMD_DONE(done),
        .CMD_OPCODE(opcode), .CMD_PAYLOAD(16'b0), .CMD_ERROR(error),
        .CMD_RAW(raw), .CMD_TX_LENGTH(tx_length), .CMD_RX_LENGTH(rx_length),
        .CMD_TX_DATA(tx_data), .CMD_REPLY(reply), .CMD_REPLY_LENGTH(reply_length)
    );

    task automatic ticks(input integer count);
        repeat (count) @(negedge clk);
    endtask

    task automatic send_reply(input [103:0] bytes, input integer count);
        latch_in = 0;
        data_in = 1;
        ticks(100);
        for (integer i = 0; i < 8*count; i = i+1) begin
            data_in = 1; ticks(109);
            data_in = ~bytes[i]; ticks(115);
            if (i % 8 == 7) begin
                data_in = 1; ticks(49);
                data_in = 0; ticks(50);
            end
        end
        latch_in = 1;
        data_in = 1;
    endtask

    localparam [103:0] status_bytes = 104'h0800008080808080800000011B;
    localparam [103:0] opaque_reply = 104'h5A00123456ABCDEF006480FFF1;
    reg [191:0] pattern;
    reg [7:0] frame;
    integer frames = 0, quick_requests = 0, map_bytes = 0, updates = 0, modes_requests = 0;
    integer remaining = 0, passed_parameters = 0;
    reg [7:0] current_command;
    reg sending_early_reply = 0;
    always @(posedge clk) if (status_update) updates = updates + 1;
    always @(negedge latch_out) if (sending_early_reply)
        $fatal(1, "Driver transmitted while adapter held the bus for an early reply");
    initial forever begin
        @(negedge latch_out);
        frames = frames + 1;
        ticks(251);
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index+1) begin
            frame[bit_index] = ~data_out;
            if (bit_index < 7) ticks(224);
        end
        @(posedge latch_out);
        ticks(180);
        if (remaining > 0) begin
            if (frame !== pattern[passed_parameters*8 +: 8])
                $fatal(1, "Opcode %h TX byte %0d got %h", current_command, passed_parameters, frame);
            passed_parameters = passed_parameters + 1;
            remaining = remaining - 1;
            if (current_command == 8'h22) map_bytes = map_bytes + 1;
            if (remaining == 0 && current_command == 8'hA5)
                send_reply(opaque_reply, 13);
        end else begin
            current_command = frame;
            case (frame)
                8'h00: begin
                    latch_in = 0; data_in = 0; ticks(200);
                    latch_in = 1; data_in = 1;
                end
                8'h01: send_reply(status_bytes, 13);
                8'h03: begin
                    quick_requests = quick_requests + 1;
                    send_reply(quick_requests == 1 ? 8'h03 : 8'hFF, 1);
                end
                8'h21: begin
                    modes_requests = modes_requests + 1;
                    send_reply(8'h80, 1);
                end
                8'h22, 8'hA5: begin remaining = 24; passed_parameters = 0; end
                8'hA6: send_reply(8'hFE, 1);
                8'hA7: ; // Silent modeled extension.
                8'hA8: begin
                    // Report early, before any of the requested payload can be sent.
                    sending_early_reply = 1;
                    send_reply(8'h65, 1);
                    sending_early_reply = 0;
                end
                default: $fatal(1, "Unexpected wire frame %h",frame);
            endcase
        end
    end

    task automatic request(input [7:0] code, input integer tx, input integer rx,
                           input [7:0] expected_error);
        integer initial_frames;
        wait (ready);
        @(negedge clk);
        initial_frames = frames;
        opcode = code; tx_length = tx; rx_length = rx; tx_data = pattern;
        raw = 1; request_valid = 1;
        @(negedge clk);
        request_valid = 0; opcode = 0; tx_length = 0; rx_length = 0; tx_data = 0; raw = 0;
        wait (done);
        if (error !== expected_error)
            $fatal(1, "Opcode %h returned %h expected %h", code, error, expected_error);
        if (expected_error == 8'hE1 && frames != initial_frames)
            $fatal(1, "Rejected request %h touched the bus", code);
        if (expected_error != 0 && {reply_length,reply} !== 0)
            $fatal(1, "Unsuccessful request %h published reply data", code);
        ticks(220); // The modeled receiver can sample the final released byte.
    endtask

    integer updates_after_timeout;
    initial begin
        for (integer i = 0; i < 24; i = i+1) pattern[i*8 +: 8] = 8'hE9 - 7*i;
        ticks(5); enable = 1;
    end

    initial if (!RAW_COMMANDS) begin
        wait(enable);
        request(8'h03, 0, 1, 8'hE1);
        if (quick_requests != 0) $fatal(1, "Disabled raw extension reached adapter");
        // Drive CMD_RAW high and out-of-range raw lengths on this typed modes read.
        request(8'h21, 31, 15, 0);
        if (modes_requests != 1 || reply_length !== 1 || reply !== 8'h80 ||
            modes_valid !== 1 || modes !== 8'h80)
            $fatal(1, "Disabled raw interface affected typed modes read");
        updates_after_timeout = updates;
        wait (updates > updates_after_timeout);
        if (connected !== 1 || controller !== 8'h1B) $fatal(1, "Lost ordinary polling");
        $display("PASS RAW_COMMANDS=0 with CMD_RAW=1: extension rejected without wire activity, typed Get Modes returned and applied 0x80, normal polling resumed");
        $finish;
    end

    initial if (RAW_COMMANDS) begin
        wait(enable);
        request(8'h03, 0, 1, 0);
        if (reply_length !== 1 || reply !== 3) $fatal(1, "Quick states reply");
        request(8'h22, 24, 0, 0);
        if (map_bytes != 24 || reply_length !== 0 || reply !== 0) $fatal(1, "Mapper framing");
        request(8'hA5, 24, 13, 0);
        if (reply !== opaque_reply || reply_length !== 13) $fatal(1, "Maximum TX/RX lengths or F1 data");
        request(8'hA6, 0, 1, 0);
        if (reply !== 8'hFE || reply_length !== 1) $fatal(1, "FE raw data");
        request(8'h03, 0, 1, 0);
        if (reply !== 8'hFF || reply_length !== 1) $fatal(1, "FF raw data");
        request(8'h00, 0, 0, 8'hE1);
        request(8'h01, 0, 13, 8'hE1);
        request(8'h02, 0, 13, 8'hE1);
        request(8'h11, 0, 0, 8'hE1);
        request(8'h12, 0, 0, 8'hE1);
        request(8'h14, 0, 0, 8'hE1);
        request(8'h18, 0, 0, 8'hE1);
        request(8'h1A, 0, 0, 8'hE1);
        request(8'h1B, 0, 0, 8'hE1);
        request(8'h1C, 2, 0, 8'hE1);
        request(8'h20, 1, 0, 8'hE1);
        request(8'h21, 0, 1, 8'hE1);
        request(8'hA5, 25, 1, 8'hE1);
        request(8'hA5, 0, 14, 8'hE1);
        request(8'hA8, 4, 0, 8'hE2);
        request(8'hA8, 4, 1, 8'hE2);
        request(8'hA7, 0, 1, 8'hE0);
        updates_after_timeout = updates;
        wait (updates > updates_after_timeout);
        if (connected !== 1 || controller !== 8'h1B) $fatal(1, "Lost ordinary polling");
        $display("PASS raw commands at USER pins: quick states, 24 TX, 13 RX, request capture, binary data, bounds, protected opcodes, early replies, timeout and resumed polling");
        $finish;
    end
    initial begin #500000000; $fatal(1, "Raw command simulation timed out"); end
endmodule
