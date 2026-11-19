`timescale 1ns/1ps
module watchdog_boundary_tb;
    reg clk = 0, enabled = 0, latch_in = 1, data_in = 1;
    wire update, valid, fault, changed, done, modes_valid, latch_out, data_out;
    wire [1:0] reason, last_reason;
    wire [7:0] kind, modes, cmd_error;
    wire [3:0] reply_length;
    wire [103:0] reply;
    integer failures = 0;

    always #10 clk = ~clk;
    LLAPI_Enhanced #(.AUTO_MODES(0), .COMMAND_INTERFACE(1)) dut (
        .CLK_50M(clk), .ENABLE(enabled), .LLAPI_SYNC(1'b0),
        .IO_LATCH_IN(latch_in), .IO_DATA_IN(data_in),
        .IO_LATCH_OUT(latch_out), .IO_DATA_OUT(data_out),
        .CMD_VALID(1'b0), .CMD_OPCODE(8'd0), .CMD_PAYLOAD(16'd0),
        .LLAPI_TYPE(kind), .LLAPI_MODES(modes), .MODES_VALID(modes_valid),
        .STATUS_UPDATE(update), .STATUS_VALID(valid), .TYPE_CHANGED(changed),
        .LINK_FAULT(fault), .FAULT_REASON(reason), .LAST_FAULT_REASON(last_reason),
        .CMD_DONE(done), .CMD_ERROR(cmd_error), .CMD_REPLY_LENGTH(reply_length), .CMD_REPLY(reply)
    );

    task reset_port;
        enabled = 0;
        latch_in = 1;
        data_in = 1;
        repeat (3) @(negedge clk);
        enabled = 1;
    endtask

    task check(input logic passed, input string message);
        if (passed !== 1'b1) begin
            $display("FAIL %s", message);
            failures++;
        end
    endtask

    // Set up the final settling clock without changing any public output
    // after this edge. The driver chooses between publication and timeout.
    task status_commit(input integer timer);
        reset_port;
        dut.state = dut.STATE_READ_END;
        dut.stage = dut.READ_STATUS;
        dut.enable = 1;
        dut.lljs_type = 11;
        dut.pending_type = 65;
        dut.packet_complete = 1;
        dut.read_byte = 13;
        for (integer i = 0; i < 13; i++) dut.read_buffer[i] = i;
        dut.read_buffer[0] = 65;
        dut.cycle = dut.TIME_WAIT;
        dut.transaction_timer = timer;
        @(negedge clk);
    endtask

    initial begin
        status_commit(dut.RECEIVE_START_TIMEOUT-1);
        check(valid && update && changed && !fault && kind == 65,
              "last in-budget clock must publish the status");
        @(negedge clk);
        check(valid && !update && !changed && !fault && kind == 65,
              "finished status must not time out on the next idle clock");

        status_commit(dut.RECEIVE_START_TIMEOUT);
        check(fault && reason == 1 && !valid && !update && !changed && kind == 0,
              "status at deadline must report only the timeout");

        // An explicit GET_MODES also reaches the same final settling edge.
        reset_port;
        dut.state = dut.STATE_READ_END;
        dut.stage = dut.READ_COMMAND;
        dut.command_busy = 1;
        dut.active_opcode = 8'h21;
        dut.enable = 1;
        dut.lljs_type = 11;
        dut.lljs_modes = 8'h04;
        dut.MODES_VALID = 1;
        dut.read_byte = 1;
        dut.read_buffer[0] = 8'h80;
        dut.cycle = dut.TIME_WAIT;
        dut.transaction_timer = dut.RECEIVE_START_TIMEOUT;
        @(negedge clk);
        check(fault && reason == 1 && done && cmd_error == 8'he0 && valid && kind == 11,
              "expired command must complete once with E0 and retain the ordinary snapshot");
        check(reply_length == 0 && reply == 0 && modes_valid && modes == 8'h04,
              "expired command must not publish mode or reply data");
        @(negedge clk);
        check(!fault && !done, "timeout events must be one clock wide");

        // Use only the external lines to reproduce a single prolonged stall.
        reset_port;
        latch_in = 0;
        data_in = 0;
        wait (fault);
        @(negedge clk);
        check(reason == 1 && dut.state == dut.STATE_WAIT_RELEASE,
              "stuck receive start must report a timeout and wait for release");
        repeat (dut.RECEIVE_START_TIMEOUT + 10) begin
            @(negedge clk);
            if (fault || !latch_out || !data_out) $fatal(1, "fault or drive during quarantine");
        end
        latch_in = 1;
        data_in = 1;
        wait (dut.state == dut.STATE_IDLE);
        @(negedge clk);
        @(negedge clk);
        check(!fault && reason == 0 && last_reason == 1,
              "releasing the same stall must not raise a second timeout");
        wait (!latch_out);
        if (failures) $fatal(1, "%0d watchdog boundary checks failed", failures);
        $display("PASS watchdog deadlines, atomic status/command outcomes and single-fault bus recovery");
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "timed out waiting for bus recovery");
    end
endmodule
