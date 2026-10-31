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

Mode writes are explicit opt-in and never automatic. The driver does not implement persistent mapper/player writes. Pressure stays separate from the ordinary buttons/axes snapshot: consume `CMD_REPLY` after successful completion. Byte zero occupies bits 7:0, byte twelve bits 103:96. Values remain raw; interpretation is the core's responsibility.

The command and its parameter bytes use individual wire frames, with the normal release/settling gap between them. Poll/status commands cannot interleave. Duration precedes level, following the vendor documentation and the public firmware parser; the older source comment has the order reversed.

## Completion and errors

`CMD_DONE` pulses for one clock. `CMD_ERROR`, `CMD_REPLY`, and `CMD_REPLY_LENGTH` remain until the next accepted request or reset. Capture them when DONE is asserted.

- `00`: transport completed. For write-only commands this means bytes sent, **not** proof of execution, motor movement or acknowledgement.
- `F1`, `FE`, `FF`: documented adapter error replies.
- `E0`: bounded transaction timeout, including an incomplete reply.
- `E1`: unsupported opcode or mode writes disabled. Nothing is sent.

ENABLE low resets/cancels an in-flight request without a DONE pulse; the integrating core must discard that request too. No command is automatically replayed after an interruption: this avoids repeating actuator commands or treating an orphan parameter as a new command. If the device lost synchronization during a multi-byte write, physical recovery may require resetting the adapter; this has not been validated.

A 1 ms engineering timeout bounds optional transactions and reception; controller poll/busy waits have the existing 7 ms budget. These limits require hardware validation, especially with slow controller protocols. A stuck bus releases the FPGA outputs, neutralizes inputs and waits for both lines to remain released. A silent optional command on an otherwise released bus preserves the last ordinary input snapshot and permits subsequent polling.

The one-byte modes bitmap can collide numerically with reserved error values. The current conservative policy treats F1/FE/FF as errors; hardware validation must confirm firmware behavior for these combinations.

## Validation boundary

Wire-level simulation covers automatic modes, unsupported/silent mode queries, all listed command opcodes, parameter order, request capture, raw pressure replies, adapter errors, optional-command timeout/recovery and polling between commands. Baseline tests retain explicit AUTO_MODES=0 to check compatibility of the earlier schedule. Simulation is not Quartus timing closure, resource measurement or hardware validation.

The core still has to request/map pressure and rumble explicitly. Independent motor control is not established by these effect commands. SNAC and LLAPI must remain mutually exclusive; this interface does not implement an SNAC wrapper.

Sources: [vendor protocol](https://bliss-box.com/pages/integration) and [public transport parser](https://github.com/ulao/Bliss-Box-LLAPI/blob/abdb246195d5d089b6fd968ebb98aa86ce3c6a70/LLAPI%20open%20source.c). The GPL firmware was inspected as a reference, not copied into the MIT driver.
