# Driver version history

Historical tags alpha.1–alpha.4 are assigned retrospectively on 2026-11-02 to actual immutable commit snapshots. They were not numbered releases on their original development dates. v0.1.0 was already published and is preserved unchanged. All are experimental source releases, not core/RBF releases.

## Version index

| Version | Snapshot commit | Main difference |
|---|---|---|
| [v0.1.0-alpha.1](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0-alpha.1) | [`d860edd`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/d860edd168afb3710f4fcce6e5df715577f50a19) | Initial Enhanced foundation |
| [v0.1.0-alpha.2](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0-alpha.2) | [`1f7cb74`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/1f7cb74736be0289986d5b14543a0fff25cd2ade) | Receive-start watchdog |
| [v0.1.0-alpha.3](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0-alpha.3) | [`db10d18`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/db10d187f92cb687ff20b8996de65d2cccfb8320) | Modes, optional commands and error handling |
| [v0.1.0-alpha.4](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0-alpha.4) | [`b397dc6`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/b397dc6512422eeadc2f6cee6455c15ecd36f7bf) | Inter-byte RX synchronization |
| [v0.1.0](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0) | [`5dbb70a`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/5dbb70afa5edea264eb146c5977db53754b869b0) | Counter and snapshot storage optimization |

## v0.1.0-alpha.1 — Initial Enhanced foundation

Snapshot: `d860edd168afb3710f4fcce6e5df715577f50a19`. Driver SHA-256: `d786b655dcc46ad7fb9f4f1287ae271fa68d171144b0e088ed711ced82ba2b5f`.

**Changes:** Deterministic reset when disabled; controller type, buttons and nine analog bytes published together after a complete packet. Original MIT reference retained with isolated legacy/Enhanced wire tests.

**Difference from predecessor:** Introduces LLAPI_Enhanced; earlier legacy counter initialization assumptions are removed. Incomplete reads cannot partially overwrite the public snapshot.

**Validation and limits:** Two original protocol simulations passed. No Quartus or physical hardware acceptance for this historical snapshot.

**Core impact:** Historical only. Later releases add watchdog, command and RX fixes.

## v0.1.0-alpha.2 — Receive-start watchdog

Snapshot: `1f7cb74736be0289986d5b14543a0fff25cd2ade`. Driver SHA-256: `7851a9ac881213d729dd8122ed36df4026155192e3d34990bae3ccf645256edc`.

**Changes:** Adds a bounded receive-start timeout, neutral controller state, released outputs and STATE_WAIT_RELEASE. Polling resumes only after both inputs remain released for the settling interval. Adds truncation, mid-bit interruption and stuck-line tests.

**Difference from predecessor:** An adapter holding latch/data low could previously leave READ_START indefinitely. The new engineering timeout is 1 ms at 50 MHz; it is not a vendor guarantee.

**Validation and limits:** 19 regression executions recorded as passed, including release glitches and one-line-only release. No Quartus/hardware acceptance.

**Core impact:** Recommended robustness correction for users of alpha.1; use the current release after per-core validation.

[Exact source comparison](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/compare/d860edd168afb3710f4fcce6e5df715577f50a19...1f7cb74736be0289986d5b14543a0fff25cd2ade).

## v0.1.0-alpha.3 — Modes, optional commands and error handling

Snapshot: `db10d187f92cb687ff20b8996de65d2cccfb8320`. Driver SHA-256: `8a98f7d3f7a44f7539461f76f10016841346d89b47bfb448e8109434191f2917`.

**Changes:** Automatic GET_MODES per connection/type, explicit validity and fallback; opt-in atomic pressure/mode/rumble request interface; parameter capture and frame ordering; bounded transactions, receive bounds, abort priority and polling arithmetic guards.

**Difference from predecessor:** Adds command ports and AUTO_MODES behavior. COMMAND_INTERFACE and ALLOW_MODE_WRITES default off. Command completion does not establish device acknowledgement or motor action.

**Validation and limits:** 26 configurations recorded as passed for modes, errors, pressure, commands, timeouts, reset and busy polling. No Quartus/hardware acceptance at this snapshot.

**Core impact:** Integration must connect optional command ports correctly. No firmware protocol change; test the target core.

[Exact source comparison](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/compare/1f7cb74736be0289986d5b14543a0fff25cd2ade...db10d187f92cb687ff20b8996de65d2cccfb8320).

## v0.1.0-alpha.4 — Inter-byte RX synchronization

Snapshot: `b397dc6512422eeadc2f6cee6455c15ecd36f7bf`. Driver SHA-256: `33d7e93c887f5c52e3fbd65dba1ea6a1592e1c10b52babb17f1aa6a73a1f324b`.

**Changes:** Extends the inter-byte fallback wait and excludes early final-data-bit edges so real synchronization edges realign each received byte. README clarifications and original-author comparison accompany this snapshot.

**Difference from predecessor:** Fixes cumulative alignment failure reproduced with simulated 228-clock bits instead of 224. No transmit timing, opcodes or firmware change.

**Validation and limits:** 30 regression configurations plus four timing/payload probes passed in separate runs. The expanded companion tests were local then and only published later in 6ce336a; they are not all present in this historical tag. Earlier 1944 Enhanced and 1943 baseline core builds subsequently passed timing with this driver content; this is not universal hardware acceptance.

**Core impact:** Recommended for earlier Enhanced RX revisions after per-core validation. This is the driver content used by 1944 Enhanced v0.2.0 and the verified 1943 baseline.

[Exact source comparison](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/compare/db10d187f92cb687ff20b8996de65d2cccfb8320...b397dc6512422eeadc2f6cee6455c15ecd36f7bf).

## v0.1.0 — Counter and snapshot storage optimization

Snapshot: `5dbb70afa5edea264eb146c5977db53754b869b0`. Driver SHA-256: `b3b58462294dc4c282f4ef6ee9d53c8952a7c58ab1f095daf6a86ce152ff65dd`.

**Changes:** Serial count narrowed to its reachable range; transaction timer width derived from timeout limits and kept saturating; pending button/axis values decoded directly from the receive buffer without redundant registers. Public packet-complete commit retained. Expanded fault/timing tests and prolonged WAIT_RELEASE test published.

**Difference from predecessor:** No public API, protocol or default-setting changes relative to alpha.4. No wraparound during extended quarantine. Core menus, autofire, SNAC routing and pause effects are outside this driver.

**Validation and limits:** 35 configurations passed in one complete runner execution. Twelve public files matched local tested bytes. Earlier four PSX integration fixtures passed; PSX Single RAM still failed fit at 4197/4191 LABs, so no accepted Enhanced RBF/final timing. Physical recovery, pressure and motor behavior pending.

**Core impact:** Optional maintenance optimization for existing integrations. PSX candidate already contains it; 1943/1944 need separate builds/tests. Not a demonstrated fix for reported 1944 P2 failure.

[Exact source comparison](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/compare/b397dc6512422eeadc2f6cee6455c15ecd36f7bf...5dbb70afa5edea264eb146c5977db53754b869b0).

## Complete commit ledger

Every original commit through v0.1.0 is listed below, including documentation-only edits. Commits within one source version do not pretend to be additional RTL changes. Current historical documentation supersedes stale “local/pending” statements in old snapshots; the snapshots themselves are not rewritten.

| UTC date | Commit | Category | Changes |
|---|---|---|---|
| 2026-10-31 15:42:20 | [`11c1eff`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/11c1eff50558286a7b55010f0d9937544748f740) | documentation/license | Initial commit |
| 2026-10-31 15:43:16 | [`16ba382`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/16ba3822af89d4191b67c1daef735f54c0433243) | documentation/license | Document experimental BlisSTer LLAPI Enhanced and preserve MIT credits |
| 2026-10-31 15:43:33 | [`6e4471c`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/6e4471c3aaf6dcd7df9a6ffbebba4f5d0585a566) | driver RTL | Add experimental driver with deterministic reset and coherent snapshots |
| 2026-10-31 15:43:52 | [`8356f7c`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/8356f7c37c68c2c20b66cb1c400f13b12ef253c1) | tests | Add legacy and Enhanced wire regression tests |
| 2026-10-31 15:44:11 | [`5be51e4`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/5be51e42995774d4533b6cb4e1bb36485689caf8) | reference | Preserve original MIT LLAPI reference for reproducible regression tests |
| 2026-10-31 15:58:09 | [`d860edd`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/d860edd168afb3710f4fcce6e5df715577f50a19) | documentation/license | Translate project documentation into English |
| 2026-10-31 17:31:52 | [`7b2aa5d`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/7b2aa5dbf723acd601496279544e6f3ada006004) | driver RTL | Bound receive-start waits and recover after line release |
| 2026-10-31 17:34:15 | [`c99b8a8`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/c99b8a81847bfca0a0b112ff266faac9562904cf) | tests | Test truncated replies, bit interruptions and stuck lead-in recovery |
| 2026-10-31 17:34:59 | [`1f7cb74`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/1f7cb74736be0289986d5b14543a0fff25cd2ade) | documentation/license | Document recovery tests and validation limits |
| 2026-10-31 17:49:23 | [`e6f7744`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/e6f7744d7e6e3d05036ee6a09f60ea6f74f4c4fb) | driver RTL | Connect modes and atomic commands; harden recovery |
| 2026-10-31 17:49:57 | [`2be7398`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/2be7398cffa8f14049092010cf07ff1b9f274a12) | tests | Cover modes, pressure, rumble and recovery on wire |
| 2026-10-31 17:50:50 | [`db10d18`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/db10d187f92cb687ff20b8996de65d2cccfb8320) | documentation/license | Document command integration and validation limits |
| 2026-11-01 11:40:23 | [`a318d7e`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/a318d7ea34d9c618c6780effc04d2faffd75015f) | driver RTL | Fix inter-byte receive synchronization with slower modeled replies |
| 2026-11-01 12:12:40 | [`4b7b810`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/4b7b81050b4123e40fadd43201ff004a66a67f5b) | documentation/license | Explain Enhanced improvements, validation limits and project credits |
| 2026-11-01 12:13:22 | [`c671b55`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/c671b559f6b733f3c6cfb4770d566afd016813fc) | documentation/license | Align next steps with Enhanced and 1942 SNAC priority |
| 2026-11-01 12:16:55 | [`1df3b5c`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/1df3b5cc6a3feeb2b5df0e698f871f96856eb831) | documentation/license | Remove Gamer-Pro Advanced FAQ from README |
| 2026-11-01 12:18:20 | [`dbf58d3`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/dbf58d3c5484abe0bfc3842dbb9ec7d7ba3a8e33) | documentation/license | Remove Next steps section from README |
| 2026-11-01 12:20:03 | [`26d3811`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/26d381114ab9da647e39d07d4209bdf4e9227aaa) | documentation/license | Document Kitrinx foundation and Enhanced improvements in plain English |
| 2026-11-01 12:21:21 | [`b397dc6`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/b397dc6512422eeadc2f6cee6455c15ecd36f7bf) | documentation/license | Shorten improvements heading |
| 2026-11-02 10:12:44 | [`6ce336a`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/6ce336ad6592c5a3adc2410dbe3f9d22fc9e3cb3) | tests | Expand fault, timing and prolonged stuck-bus regression coverage |
| 2026-11-02 10:13:42 | [`92bae36`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/92bae36391d2418887d170a75c6c19bef11fdcbe) | driver RTL | Reduce redundant snapshot storage and bound counters |
| 2026-11-02 10:14:48 | [`5dbb70a`](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/commit/5dbb70afa5edea264eb146c5977db53754b869b0) | documentation/license | Document storage updates and per-core validation requirements |

## Version policy

- Preserve existing release/tag targets; never overwrite older versions. Historical alpha labels are a one-time backfill, not the naming scheme for new work.
- Future driver fixes and compatible optimizations increment the patch (next code update: v0.1.1); added functionality increments the minor. Breaking interface changes require explicit migration notes and a new minor during v0.x development.
- Tests/documentation-only commits are recorded as such and do not imply a new driver binary. Bundle them with the corresponding source release or label a documentation-only release explicitly.
- Each update records its exact commit, driver SHA-256, changes from the preceding version, test evidence and limits, and whether each consuming core needs a required or optional update.
- Each core pins a driver revision; its RBF has independent provenance, fitting, five timing-category checks and hardware status. Source publication does not silently replace core binaries.
- Preserve Kitrinx/Jamie Dickson attribution and the MIT driver license. Jotego cores retain GPL and all applicable dependency notices. No licensing relabeling.


## v0.2.0-dev (unreleased candidate)

Adds optional snapshot validity/publication/fault telemetry. No new transport commands or timing changes. Based on v0.1.0; no release commit or tag assigned until validation/publication. See CHANGELOG.md and README.md for semantics and integration boundaries.
