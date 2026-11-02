# BlisSTer LLAPI Enhanced

A compact, robust LLAPI driver for MiSTer, with coherent controller readings, bounded communication recovery and optional interfaces for pressure and rumble. The project supports integrations using two independent LLAPI ports and the official MiSTer Main.

## Versions

Current development source: **v0.2.1-dev**. Latest tagged release: [v0.1.0](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0).

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

## v0.2.1-dev — compact fault classification

Adds optional `FAULT_REASON[1:0]`, valid only during `LINK_FAULT`:

| Value | Meaning |
|---|---|
| 0 | No fault event on this cycle |
| 1 | Poll/start/general transaction timeout |
| 2 | Rejected status response (protocol error or complete type-zero status) |
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

For v0.2.1-dev, fault classification and cycle-equivalence tests are added to the existing regression. Results are recorded in `tests/v0.2.1-validation.json`; FPGA fitting and hardware remain pending.

The complete driver regression passed **35 configurations**. Coverage includes complete and truncated status packets, interrupted payloads, mode queries, controller changes, same-type reconnection, receive timing variation and prolonged blocked-bus recovery.

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

The integrating core should neutralize invalid inputs and clear latched autofire, qualify sustained loss after a previously valid connection, preserve the other player's inputs and require explicit confirmation before resuming after a disconnect pause.

The proposed 1943 pause policy waits for **2000 consecutive millisecond loss ticks**. Brief recovery cancels the pending pause; reconnection after a pause does not resume automatically. The 1943 development integration has passed simulated loss, reconnection and explicit-resume tests. Its release and physical validation are tracked separately from the driver.

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
- **UltimateMiSTer.com — RickDangerous:** Enhanced project development, core integration, regression testing and documentation.
- **Bliss-Box / ulao:** LLAPI protocol documentation and public transport reference.

The driver source is in `rtl/llapi_enhanced.sv`. See [LICENSE](LICENSE). Reference files retain their original notices; core integrations retain their respective licenses and credits.

## Project priorities

Develop a compact, robust LLAPI driver for MiSTer, with reliable controller identification, consistent input updates, independent recovery for each port and optional interfaces for pressure and rumble. Prioritize efficient FPGA resource usage, thorough testing and clear versioned documentation.

## Change-recording policy

Every driver change is recorded in this GitHub repository with source, regression tests, a version identifier, changelog and validation limits. Descriptions highlight new functionality and demonstrated benefits. Development versions, tagged releases and hardware validation remain clearly distinguished.

Enhanced arcade launchers use `_LLAPI Enhanced/_Arcade` with names such as `1943-LLAPI-SNAC`; binaries are stored under `_LLAPI Enhanced/cores`.
