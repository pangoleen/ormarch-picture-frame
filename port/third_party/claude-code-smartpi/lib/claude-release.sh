# shellcheck shell=sh
# claude-release.sh — single source of truth for "where Claude Code comes from and which
# version this board runs". POSIX sh.
#
# Sourced by install.sh (at install time) and by claude-check-update (installed as
# /opt/claude-code/lib/claude-code/claude-release.sh, next to VERSION), so the installer and
# the update probe always agree on "latest".

CLAUDE_REL="https://downloads.claude.ai/claude-code-releases"
CLAUDE_MAX_URL="https://raw.githubusercontent.com/Yumi-Lab/claude-code-smartpi/main/MAX_VERSION"

# ponytail: "latest" is capped at MAX_VERSION (repo root), the newest release verified to run
# under Node. Since 2.1.271 the TUI renderer instantiates Bun.ant.CellSegmenter, a native cell
# engine that only Anthropic's internal Bun build has: under Node the interactive screen stays
# blank. Lifting the cap needs a JS port of that engine; until then, bump MAX_VERSION after
# verifying a newer release on a pad. Read from GitHub at every check, so a bump reaches every
# pad without reinstalling anything.

# First line of a URL, whitespace stripped; empty on failure.
claude_fetch_line() { curl -fsSL --max-time 15 "$1" 2>/dev/null | head -1 | tr -d '[:space:]'; }

# Newest version this board should run: min(newest release, MAX_VERSION). Empty when either
# is unknown or malformed (offline, GitHub or Anthropic unreachable).
claude_latest_version() {
  _new="$(claude_fetch_line "$CLAUDE_REL/latest")"
  _max="$(claude_fetch_line "$CLAUDE_MAX_URL")"
  case "$_new$_max" in *[!0-9.]*) return 0 ;; esac
  if [ -n "$_new" ] && [ -n "$_max" ]; then printf '%s\n%s\n' "$_new" "$_max" | sort -V | head -1; fi
}
