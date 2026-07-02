# Design: Differentiated agent notifications (tmux + Ghostty)

**Date:** 2026-07-01
**Status:** Approved for planning
**Repo:** `~/src/config` (dotfiles)

## Problem

The current tmux config notifies via `monitor-activity on` (line 47) plus a single
undifferentiated bell/highlight path. Two problems:

1. **Oversensitive.** `monitor-activity` flags a window on *any* byte of output, so
   Claude Code / cursor-agent spinners and background ticks trip it constantly, even
   when nothing needs the user.
2. **Undifferentiated.** Every event looks identical — top-bar bell glyph + the
   tokyo-night black window highlight. No color coding, no sound, and no distinction
   between "operation finished" and "needs my approval."

The root cause of (1) is that tmux only sees raw bytes and cannot tell those states
apart. The fix is to stop guessing from bytes and instead let each app emit a
*deliberate* signal via its hook system.

## Goals

- Only notify on two real events: **operation complete** and **needs approval**.
- Differentiate them by **color + motion + sound** at a glance / by ear.
- Two channels: **in-tmux** (color-coded window highlight + chime while looking at
  the session) and **macOS banner + dock bounce** (when the terminal is unfocused).
- Work symmetrically for both Claude Code and cursor-agent CLIs running in tmux panes.
- Manage cleanly in the dotfiles repo without clobbering existing/enterprise settings.

## Non-goals

- No routing notifications *through* Ghostty (OSC 9/777 + tmux passthrough). Hooks are
  shell scripts with full system access, so they act directly (`afplay`, `osascript`,
  `tmux`). Ghostty stays a passive display surface.
- No general-purpose notification framework. Two event types only (YAGNI).
- No handling of Cursor the GUI IDE — CLI (`cursor-agent`) only.

## Architecture

```
Claude Code hook  ─┐
                   ├─► bin/agent-notify <event> <app> ─┬─► tmux set-window-option @notify_state
cursor-agent hook ─┘                                   ├─► afplay <per-event sound>
                                                       └─► osascript banner (per-event)
```

One dispatcher script is the single orchestration point. Each app's hooks call it with
an event type; the script performs all three output actions.

### Component 1 — `bin/agent-notify` (the dispatcher)

- **Location:** `~/src/config/bin/agent-notify`, symlinked to `~/.local/bin/agent-notify`.
- **Interface:** `agent-notify <event> [app]`
  - `event` ∈ `{approval, complete}` (required)
  - `app` ∈ `{claude, cursor}` (optional, for banner labeling; default `agent`)
- **Environment it reads:** `$TMUX`, `$TMUX_PANE` (inherited from the pane the CLI runs
  in — this is how it targets the right window).
- **Behavior:**
  1. **tmux visual** — if `$TMUX` is set:
     `tmux set-option -w -t "$TMUX_PANE" @notify_state "$event"`
     (`-w` sets the window *containing* that pane).
     If `$TMUX` is unset, skip silently.
  2. **audio** — `afplay "<sound-for-event>" &` (backgrounded so the hook never blocks).
  3. **OS banner** — `osascript -e 'display notification …'` with a per-event title.
- **Failure policy:** each action is independent and best-effort; a missing `$TMUX` or a
  failed `afplay` must not abort the others and must not return non-zero to the caller
  (a failing hook must never wedge the agent). Let real errors surface in logs, but do
  not swallow-with-`or {}` in a way that hides a broken install — see Testing.

### Component 2 — Sensory mapping

| Event | tmux color | Motion | macOS sound | Banner title |
|---|---|---|---|---|
| **approval** | red / orange | blink | `Sosumi` (sharp) | `🔴 Needs approval — <app>` |
| **complete** | green | steady | `Glass` (soft) | `✅ Done — <app>` |

Sounds are `/System/Library/Sounds/<name>.aiff`. Colors and sounds are single-line
constants in the script, trivially editable.

### Component 3 — `tmux.conf` changes

- **Flip line 47:** `set-window-option -g monitor-activity off` — root-cause fix for
  false positives. We no longer let tmux guess from raw bytes.
- Leave `visual-bell`/`visual-activity off` (lines 53–54); we no longer use the
  bell/activity path at all. `bell-action` (line 50) becomes irrelevant to this feature
  but is left as-is (Chesterton's fence — out of scope to remove).
- **Per-window color**, added *after* the tpm `run` line (so it layers over the theme):
  override `window-status-format` / `window-status-current-format` to wrap
  tokyo-night's output with a conditional keyed on `@notify_state`, e.g.
  `#{?#{==:#{@notify_state},approval},#[bg=colour red blink],#{?#{==:#{@notify_state},complete},#[bg=green],}}`
  (exact form determined at implementation — see Risks).
- **Auto-clear on focus:**
  `set-hook -g after-select-window 'set-window-option @notify_state none'`
  so a window's highlight clears when the user switches to it.
- **Default:** `set -gw @notify_state none` (avoids empty-lookup edge cases; the format
  conditional already treats empty as "not set," so this is belt-and-suspenders).

### Component 4 — Claude Code hooks

Clean mapping (Claude has purpose-built events):

- `Notification` → `agent-notify approval claude` (fires when Claude needs permission or
  input has been idle) 
- `Stop` → `agent-notify complete claude` (fires when Claude finishes a response)

Merged into `~/.claude/settings.json` under the `hooks` key (see Component 6). Command
uses an absolute path: `$HOME/.local/bin/agent-notify approval claude`.

### Component 5 — cursor-agent hooks + approval policy (Option A)

cursor-agent has **no dedicated "waiting for approval" hook**, and its `stop` payload
(`completed|aborted|error`) does not distinguish "done" from "waiting." Chosen approach
(**Option A**): the pre-execution hook *becomes* the approval gate.

- `stop` (status `completed`) → `agent-notify complete cursor`.
  (status `aborted`/`error` → no notification for MVP.)
- `beforeShellExecution` and `beforeMCPExecution` → evaluate the command against a
  **policy**:
  - If it matches the **ask-list** (destructive / network / privileged), the hook
    returns a permission decision requesting approval **and** fires
    `agent-notify approval cursor`.
  - Otherwise the hook allows silently (no notification) — this is what preserves the
    "not oversensitive" goal.

**Default policy (conservative, clearly editable):** trigger ask+notify on patterns like
`rm `, `sudo `, `git push`, `git reset --hard`, `curl … | sh`, `dd `, `mkfs`, `:(){`,
writes to `/etc`, force-push, etc. Everything else allowed silently. Patterns live in a
small list at the top of the policy logic. Patrick will refine this list during spec
review.

- Config file: `~/.cursor/hooks.json` (created fresh; none exists today).
- **To verify at implementation:** exact JSON output schema cursor expects from
  `beforeShellExecution` (key names for the allow/ask/deny decision and any user
  message). The dispatcher itself is app-agnostic; the ask/allow decision + JSON
  response is emitted by the cursor hook wrapper, which then calls `agent-notify`.

### Component 6 — install / settings management

**Decision:** do NOT symlink `~/.claude/settings.json` wholesale.

Rationale (verified 2026-07-01):
- Settings are **per-home-directory, not per-account** — one file serves both work and
  personal Claude logins on this Mac.
- Enterprise managed settings live at a separate path
  (`/Library/Application Support/ClaudeCode/managed-settings.json`) and always win on
  precedence; if an org sets `allowManagedHooksOnly: true`, user hooks are blocked
  entirely. **This machine currently has no managed settings / MDM plist**, so hooks
  will run — but the merge approach stays robust if that changes.
- The existing `~/.claude/settings.json` (634 B) holds real content (`model`, `theme`,
  `enabledPlugins`, `extraKnownMarketplaces`, `skipAutoPermissionPrompt`) and no `hooks`
  key. A whole-file symlink would clobber it, and Claude writes-through (e.g. `/config`,
  permission grants) would churn the repo with possibly work-specific data.

**Approach:**
- `symlink_dotfiles` in `install`: add
  `ln -sf ${SCRIPT_DIR}/bin/agent-notify ${HOME}/.local/bin/agent-notify`
  (creating `~/.local/bin` if needed).
- Add an idempotent **`jq` merge** step (new function in `install`) that injects the
  notify `hooks` block into `~/.claude/settings.json`, preserving all existing keys, and
  creates/merges `~/.cursor/hooks.json`. Re-running `install` re-merges without
  duplicating.
- `osascript` and `afplay` are macOS built-ins — no Brewfile additions required.
- The tmux change ships via the already-symlinked `tmux.conf`.

## State lifecycle

1. Agent event fires → hook → `agent-notify` sets `@notify_state` on the window +
   sound + banner.
2. Window shows red/blink (approval) or green/steady (complete) in the status bar.
3. User switches to that window → `after-select-window` hook clears `@notify_state` →
   highlight returns to normal.
4. Later events overwrite the state (latest wins; approval during a run, complete at
   end is the normal sequence).

## Error handling & edge cases

- **No tmux** (`$TMUX` unset): skip the tmux action; still play sound + banner.
- **Hook must never block or fail the agent:** `afplay` backgrounded; script returns 0.
- **Already-focused window:** state still set; clears on next select. (Optional later
  refinement: suppress in-tmux highlight if the target pane is the active pane of the
  attached client. Not in MVP.)
- **Multi-pane windows:** state is per-window (status bar colors windows, not panes).
  Acceptable.

## Risks / to verify during implementation

1. **Ghostty `#[blink]` rendering** in the tmux status line. If Ghostty doesn't render
   the blink SGR there, fall back to `bold` + `reverse`, or a lightweight background
   toggler. Decide during build; do not block the rest.
2. **tokyo-night-tmux format injection.** The plugin owns `window-status-format`. Confirm
   whether overriding it post-`run` sticks, or whether the theme re-applies via its own
   hook. Fallback: prepend a colored/blinking indicator glyph rather than restyling the
   whole entry.
3. **cursor `beforeShellExecution` output schema** — confirm exact JSON keys for the
   allow/ask decision.

## Testing plan

- **Unit-ish, manual:** in a tmux pane, run `agent-notify approval claude` → verify
  red/blink window highlight + Sosumi + banner; switch to the window → verify it clears.
  Repeat `agent-notify complete claude` → green/steady + Glass + banner.
- **No-tmux:** run outside tmux → verify sound + banner, no error.
- **Claude end-to-end:** trigger a real permission prompt (approval) and a real response
  end (complete); verify each fires the right notification.
- **Cursor end-to-end:** `stop` on a completed run → complete notification; run a
  denylisted command → ask prompt + approval notification; run an allow-listed command →
  no notification.
- **Idempotent install:** run `install` twice → verify `~/.claude/settings.json` keeps
  all prior keys and the hooks block is present exactly once.

## Rollback

- Revert `tmux.conf` (restore `monitor-activity on`, remove the format override + hook).
- Remove the `hooks` block from `~/.claude/settings.json` and delete `~/.cursor/hooks.json`.
- Remove the `agent-notify` symlink and `bin/agent-notify`.
All changes are additive and individually reversible.
