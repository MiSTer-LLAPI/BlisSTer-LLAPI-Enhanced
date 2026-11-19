`timescale 1ns/1ps
// Standalone: compile with rtl/llapi_enhanced.sv and select poll_overlap_tb.
module poll_overlap_tb #(parameter bit AUTO_MODES = 1);
    reg clk = 0, enable = 0, latch_in = 1, data_in = 1, valid = 0;
    wire latch_out, data_out, ready, done, snapshot_valid, update, fault, modes_valid;
    wire [1:0] reason;
    wire [7:0] kind, modes, error_code;
    wire [31:0] buttons;
    wire [71:0] axes;
    wire [103:0] reply;
    wire [3:0] length;
    integer updates = 0, faults = 0, completions = 0;
    always #10 clk = ~clk;

    LLAPI_Enhanced #(.COMMAND_INTERFACE(1), .AUTO_MODES(AUTO_MODES)) dut (
        .CLK_50M(clk), .ENABLE(enable), .LLAPI_SYNC(1'b0),
        .IO_LATCH_IN(latch_in), .IO_LATCH_OUT(latch_out),
        .IO_DATA_IN(data_in), .IO_DATA_OUT(data_out),
        .CMD_VALID(valid), .CMD_READY(ready), .CMD_OPCODE(8'h02), .CMD_PAYLOAD(16'd0),
        .CMD_DONE(done), .CMD_ERROR(error_code), .CMD_REPLY(reply), .CMD_REPLY_LENGTH(length),
        .LLAPI_TYPE(kind), .LLAPI_BUTTONS(buttons), .LLAPI_ANALOG(axes),
        .STATUS_VALID(snapshot_valid), .STATUS_UPDATE(update),
        .LLAPI_MODES(modes), .MODES_VALID(modes_valid), .LINK_FAULT(fault), .FAULT_REASON(reason)
    );

    always @(negedge clk) begin
        if (update) updates = updates + 1;
        if (done) completions = completions + 1;
        if (fault) faults = faults + 1;
        if (updates > 0 && (!snapshot_valid || kind !== 8'd11 ||
            buttons !== 32'h00000001 || axes !== 72'h080000808080808080))
            $fatal(1, "ordinary snapshot lost during poll overlap");
    end

    task ticks(input integer n);
        repeat(n) @(negedge clk);
    endtask

    task expect_frame(input [7:0] expected);
        reg [7:0] received;
        @(negedge latch_out);
        ticks(251);
        for (integer bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
            received[bit_no] = ~data_out;
            if (bit_no < 7) ticks(224);
        end
        if (received !== expected) $fatal(1, "wire opcode %h, expected %h", received, expected);
        @(posedge latch_out);
        ticks(180);
    endtask

    task send_reply(input [103:0] bytes, input integer num_bytes);
        latch_in = 0;
        data_in = 1;
        ticks(100);
        for (integer n = 0; n < 8*num_bytes; n = n + 1) begin
            data_in = 1; ticks(109);
            data_in = ~bytes[n]; ticks(115);
            if (n % 8 == 7) begin
                data_in = 1; ticks(49);
                data_in = 0; ticks(50);
            end
        end
        latch_in = 1;
        data_in = 1;
    endtask

    task answer_poll_and_status(input integer busy_ticks);
        expect_frame(8'h00);
        latch_in = 0; data_in = 0; ticks(busy_ticks);
        latch_in = 1; data_in = 1;
        expect_frame(8'h01);
        send_reply(104'h0800008080808080800000010b, 13);
    endtask

    // The deadline is observed only to place the stimulus. Both the link and
    // the deadline advance normally, with no force or register assignment.
    task request_pressure_near_deadline;
        wait (ready);
        wait (dut.sync_counter >= dut.poll_time - dut.poll_offset - 1200);
        @(negedge clk);
        if (!ready) $fatal(1, "command missed its acceptance window");
        valid = 1; ticks(1); valid = 0;
        expect_frame(8'h02);
        if (!dut.poll_due) $fatal(1, "deadline did not overlap command");
    endtask

    // Give the scheduler enough time to launch a poll in the broken design.
    task delay_reply;
        wait (dut.poll_due);
        repeat (800) begin
            ticks(1);
            if (latch_out !== 1 || done || fault)
                $fatal(1, "poll interrupted the outstanding auxiliary reply");
        end
    endtask

    localparam [103:0] PRESSURE = 104'h0c0b0a09080706050403020101;
    initial begin
        ticks(5); enable = 1;
        // A long controller poll brings the next deadline into the automatic
        // modes response window, even with the normal unsynchronized cadence.
        answer_poll_and_status(AUTO_MODES ? 140000 : 200);
        if (AUTO_MODES) begin
            expect_frame(8'h21);
            delay_reply();
            send_reply(104'h80, 1);
            wait (modes_valid);
            if (modes !== 8'h80 || completions || faults) $fatal(1, "automatic modes failed");
        end

        answer_poll_and_status(200);
        request_pressure_near_deadline();
        delay_reply();
        send_reply(PRESSURE, 13);
        wait (done);
        if (error_code !== 0 || length !== 13 || reply !== PRESSURE || faults)
            $fatal(1, "late pressure reply lost");

        answer_poll_and_status(200);
        request_pressure_near_deadline();
        // Leave the bus released until the command's own watchdog expires.
        while (!done) begin
            ticks(1);
            if (latch_out !== 1) $fatal(1, "poll sent before silent command timed out");
        end
        if (error_code !== 8'he0 || length !== 0 || reply !== 0 || !fault || reason !== 1)
            $fatal(1, "incorrect silent-command completion");
        answer_poll_and_status(200);
        wait (ready);
        if (updates != 4 || faults != 1 || completions != 2 || modes_valid !== AUTO_MODES)
            $fatal(1, "unexpected publications, faults or completions after recovery");
        $display("PASS poll overlap AUTO_MODES=%0d: delayed replies, silent pressure E0, stable inputs and resumed polling", AUTO_MODES);
        $finish;
    end
    initial begin #60000000; $fatal(1, "poll overlap test timed out"); end
endmodule
