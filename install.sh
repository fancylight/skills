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
# Do NOT overlay flow/templates/codex/ (Codex-only overrides).
echo "Installing templates..."
copy "$SCRIPT_DIR/flow/templates" "$TARGET_DIR/commands/flow/templates"
# Remove Codex-only overrides if the full templates tree was copied
if $DRY_RUN; then
  echo "  [dry-run] rm -rf $TARGET_DIR/commands/flow/templates/codex"
else
  rm -rf "$TARGET_DIR/commands/flow/templates/codex"
fi

# Shared host-agnostic scripts (validators + test controller)
echo "Installing shared scripts..."
if $DRY_RUN; then
  echo "  [dry-run] cp flow/scripts/*.ps1 -> $TARGET_DIR/commands/flow/scripts/"
else
  mkdir -p "$TARGET_DIR/commands/flow/scripts"
  cp -f "$SCRIPT_DIR"/flow/scripts/*.ps1 "$TARGET_DIR/commands/flow/scripts/" 2>/dev/null || true
  # Refuse to install shim files if any leaked
  for f in "$TARGET_DIR/commands/flow/scripts"/*.ps1; do
    [ -f "$f" ] || continue
    if head -n 3 "$f" | grep -qE '^# Shim'; then
      echo "Refusing to install shim as runtime script: $f" >&2
      exit 1
    fi
  done
fi

# Control-plane + schema docs (protocol SoT for agents)
echo "Installing flow docs..."
if $DRY_RUN; then
  echo "  [dry-run] cp flow/docs/*.md -> $TARGET_DIR/commands/flow/docs/"
else
  mkdir -p "$TARGET_DIR/commands/flow/docs"
  cp -f "$SCRIPT_DIR"/flow/docs/*.md "$TARGET_DIR/commands/flow/docs/"
fi

# system-test harness template tree (integration test scaffold)
echo "Installing system-test templates..."
if [ -d "$SCRIPT_DIR/flow/templates/system-test" ]; then
  if $DRY_RUN; then
    echo "  [dry-run] cp flow/templates/system-test -> $TARGET_DIR/commands/flow/templates/system-test"
  else
    mkdir -p "$TARGET_DIR/commands/flow/templates/system-test"
    cp -r "$SCRIPT_DIR/flow/templates/system-test"/. "$TARGET_DIR/commands/flow/templates/system-test"/
  fi
fi

echo ""
if $DRY_RUN; then
  echo "Dry-run complete. Re-run without --dry-run to apply."
else
  echo "Done. Restart Claude Code (or run /reload-plugins) to activate."
  echo "Then type /flow: to see available commands."
fi
