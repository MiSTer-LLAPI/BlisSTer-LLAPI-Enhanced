`timescale 1ns/1ps
module manual_modes_swap_tb;
    reg clk = 0, enable = 0;
    reg adapter_latch = 1, adapter_data = 1, request_valid = 0;
    wire host_latch, host_data, ready, done, update, changed, modes_valid;
    wire [7:0] controller, modes, error;
    wire [31:0] buttons;
    wire [103:0] reply;
    wire [3:0] reply_length;
    always #10 clk = ~clk;

    LLAPI_Enhanced #(.AUTO_MODES(0), .COMMAND_INTERFACE(1)) dut(
        .CLK_50M(clk), .ENABLE(enable), .LLAPI_SYNC(1'b0),
        .IO_LATCH_IN(adapter_latch), .IO_DATA_IN(adapter_data),
        .IO_LATCH_OUT(host_latch), .IO_DATA_OUT(host_data),
        .CMD_VALID(request_valid), .CMD_OPCODE(8'h21), .CMD_PAYLOAD(16'd0),
        .CMD_READY(ready), .CMD_DONE(done), .CMD_ERROR(error),
        .CMD_REPLY(reply), .CMD_REPLY_LENGTH(reply_length),
        .LLAPI_TYPE(controller), .LLAPI_BUTTONS(buttons), .LLAPI_MODES(modes),
        .MODES_VALID(modes_valid), .STATUS_UPDATE(update), .TYPE_CHANGED(changed)
    );

    reg [7:0] adapter_type = 11, adapter_modes = 8'h80;
    reg [7:0] frame, data_bytes[0:12];
    integer requests = 0, queries = 0;

    task ticks(input integer n);
        repeat (n) @(negedge clk);
    endtask

    task send_bytes(input integer count);
        adapter_latch = 0;
        adapter_data = 1;
        ticks(100);
        for (integer i = 0; i < count; i++) begin
            for (integer b = 0; b < 8; b++) begin
                adapter_data = 1;
                ticks(109);
                adapter_data = ~data_bytes[i][b];
                ticks(115);
            end
            adapter_data = 1;
            ticks(49);
            adapter_data = 0;
            ticks(50);
        end
        adapter_latch = 1;
        adapter_data = 1;
    endtask

    initial forever begin
        @(negedge host_latch);
        ticks(251);
        for (integer b = 0; b < 8; b++) begin
            frame[b] = ~host_data;
            if (b < 7) ticks(224);
        end
        @(posedge host_latch);
        ticks(180);
        case (frame)
            8'h00: begin
                adapter_latch = 0;
                adapter_data = 0;
                ticks(200);
                adapter_latch = 1;
                adapter_data = 1;
            end
            8'h01: begin
                data_bytes[0] = adapter_type;
                send_bytes(13);
            end
            8'h21: begin
                queries++;
                if (queries > requests) $fatal(1, "unsolicited mode query in manual mode");
                data_bytes[0] = adapter_modes;
                send_bytes(1);
            end
            default: $fatal(1, "unexpected wire command %h", frame);
        endcase
    end

    task read_modes;
        wait (ready);
        @(negedge clk);
        requests++;
        request_valid = 1;
        @(negedge clk);
        request_valid = 0;
        wait (done);
        @(negedge clk);
        if (queries != requests || error !== 0 || reply_length !== 1 ||
            reply[7:0] !== adapter_modes || modes_valid !== 1 || modes !== adapter_modes)
            $fatal(1, "explicit mode query failed");
    endtask

    task check_status(input [7:0] id, input swap, input [3:0] dpad);
        @(posedge update);
        @(negedge clk);
        if (controller !== id || changed !== swap || buttons[27:24] !== dpad)
            $fatal(1, "status type=%h changed=%b dpad=%b", controller, changed, buttons[27:24]);
    endtask

    initial begin
        for (integer i = 0; i < 13; i++) data_bytes[i] = 0;
        data_bytes[4] = 20;  // left on X
        data_bytes[5] = 230; // down on Y
        data_bytes[12] = 8;  // neutral hat
        ticks(5);
        enable = 1;
        check_status(11, 0, 0);
        read_modes();
        check_status(11, 0, 4'b0110);
        adapter_type = 65;
        adapter_modes = 0;
        check_status(65, 1, 0);
        if (modes_valid !== 0 || modes !== 0)
            $fatal(1, "direct type change retained previous manual modes: valid=%b modes=%h", modes_valid, modes);
        check_status(65, 0, 0);
        read_modes();
        check_status(65, 0, 0);
        if (modes_valid !== 1 || modes !== 0 || queries != 2)
            $fatal(1, "replacement controller's valid zero bitmap lost");
        $display("PASS manual modes: explicit query, direct swap invalidation, no stale D-pad, explicit refresh");
        $finish;
    end

    initial begin
        #60000000;
        $fatal(1, "manual modes test timed out");
    end
endmodule
