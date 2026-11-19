# BlisSTer LLAPI Enhanced

A compact, robust LLAPI driver for MiSTer, with coherent controller readings, bounded communication recovery and optional interfaces for pressure and rumble. The project supports integrations using two independent LLAPI ports and the official MiSTer Main.

## Driver v0.5.0 — immediate polling under contention and recovery

A pending auxiliary command can use its post-report slot even when the frame-based poll is due. If the data line stays low before the next poll, the transaction watchdog invalidates the stale report and waits for bus release. Simulations cover mode discovery followed by pressure and resumed polling, plus recovery from a blocked line through a fresh report.

## Driver v0.4.0

A core can enable `IMMEDIATE_REPOLL=1` independently on each port. After publishing a complete controller report from Get Data (`0x01`), the driver starts the next Poll (`0x00`) as soon as the bus turnaround permits. The adapter can then sample the controller while the core uses the last complete report. Automatic mode discovery and accepted commands retain access to the bus. The default value of zero preserves frame-based scheduling for existing cores and provides a reference for comparison.

### How the driver evolved

| Revision | What changed for a core or its player |
|---|---|
| Original LLAPI | Jamie Dickson (Kitrinx) implemented the serial protocol used to poll Bliss-Box hardware and read controller data. This implementation is the reference for the Enhanced driver. |
| 0.1 alpha 1–2 | Deterministic reset and complete controller snapshots kept buttons and axes from different reports from being mixed. A receive-start timeout and bus-release check allowed recovery from stalled transfers. |
| 0.1 alpha 3–4 | Added controller-mode discovery, optional pressure and rumble transactions, transport error handling and a correction to synchronization between received bytes. |
| 0.1.0 | Reduced counter widths and redundant snapshot storage while preserving complete updates. Expanded fault, payload and timing tests. |
| 0.2.0–0.2.1 | Added snapshot-valid, update and link-fault signals, then a two-bit fault reason so a core can distinguish a timeout from a rejected report. |
| 0.3.0 | Added direct controller-type change detection and independent fault history per port. Improved cold start, command arbitration at a polling deadline and invalidation of stale controller modes. |
| 0.3.1 | Added optional firmware extension commands with up to 24 parameter bytes and 13 reply bytes per request. |
| 0.4.0 | Added optional immediate re-polling after a complete report. A simulated adapter checks the next opcode at the pins and the interval from report publication to transmission. |
| 0.5.0 | Protected the post-report command slot and bounded the wait for a blocked data line. |

### Hardware reference for the scheduling change

On a MiSTer running the Contra P1 timing diagnostic with the previous scheduler, three SNES reports were followed by a new poll after 15.734–15.738 ms. Three PSX DualShock reports were followed by a new poll after 10 µs. The polling operation itself took 575–577 µs on SNES and 3.920–3.921 ms on DualShock. These measurements describe the driver and adapter. The planned 1944 comparison will measure the new scheduler on hardware. Button-to-screen latency remains unmeasured.

## Optional extension commands

A core can submit a firmware-supported extension opcode with up to 24 parameter bytes and request up to 13 reply bytes. The driver captures the request, sends the bytes using the existing LLAPI timing, and resumes controller polling. Enable this per port at synthesis time. See [the command interface and a quick-states example](TRANSACTIONS.md#extension-commands-v031-dev-candidate). Physical validation of this interface is pending.

## What changed in the Enhanced cores?

With v0.3.0-dev, a core can tell when one port reports a different controller type between two complete reads. In a two-player simulation, P1 switched from SNES to PSX DualShock while holding autofire. The core stopped P1’s autofire until the button was released and pressed again. P2 kept firing at the same rate and could press and release Jump throughout the swap. Each port also remembers its most recent communication fault after the connection recovers.

The **Controller Guide** in [Contra Enhanced v0.8.0](https://github.com/MiSTer-LLAPI/jtcores/releases/tag/v0.8.0-contra-enhanced) shows player and button information for the selected LLAPI or SNAC interface. In its **Autofire** menu, each player can enable HOLD on a dedicated button and choose a speed. Both players start with autofire off. The core provides these menus and SNAC support. BlisSTer also has its own turbo shortcut: hold the desired button and tap START three times to toggle it. See the [Bliss-Box manual](https://bliss-box.com/pages/manual_gpa).

The [Contra build](https://github.com/MiSTer-LLAPI/jtcores/actions/runs/44514130638) passed its controller simulations and all five timing checks. Hardware testing is under way on MiSTer and BlisSTer. The direct-swap result above is from simulation.

## Versions

Current driver source: **v0.5.0**.

See [CHANGELOG.md](CHANGELOG.md) for changes and [VERSIONS.md](VERSIONS.md) for version history. Driver versions are independent of core release numbers. Each core release records its exact driver revision and file hash.

## Features and benefits

- **Compact internal implementation:** bounded counter widths and direct receive-buffer decoding avoid redundant pending button and axis storage.
- **Coherent input updates:** controller type, buttons and all nine analog payload bytes are published together after a complete status reply. Partial replies cannot overwrite part of the previous snapshot.
- **Controller identification and modes:** automatic mode queries refresh information after a controller-type change or an observed reconnection, including reconnection of the same type.
- **Bounded recovery:** receive and transaction timeouts, neutral inputs on detected link loss and a wait-for-release state handle tested communication failures without endless waits or repeated transmissions into a blocked bus.
- **Independent ports:** each driver instance maintains its own communication state and can be reset for rediscovery without resetting another instance or the game.
- **Optional command interface:** atomic requests provide pressure readings, mode queries and rumble commands where supported. Command payloads are kept together; mode writes remain disabled by default. See [TRANSACTIONS.md](TRANSACTIONS.md).
- **Consistent startup:** disabling an instance resets its transaction, synchronization and controller state deterministically.

FPGA resource usage must be measured in each core integration. Lower physical input latency has not been demonstrated. Pressure and rumble require integration and physical testing with the relevant controller and adapter.

## v0.3.0-dev — controller changes and per-port fault history

Each driver instance publishes `TYPE_CHANGED` for one 50 MHz clock alongside
the new complete status report when a valid controller ID replaces a different
valid ID. Initial detection, repeated IDs and reconnection after an observed
loss do not trigger this event. Two controllers reporting the same ID cannot
be distinguished by identity alone. Capture the event in the source clock domain
before transferring it to a different clock.

`LAST_FAULT_REASON[1:0]` retains the most recent reason listed below, including
after successful communication resumes. Sampling `ENABLE=0` clears it to
zero for that port. The existing `FAULT_REASON` still reads zero between fault
events. Each port has independent history.

## v0.2.1-dev — compact fault classification

Adds optional `FAULT_REASON[1:0]`, valid only during `LINK_FAULT`:

| Value | Meaning |
|---|---|
| 0 | No fault event on this cycle |
| 1 | Poll/start/general transaction timeout |
| 2 | Rejected status response (protocol error or complete type-zero status), or a premature reply to a raw command in v0.3.1-dev |
| 3 | Transaction watchdog expired during receive/byte-wait phase |

The code describes the detected condition, not its physical cause. A truncated reply can lead to code 1 or 3 depending on where reception stopped; neither proves unplug. Intentional `ENABLE=0` clears both event and reason. Capture the reason with the fault pulse in `CLK_50M`; use a safe event/mailbox transfer across clock domains.

Two additional RTL register bits; no new timers, counters, receive buffers, opcodes or polling changes. Unused outputs may be optimized away; actual FPGA usage remains a per-core Quartus measurement. Existing complete-packet publication, neutralization and redetection behavior are retained. No reduced-latency or P2 hardware-fix claim.

## New in v0.2.0-dev

Three optional outputs give integrating cores clearer communication information:

| Output | Meaning |
| --- | --- |
| `STATUS_VALID` | Qualifies the last complete controller snapshot using existing link and identity state. |
| `STATUS_UPDATE` | One-cycle event when a complete successful status snapshot is published. |
| `LINK_FAULT` | One-cycle event for a reported status error or transport timeout. |

The update adds two event registers at RTL level and no diagnostic counters. Unused outputs are eligible for removal during synthesis. Polling schedules and wire timings are unchanged. A simulated controller-change/reconnection fixture confirmed cycle-for-cycle equivalence of the existing outputs with v0.1.0.

These signals run in the `CLK_50M` domain. Synchronize levels and capture pulses safely when crossing clock domains. Named-port instantiations can leave the new outputs open; positional instantiations must be updated.

`STATUS_VALID` is snapshot validity, not a physical-presence sensor or a freshness timer. An auxiliary-command timeout can raise `LINK_FAULT` while the controller snapshot remains valid. Do not pause gameplay on an isolated fault pulse.

## Validation

The v0.3.0-dev suite includes direct type changes, per-port fault retention,
cold boot with ENABLE held high, timeout arbitration, a prolonged bus stall,
poll scheduling during auxiliary commands and manual mode invalidation. See
[the v0.3.0 validation record](tests/v0.3.0-validation.json).

For v0.2.1-dev, fault classification and cycle-equivalence tests are added to the existing regression. Results are recorded in `tests/v0.2.1-validation.json`; FPGA fitting and hardware remain pending.

The earlier v0.1.0 regression passed **35 configurations**. Coverage includes complete and truncated status packets, interrupted payloads, mode queries, controller changes, same-type reconnection, receive timing variation and prolonged blocked-bus recovery.

The 1943 development integration passed **12 integration fixtures**, plus a simulated two-port wire test. Its new FPGA build is tracked separately. Simulation does not establish hardware behavior or final FPGA fitting and timing.

The development validation record is available in [tests/v0.2.0-validation.json](tests/v0.2.0-validation.json). The reported physical player-two issue is not fixed by this update.

### Run the tests

Requirements: Python 3 and Icarus Verilog with SystemVerilog support.

```sh
bash tests/run.sh
```

Run from the repository root. The runner uses a temporary build directory and preserves the stored reference source. Tests cover atomic input publication, deterministic reset, all nonempty truncated status/pressure reply lengths, interrupted command frames, errors, mode rediscovery and recovery after blocked lines.

## Driver and core responsibilities

The driver handles polling, complete replies, controller information and communication recovery. The core implements menus, readable controller names, guides, autofire, pause behavior and visual effects.

Loss of communication is not proof of physical unplug: an adapter reset, wiring problem or temporary fault can also cause it. Intentional transport disable, including OSD polling suspension, must not be treated as unplug.

For per-port rediscovery, hold that instance's `ENABLE` low for at least one `CLK_50M` edge, then re-enable normal polling. This resets the driver instance; it is not a physical reset command to the controller or adapter.

The integrating core should neutralize invalid inputs, clear the affected player's autofire, qualify sustained loss after a previously valid connection and preserve the other player's inputs. The core decides when gameplay resumes.

In the Enhanced arcade integration, sustained loss on a previously active port pauses play. A three-second countdown starts once all previously active ports have a valid controller again. Losing a controller during the countdown cancels it.

## SNAC and USB integration

SNAC and LLAPI must not drive the shared interface simultaneously. Release the previous interface before enabling the next and preserve USB input support.

SNAC readers need protocol-specific evidence of connection validity. Do not infer disconnect from no buttons being pressed, and do not present a selected protocol as a detected controller. Where reliable detection is unavailable, retain manual pause. USB disconnect notifications also require an explicitly verified interface from the official Main.

Each core should expose only controller modes with enough buttons and capabilities for the game, including Start, credits and player count. Autofire remains off by default and unavailable where no suitable spare button exists.

## Integration checklist

- Pin the driver version, commit and file hash.
- Test A-only, B-only and both ports with distinct simultaneous inputs.
- Test loss and recovery of either port while preserving the other.
- Test unused ports, brief interruptions, adapter reset, controller changes, OSD suspension and interface changes.
- Keep transport recovery, pause policy and game-specific routing separate.
- Use the official MiSTer Main without requiring modifications.
- Validate FPGA fit, all timing categories and resource usage for each core; validate hardware separately.
- Add optional features only where FPGA capacity and timing permit them.

Existing core releases remain pinned to their own driver source. Updating the driver repository does not update installed core binaries automatically.

## Credits and license

- **Jamie Dickson (Kitrinx):** original MiSTer LLAPI driver. Original copyright notices and the MIT license are preserved.
- **UltimateMiSTer.com (RickDangerous):** Enhanced project development, core integration, regression testing and documentation.
- **Bliss-Box / ulao:** LLAPI protocol documentation and public transport reference.

The driver source is in `rtl/llapi_enhanced.sv`. See [LICENSE](LICENSE). Reference files retain their original notices; core integrations retain their respective licenses and credits.

## Project priorities

Develop a compact, robust LLAPI driver for MiSTer, with reliable controller identification, consistent input updates, independent recovery for each port and optional interfaces for pressure and rumble. Prioritize efficient FPGA resource usage, thorough testing and clear versioned documentation.

## Change-recording policy

Every driver change is recorded in this GitHub repository with source, regression tests, a version identifier, changelog and validation limits. Descriptions highlight new functionality and demonstrated benefits. Development versions, tagged releases and hardware validation remain clearly distinguished.

Enhanced arcade launchers use `_LLAPI Enhanced/_Arcade` with names such as `1943-LLAPI-SNAC`; binaries are stored under `_LLAPI Enhanced/cores`.
