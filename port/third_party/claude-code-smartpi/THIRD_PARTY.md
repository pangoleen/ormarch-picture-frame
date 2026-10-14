# Claude Code ARMv7 compatibility layer

This directory is a pinned copy of the runtime files from
[`Yumi-Lab/claude-code-smartpi`](https://github.com/Yumi-Lab/claude-code-smartpi)
commit `a9cac19982b922745c1ba33a4a3fe9ea2a94719b` (2026-10-13), licensed under
the included MIT license.

`install.sh` has only been adapted from Debian's `apt` package names to Arch
Linux ARM's `pacman` names. It obtains the Claude Code source payload from
Anthropic's HTTPS release endpoint at installation time; it does not ship a
Claude binary. This remains an unsupported compatibility layer, so it pins
Claude Code to the upstream release in `MAX_VERSION` until it is tested on the
PF1007L.
