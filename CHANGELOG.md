# BlisSTer LLAPI Enhanced changelog

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


## v0.2.0-dev — connection telemetry (unreleased)

- Added `STATUS_VALID`: combinational qualification of the existing complete snapshot and link state; no extra validity storage. This is not a physical-presence detector.
- Added single-cycle `STATUS_UPDATE` on complete successful status publication, and `LINK_FAULT` on status errors or transport timeout. Auxiliary-command timeouts may raise LINK_FAULT while STATUS_VALID remains high; cores must not pause on an isolated fault pulse.
- Intentional ENABLE=0 clears telemetry without reporting unplug. Existing per-instance disable/reset remains the supported rediscovery mechanism; no new firmware command or board-reset control was invented.
- Existing atomic snapshots, same-type reconnection mode refresh, timeout neutralization and per-instance recovery retained. No polling schedule or wire timing changes.
- Two event registers added in RTL; unused outputs are eligible for synthesis pruning. No Quartus area or latency improvement claimed. Diagnostic counters deliberately omitted.
- Named-port integrations can leave new outputs open. Positional instantiations must be updated. Telemetry is in CLK_50M; cross-domain consumers must synchronize levels and capture pulses safely.
- 1943 development candidate uses the new source; published cores remain unchanged. P2 hardware issue is not fixed by this change.

The complete version-by-version differences, checksums, compatibility notes and every original commit are recorded in [VERSIONS.md](VERSIONS.md).

## v0.1.0 — 2026-11-02

- Reduced counter widths and redundant snapshot storage, preserving saturation and atomic public outputs.
- Published expanded fault, payload, controller-mode and timing tests; 35 configurations passed in one complete run.
- Optional update for existing integrations; target-core fitting/timing and hardware validation still required. PSX Single RAM remains above capacity. No 1944 P2 fix is claimed.
- Exact snapshot: `5dbb70afa5edea264eb146c5977db53754b869b0`.

## Historical source milestones

Tags below are assigned retrospectively on 2026-11-02. Original code history and v0.1.0 remain unchanged.

- **v0.1.0-alpha.4** (2026-11-01 snapshot): inter-byte receive synchronization fix; no transmit/protocol change.
- **v0.1.0-alpha.3** (2026-10-31 snapshot): automatic modes, optional atomic commands, transport errors and bounded recovery.
- **v0.1.0-alpha.2** (2026-10-31 snapshot): receive-start watchdog and wait-for-release recovery.
- **v0.1.0-alpha.1** (2026-10-31 snapshot): deterministic reset and coherent controller snapshots with original reference/tests.

## Documentation update — 2026-11-02

- Added complete historical version and commit ledger, source comparisons, validation boundaries and future versioning policy.
- Replaced stale local/unpublished follow-up descriptions with version-scoped records. No RTL or test change in this documentation update.
- Driver MIT license and original credits preserved; core integrations retain their own licenses.
