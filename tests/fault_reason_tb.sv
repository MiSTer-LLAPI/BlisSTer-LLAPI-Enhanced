`timescale 1ns/1ps
// Directed state-boundary test. Wire-level recovery is covered by run.sh.
module fault_reason_tb;
reg clk=0,en=0;always #10 clk=~clk;
wire fault;wire[1:0] reason;
LLAPI_Enhanced dut(.CLK_50M(clk),.ENABLE(en),.LLAPI_SYNC(1'b0),.IO_LATCH_IN(1'b1),.IO_DATA_IN(1'b1),.CMD_VALID(1'b0),.CMD_OPCODE(8'd0),.CMD_PAYLOAD(16'd0),.LINK_FAULT(fault),.FAULT_REASON(reason));
task reset_driver;begin en=0;repeat(3)@(negedge clk);if(fault||reason!=0)$fatal(1,"disable not clear");en=1;end endtask
task check(input[1:0] expected);begin @(negedge clk);if(!fault||reason!==expected)$fatal(1,"fault reason %d expected %d",reason,expected);end endtask
initial begin
reset_driver;
force dut.state=dut.STATE_READ_START;force dut.cycle=500000;force dut.transaction_timer=0;check(1);
release dut.state;release dut.cycle;release dut.transaction_timer;
reset_driver;
force dut.state=dut.STATE_READ_END;force dut.stage=dut.READ_STATUS;force dut.cycle=500000;force dut.transaction_timer=0;force dut.packet_complete=1;force dut.pending_type=0;check(2);
release dut.state;release dut.stage;release dut.cycle;release dut.transaction_timer;release dut.packet_complete;release dut.pending_type;
reset_driver;
force dut.state=dut.STATE_READ;force dut.stage=dut.READ_STATUS;force dut.transaction_timer=500000;check(3);
release dut.state;release dut.stage;release dut.transaction_timer;
reset_driver;
$display("PASS fault reason timeout/rejected status/receive watchdog and disable clear");$finish;
end
endmodule
