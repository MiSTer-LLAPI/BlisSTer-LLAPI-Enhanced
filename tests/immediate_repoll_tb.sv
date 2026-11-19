`timescale 1ns/1ps
// Standalone: compile with rtl/llapi_enhanced.sv and select poll_overlap_tb.
module immediate_repoll_tb;
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

    LLAPI_Enhanced #(.COMMAND_INTERFACE(1), .AUTO_MODES(0), .IMMEDIATE_REPOLL(1)) dut (
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

    time published;
    always @(posedge update) published = $time;
    initial begin
        ticks(5); enable = 1;
        answer_poll_and_status(200);
        wait (update);
        @(negedge latch_out);
        if ($time - published < 10000 || $time - published > 10200)
            $fatal(1, "unexpected report-to-poll interval %0d ns", $time-published);
        ticks(251);
        repeat (8) begin
            if (data_out !== 1) $fatal(1, "next opcode was not 00");
            ticks(224);
        end
        $display("PASS complete status followed by physical poll frame after bus turnaround");
        $finish;
    end
    initial begin #40000000; $fatal(1, "repoll timed out"); end
endmodule
