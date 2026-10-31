/* HDL implementation of Low-Latency API protocol
* 
* Copyright 2019 Jamie Dickson aka Kitrinx
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
* documentation files (the "Software"), to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
* and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all copies or substantial portions
* of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
* TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
* CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
* IN THE SOFTWARE.
*/

// Feb, 1 2019 - Initial Release

// ***** NOTE ******
// On IO board 5.5 the bliss box requires external pull-up resistors to communicate properly

// Data payload bit order:

// Byte 0:
// uint8_t Controller Type (or error code)
// Notable ID's are:
// 18 - NES
// 21 - Gen 3 button
// 22 - Gen 6 button
// 27 - SNES
// 28 - NES Zapper
// 41 - Atari Paddles
// 51 - NeGcon
// 65 - PSX Digital
// 11 - PSX DS
// 12 - PSX DS2
// more info: https://docs.google.com/document/d/12XpxrmKYx_jgfEPyw-O2zex1kTQZZ-NSBdLO2RQPRzM/edit

// Bytes 1-2:
// Buttons
// XXX: These are not accurate in 3.0, see the linked document instead
// System SNES    Genesis PSX    Gun   Saturn
//  0:     Y       A       □      Click A
//  1:     B       B       ×      Light B
//  2:     X       X       △      NA    X
//  3:     A       Y       ○      NA    Y
//  4:     Select  Mode    Select NA    NA
//  5:     Start   Start   Start  NA    Start
//  6:     LT      NA      L1     NA    L
//  7:     RT      NA      R1     NA    R

//  8:     NA      Z       L2     NA    Z
//  9:     NA      C       R2     NA    C
// 10:     U       U       U      NA    NA
// 11:     D       D       D      NA    NA
// 12:     L       L       L      NA    NA
// 13:     R       R       R      NA    NA
// 14:     0       NA      L3     NA    NA
// 15:     1       NA      R3     NA    NA

// 16:     2       NA      NA     NA    NA
// 17:     3       NA      NA     NA    NA
// 18:     4       NA      NA     NA    NA
// 19:     5       NA      NA     NA    NA
// 20:     6       NA      NA     NA    NA
// 21:     7       NA      NA     NA    NA
// 22:     8       NA      NA     NA    NA
// 23: This bit can be the "special" trigger button for retroarch
// more info: https://docs.google.com/spreadsheets/d/1Bk3j5kaKfV1tOfzCq3GLKFsff027RdmwOuSfBLM3Ims/edit#gid=0

// Bytes 4-12: (uint8_t's)
// 04: Axis 1 X
// 05: Axis 1 Y
// 06: Axis 1 Z
// 07: Axis 2 X
// 08: Axis 2 Y
// 09: Axis 2 Z
// 10: Slider
// 11: Dial
// 12: Hat

// Modes:
// 0: autopause state
// 1:
// 2: 
// 3: Hotswap Disabled
// 4: UDLR mode
// 5: Analog to D-pad
// 6: autopause dis.
// 7: d-pad only mode

module LLAPI_Enhanced #(
    parameter bit AUTO_MODES = 1,
    parameter bit COMMAND_INTERFACE = 0,
    parameter bit ALLOW_MODE_WRITES = 0
)
(
	input         CLK_50M,
	input         ENABLE,        // If 0, module will be disabled and pins will be set to Z
	input         IO_LATCH_IN,   // D+ top level IO pin
	output reg    IO_LATCH_OUT,
	input         IO_DATA_IN,    // D- top level IO pin
	output reg    IO_DATA_OUT,
	input         LLAPI_SYNC,     // Pos edge corresponds with when the core needs the data, from core
	output        LLAPI_EN,       // High when device is communicating, passed to core
	output [7:0]  LLAPI_TYPE,     // Enumerated controller type, passed to core
	output [7:0]  LLAPI_MODES,    // Modes that the bliss box may be in, passed to core
	output [31:0] LLAPI_BUTTONS,  // Vector of buttons, 1 == pressed, passed to core
	output [71:0] LLAPI_ANALOG,   // Unsigned 8 bit vector of analog axis, passed to core
    input CMD_VALID,
    input [7:0] CMD_OPCODE,
    input [15:0] CMD_PAYLOAD, // low byte first: duration, then level for 1C
    output CMD_READY,
    output reg CMD_DONE,
    output reg [7:0] CMD_ERROR, // 0=transport completed, E0=timeout, E1=rejected
    output reg [103:0] CMD_REPLY,
    output reg [3:0] CMD_REPLY_LENGTH,
    output reg MODES_VALID
);

// Commands
enum bit [7:0] {
	LLAPI_POLL               = 8'h00, // Holds latch low until done
	LLAPI_STATUS             = 8'h01, // Returns 13 bytes, see above
	LLAPI_PRESSURE_STATUS    = 8'h02, // Returns 13 bytes: player ID then 12 pressures
	LLAPI_SET_MODES          = 8'h20, // Requires 1 byte payload
	LLAPI_GET_MODES          = 8'h21, // Returns bit field of active modes, 1 byte. see above
	// Rumble
	LLAPI_RUMBLE_CONST_START_FROM_PARMS = 8'h11, //must set parms first
	LLAPI_RUBMLE_CONST_END              = 8'h12,
	LLAPI_RUMBLE_SINE_START_FROM_PARMS  = 8'h14, //must set parms first
	LLAPI_RUMBLE_SINE_END               = 8'h18,
	LLAPI_RUMBLE_CONST_JOLT             = 8'h1A,
	LLAPI_RUMBLE_SINE_JOLT              = 8'h1B,
	LLAPI_RUMBLE_PARMS                  = 8'h1C //followed by 2 bytes of data containing the parms (duration and then level)
} commands;

// Errors
enum bit [7:0] {
	LLAPI_ERROR_NODATA       = 8'h00,
	LLAPI_ERROR_AP_NO_REPORT = 8'hFF
} errors;

// Timing (one 50mhz cycle == 0.02us)
enum bit [20:0] {
	TIME_POLL   = 21'd350000, // 7ms - default polling period if no sync is used
	TIME_SETTLE = 21'd150,    // 3us - to account for bidirectional IO pins slew rate
	TIME_WAIT   = 21'd500,    // 10us - time to wait after a reply before writing again
	TIME_LEADIN = 21'd84,     // 1.5us - at start of new transactions
	TIME_BIT_H  = 21'd109,    // 2.2us - always-high first bit-half
	TIME_BIT_R  = 21'd115,    // 2.3us - variable second bit-half
	TIME_SYNC_H = 21'd49,     // 1us - sync pulse between bytes high time
	TIME_SYNC_L = 21'd50,     // 1us - sync pulse between bytes low time
	TIME_BUFFER = 21'd9500    // 3 scanlines of wiggle room
} time_periods;

typedef enum bit [3:0] {
	READ_IDLE,
	READ_POLL,
	WRITE_STATUS,
	READ_STATUS,
	WRITE_SETUP,
	WRITE_MODES,
	READ_MODES,
    READ_COMMAND,
    WRITE_PAYLOAD
} execution_stage;

typedef enum bit [3:0] {
	STATE_IDLE,
	STATE_WRITE_START,
	STATE_WRITE,
	STATE_WRITE_END,
	STATE_READ_START,
	STATE_READ_WAIT,
	STATE_READ,
	STATE_READ_END,
    STATE_WAIT_RELEASE
} execution_state;

// Conservative receive-start limit: 1 ms at 50 MHz; requires hardware validation.
localparam [20:0] RECEIVE_START_TIMEOUT = 21'd50000;

logic [20:0]  cycle, count, poll_offset, poll_counter, poll_offset_latch, sync_counter;
logic [31:0]  write_buffer;
logic [3:0]   write_length;
logic [2:0]   read_bit; // Relies on overflow
logic [3:0]   read_byte;
logic [7:0]   read_buffer[13];
logic [3:0]   read_length;

logic modes_attempted, command_busy, command_slot;
logic [1:0] payload_remaining;
logic [7:0] active_opcode;
logic [20:0] transaction_timer;
function automatic valid_command(input [7:0] op);
    valid_command = op == 8'h02 || op == 8'h21 || op == 8'h11 || op == 8'h12 ||
        op == 8'h14 || op == 8'h18 || op == 8'h1a || op == 8'h1b || op == 8'h1c ||
        (ALLOW_MODE_WRITES && op == 8'h20);
endfunction
function automatic protocol_error(input [7:0] v);
    protocol_error = v == 8'hf1 || v == 8'hfe || v == 8'hff;
endfunction
logic [31:0] pending_buttons;
logic [71:0] pending_analog;
logic [7:0] pending_type;
logic packet_complete;
logic [31:0]  lljs_buttons;
logic [71:0]  lljs_analog;
logic [7:0]   lljs_type;
logic [7:0]   lljs_modes;

reg   [20:0]  poll_time = TIME_POLL;

logic latch;
logic is_latched;
logic data_in, data_out;
logic enable;
logic old_sync, new_sync, old_data;

execution_stage stage = READ_IDLE;
execution_state state = STATE_IDLE;

wire auxiliary = command_busy || stage == READ_MODES;
wire poll_due = sync_counter >= ((enable && poll_time > TIME_BUFFER &&
    poll_offset < poll_time - TIME_BUFFER) ? poll_time - poll_offset : poll_time);
assign CMD_READY = COMMAND_INTERFACE && ENABLE && enable && command_slot &&
    !command_busy && stage == READ_IDLE && state == STATE_IDLE &&
    !is_latched && data_in && !poll_due && cycle > TIME_WAIT;
assign LLAPI_TYPE = lljs_type;
assign LLAPI_BUTTONS = lljs_buttons;
assign LLAPI_ANALOG = lljs_analog;
assign LLAPI_MODES = lljs_modes;
assign LLAPI_EN = enable;

always_comb begin
	if (latch) begin
		IO_LATCH_OUT = 1'b0;
		IO_DATA_OUT = data_out;
	end else begin
		IO_LATCH_OUT = 1'b1;
		IO_DATA_OUT = 1'b1;
	end
end

always_ff @(posedge CLK_50M) begin
	if (ENABLE) begin
    CMD_DONE <= 0;
    if (stage != READ_IDLE || state != STATE_IDLE) begin
        if (transaction_timer != 21'h1fffff) transaction_timer <= transaction_timer + 1'b1;
    end else transaction_timer <= 0;
	old_sync <= new_sync;
	new_sync <= LLAPI_SYNC;
	cycle <= cycle + 1'b1;

	if (~latch) begin
		is_latched <= ~IO_LATCH_IN;
		old_data <= data_in;
		data_in <= IO_DATA_IN;
	end

	if (~old_sync && new_sync && sync_counter > poll_offset_latch) begin
		sync_counter <= 0;
		poll_time <= poll_counter > (TIME_BUFFER + TIME_WAIT) ? poll_counter - TIME_BUFFER : TIME_POLL; // about 3 scanlines of wobble room
		poll_counter <= 0;
	end else begin
		if (sync_counter != 21'h1fffff) sync_counter <= sync_counter + 1'b1;
		if (poll_counter != 21'h1fffff) poll_counter <= poll_counter + 1'b1;
	end

	if (stage == READ_POLL || stage == READ_STATUS)
		if (poll_offset != 21'h1fffff) poll_offset <= poll_offset + 1'b1;

	case (state)
		STATE_IDLE: begin
			if (is_latched) begin // remote device wants to talk
				enable <= 1'b1;
				cycle <= 0;
				count <= 0;
				read_byte <= 0;
                packet_complete <= 0;
				state <= STATE_READ_START;
			end else if (stage == WRITE_PAYLOAD) begin
                if (cycle > TIME_WAIT && data_in) begin
                    cycle <= 0; state <= STATE_WRITE_START; stage <= READ_COMMAND;
                end
            end else if (CMD_READY && CMD_VALID) begin
                command_slot <= 0; CMD_ERROR <= 0; CMD_REPLY <= 0; CMD_REPLY_LENGTH <= 0;
                if (!valid_command(CMD_OPCODE)) begin CMD_DONE <= 1; CMD_ERROR <= 8'he1; end
                else begin
                    command_busy <= 1; active_opcode <= CMD_OPCODE;
                    write_buffer <= {8'd0, CMD_PAYLOAD, CMD_OPCODE};
                    payload_remaining <= CMD_OPCODE == 8'h1c ? 2 : (CMD_OPCODE == 8'h20 ? 1 : 0);
                    read_length <= CMD_OPCODE == 8'h02 ? 13 : (CMD_OPCODE == 8'h21 ? 1 : 0);
                    stage <= READ_COMMAND; state <= STATE_WRITE_START;
                    cycle <= 0; transaction_timer <= 0;
                end
            end else if (stage == WRITE_STATUS) begin // We just got a poll result
				if (cycle > TIME_WAIT) begin
					cycle <= 0;
					state <= STATE_WRITE_START;
					stage <= READ_STATUS;
					read_length <= 'd13;
					write_buffer <= {24'd0, LLAPI_STATUS};
				end
			end else if (stage == WRITE_MODES) begin
				if (cycle > TIME_WAIT) begin
					cycle <= 0;
					stage <= READ_MODES;
					read_length <= 1'd1;
					state <= STATE_WRITE_START;
					write_buffer <= {24'd0, LLAPI_GET_MODES};
				end
			end else if (poll_due) begin // Trigger timed device poll. Offset can not be > half the poll time.
				count <= count + 1'b1;
				if (count > TIME_WAIT) begin
					if (stage != READ_IDLE) begin // IO timeout, device disconnect/defunct
						enable <= 1'b0;
						poll_offset <= 0;
						poll_time <= poll_offset_latch > TIME_BUFFER ? poll_offset_latch : TIME_POLL;
						poll_offset_latch <= 21'd350000;
						lljs_buttons <= 24'h0;
						lljs_type <= 8'h0;
						lljs_analog <= 72'h080000808080808080;
                        lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
					end
					poll_offset <= 0;
					sync_counter <= 0;
					cycle <= 0;
					count <= 0;
					read_length <= 0;
					state <= STATE_WRITE_START;
                    transaction_timer <= 0; payload_remaining <= 0;
					stage <= READ_POLL;
					write_buffer <= {24'd0, LLAPI_POLL};
				end
			end
		end

		STATE_WRITE_START: begin
			if (cycle == 0) begin
				data_out <= 1'b0; 
				latch <= 1'b1; // Take control
				write_length <= 'h8; // Always 8 for now
			end else if (cycle >= TIME_LEADIN) begin
				cycle <= 0;
				state <= STATE_WRITE;
			end
		end

		STATE_WRITE: begin
			if (write_length == 0) begin
				state <= STATE_WRITE_END;
				cycle <= 0;
			end else if (cycle == 'd0) begin // high half-bit
				data_out <= 1'b1;
			end else if (cycle == TIME_BIT_H) begin // data half-bit
				data_out <= ~write_buffer[0];
				write_buffer <= {1'b0, write_buffer[31:1]};
			end else if (cycle >= (TIME_BIT_R + TIME_BIT_H)) begin
				write_length <= write_length - 1'b1;
				cycle <= 0;
			end
		end

		STATE_WRITE_END: begin
			if (cycle == 0)
				data_out <= 1'b1;
			else if (cycle == TIME_SYNC_H)
				data_out <= 1'b0;
			else if (cycle == (TIME_SYNC_H + TIME_SYNC_L)) begin
				latch <= 1'b0; // Release
			end else if (cycle >= (TIME_SYNC_H + TIME_SYNC_L + TIME_SETTLE)) begin
				state <= STATE_IDLE;
                if (command_busy && payload_remaining != 0) begin
                    payload_remaining <= payload_remaining - 1'b1;
                    stage <= WRITE_PAYLOAD;
                end else if (command_busy && read_length == 0) begin
                    command_busy <= 0; CMD_DONE <= 1; stage <= READ_IDLE;
                    if (active_opcode == 8'h20) begin modes_attempted <= 0; MODES_VALID <= 0; lljs_modes <= 0; end
                end
                cycle <= 0;
            end
        end

        STATE_READ_START: begin
            if (cycle >= ((stage == READ_POLL) ? TIME_POLL : RECEIVE_START_TIMEOUT)) begin
                // Discard this transaction and wait for both input lines to release.
                // Never repeatedly transmit into a device holding the bus low.
                state <= STATE_WAIT_RELEASE;
                stage <= READ_IDLE;
                cycle <= 0; count <= 0;
                packet_complete <= 0;
                latch <= 0; data_out <= 1;
                enable <= 0;
                lljs_type <= 0; lljs_modes <= 0; lljs_buttons <= 0;
                modes_attempted <= 0; MODES_VALID <= 0;
                lljs_analog <= 72'h080000808080808080;
            end else if (cycle >= TIME_SETTLE && ~is_latched) begin // Just a busy wait/poll/blip
				cycle <= 0;
				if (stage == READ_POLL) begin // Poll processing gets its own budget.
                    stage <= WRITE_STATUS; transaction_timer <= 0;
                end
				state <= STATE_IDLE;
			end else if (count >= 'd10) begin // Allows for latch to be seen if both are released together
				cycle <= 'd10;
				read_bit <= 3'h0;
				state <= STATE_READ;
			end else if (cycle >= TIME_LEADIN && data_in) begin // If we get data high it means we're reading
				count <= count + 1'b1;
			end
		end

        STATE_WAIT_RELEASE: begin
            latch <= 0; data_out <= 1;
            if (is_latched || !data_in) cycle <= 0;
            else if (cycle >= TIME_SETTLE) begin
                state <= STATE_IDLE; stage <= READ_IDLE;
                cycle <= 0; count <= 0;
                poll_offset <= 0; poll_offset_latch <= 0;
                poll_time <= TIME_POLL;
                sync_counter <= TIME_POLL; poll_counter <= 0;
            end
        end

		STATE_READ_WAIT: begin // the space between the bytes
			if (cycle > (TIME_SYNC_H + TIME_SYNC_L + 'd5) ||
				((cycle > 'd25) && ~old_data && data_in)) begin // Re align during wait if needed
				cycle <= 0;
				read_bit <= 3'h0;
				if (read_byte >= read_length) state <= STATE_READ_END; else state <= STATE_READ;
			end
		end

		STATE_READ: begin
			if (~is_latched) begin // Accounts from random timing errors or unexpected events
				cycle <= 0;
				state <= STATE_IDLE;
			end else if (read_byte >= read_length || read_byte >= 13) begin
                state <= STATE_READ_END; cycle <= 0;
            end else if (cycle == (TIME_BIT_H + (TIME_BIT_R >> 1))) begin // latch in the middle of the data window
				read_buffer[read_byte][read_bit] <= ~data_in;
				read_bit <= read_bit + 1'b1;
			end else if (cycle >= TIME_BIT_H + TIME_BIT_R) begin
				cycle <= 0;
				if (read_bit == 3'h0) begin // This relies on overflow behavior
					if (read_byte == 0) begin
						if (stage == READ_STATUS) begin
							pending_type <= read_buffer[0];
						end
					end else if (read_byte == 'd12 && stage == READ_STATUS) begin
                        packet_complete <= 1;
						pending_buttons[31:0] <= {
							4'd0, 
							(read_buffer[12][3] ? 4'd0 :
							{
								(read_buffer[12][2:0] == 3'h0 || read_buffer[12][2:0] == 3'h1 || read_buffer[12][2:0] == 3'h7), //U
								(read_buffer[12][2:0] == 3'h4 || read_buffer[12][2:0] == 3'h3 || read_buffer[12][2:0] == 3'h5), //D
								(read_buffer[12][2:0] == 3'h6 || read_buffer[12][2:0] == 3'h5 || read_buffer[12][2:0] == 3'h7), //L
								(read_buffer[12][2:0] == 3'h2 || read_buffer[12][2:0] == 3'h1 || read_buffer[12][2:0] == 3'h3) //R
							}),
							read_buffer[3],
							read_buffer[2],
							read_buffer[1]
						};

						pending_analog[71:0] <= {
							read_buffer[12],
							read_buffer[11],
							read_buffer[10],
							read_buffer[9],
							read_buffer[8],
							read_buffer[7],
							read_buffer[6],
							read_buffer[5],
							read_buffer[4]
						};
					end
					poll_offset_latch <= poll_offset < (21'h1fffff - TIME_BUFFER) ? poll_offset + TIME_BUFFER : 21'h1fffff;
					read_byte <= read_byte + 1'd1;
                    if (read_byte == 0 && stage != READ_MODES && protocol_error(read_buffer[0])) read_length <= 1;
					state <= STATE_READ_WAIT;
				end
			end
		end
		/*
		#define DPAD_UP      0x04    00000100
		#define DPAD_DOWN    0x08    00001000
		#define DPAD_LEFT    0x10    00010000  
		#define DPAD_RIGHT   0x20    00100000

		#define DPAD_UPLEFT        0x14
		#define DPAD_DOWNLEFT    0x18
		#define DPAD_UPRIGHT    0x24
		#define DPAD_DOWNRIGHT    0x28
		#define DPAD_REST    0xff
		*/

		STATE_READ_END: begin
			// latch data to correct registers based on stage
			if (cycle >= TIME_WAIT) begin // bliss box holds the line low for about 3us after reply
                // Publish type, buttons and all axes together after a complete packet.
                if (stage == READ_STATUS && packet_complete && pending_type != 0 && !protocol_error(pending_type)) begin
                    command_slot <= 1;
                    lljs_type <= pending_type;
                    lljs_buttons <= pending_buttons;
                    lljs_analog <= pending_analog;
                    if (MODES_VALID && pending_type == lljs_type && lljs_modes[7]) begin
                        lljs_buttons[27] <= pending_buttons[27] | (pending_analog[15:8] < 50);
                        lljs_buttons[26] <= pending_buttons[26] | (pending_analog[15:8] > 200);
                        lljs_buttons[25] <= pending_buttons[25] | (pending_analog[7:0] < 50);
                        lljs_buttons[24] <= pending_buttons[24] | (pending_analog[7:0] > 200);
                    end
                end
                packet_complete <= 0;
                stage <= READ_IDLE;
                if (stage == READ_STATUS && packet_complete && pending_type != 0 && !protocol_error(pending_type) && AUTO_MODES && (!modes_attempted || pending_type != lljs_type)) begin
                    stage <= WRITE_MODES; modes_attempted <= 1;
                    lljs_modes <= 0; MODES_VALID <= 0; transaction_timer <= 0;
                end
                if (stage == READ_STATUS && ((read_byte == 1 && protocol_error(read_buffer[0])) || (packet_complete && pending_type == 0))) begin
                    enable <= 0; lljs_type <= 0; lljs_buttons <= 0;
                    lljs_analog <= 72'h080000808080808080;
                    lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
                end
                if ((stage == READ_MODES || (command_busy && active_opcode == 8'h21)) && read_byte == 1) begin
                    if (!protocol_error(read_buffer[0])) begin
                        lljs_modes <= read_buffer[0]; MODES_VALID <= 1;
                    end else begin lljs_modes <= 0; MODES_VALID <= 0; end
                end
                if (command_busy) begin
                    CMD_DONE <= 1; command_busy <= 0;
                    CMD_REPLY_LENGTH <= read_byte;
                    for (integer n=0; n<13; n=n+1)
                        if (n < read_byte) CMD_REPLY[n*8 +: 8] <= read_buffer[n];
                    if (read_byte == 1 && protocol_error(read_buffer[0])) CMD_ERROR <= read_buffer[0];
                end
                cycle <= 0;
                state <= STATE_IDLE;
			end
		end

		default: begin
			cycle <= 0;
			count <= 0;
			stage <= READ_IDLE;
			state <= STATE_IDLE;
		end
    endcase
    if (transaction_timer >= ((stage == READ_POLL) ? TIME_POLL : RECEIVE_START_TIMEOUT) && state != STATE_WAIT_RELEASE) begin
        if (is_latched || !data_in) state <= STATE_WAIT_RELEASE; else state <= STATE_IDLE;
        stage <= READ_IDLE; cycle <= 0; count <= 0; transaction_timer <= 0;
        latch <= 0; data_out <= 1; packet_complete <= 0; payload_remaining <= 0;
        if (command_busy) begin CMD_DONE <= 1; CMD_ERROR <= 8'he0; command_busy <= 0; end
        if (!auxiliary || is_latched || !data_in) begin
            enable <= 0; lljs_type <= 0; lljs_buttons <= 0;
            lljs_analog <= 72'h080000808080808080;
            lljs_modes <= 0; MODES_VALID <= 0; modes_attempted <= 0;
        end
    end
    end else begin
        // ENABLE low resets transaction/synchronization state deterministically.
        modes_attempted <= 0; MODES_VALID <= 0; command_busy <= 0; command_slot <= 0;
        payload_remaining <= 0; active_opcode <= 0; transaction_timer <= 0;
        CMD_DONE <= 0; CMD_ERROR <= 0; CMD_REPLY <= 0; CMD_REPLY_LENGTH <= 0;
        pending_type <= 0; pending_buttons <= 0; pending_analog <= 0; packet_complete <= 0;
        cycle <= 0; count <= 0; poll_offset <= 0; poll_counter <= 0;
        poll_offset_latch <= 0; sync_counter <= 0; poll_time <= TIME_POLL;
        write_buffer <= 0; write_length <= 0;
        read_bit <= 0; read_byte <= 0; read_length <= 0;
        is_latched <= 0; data_in <= 1; old_data <= 1; data_out <= 1;
        old_sync <= 0; new_sync <= 0;
		latch <= 1'b0;
		enable <= 1'b0;
		lljs_analog <= 0;
		lljs_buttons <= 0;
		lljs_modes <= 0;
		lljs_type <= 0;
		state <= STATE_IDLE;
		stage <= READ_IDLE;
	end
end

endmodule

