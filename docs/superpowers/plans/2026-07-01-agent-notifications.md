# Agent Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give tmux differentiated, low-false-positive notifications (color+blink+sound+banner) when Claude Code or cursor-agent finishes work or needs approval.

**Architecture:** App hooks (Claude `Notification`/`Stop`, cursor `beforeShellExecution`/`beforeMCPExecution`/`stop`) call a portable dispatcher script `agent-notify`, which sets per-window tmux state, plays a per-event sound, and fires a desktop banner. A second script `cursor-shell-gate` implements cursor's approval policy (Option A). `tmux.conf` stops using `monitor-activity` (the false-positive source) and colors windows from a `@notify_state` window option. `install` symlinks the scripts and merges the hook config non-destructively.

**Tech Stack:** POSIX/bash shell scripts, tmux format options + hooks, `jq` (merge + JSON parsing), `bats-core` (tests), `shellcheck` (lint). macOS: `afplay`/`osascript`. Linux/CachyOS: `pw-play`/`paplay`/`canberra-gtk-play` + `notify-send`.

## Global Constraints

- Platforms: **macOS** and **Linux (CachyOS)** only. No Windows.
- Scripts are **best-effort and MUST always `exit 0`** — a failing hook must never wedge the agent.
- Hooks reference scripts by absolute path via `$HOME/.local/bin/`.
- `jq` is the only hard runtime dependency for the install merge.
- Do **NOT** clobber `~/.claude/settings.json` — merge only our hook keys, preserving all existing keys.
- Do **NOT** whole-file-symlink Claude/cursor settings.
- Git: add files **individually** (`git add .` is forbidden), plain imperative commit subjects (repo convention — no ticket prefix), **no `Co-Authored-By` lines**.
- Every script passes `shellcheck` clean.

---

### Task 1: `agent-notify` dispatcher

**Files:**
- Create: `bin/agent-notify`
- Create: `tests/agent-notify.bats`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces: CLI `agent-notify <event> [app]` where `event ∈ {approval, complete}`, `app` is a label string (default `agent`). Side effects: sets tmux window option `@notify_state` to the event on the pane's window (when in tmux); plays a per-event sound; fires a per-event desktop banner. Always exits 0.

- [ ] **Step 0: Install the test runner (prerequisite)**

Run (macOS): `brew install bats-core`
Run (CachyOS): `sudo pacman -S --needed bats`
Verify: `bats --version` prints a version.

- [ ] **Step 1: Write the failing tests**

Create `tests/agent-notify.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BIN="$REPO/bin/agent-notify"
  # Sandbox PATH with fakes that record their args to $LOG.
  FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKEBIN"
  LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$LOG"
  for tool in afplay osascript notify-send canberra-gtk-play pw-play paplay; do
    { echo '#!/usr/bin/env bash'
      echo "echo \"$tool \$*\" >> \"$LOG\""
    } > "$FAKEBIN/$tool"
    chmod +x "$FAKEBIN/$tool"
  done
  PATH="$FAKEBIN:$PATH"
  unset TMUX TMUX_PANE   # default: not in tmux
}

# Force platform by planting a fake `uname` earlier on PATH.
_force_uname() {
  { echo '#!/usr/bin/env bash'
    echo "[ \"\$1\" = -s ] && echo \"$1\" || /usr/bin/uname \"\$@\""
  } > "$FAKEBIN/uname"
  chmod +x "$FAKEBIN/uname"
}

@test "unknown event exits 0 and does nothing" {
  run "$BIN" bogus
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}

@test "macos approval plays Sosumi and shows a banner" {
  _force_uname Darwin
  run "$BIN" approval claude
  [ "$status" -eq 0 ]
  sleep 0.2   # audio is backgrounded
  grep -q "afplay .*Sosumi.aiff" "$LOG"
  grep -q "osascript .*Needs approval" "$LOG"
}

@test "macos complete plays Glass" {
  _force_uname Darwin
  run "$BIN" complete claude
  sleep 0.2
  grep -q "afplay .*Glass.aiff" "$LOG"
  grep -q "osascript .*Done" "$LOG"
}

@test "linux approval uses notify-send critical and a player" {
  _force_uname Linux
  run "$BIN" approval cursor
  [ "$status" -eq 0 ]
  sleep 0.2
  grep -q "notify-send .*-u critical" "$LOG"
  grep -Eq "canberra-gtk-play .*dialog-warning|pw-play .*dialog-warning|paplay .*dialog-warning" "$LOG"
}

@test "no-tmux run does not error" {
  _force_uname Darwin
  run "$BIN" complete
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/agent-notify.bats`
Expected: FAIL — `agent-notify` does not exist yet.

- [ ] **Step 3: Write `bin/agent-notify`**

```bash
#!/usr/bin/env bash
# agent-notify — differentiated notifications for coding-agent CLIs.
# Usage: agent-notify <approval|complete> [app]
# Best-effort: always exits 0 so it can never wedge a calling hook.
set -u

event="${1:-}"
app="${2:-agent}"

case "$event" in
  approval)
    macos_sound="/System/Library/Sounds/Sosumi.aiff"
    fd_sound="dialog-warning"
    urgency="critical"
    title="🔴 Needs approval — ${app}"
    body="Waiting for your input."
    ;;
  complete)
    macos_sound="/System/Library/Sounds/Glass.aiff"
    fd_sound="complete"
    urgency="normal"
    title="✅ Done — ${app}"
    body="Operation finished."
    ;;
  *)
    echo "usage: agent-notify <approval|complete> [app]" >&2
    exit 0
    ;;
esac

# 1. tmux window state (portable)
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
  tmux set-option -w -t "$TMUX_PANE" @notify_state "$event" 2>/dev/null || true
fi

# 2. audio (backgrounded, best-effort)
play_sound() {
  case "$(uname -s)" in
    Darwin)
      [ -r "$macos_sound" ] && afplay "$macos_sound"
      ;;
    Linux)
      if command -v canberra-gtk-play >/dev/null 2>&1; then
        canberra-gtk-play -i "$fd_sound"
      elif command -v pw-play >/dev/null 2>&1; then
        pw-play "/usr/share/sounds/freedesktop/stereo/${fd_sound}.oga"
      elif command -v paplay >/dev/null 2>&1; then
        paplay "/usr/share/sounds/freedesktop/stereo/${fd_sound}.oga"
      fi
      ;;
  esac
}
play_sound >/dev/null 2>&1 &

# 3. desktop banner (best-effort)
case "$(uname -s)" in
  Darwin)
    if command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"${body}\" with title \"${title}\"" >/dev/null 2>&1 || true
    fi
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -a "$app" -u "$urgency" "$title" "$body" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
```

Then: `chmod +x bin/agent-notify`

- [ ] **Step 4: Run tests + shellcheck to verify pass**

Run: `bats tests/agent-notify.bats`
Expected: all 5 tests PASS.
Run: `shellcheck bin/agent-notify`
Expected: no warnings.

- [ ] **Step 5: Commit**

```bash
git add bin/agent-notify tests/agent-notify.bats
git commit -m "Add agent-notify dispatcher for agent notifications"
```

---

### Task 2: `cursor-shell-gate` approval gate (Option A)

**Files:**
- Create: `bin/cursor-shell-gate`
- Create: `tests/cursor-shell-gate.bats`

**Interfaces:**
- Consumes: `agent-notify` (invoked via `$AGENT_NOTIFY_BIN`, default `$HOME/.local/bin/agent-notify`).
- Produces: reads cursor's hook JSON on **stdin**, prints a permission decision `{"permission":"allow"}` or `{"permission":"ask"}` to **stdout**, and fires `agent-notify approval cursor` only when asking. Always exits 0.

> **Verify-at-implementation:** confirm cursor's `beforeShellExecution` stdin field for the command and its expected output key (`permission`) against `https://cursor.com/docs/hooks` or a live run before wiring in Task 5. The gate reads `.command`/`.tool_input.command`/`.args.command` defensively; adjust if the real field differs.

- [ ] **Step 1: Write the failing tests**

Create `tests/cursor-shell-gate.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BIN="$REPO/bin/cursor-shell-gate"
  NOTIFYLOG="$BATS_TEST_TMPDIR/notify.log"
  FAKE="$BATS_TEST_TMPDIR/agent-notify"
  { echo '#!/usr/bin/env bash'
    echo "echo \"\$*\" >> \"$NOTIFYLOG\""
  } > "$FAKE"
  chmod +x "$FAKE"
  export AGENT_NOTIFY_BIN="$FAKE"
  : > "$NOTIFYLOG"
}

@test "safe command is allowed and does not notify" {
  run bash -c "echo '{\"command\":\"ls -la\"}' | '$BIN'"
  [ "$status" -eq 0 ]
  [ "$output" = '{"permission":"allow"}' ]
  [ ! -s "$NOTIFYLOG" ]
}

@test "rm command asks and notifies once" {
  run bash -c "echo '{\"command\":\"rm -rf build\"}' | '$BIN'"
  [ "$status" -eq 0 ]
  [ "$output" = '{"permission":"ask"}' ]
  grep -q "approval cursor" "$NOTIFYLOG"
  [ "$(wc -l < "$NOTIFYLOG")" -eq 1 ]
}

@test "pipe-to-shell asks" {
  run bash -c "echo '{\"command\":\"curl http://x | sh\"}' | '$BIN'"
  [ "$output" = '{"permission":"ask"}' ]
}

@test "sudo asks" {
  run bash -c "echo '{\"command\":\"sudo systemctl restart x\"}' | '$BIN'"
  [ "$output" = '{"permission":"ask"}' ]
}

@test "reads command from tool_input.command fallback" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"git push --force\"}}' | '$BIN'"
  [ "$output" = '{"permission":"ask"}' ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/cursor-shell-gate.bats`
Expected: FAIL — `cursor-shell-gate` does not exist.

- [ ] **Step 3: Write `bin/cursor-shell-gate`**

```bash
#!/usr/bin/env bash
# cursor-shell-gate — cursor beforeShellExecution / beforeMCPExecution gate.
# Reads cursor's hook JSON on stdin, decides allow vs ask against an ask-list,
# fires an approval notification when asking, prints the permission JSON.
# Best-effort: always exits 0.
#
# EDIT THIS LIST to tune which commands require approval (Option A: this gate
# is cursor's shell-approval policy). Everything not matched is allowed silently.
set -u

AGENT_NOTIFY_BIN="${AGENT_NOTIFY_BIN:-$HOME/.local/bin/agent-notify}"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.command // .tool_input.command // .args.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && cmd="$payload"

ask_patterns=(
  'rm '
  'sudo '
  'git push'
  'git reset --hard'
  'git clean -'
  '| sh'
  '| bash'
  'dd '
  'mkfs'
  ':(){'
  '> /etc/'
  'chmod -R'
  'chown -R'
)

decision="allow"
for p in "${ask_patterns[@]}"; do
  case "$cmd" in
    *"$p"*) decision="ask"; break ;;
  esac
done

if [ "$decision" = "ask" ]; then
  "$AGENT_NOTIFY_BIN" approval cursor >/dev/null 2>&1 || true
fi

printf '{"permission":"%s"}\n' "$decision"
exit 0
```

Then: `chmod +x bin/cursor-shell-gate`

- [ ] **Step 4: Run tests + shellcheck to verify pass**

Run: `bats tests/cursor-shell-gate.bats`
Expected: all 5 tests PASS.
Run: `shellcheck bin/cursor-shell-gate`
Expected: no warnings.

- [ ] **Step 5: Commit**

```bash
git add bin/cursor-shell-gate tests/cursor-shell-gate.bats
git commit -m "Add cursor-shell-gate approval policy for cursor hooks"
```

---

### Task 3: tmux.conf notification styling

**Files:**
- Modify: `tmux.conf` (line 47; append block after the tpm `run` line at ~125)

**Interfaces:**
- Consumes: `@notify_state` window option set by `agent-notify` (values `approval`, `complete`, `none`).
- Produces: window highlight (red+blink for approval, green for complete) via `window-status-format`; auto-clear of `@notify_state` on `after-select-window`.

- [ ] **Step 1: Turn off activity monitoring (the false-positive source)**

In `tmux.conf`, change line 47 from:
```tmux
set-window-option -g monitor-activity on
```
to:
```tmux
# Notifications are now driven by app hooks (see agent-notify), not by raw
# output monitoring, which produced false positives on spinner/tick output.
set-window-option -g monitor-activity off
```

- [ ] **Step 2: Append the notification styling block after the tpm `run` line**

At the very end of `tmux.conf` (after `run '~/.tmux/plugins/tpm/tpm'`, so it wins over the theme/default), add:

```tmux
################################################################################
# Agent notifications (driven by agent-notify via app hooks)
################################################################################

# Default state so the format's conditionals resolve on untouched windows.
set -gw @notify_state none

# Color the window in the status bar based on its notification state.
# approval -> red + blink (urgent, blocking); complete -> green (informational).
set -g window-status-format "#{?#{==:#{@notify_state},approval},#[bg=colour160 fg=colour231 bold blink],#{?#{==:#{@notify_state},complete},#[bg=colour28 fg=colour231 bold],}} #I:#W#F #[default]"
set -g window-status-current-format "#[fg=colour231 bg=colour24 bold] #I:#W#F #[default]"

# Clear a window's notification state when you switch to it.
set-hook -g after-select-window 'set-window-option @notify_state none'
```

- [ ] **Step 3: Verify the auto-clear behavior headlessly**

Run:
```bash
tmux -L ntest kill-server 2>/dev/null
tmux -L ntest new-session -d
tmux -L ntest set-hook -g after-select-window 'set-window-option @notify_state none'
tmux -L ntest set -gw @notify_state none
tmux -L ntest set-option -w -t :1 @notify_state approval
tmux -L ntest new-window          # selects the new window
tmux -L ntest select-window -t :1 # triggers after-select-window on window 1
tmux -L ntest show-options -w -t :1 @notify_state
tmux -L ntest kill-server
```
Expected: the final `show-options` prints `@notify_state none` (the hook cleared it on select).

- [ ] **Step 4: Verify the color/blink visually (manual)**

Run: `tmux source-file tmux.conf` inside a live tmux session (or reload with `prefix r`), then in another window run `tmux set-option -w -t :2 @notify_state approval`.
Expected: window 2 in the status bar turns red and blinks. Repeat with `complete` → green, steady. Switch to window 2 → highlight clears.
If blink does not render in Ghostty's status line: replace `blink` with `reverse` in the `window-status-format` line and re-verify. Record which was used.

- [ ] **Step 5: Commit**

```bash
git add tmux.conf
git commit -m "Drive tmux window notifications from @notify_state, not activity"
```

---

### Task 4: `install` — symlinks, hook merge, Linux deps

**Files:**
- Modify: `install` (add functions; guard `main`; extend `symlink_dotfiles` and `main`)
- Modify: `macos/Brewfile` (add `bats-core`)
- Create: `tests/install-merge.bats`

**Interfaces:**
- Consumes: `bin/agent-notify`, `bin/cursor-shell-gate` (from Tasks 1–2).
- Produces: sourceable functions `merge_claude_hooks [settings_path]` and `write_cursor_hooks [target_path]`; symlinks both scripts into `~/.local/bin`; warns on missing Linux deps.

- [ ] **Step 1: Write the failing tests**

Create `tests/install-merge.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Source install without running main(). install sets `set -e`; neutralize it
  # in the test shell so intentional non-zero assertions don't abort the test.
  source "$REPO/install"
  set +e
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
}

@test "merge preserves existing keys and adds hooks" {
  echo '{"model":"opus","theme":"dark"}' > "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  [ "$(jq -r '.model' "$SETTINGS")" = "opus" ]
  [ "$(jq -r '.theme' "$SETTINGS")" = "dark" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].type' "$SETTINGS")" = "command" ]
  jq -e '.hooks.Notification' "$SETTINGS"
}

@test "merge is idempotent (no duplicate hook entries)" {
  echo '{}' > "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  [ "$(jq '.hooks.Stop | length' "$SETTINGS")" -eq 1 ]
  [ "$(jq '.hooks.Notification | length' "$SETTINGS")" -eq 1 ]
}

@test "merge creates file when absent" {
  rm -f "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  jq -e '.hooks.Stop' "$SETTINGS"
}

@test "cursor hooks written with gate and stop entries" {
  TARGET="$BATS_TEST_TMPDIR/hooks.json"
  write_cursor_hooks "$TARGET"
  jq -e '.hooks.beforeShellExecution[0].command' "$TARGET"
  jq -e '.hooks.stop[0].command' "$TARGET"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/install-merge.bats`
Expected: FAIL — functions not defined / `main` runs on source.

- [ ] **Step 3: Add functions and guard `main` in `install`**

In `install`, extend `symlink_dotfiles` — add before its closing `}`:

```bash
  mkdir -p "${HOME}/.local/bin"
  ln -sf "${SCRIPT_DIR}/bin/agent-notify" "${HOME}/.local/bin/agent-notify"
  ln -sf "${SCRIPT_DIR}/bin/cursor-shell-gate" "${HOME}/.local/bin/cursor-shell-gate"
```

Add these new functions (e.g. after `symlink_dotfiles`):

```bash
merge_claude_hooks() {
  local settings="${1:-$HOME/.claude/settings.json}"
  local bin='$HOME/.local/bin/agent-notify'
  mkdir -p "$(dirname "$settings")"
  [ -f "$settings" ] || echo '{}' > "$settings"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg notif "$bin approval claude" \
    --arg stop  "$bin complete claude" \
    '.hooks = (.hooks // {})
     | .hooks.Notification = [ { "hooks": [ { "type": "command", "command": $notif } ] } ]
     | .hooks.Stop         = [ { "hooks": [ { "type": "command", "command": $stop  } ] } ]' \
    "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "merged Claude hooks into $settings"
}

write_cursor_hooks() {
  local target="${1:-$HOME/.cursor/hooks.json}"
  local gate='$HOME/.local/bin/cursor-shell-gate'
  local notify='$HOME/.local/bin/agent-notify'
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [ { "command": "$gate" } ],
    "beforeMCPExecution": [ { "command": "$gate" } ],
    "stop": [ { "command": "sh -c 'test \"\$(jq -r .status)\" = completed && $notify complete cursor'" } ]
  }
}
EOF
  echo "wrote cursor hooks to $target"
}

linux_setup() {
  local missing=0
  command -v jq >/dev/null 2>&1 || { echo "WARN: jq missing (pacman -S jq)"; missing=1; }
  command -v notify-send >/dev/null 2>&1 || { echo "WARN: notify-send missing (pacman -S libnotify)"; missing=1; }
  if ! command -v pw-play >/dev/null 2>&1 \
     && ! command -v paplay >/dev/null 2>&1 \
     && ! command -v canberra-gtk-play >/dev/null 2>&1; then
    echo "WARN: no audio player (pacman -S pipewire libcanberra)"; missing=1
  fi
  [ "$missing" -eq 0 ] && echo "linux notification deps OK"
}
```

In `main()`, after the macOS branch, add the Linux branch and the hook wiring:

```bash
  if [[ $operating_system == "linux" ]]; then
    linux_setup
  fi

  neovim_config_setup
  symlink_dotfiles
  merge_claude_hooks
  write_cursor_hooks
```

At the bottom of `install`, replace the bare `main` call with:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
```

In `macos/Brewfile`, add (alphabetically near the top of the `brew` entries):

```ruby
brew "bats-core"
```

- [ ] **Step 4: Run tests + shellcheck to verify pass**

Run: `bats tests/install-merge.bats`
Expected: all 4 tests PASS.
Run: `shellcheck install`
Expected: no new warnings.

- [ ] **Step 5: Commit**

```bash
git add install macos/Brewfile tests/install-merge.bats
git commit -m "Install: symlink notify scripts and merge agent hook config"
```

---

### Task 5: Wire live hooks + end-to-end verification (macOS)

**Files:**
- Modify: `~/.claude/settings.json` (via `install` merge — not committed to repo)
- Create: `~/.cursor/hooks.json` (via `install` — not committed to repo)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: live, verified notifications on this macOS machine.

> This task is integration + manual verification; there is no bats file. Run the real install path and confirm real notifications fire.

- [ ] **Step 1: Confirm cursor hook schema before wiring**

Fetch `https://cursor.com/docs/hooks` (or run a throwaway `cursor-agent` command) and confirm: (a) the stdin field name carrying the shell command for `beforeShellExecution`, and (b) the output key for the decision (expected `permission` with value `allow`/`ask`). If either differs from Task 2's assumptions, update `bin/cursor-shell-gate` (the `jq` field list and/or the printed key) and re-run `bats tests/cursor-shell-gate.bats`, then amend the Task 2 commit or add a fixup commit.

- [ ] **Step 2: Back up existing Claude settings, then run install**

Run:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
cd ~/src/config && ./install
```
Expected: install completes; prints "merged Claude hooks…" and "wrote cursor hooks…".

- [ ] **Step 3: Verify settings were merged, not clobbered**

Run: `jq -r 'keys[]' ~/.claude/settings.json`
Expected: still includes `model`, `theme`, `enabledPlugins`, `extraKnownMarketplaces`, `skipAutoPermissionPrompt`, plus new `hooks`.
Run: `jq '.hooks' ~/.claude/settings.json`
Expected: `Notification` and `Stop` each map to the `agent-notify` commands.
Run: `diff <(jq 'del(.hooks)' ~/.claude/settings.json) <(jq . ~/.claude/settings.json.bak)`
Expected: no differences (only `.hooks` was added).

- [ ] **Step 4: Reload tmux and verify the symlinks resolve**

Run: `tmux source-file ~/.tmux.conf && ls -l ~/.local/bin/agent-notify ~/.local/bin/cursor-shell-gate`
Expected: both symlinks point into `~/src/config/bin/`.

- [ ] **Step 5: End-to-end — Claude complete + approval**

In a tmux pane, run a real Claude Code session. Trigger a normal response end.
Expected: `Stop` fires → green window highlight + Glass chime + "✅ Done" banner; switching to that window clears the highlight.
Then trigger a permission prompt (an action Claude must ask to run).
Expected: `Notification` fires → red/blink highlight + Sosumi chime + "🔴 Needs approval" banner.

- [ ] **Step 6: End-to-end — cursor complete + approval**

In a tmux pane, run a real `cursor-agent` session to completion.
Expected: `stop` (status completed) → green + Glass + "✅ Done — cursor".
Then have it attempt an ask-listed command (e.g. something matching `rm ` or `git push`).
Expected: `cursor-shell-gate` returns `ask` → cursor prompts → red/blink + Sosumi + "🔴 Needs approval — cursor". A safe command (e.g. `ls`) produces no notification.

- [ ] **Step 7: Clean up backup**

Run: `rm ~/.claude/settings.json.bak`
(Only after Steps 3–6 confirm everything works. If anything failed, restore with `mv ~/.claude/settings.json.bak ~/.claude/settings.json`.)

- [ ] **Step 8: No commit**

Steps here modify machine-local files outside the repo (`~/.claude`, `~/.cursor`), which are intentionally not tracked. Nothing to commit.

---

## Notes for the CachyOS machine (deferred verification)

When installing on CachyOS later (not part of this macOS run):
- Run `./install`; heed any `linux_setup` WARN lines (`pacman -S jq libnotify pipewire libcanberra`).
- Re-run the Task 3 Step 4 visual check and Task 5 Steps 5–6 end-to-end checks under your desktop environment.
- Confirm `-u critical` banners persist until dismissed and the chosen audio player fires (`canberra-gtk-play`/`pw-play`/`paplay`).
- If the freedesktop `dialog-warning`/`complete` sounds are absent, install the sound theme or switch `agent-notify`'s `fd_sound` ids.
