`timescale 1ns/1ps
module legacy_wire_tb;
 reg clk=0, enabled=0, latch_in=1, data_in=1;
 wire latch_out,data_out,active;wire [7:0] kind,modes;wire [31:0] buttons;wire [71:0] analog_data;
 always #10 clk=~clk;
 LLAPI dut(.CLK_50M(clk),.ENABLE(enabled),.LLAPI_SYNC(1'b0),
 .IO_LATCH_IN(latch_in),.IO_DATA_IN(data_in),.IO_LATCH_OUT(latch_out),.IO_DATA_OUT(data_out),
 .LLAPI_EN(active),.LLAPI_TYPE(kind),.LLAPI_MODES(modes),.LLAPI_BUTTONS(buttons),.LLAPI_ANALOG(analog_data));
 reg [7:0] packet[0:12]; integer i,b,polls=0,statuses=0,jolts=0,stops=0;reg [7:0] command;
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task status_reply;
 begin
  latch_in=0;data_in=1;ticks(100);
  for(i=0;i<13;i=i+1)begin
   for(b=0;b<8;b=b+1)begin
    data_in=1;ticks(109);data_in=~packet[i][b];ticks(115);
   end
   data_in=1;ticks(49);data_in=0;ticks(50);
  end
  latch_in=1;data_in=1;
 end
 endtask
 // Adapter decodes the real output wire. No internal connection flag is forced.
 initial forever begin
  @(negedge latch_out);ticks(251);
  for(integer k=0;k<8;k=k+1) begin command[k]=~data_out;if(k<7)ticks(224);end
  @(posedge latch_out);ticks(600);
  if(command==8'h00)begin
   polls=polls+1;latch_in=0;data_in=0;ticks(200);latch_in=1;data_in=1;ticks(10);
  end else if(command==8'h01)begin statuses=statuses+1;status_reply();end
  else if(command==8'h1a) jolts=jolts+1;
  else if(command==8'h12 || command==8'h18) stops=stops+1;
  else $fatal(1,"unexpected command %h",command);
 end
 initial begin
  packet[0]=11;packet[1]=8'h81;packet[2]=8'h42;packet[3]=8'h24;
  packet[4]=8'h20;packet[5]=8'he0;packet[6]=8'h80;packet[7]=8'h41;
  packet[8]=8'hc2;packet[9]=8'h80;packet[10]=0;packet[11]=0;packet[12]=8'h02;
  ticks(5);
  // Model the FPGA power-up zero values of pre-existing uninitialised counters.
  // Reception/discovery itself is exercised solely through the two input pins.
  dut.cycle=0;dut.count=0;dut.sync_counter=0;dut.poll_counter=0;
  dut.poll_offset=0;dut.poll_offset_latch=0;
  enabled=1;
  wait(statuses==1);wait(dut.stage==dut.READ_IDLE);ticks(10);
  if(!active || kind!==11 || buttons!==32'h01244281 || analog_data!==72'h02000080c24180e020)
   $fatal(1,"decoded active=%b type=%h buttons=%h analog=%h",active,kind,buttons,analog_data);
  packet[0]=65;packet[1]=8'h02;packet[12]=8'h08;
  wait(statuses==2);wait(dut.stage==dut.READ_IDLE);ticks(10);
  if(kind!==65 || buttons!==32'h00244202)$fatal(1,"digital report not preserved");
  $display("PASS legacy physical-wire polling, full analog payload and digital controller transition");$finish;
 end
 initial begin #30000000;$fatal(1,"input protocol timeout state=%d stage=%d cycle=%d sync=%d active=%b",dut.state,dut.stage,dut.cycle,dut.sync_counter,active);end
endmodule
