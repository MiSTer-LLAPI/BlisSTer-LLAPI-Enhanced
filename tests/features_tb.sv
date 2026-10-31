`timescale 1ns/1ps
module features_tb;
 parameter integer POLL_BUSY_TICKS=200;
 parameter integer MODE_WRITES=1;
 parameter integer MODE_REPLY=128; // -1 means unsupported/no reply
 reg clk=0,en=0,sync=0,li=1,di=1,valid=0;
 reg [7:0] op=0;reg [15:0] payload=0;
 wire lo,dout,active,ready,done,mvalid;
 wire [7:0] kind,modes,err;wire[31:0] buttons;wire[71:0] analog_data;
 wire[103:0] reply;wire[3:0] length;
 always #10 clk=~clk;
 LLAPI_Enhanced #(.COMMAND_INTERFACE(1),.ALLOW_MODE_WRITES(MODE_WRITES)) dut(
 .CLK_50M(clk),.ENABLE(en),.LLAPI_SYNC(sync),.IO_LATCH_IN(li),.IO_DATA_IN(di),
 .IO_LATCH_OUT(lo),.IO_DATA_OUT(dout),.LLAPI_EN(active),.LLAPI_TYPE(kind),
 .LLAPI_MODES(modes),.LLAPI_BUTTONS(buttons),.LLAPI_ANALOG(analog_data),
 .CMD_VALID(valid),.CMD_OPCODE(op),.CMD_PAYLOAD(payload),.CMD_READY(ready),
 .CMD_DONE(done),.CMD_ERROR(err),.CMD_REPLY(reply),.CMD_REPLY_LENGTH(length),.MODES_VALID(mvalid));
 integer polls=0,statuses=0,queries=0,remaining=0,params=0,commands=0;
 reg [7:0] command,parameter_bytes[0:2];reg [7:0] bytes[0:12];
 reg [7:0] status_error=0; reg no_controller=0;
 reg suppress_pressure=0;reg [7:0] error_pressure=0;
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task send(input integer n);
 begin
  li=0;di=1;ticks(100);
  for(integer i=0;i<n;i=i+1)begin
   for(integer b=0;b<8;b=b+1)begin di=1;ticks(109);di=~bytes[i][b];ticks(115);end
   di=1;ticks(49);di=0;ticks(50);
  end
  li=1;di=1;
 end endtask
 initial forever begin
  @(negedge lo);ticks(251);
  for(integer k=0;k<8;k=k+1)begin command[k]=~dout;if(k<7)ticks(224);end
  @(posedge lo);ticks(180);
  if(remaining>0)begin
   parameter_bytes[params]=command;params=params+1;remaining=remaining-1;
  end else case(command)
   0:begin polls=polls+1;li=0;di=0;ticks(POLL_BUSY_TICKS);li=1;di=1;end
   1:begin
    statuses=statuses+1;
    bytes[0]=no_controller ? 0 : 11;bytes[1]=1;bytes[2]=0;bytes[3]=0;
    for(integer a=4;a<10;a=a+1)bytes[a]=128;
    bytes[4]=20;bytes[5]=230;bytes[10]=0;bytes[11]=0;bytes[12]=8;
    if(status_error!=0)begin bytes[0]=status_error;send(1);end else send(13);
   end
   'h21:begin queries=queries+1;if(MODE_REPLY>=0)begin bytes[0]=MODE_REPLY;send(1);end end
   'h02:begin
    if(!suppress_pressure)begin
     for(integer a=0;a<13;a=a+1) bytes[a]=a+1;
     if(error_pressure)begin bytes[0]=error_pressure;send(1);end else send(13);
    end
   end
   'h1c:begin remaining=2;params=0;end
   'h20:begin remaining=1;params=0;end
   'h11,'h12,'h14,'h18,'h1a,'h1b:commands=commands+1;
   default:$fatal(1,"unexpected wire command %h",command);
  endcase
 end
 task request(input [7:0] opcode,input [15:0] data,input [7:0] expected_error);
 begin
  wait(ready);@(negedge clk);op=opcode;payload=data;valid=1;
  @(negedge clk);valid=0;op=0;payload=0;
  wait(done);@(negedge clk);
  ticks(100);
  if(err!==expected_error)$fatal(1,"command %h error %h expected %h",opcode,err,expected_error);
 end endtask
 integer before_status;
 initial begin
  ticks(5);en=1;
  repeat(3)begin ticks(100);sync=1;ticks(5);sync=0;end
  if(dut.poll_time>350000)$fatal(1,"poll period underflow");
  wait(queries==1);wait(ready);
  if(MODE_REPLY==128)begin
   if(!mvalid || modes!==128)$fatal(1,"GET_MODES not published");
   wait(statuses==2);wait(ready);
   if(buttons[27:24]!==4'b0110)$fatal(1,"mode-dependent analog dpad not active: %h",buttons);
  end else if(mvalid || modes!==0)$fatal(1,"unsupported modes marked valid");
  request('h02,0,0);
  if(length!==13 || reply[7:0]!==1 || reply[103:96]!==13)$fatal(1,"pressure reply incorrect");
  before_status=statuses;
  request('h1c,16'hb407,0);
  if(remaining || params!=2 || parameter_bytes[0]!==7 || parameter_bytes[1]!==180)
   $fatal(1,"rumble parameters interleaved/reversed/missing");
  if(statuses<=before_status)$fatal(1,"command stream starved polling");
  request('h11,0,0);request('h12,0,0);request('h14,0,0);request('h18,0,0);
  request('h1a,0,0);request('h1b,0,0);
  if(commands!=6)$fatal(1,"missing rumble commands");
  request('h20,16'h0058,MODE_WRITES ? 0 : 8'he1);
  if(MODE_WRITES && (params!=1 || parameter_bytes[0]!==8'h58))$fatal(1,"mode payload wrong");
  request('h99,0,'he1);
  error_pressure='hf1;request('h02,0,'hf1);
  error_pressure='hfe;request('h02,0,'hfe);
  error_pressure='hff;request('h02,0,'hff);error_pressure=0;
  suppress_pressure=1;request('h02,0,'he0);suppress_pressure=0;
  if(!active || kind!==11)$fatal(1,"optional command timeout disconnected healthy controller");
  request('h02,0,0);
  if(length!=13)$fatal(1,"no recovery after optional timeout");
  status_error=8'hfe;before_status=statuses;
  wait(statuses>before_status);wait(!active);ticks(10);
  if(kind!==0 || buttons!==0 || analog_data!==72'h080000808080808080 || mvalid)
   $fatal(1,"status error did not neutralize controls");
  status_error=0;wait(ready);
  no_controller=1;before_status=statuses;
  wait(statuses>before_status);wait(!active);ticks(10);
  if(kind!==0 || buttons!==0 || analog_data!==72'h080000808080808080)
   $fatal(1,"no-controller status did not neutralize controls");
  no_controller=0;wait(ready);
  // Reset cancels a newly accepted request before transmission.
  wait(ready);@(negedge clk);op='h02;valid=1;
  @(negedge clk);valid=0;en=0;ticks(5);
  if(active || ready || done || lo!==1 || dout!==1)$fatal(1,"reset did not cancel request safely");
  en=1;wait(ready);
  // Fast sync edges are covered at startup above.

  $display("PASS features: automatic modes=%0d, pressure, atomic rumble/mode payloads, errors, bounded timeout, recovery, poll fairness",MODE_REPLY);$finish;
 end
 initial begin #250000000;$fatal(1,"feature timeout state=%d stage=%d statuses=%d queries=%d",dut.state,dut.stage,statuses,queries);end
endmodule
