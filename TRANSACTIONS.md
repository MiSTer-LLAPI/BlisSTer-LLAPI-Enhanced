# Optional command interface

Experimental FPGA-side implementation for existing BlisSTer LLAPI firmware. No firmware modification is required by the interface design; operation on physical hardware has not yet been validated.

## Integration

`AUTO_MODES=1` (default) queries `0x21` after the first complete status and after a controller-type change. `MODES_VALID` distinguishes a returned bitmap from the zero fallback. Unsupported/error/silent queries do not stop ordinary polling. The query is attempted once per connection/type; after an explicit mode write it is refreshed. Set `AUTO_MODES=0` to retain the earlier poll/status-only schedule.

`COMMAND_INTERFACE=0` (default) removes the optional request path; unused request ports can remain unconnected in existing named-port instantiations. Enable it with `COMMAND_INTERFACE=1`. Positional instantiations must be updated for the added ports.

All request signals are synchronous to `CLK_50M`. A request is accepted on a rising edge with both `CMD_VALID` and `CMD_READY` high. Hold opcode and payload stable until that edge, then withdraw VALID unless another request is intended. The driver captures the entire request. Later changes to request inputs cannot change the in-flight command.

Only one command is in flight. At most one optional command is accepted between successful ordinary status reports. Due polls have priority. Automatic mode queries precede optional commands. This bounds command traffic without promising a measured latency improvement.

| Opcode | Operation | Payload | Reply |
|---|---|---|---|
| `02` | Pressure | None | 13 bytes: player ID and 12 pressure values |
| `21` | Get modes | None | One bitmap byte |
| `1C` | Set rumble parameters | Low payload byte: duration; high byte: level | No documented acknowledgement |
| `11`, `14` | Start constant/sine effect | Set parameters first using `1C` | No documented acknowledgement |
| `12`, `18` | Stop constant/sine effect | None | No documented acknowledgement |
| `1A`, `1B` | Constant/sine jolt | None | No documented acknowledgement |
| `20` | Set modes | Low payload byte | Disabled unless `ALLOW_MODE_WRITES=1` |

Mode writes are explicit opt-in and never automatic. The built-in interface has no mapper/player write commands. Pressure stays separate from the ordinary buttons/axes snapshot: consume `CMD_REPLY` after successful completion. Byte zero occupies bits 7:0, byte twelve bits 103:96. Values remain raw; interpretation is the core's responsibility.

The command and its parameter bytes use individual wire frames, with the normal release/settling gap between them. Poll/status commands cannot interleave. Duration precedes level, following the vendor documentation and the public firmware parser; the older source comment has the order reversed.

## Extension commands (v0.3.1-dev candidate)

Enable both `COMMAND_INTERFACE=1` and `RAW_COMMANDS=1` on the desired port. Drive `CMD_RAW=0` for a built-in command. With `CMD_RAW=1`, present the following descriptor at the normal `CMD_READY && CMD_VALID` handshake. Existing named-port integrations can omit the extension inputs with the default parameters.

| Field | Meaning |
| --- | --- |
| `CMD_OPCODE` | Extension opcode, one byte |
| `CMD_TX_LENGTH` | Number of parameter bytes following the opcode, from 0 to 24 |
| `CMD_TX_DATA` | Packed parameter bytes, with byte zero in bits 7:0 |
| `CMD_RX_LENGTH` | Expected number of reply bytes, from 0 to 13. Use zero for a write-only transaction. |

For example, `GET_QUICK_STATES` (0x03) uses zero parameters and expects one byte. The raw reply is in `CMD_REPLY[7:0]` when `CMD_DONE` pulses. The caller interprets the returned bytes, including values F1, FE and FF. If the firmware sends a one-byte error instead of a longer declared reply, the request can time out. A write-only completion records transmission; a physical effect requires separate confirmation.

For an ordinary SNES pad, use the normal poll (0x00) followed by controller status (0x01). To test the new read-only quick-states request, use a supported light gun. Wait for a valid controller report and submit one descriptor with `CMD_RAW=1`, `CMD_OPCODE=8'h03`, `CMD_TX_LENGTH=0`, `CMD_TX_DATA=0` and `CMD_RX_LENGTH=1`. Record the firmware version independently, the controller, `CMD_ERROR`, the reply length and byte, and the next ordinary status report. The vendor defines only gun trigger and light in bits 0 and 1. Observe the two bits with the trigger released and pressed, and with light detected if the setup supports it. Record F1, FE or FF as possible firmware errors before interpreting any status bits.

The simulation also exercises a 24-byte write using `SET_MAPPER` (0x22). The [vendor table](https://bliss-box.com/pages/integration) lists 24 parameter bytes, while the [published example parser](https://github.com/ulao/Bliss-Box-LLAPI/blob/abdb246195d5d089b6fd968ebb98aa86ce3c6a70/LLAPI%20open%20source.c) initializes its parameter counter to 23. Confirm the count for the target firmware before attempting this write on hardware. The fixture verifies byte order only.

Raw requests reuse the normal serializer, wait for their turn between controller reports and capture all parameters before transmission. They have a 7 ms total budget at 50 MHz, including replies. Unsupported lengths, raw overrides of typed commands (including mode writes), and raw poll/status requests return E1 without sending any bytes. The adapter must implement the supplied opcode and the caller must know its wire format. An unsupported opcode cannot be used to discover firmware features reliably. After an interrupted multi-byte write the adapter may need a port reset.

## Completion and errors

`CMD_DONE` pulses for one clock. `CMD_ERROR`, `CMD_REPLY`, and `CMD_REPLY_LENGTH` remain until the next accepted request or reset. Capture them when DONE is asserted.

- `00`: transport completed. For write-only commands this means bytes sent, **not** proof of execution, motor movement or acknowledgement.
- `F1`, `FE`, `FF`: documented adapter error replies on built-in commands. Raw commands return these bytes as data.
- `E0`: bounded transaction timeout, including an incomplete reply.
- `E1`: rejected descriptor, unsupported built-in opcode or disabled mode write. Nothing is sent. The command slot remains available for a corrected request.
- `E2`: the adapter requested a reply transfer while outgoing typed or raw parameter bytes were still pending. The request stops, the reply length is zero, and polling can resume after the lines are released.

ENABLE low resets/cancels an in-flight request without a DONE pulse; the integrating core must discard that request too. No command is automatically replayed after an interruption: this avoids repeating actuator commands or treating an orphan parameter as a new command. If the device lost synchronization during a multi-byte write, physical recovery may require resetting the adapter; this has not been validated.

A 1 ms timeout bounds built-in optional transactions. Raw extension transactions and controller polls have a 7 ms budget. These limits require hardware validation, especially with slow controller protocols. A stuck bus releases the FPGA outputs, neutralizes inputs and waits for both lines to remain released. A silent optional command on an otherwise released bus preserves the last ordinary input snapshot and permits subsequent polling.

The one-byte modes bitmap can collide numerically with reserved error values. The current conservative policy treats F1/FE/FF as errors; hardware validation must confirm firmware behavior for these combinations.

## Validation boundary

Wire-level simulation covers automatic modes, unsupported/silent mode queries, all listed command opcodes, parameter order, request capture, raw pressure replies, adapter errors, optional-command timeout/recovery and polling between commands. Baseline tests retain explicit AUTO_MODES=0 to check compatibility of the earlier schedule. Simulation is not Quartus timing closure, resource measurement or hardware validation.

The core still has to request/map pressure and rumble explicitly. Independent motor control is not established by these effect commands. SNAC and LLAPI must remain mutually exclusive; this interface does not implement an SNAC wrapper.

Sources: [vendor protocol](https://bliss-box.com/pages/integration) and [public transport parser](https://github.com/ulao/Bliss-Box-LLAPI/blob/abdb246195d5d089b6fd968ebb98aa86ce3c6a70/LLAPI%20open%20source.c). The GPL firmware was inspected as a reference, not copied into the MIT driver.

## Interrupted-write regression

`features_tb.sv` with `PAYLOAD_FAULTS=1` blocks the adapter after the rumble parameter opcode and after its first parameter. It checks one E0 completion, no further frames while blocked, neutral controller outputs and released driver pins.

`RESET_PAYLOAD=1` disables the driver early, halfway and late in each of the three outgoing frames (opcode, duration, level): nine cases. It checks cancellation without DONE, released pins, no automatic replay and a successful fresh request afterward.

Both recovery fixtures explicitly reset the modeled adapter's parameter parser. These results do not demonstrate recovery after a driver-only reset against real firmware retaining a partial command. They also do not prove motor stop or rumble expiration. Those remain physical validation requirements.

## Storage optimization

The serial count is bounded to TIME_WAIT+1. The transaction timer width is derived from the maximum poll/receive-start timeout and counts only active transactions. The timer resets while idle or waiting for both lines to release. At the deadline the watchdog takes priority over reply publication. Packet completion still gates atomic publication of controller type, buttons and axes. External ports and handshake semantics are unchanged.
