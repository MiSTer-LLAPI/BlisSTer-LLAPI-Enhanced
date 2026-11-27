#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# Icarus rejects the upstream trailing concatenation comma accepted by Quartus.
# Normalize syntax in the temporary simulation copy only; preserve pinned source.
python3 - "$build/legacy.sv" <<'PYCODE'
from pathlib import Path
import sys
s=Path('reference/SNES_MiSTer-a922e326-llapi.sv').read_text()
assert s.count(", //R")==1
s=s.replace(", //R", " //R")
s=s.replace("output        IO_LATCH_OUT", "output reg    IO_LATCH_OUT").replace("output        IO_DATA_OUT", "output reg    IO_DATA_OUT")
s=s.replace("state <= (read_byte >= read_length) ? STATE_READ_END : STATE_READ;", "if (read_byte >= read_length) state <= STATE_READ_END; else state <= STATE_READ;")
Path(sys.argv[1]).write_text(s)
PYCODE
iverilog -g2012 -s legacy_wire_tb -o "$build/legacy" "$build/legacy.sv" tests/legacy_wire_tb.sv
vvp "$build/legacy"

# Exercise every nonempty truncated status-packet length, followed by recovery.
for truncated_bytes in 1 2 3 4 5 6 7 8 9 10 11 12; do
  iverilog -g2012 -s enhanced_reset_tb -Penhanced_reset_tb.TRUNCATE_BYTES="$truncated_bytes" -o "$build/enhanced" rtl/llapi_enhanced.sv tests/enhanced_reset_tb.sv
  vvp "$build/enhanced"
done

# Interrupt a bit before, near, and after the receiver's sampling window.
for abort_ticks in 50 160 165 170 220; do
  iverilog -g2012 -s enhanced_reset_tb -Penhanced_reset_tb.ABORT_TICKS="$abort_ticks" -o "$build/enhanced" rtl/llapi_enhanced.sv tests/enhanced_reset_tb.sv
  vvp "$build/enhanced"
done

iverilog -g2012 -s stuck_leadin_tb -o "$build/stuck" rtl/llapi_enhanced.sv tests/stuck_leadin_tb.sv
vvp "$build/stuck"

# Exercise default automatic modes, unsupported replies and silent adapters.
for modes in 128 241 254 255 -1; do
  iverilog -g2012 -s features_tb -Pfeatures_tb.MODE_REPLY="$modes" -o "$build/features" rtl/llapi_enhanced.sv tests/features_tb.sv
  vvp "$build/features"
done

iverilog -g2012 -s features_tb -Pfeatures_tb.MODE_WRITES=0 -o "$build/features" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/features"

# A slow controller poll must not be mistaken for a stuck receive lead-in.
iverilog -g2012 -s features_tb -Pfeatures_tb.POLL_BUSY_TICKS=100000 -o "$build/features" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/features"

# All incomplete pressure payload lengths, each followed by a complete reply.
iverilog -g2012 -s features_tb -Pfeatures_tb.PRESSURE_FAULTS=1 -o "$build/pressure-faults" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/pressure-faults"

# Block the adapter between rumble parameter frames; explicitly reset its parser for recovery.
iverilog -g2012 -s features_tb -Pfeatures_tb.PAYLOAD_FAULTS=1 -o "$build/payload-faults" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/payload-faults"

# Disable during each outgoing rumble parameter frame at three bit positions.
iverilog -g2012 -s features_tb -Pfeatures_tb.RESET_PAYLOAD=1 -o "$build/payload-resets" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/payload-resets"

# Modes must be invalidated and rediscovered on controller changes/reconnection.
iverilog -g2012 -s features_tb -Pfeatures_tb.TYPE_RECONNECT=1 -o "$build/type-reconnect" rtl/llapi_enhanced.sv tests/features_tb.sv
vvp "$build/type-reconnect"

# Timing variations are engineering probes, not a vendor tolerance guarantee.
for delta in -2 2; do
  for patterns in 0 1; do
    iverilog -g2012 -s features_tb -Pfeatures_tb.RX_DELTA="$delta" -Pfeatures_tb.PATTERN_SWEEP="$patterns" -o "$build/rx" rtl/llapi_enhanced.sv tests/features_tb.sv
    vvp "$build/rx"
  done
done

# Keep the bus quarantined beyond the old 21-bit timer range, then recover.
iverilog -g2012 -s long_wait_tb -o "$build/long-wait" rtl/llapi_enhanced.sv tests/long_wait_tb.sv
vvp "$build/long-wait"

# Classify faults at each source and clear the reason on intentional disable.
iverilog -g2012 -s fault_reason_tb -o "$build/fault-reason" rtl/llapi_enhanced.sv tests/fault_reason_tb.sv
vvp "$build/fault-reason"
# Existing public outputs must stay identical across same-type reconnect.
iverilog -g2012 -s features_tb -Pfeatures_tb.TYPE_RECONNECT=1 -o "$build/equivalence" rtl/llapi_enhanced.sv tests/baseline_v020.sv tests/equivalence_v021_tb.sv
vvp "$build/equivalence"

# Cold power-up and reviewed transaction, recovery and identity boundaries.
for fixture in cold_start_tb watchdog_boundary_tb poll_overlap_tb manual_modes_swap_tb; do
    iverilog -g2012 -s "$fixture" -o "$build/$fixture" rtl/llapi_enhanced.sv "tests/$fixture.sv"
    vvp "$build/$fixture"
done
iverilog -g2012 -s poll_overlap_tb -Ppoll_overlap_tb.AUTO_MODES=0 -o "$build/manual-poll" rtl/llapi_enhanced.sv tests/poll_overlap_tb.sv
vvp "$build/manual-poll"

# Decode extension transactions at the simulated adapter pins.
iverilog -g2012 -s raw_commands_tb -o "$build/raw" rtl/llapi_enhanced.sv tests/raw_commands_tb.sv
vvp "$build/raw"
iverilog -g2012 -s raw_commands_tb -Praw_commands_tb.RAW_COMMANDS=0 -o "$build/raw-off" rtl/llapi_enhanced.sv tests/raw_commands_tb.sv
vvp "$build/raw-off"

iverilog -g2012 -s immediate_repoll_tb -o "$build/repoll" rtl/llapi_enhanced.sv tests/immediate_repoll_tb.sv
vvp "$build/repoll"
for mode in AUX BLOCKED; do
    iverilog -g2012 -s immediate_repoll_tb -P"immediate_repoll_tb.$mode=1" -o "$build/repoll" rtl/llapi_enhanced.sv tests/immediate_repoll_tb.sv
    vvp "$build/repoll"
done

for extended in 0 1; do
    for noise in 0 1; do
        iverilog -g2012 -s receive_start_tb -Preceive_start_tb.EXPECT_FIX=1 -Preceive_start_tb.EXTENDED_ACK="$extended" -Preceive_start_tb.CHECK_NOISE="$noise" -o "$build/start" rtl/llapi_enhanced.sv tests/receive_start_tb.sv
        vvp -N "$build/start"
    done
done
for command_case in 0 1 2 3; do
    for early in 0 1; do
        iverilog -g2012 -s commands_tb -Pcommands_tb.CASE="$command_case" -Pcommands_tb.EARLY="$early" -o "$build/commands" rtl/llapi_enhanced.sv tests/commands_tb.sv
        vvp -N "$build/commands"
    done
done
