`timescale 1ns/1ps
module features_tb;
 parameter integer RX_DELTA=0; // simulated adapter half-bit variation in 20ns ticks
 parameter integer PATTERN_SWEEP=0;
 parameter integer TYPE_RECONNECT=0;
 parameter integer RESET_PAYLOAD=0;
 parameter integer PAYLOAD_FAULTS=0;
 parameter integer PRESSURE_FAULTS=0;
 parameter integer POLL_BUSY_TICKS=200;
 parameter integer MODE_WRITES=1;
 parameter integer MODE_REPLY=128; // -1 means unsupported/no reply
 reg clk=0,en=0,sync=0,li=1,di=1,valid=0;
 reg [7:0] op=0;reg [15:0] payload=0;
 wire lo,dout,active,ready,done,mvalid,status_valid,status_update,link_fault;
 integer updates=0,faults=0;
 reg previous_update=0,previous_fault=0;
 wire [7:0] kind,modes,err;wire[31:0] buttons;wire[71:0] analog_data;
 wire[103:0] reply;wire[3:0] length;
 always @(negedge clk) begin
  if(status_update && previous_update) $fatal(1,"status pulse longer than one cycle");
  if(link_fault && previous_fault) $fatal(1,"fault pulse longer than one cycle");
  previous_update=status_update; previous_fault=link_fault;
  if(status_update) begin
   updates=updates+1;
   if(!status_valid || kind==0) $fatal(1,"update without valid snapshot");
  end
  if(link_fault) faults=faults+1;
  if(!en && status_valid) $fatal(1,"disabled snapshot valid");
 end
 always #10 clk=~clk;
 LLAPI_Enhanced #(.COMMAND_INTERFACE(1),.ALLOW_MODE_WRITES(MODE_WRITES)) dut(
 .CLK_50M(clk),.ENABLE(en),.LLAPI_SYNC(sync),.IO_LATCH_IN(li),.IO_DATA_IN(di),
 .IO_LATCH_OUT(lo),.IO_DATA_OUT(dout),.LLAPI_EN(active),.LLAPI_TYPE(kind),
 .LLAPI_MODES(modes),.LLAPI_BUTTONS(buttons),.LLAPI_ANALOG(analog_data),
 .CMD_VALID(valid),.CMD_OPCODE(op),.CMD_PAYLOAD(payload),.CMD_READY(ready),
 .CMD_DONE(done),.CMD_ERROR(err),.CMD_REPLY(reply),.CMD_REPLY_LENGTH(length),.MODES_VALID(mvalid),.STATUS_VALID(status_valid),.STATUS_UPDATE(status_update),.LINK_FAULT(link_fault));
 integer polls=0,statuses=0,queries=0,remaining=0,params=0,commands=0;
 reg [7:0] command,parameter_bytes[0:2];reg [7:0] bytes[0:12];
 reg [7:0] controller_type=11;
 integer mode_response=MODE_REPLY;
 reg [7:0] status_error=0; reg no_controller=0;
 integer pressure_bytes=13, pattern_base=0;
 integer payload_stall_after=-1, wire_frames=0, completions=0;
 always @(posedge clk) if(done) completions=completions+1;
 always @(negedge lo) wire_frames=wire_frames+1;
 reg suppress_pressure=0;reg [7:0] error_pressure=0;
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task send(input integer n);
 begin
  li=0;di=1;ticks(100);
  for(integer i=0;i<n;i=i+1)begin
   for(integer b=0;b<8;b=b+1)begin di=1;ticks(109+RX_DELTA);di=~bytes[i][b];ticks(115+RX_DELTA);end
   di=1;ticks(49);di=0;ticks(50);
  end
  li=1;di=1;
 end endtask
 initial forever begin : adapter_frame
  @(negedge lo);ticks(251);
  if(!en)disable adapter_frame;
  for(integer k=0;k<8;k=k+1)begin
   if(!en)disable adapter_frame;
   command[k]=~dout;if(k<7)ticks(224);
  end
  if(!en)disable adapter_frame;
  @(posedge lo);ticks(180);
  if(!en)disable adapter_frame;
  if(remaining>0)begin
   parameter_bytes[params]=command;params=params+1;remaining=remaining-1;
   if(params==payload_stall_after)begin li=0;di=0;end
  end else case(command)
   0:begin polls=polls+1;li=0;di=0;ticks(POLL_BUSY_TICKS);li=1;di=1;end
   1:begin
    statuses=statuses+1;
    bytes[0]=no_controller ? 0 : controller_type;bytes[1]=1;bytes[2]=0;bytes[3]=0;
    for(integer a=4;a<10;a=a+1)bytes[a]=128;
    bytes[4]=20;bytes[5]=230;bytes[10]=0;bytes[11]=0;bytes[12]=8;
    if(status_error!=0)begin bytes[0]=status_error;send(1);end else send(13);
   end
   'h21:begin queries=queries+1;if(mode_response>=0)begin bytes[0]=mode_response;send(1);end end
   'h02:begin
    if(!suppress_pressure)begin
     for(integer a=0;a<13;a=a+1) bytes[a]=(PATTERN_SWEEP && a>0) ? ((pattern_base+a-1)&255) : a+1;
     if(error_pressure)begin bytes[0]=error_pressure;send(1);end else send(pressure_bytes);
    end
   end
   'h1c:begin remaining=2;params=0;if(payload_stall_after==0)begin li=0;di=0;end end
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
 integer before_status, held_frames, done_before, query_before;
 initial begin
  ticks(5);en=1;
  repeat(3)begin ticks(100);sync=1;ticks(5);sync=0;end
  if(dut.poll_time>350000)$fatal(1,"poll period underflow");
  wait(queries==1);wait(ready);
  if(MODE_REPLY==128)begin
   if(!mvalid || modes!==128)$fatal(1,"GET_MODES not published");
   wait(statuses==2);wait(ready);
   if(buttons[27:24]!==4'b0110)$fatal(1,"mode-dependent analog dpad not active: buttons=%h analog=%h rx_delta=%0d",buttons,analog_data,RX_DELTA);
  end else if(mvalid || modes!==0)$fatal(1,"unsupported modes marked valid");
  if(PATTERN_SWEEP)begin
   for(integer batch=0;batch<22;batch=batch+1)begin
    pattern_base=batch*12;
    request('h02,0,0);
    if(length!==13 || reply[7:0]!==1)$fatal(1,"pattern header/length");
    for(integer b=1;b<13;b=b+1)
     if(reply[b*8 +: 8]!==((pattern_base+b-1)&255))
      $fatal(1,"pattern mismatch delta=%0d batch=%0d byte=%0d got=%h",RX_DELTA,batch,b,reply[b*8 +: 8]);
   end
   $display("PASS receive patterns: all256 payload values across22 replies delta=%0d",RX_DELTA);$finish;
  end
  if(TYPE_RECONNECT)begin
   query_before=queries;before_status=statuses;
   wait(statuses>=before_status+2);wait(ready);
   if(queries!=query_before)$fatal(1,"modes queried repeatedly without change");
   controller_type=65;mode_response=0;
   wait(kind==65);
   if(mvalid || modes!==0)$fatal(1,"old modes leaked across controller type change");
   wait(ready);
   if(queries!=query_before+1 || !mvalid || modes!==0)
    $fatal(1,"new controller modes not refreshed");
   if(buttons[27:24]!==0)$fatal(1,"previous analog dpad mode leaked");
   query_before=queries;no_controller=1;
   wait(!active);ticks(10);
   if(status_valid || faults==0 || mvalid || modes!==0 || kind!==0 || buttons!==0)
    $fatal(1,"disconnect retained type/modes/buttons");
   no_controller=0;mode_response=128;
   wait(ready);
   if(!status_valid || updates<3 || kind!==65 || !mvalid || modes!==128 || queries!=query_before+1)
    $fatal(1,"same-type reconnect did not rediscover modes");
   before_status=statuses;wait(statuses>before_status);wait(ready);
   if(buttons[27:24]!==4'b0110)$fatal(1,"reconnected modes not applied");
   $display("PASS type/modes reconnect: one query per connection/type, invalidation on swap, zero bitmap valid, same-type reconnect refresh and mode application");
   $finish;
  end
  if(RESET_PAYLOAD)begin
   // Cancel opcode, duration and level frames at early/middle/late points.
   for(integer frame_idx=1;frame_idx<=3;frame_idx=frame_idx+1)begin
    for(integer point=0;point<3;point=point+1)begin
     wait(ready);@(negedge clk);op='h1c;payload=16'hb407;valid=1;
     @(negedge clk);valid=0;op=0;payload=0;done_before=completions;
     repeat(frame_idx)@(negedge lo);
     ticks(point==0 ? 50 : (point==1 ? 900 : 1800));
     en=0;ticks(5);
     if(active || ready || done || lo!==1 || dout!==1 || length!==0 || reply!==0)
      $fatal(1,"reset did not cancel frame=%0d point=%0d",frame_idx,point);
     held_frames=wire_frames;ticks(3000);
     if(wire_frames!==held_frames || completions!==done_before)
      $fatal(1,"reset emitted frame/completion");
     // A physical adapter may retain orphan parameters: model its reset
     // explicitly, do not claim driver-only reset resynchronizes firmware.
     remaining=0;params=0;li=1;di=1;en=1;
     wait(ready);
     if(params!=0 || remaining!=0 || completions!==done_before)
      $fatal(1,"canceled payload replayed after restart");
     request('h1c,16'hb407,0);
     if(remaining || params!=2 || parameter_bytes[0]!==7 || parameter_bytes[1]!==180)
      $fatal(1,"fresh payload failed after reset");
    end
   end
   $display("PASS payload resets:9 cancellations across opcode/duration/level, early/middle/late, released outputs, no completion/replay, fresh request after modeled adapter reset");
   $finish;
  end
  if(PAYLOAD_FAULTS)begin
   for(integer boundary=0;boundary<2;boundary=boundary+1)begin
    payload_stall_after=boundary;done_before=completions;
    request('h1c,16'hb407,'he0);
    if(params!==boundary)$fatal(1,"payload sent beyond blocked boundary %0d params=%0d",boundary,params);
    if(completions!==done_before+1)$fatal(1,"timeout completion count");
    if(active || kind!==0 || buttons!==0 || mvalid || lo!==1 || dout!==1)
     $fatal(1,"blocked payload did not disconnect/release bus");
    held_frames=wire_frames;ticks(60000);
    if(wire_frames!==held_frames || completions!==done_before+1)
     $fatal(1,"blocked bus retransmission or repeated completion");
    // Reset the modeled adapter parser before reconnecting. This does NOT
    // establish that real firmware discards orphan parameters on its own.
    payload_stall_after=-1;remaining=0;params=0;li=1;di=1;
    wait(ready);
    if(!active || kind!==11)$fatal(1,"no link recovery after modeled adapter reset");
    request('h1c,16'hb407,0);
    if(remaining || params!=2 || parameter_bytes[0]!==7 || parameter_bytes[1]!==180)
     $fatal(1,"payload recovery incorrect");
   end
   $display("PASS payload faults: stalls after opcode/first parameter, one timeout, no writes while blocked, neutral inputs, recovery after modeled adapter reset");
   $finish;
  end
  if(PRESSURE_FAULTS)begin
   // Every incomplete pressure payload must fail, publish no partial reply,
   // preserve ordinary inputs, and recover on the next complete transaction.
   for(integer cut=1;cut<=12;cut=cut+1)begin
    pressure_bytes=cut;
    request('h02,0,'he0);
    if(length!==0 || reply!==0)$fatal(1,"partial pressure published cut=%0d",cut);
    if(!active || kind!==11 || buttons[0]!==1 || analog_data[7:0]!==20)
     $fatal(1,"pressure truncation corrupted ordinary input cut=%0d",cut);
    pressure_bytes=13;
    request('h02,0,0);
    if(length!==13)$fatal(1,"pressure recovery length cut=%0d",cut);
    for(integer byte_idx=0;byte_idx<13;byte_idx=byte_idx+1)
     if(reply[byte_idx*8 +: 8] !== byte_idx+1)
      $fatal(1,"pressure recovery data cut=%0d byte=%0d",cut,byte_idx);
   end
   $display("PASS pressure faults: all12 truncated replies rejected, ordinary inputs preserved, all13 recovery bytes checked");
   $finish;
  end
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

  $display("PASS features: rx_delta=%0d automatic modes=%0d, pressure, atomic rumble/mode payloads, errors, bounded timeout, recovery, poll fairness",RX_DELTA,MODE_REPLY);$finish;
 end
 initial begin #500000000;$fatal(1,"feature timeout state=%d stage=%d statuses=%d queries=%d",dut.state,dut.stage,statuses,queries);end
endmodule
