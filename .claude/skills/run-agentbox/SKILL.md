---
name: run-agentbox
description: Build, launch, drive, screenshot, and test the AgentBox macOS menu bar app. Use when asked to run AgentBox, start the app, take a screenshot of the menu or details window, verify a UI change in the real app, or run the AgentBox test suites.
---

# Run AgentBox

AgentBox ships `AgentBoxMenuBar`, a SwiftUI `MenuBarExtra` app plus a
`Window` scene. It is built with Tuist + `xcodebuild` and driven through the
macOS accessibility API by `.claude/skills/run-agentbox/driver.sh`.

macOS only. All paths are relative to the repository root.

## Prerequisites

Already present on this machine; install only if missing:

```bash
brew install just
mise use -g tuist   # or: brew install tuist
```

Grant the terminal running the driver two permissions in System Settings >
Privacy & Security, or every command fails:

- **Accessibility** - System Events drives the menu. Without it, `osascript`
  returns `-1719` and clicks silently do nothing.
- **Screen Recording** - `screencapture` writes the screenshots. Without it,
  every PNG is a black rectangle.

## Run (agent path)

One command builds, launches, drives both menu actions, screenshots each
state, and stops the app:

```bash
AGENTBOX_SHOT_DIR=/tmp/agentbox-run .claude/skills/run-agentbox/driver.sh smoke
```

Verified output:

```
** BUILD SUCCEEDED **
launched: 88979
status item: Shield, 916, 4, 32, 24
menu items: Assurance: Unavailable, Active sessions: 0, missing value, Open Details, Emergency Stop
/tmp/agentbox-run/menu-initial.png
clicked: Emergency Stop
/tmp/agentbox-run/menu-after-stop.png
clicked: Open Details
windows: AgentBox Details, 297, 398, 420, 260
/tmp/agentbox-run/details.png
stopped
```

**Read the PNGs.** A black image means Screen Recording permission is missing,
not that the app failed.

Individual commands, for driving one flow at a time:

```bash
D=.claude/skills/run-agentbox/driver.sh
$D build                      # tuist generate + xcodebuild
$D launch                     # kills any running copy, opens the app
$D status-item                # -> Shield, 916, 4, 32, 24   (name, x, y, w, h in points)
$D menu                       # opens the status menu, prints its item titles
$D click "Emergency Stop"     # opens the menu, clicks one item by title
$D click "Open Details"
$D windows                    # -> AgentBox Details, 297, 398, 420, 260
$D shot-menu  <label>         # screenshots the open status menu
$D shot-window <label>        # raises the app, screenshots window 1
$D quit
```

Screenshots land in `$AGENTBOX_SHOT_DIR`, default `$TMPDIR/agentbox-run`.

## Build only

```bash
tuist generate --no-open --cache-profile none
just xcode-build-menubar
```

## Test

Two separate suites; run both.

```bash
swift test    # Domain + Broker: 32 tests
xcodebuild -workspace AgentBox.xcworkspace -scheme AgentBoxMenuBar \
  -configuration Debug test CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.0 \
  2>&1 | grep -E "(error:|Test run|TEST SUCCEEDED|TEST FAILED)"   # MenuBar: 15 tests
```

SwiftUI views carry ViewInspector structure tests and `swift-snapshot-testing`
image tests. Reference images live in
`Tests/AgentBoxMenuBarTests/__Snapshots__/` and are committed. Re-record only
for an intentional UI change: delete the stale PNG and re-run the suite, which
records it and reports a failure on that first run only.

```bash
swiftlint lint --strict            # must report 0 violations
swift format format --in-place Sources/*/*.swift
```

## Gotchas

- **`Assurance: Unavailable` and `Active sessions: 0` are correct**, not a
  failure. `AgentBoxMenuBarApp` wires `UnavailableSessionControl`, and
  `/usr/local/bin/container system status` reports `apiserver is not running`
  on this machine. Emergency Stop therefore answers `Emergency stop
  unavailable.` That is the fail-closed path working.
- **The status item is on `menu bar 2`**, not `menu bar 1`. `menu bar 1` is
  the app's own File/Edit/View menu, because the target has no `LSUIElement`
  key and so keeps a Dock icon and a full menu bar.
- **Its accessibility name is `Shield`**, derived from
  `MenuBarExtra(systemImage: "shield")`. It changes if that symbol changes.
- **`click menu bar item ...` prints `missing value` and still succeeds.**
  Do not treat that output as an error.
- **`menu-items` prints `missing value` between `Active sessions` and
  `Open Details`.** That entry is the `Divider()`.
- **An open menu has no accessibility geometry**, so `shot-menu` cannot ask
  where it is. It captures a fixed 400x250-point box anchored 10 points left
  of the status item, because the menu opens rightward from that anchor.
- **`openWindow(id:)` does not raise the app.** After `click "Open Details"`
  the window exists but sits behind whatever was frontmost, so a screenshot
  captures the wrong app. `shot-window` sets `frontmost` first; do the same
  in any custom capture.
- **`screencapture -R` takes points, not pixels.** On this Retina display the
  written PNG is 2x the region you asked for: `-R 0,0,3000,60` returns a
  3024x120 image clipped to the 1512-point display width.
- **A menu bar manager can hide the icon** while accessibility still reports
  its position; clicks keep working even when the shield is not on screen.
- **`timeout` does not exist in this shell.** Use the `timeout` argument of
  the Bash tool instead of prefixing commands with it.
- **There is no `AgentBoxMenuBarTests` scheme.** Those tests run through the
  `AgentBoxMenuBar` scheme.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `driver: app not built at '/...'; run: driver.sh build` | Run `driver.sh build`, or the DerivedData copy was cleaned. |
| `osascript` error `-1719` / clicks do nothing | Grant the terminal Accessibility permission. |
| Screenshot PNG is entirely black | Grant the terminal Screen Recording permission. |
| `driver: no window; run: driver.sh click 'Open Details'` | The Window scene is closed; click Open Details first. |
| `xcodebuild: ... does not contain a scheme named "AgentBoxMenuBarTests"` | Use the `AgentBoxMenuBar` scheme. |
| `The '--no-binary-cache' flag is deprecated` | Use `tuist generate --no-open --cache-profile none`. |
