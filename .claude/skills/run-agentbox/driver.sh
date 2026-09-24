#!/bin/bash
# AgentBox run driver. Builds, launches, and drives the AgentBoxMenuBar app
# through the macOS accessibility API so an agent can observe real UI state.
#
# Usage: .claude/skills/_candidates/run-agentbox/driver.sh <command> [args]
set -uo pipefail

APP_NAME="AgentBoxMenuBar"
WORKSPACE="AgentBox.xcworkspace"
SHOT_DIR="${AGENTBOX_SHOT_DIR:-${TMPDIR:-/tmp}/agentbox-run}"

die() { echo "driver: $*" >&2; exit 1; }

app_path() {
  local path
  path=$(xcodebuild -workspace "$WORKSPACE" -scheme "$APP_NAME" \
    -configuration Debug -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR = /{d=$3} / FULL_PRODUCT_NAME = /{n=$3} END{print d"/"n}')
  [ -d "$path" ] || die "app not built at '$path'; run: driver.sh build"
  echo "$path"
}

# Runs one AppleScript against the app process. Prints stdout, keeps stderr.
ax() { osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to $1"; }

cmd_build() {
  tuist generate --no-open --cache-profile none >/dev/null 2>&1 \
    || tuist generate --no-open --no-binary-cache >/dev/null 2>&1 \
    || die "tuist generate failed"
  xcodebuild -workspace "$WORKSPACE" -scheme "$APP_NAME" -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.0 2>&1 \
    | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)' | tail -5
}

cmd_launch() {
  cmd_quit >/dev/null 2>&1
  open "$(app_path)" || die "open failed"
  for _ in $(seq 1 20); do
    pgrep -qf "$APP_NAME" && { sleep 1; echo "launched: $(pgrep -f "$APP_NAME" | head -1)"; return 0; }
    sleep 0.5
  done
  die "app did not start"
}

cmd_quit() { pkill -f "$APP_NAME" && echo "stopped" || echo "not running"; }

# Prints the status-bar item as: name, x, y, width, height (points).
cmd_status_item() { ax 'get {name, position, size} of every menu bar item of menu bar 2'; }

# Opens the status-bar menu. Required before `menu-items` or `click`.
cmd_menu() { ax 'click menu bar item 1 of menu bar 2' >/dev/null 2>&1; sleep 0.6; cmd_menu_items; }

cmd_menu_items() { ax 'get name of every menu item of menu 1 of menu bar item 1 of menu bar 2'; }

# Clicks one status-bar menu item by title. Opens the menu first.
cmd_click() {
  local item="${1:?usage: driver.sh click <menu item title>}"
  ax 'click menu bar item 1 of menu bar 2' >/dev/null 2>&1
  sleep 0.6
  ax "click menu item \"$item\" of menu 1 of menu bar item 1 of menu bar 2" >/dev/null 2>&1
  sleep 1
  echo "clicked: $item"
}

# Prints every app window as: name, x, y, width, height (points).
cmd_windows() { ax 'get {name, position, size} of every window'; }

cmd_front() { ax 'set frontmost of true' >/dev/null 2>&1 || osascript -e "tell application \"System Events\" to set frontmost of process \"$APP_NAME\" to true"; sleep 0.8; echo "frontmost"; }

# Screenshots window 1 with a 10-point margin. Screenshots are 2x the point size.
cmd_shot_window() {
  local label="${1:-window}"
  mkdir -p "$SHOT_DIR"
  osascript -e "tell application \"System Events\" to set frontmost of process \"$APP_NAME\" to true" >/dev/null 2>&1
  sleep 0.8
  local geometry
  geometry=$(ax 'get {position, size} of window 1' 2>/dev/null) || die "no window; run: driver.sh click 'Open Details'"
  local x y w h
  IFS=', ' read -r x y w h <<< "$(echo "$geometry" | tr -d ' ')"
  [ -n "${h:-}" ] || die "could not read window geometry: $geometry"
  local out="$SHOT_DIR/$label.png"
  screencapture -x -R "$((x - 10)),$((y - 10)),$((w + 20)),$((h + 20))" "$out" || die "screencapture failed"
  echo "$out"
}

# Screenshots an open status-bar menu, which has no accessibility geometry.
cmd_shot_menu() {
  local label="${1:-menu}"
  mkdir -p "$SHOT_DIR"
  ax 'click menu bar item 1 of menu bar 2' >/dev/null 2>&1
  sleep 0.8
  local geometry x
  geometry=$(cmd_status_item | tr -d ' ')
  x=$(echo "$geometry" | cut -d, -f2)
  [ -n "$x" ] || die "status item not found"
  local out="$SHOT_DIR/$label.png"
  screencapture -x -R "$((x - 10)),0,400,250" "$out" || die "screencapture failed"
  echo "$out"
}

cmd_smoke() {
  cmd_build || return 1
  cmd_launch || return 1
  echo "status item: $(cmd_status_item)"
  echo "menu items: $(cmd_menu)"
  cmd_shot_menu menu-initial
  cmd_click "Emergency Stop"
  cmd_shot_menu menu-after-stop
  cmd_click "Open Details"
  echo "windows: $(cmd_windows)"
  cmd_shot_window details
  cmd_quit
}

case "${1:-}" in
  build) shift; cmd_build "$@" ;;
  launch) shift; cmd_launch "$@" ;;
  quit) shift; cmd_quit "$@" ;;
  status-item) shift; cmd_status_item "$@" ;;
  menu) shift; cmd_menu "$@" ;;
  menu-items) shift; cmd_menu_items "$@" ;;
  click) shift; cmd_click "$@" ;;
  windows) shift; cmd_windows "$@" ;;
  front) shift; cmd_front "$@" ;;
  shot-window) shift; cmd_shot_window "$@" ;;
  shot-menu) shift; cmd_shot_menu "$@" ;;
  smoke) shift; cmd_smoke "$@" ;;
  *) die "commands: build launch quit status-item menu menu-items click windows front shot-window shot-menu smoke" ;;
esac
