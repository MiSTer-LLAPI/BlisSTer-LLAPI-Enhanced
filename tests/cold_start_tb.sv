// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module cold_start_tb;
    reg clk = 0;
    always #10 clk = !clk;
    wire latch_out, data_out, valid, updated, changed, fault;
    wire [1:0] last_fault;
    LLAPI_Enhanced dut(.CLK_50M(clk), .ENABLE(1'b1), .LLAPI_SYNC(1'b0),
        .IO_LATCH_IN(1'b1), .IO_DATA_IN(1'b1), .IO_LATCH_OUT(latch_out),
        .IO_DATA_OUT(data_out), .CMD_VALID(1'b0), .CMD_OPCODE(8'd0),
        .CMD_PAYLOAD(16'd0), .STATUS_VALID(valid), .STATUS_UPDATE(updated),
        .TYPE_CHANGED(changed), .LINK_FAULT(fault), .LAST_FAULT_REASON(last_fault));

    initial begin
        @(negedge clk);
        if ({latch_out,data_out,valid,updated,changed,fault,last_fault} !== 8'b11000000)
            $fatal(1,"Port was not initialized after first enabled clock");
        @(negedge latch_out);
        repeat (251) @(negedge clk);
        for (integer bit_index=0; bit_index<8; bit_index=bit_index+1) begin
            if (data_out !== 1'b1) $fatal(1,"First command was not POLL");
            if (bit_index<7) repeat (224) @(negedge clk);
        end
        @(posedge latch_out);
        $display("PASS cold boot with ENABLE tied high emits first poll");
        $finish;
    end
    initial begin
        #8000000;
        $fatal(1,"First poll missing");
    end
endmodule
