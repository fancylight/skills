#!/usr/bin/env bash
# Flow Skill installer
# Usage:
#   ./install.sh           — install to user-level (~/.claude)
#   ./install.sh --project — install to current project (./.claude)
#   ./install.sh --dry-run — preview what would be copied

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
TARGET_DIR="$HOME/.claude"

for arg in "$@"; do
  case "$arg" in
    --project) TARGET_DIR="$(pwd)/.claude" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: $0 [--project] [--dry-run]"
      echo "  (no flag)   install to ~/.claude (user-level, all projects)"
      echo "  --project   install to ./.claude (current project only)"
      echo "  --dry-run   preview without copying"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

copy() {
  local src="$1" dst="$2"
  if $DRY_RUN; then
    echo "  [dry-run] cp -r $src -> $dst"
  else
    mkdir -p "$dst"
    # Trailing slash on src = copy contents INTO dst (idempotent)
    # Without slash, repeated runs create nested directories
    cp -r "$src"/. "$dst"/
  fi
}

echo "Flow Skill installer"
echo "Target: $TARGET_DIR"
$DRY_RUN && echo "(dry-run mode — no files will be written)"
echo ""

# Commands
echo "Installing commands..."
copy "$SCRIPT_DIR/.claude/commands/flow" "$TARGET_DIR/commands/flow"

# Skills
echo "Installing skills..."
for skill_dir in "$SCRIPT_DIR"/.claude/skills/flow-*/; do
  skill_name="$(basename "$skill_dir")"
  copy "$skill_dir" "$TARGET_DIR/skills/$skill_name"
done

# Templates — placed alongside commands so agent can find them at commands/flow/templates/
echo "Installing templates..."
copy "$SCRIPT_DIR/flow/templates" "$TARGET_DIR/commands/flow/templates"

echo ""
if $DRY_RUN; then
  echo "Dry-run complete. Re-run without --dry-run to apply."
else
  echo "Done. Restart Claude Code (or run /reload-plugins) to activate."
  echo "Then type /flow: to see available commands."
fi
