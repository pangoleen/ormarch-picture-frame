#!/usr/bin/env python3
"""Apply the two architecture-specific Omarchy source patches.

The upstream source treats every non-aarch64 machine as x86 and routes agent
installs through mise. Neither assumption holds on this 32-bit ARM frame.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "bin/omarchy-hw-platform"
original = path.read_text()
before = '''    if [[ $machine == "aarch64" ]]; then
      echo aarch64
    else
      echo x86
    fi'''
after = '''    if [[ $machine == "aarch64" ]]; then
      echo aarch64
    elif [[ $machine == "armv7l" ]]; then
      echo armv7
    else
      echo x86
    fi'''
if after not in original:
    if original.count(before) != 1:
        raise SystemExit("Platform detector changed upstream; review it before patching")
    backup = path.with_name(path.name + ".before-frame-port")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text(original.replace(before, after))

agent_path = pathlib.Path(sys.argv[1]) / "bin/omarchy-default-agent"
agent_original = agent_path.read_text()
agent_before = 'agent_package=${agent_package:-$agent}'
agent_after = '''if [[ $agent == "claude" && $(uname -m) == "armv7l" ]]; then
  echo "Claude Code has no native Linux armv7 build, so it cannot run on this frame." >&2
  echo "Use an ARMv7-compatible agent or run Claude Code on another machine." >&2
  exit 1
fi

agent_package=${agent_package:-$agent}'''
if agent_after not in agent_original:
    if agent_original.count(agent_before) != 1:
        raise SystemExit("Default-agent launcher changed upstream; review it before patching")
    backup = agent_path.with_name(agent_path.name + ".before-frame-port")
    if not backup.exists():
        backup.write_bytes(agent_path.read_bytes())
    agent_path.write_text(agent_original.replace(agent_before, agent_after))
