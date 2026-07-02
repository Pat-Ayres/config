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
- Work on **both macOS (work) and Linux/CachyOS (personal)** from the same repo.
- Manage cleanly in the dotfiles repo without clobbering existing/enterprise settings.

## Platform support

Targets: **macOS** and **Linux (CachyOS — Arch-based, PipeWire, libnotify)**. Windows is
out of scope. The tmux layer is portable as-is. Only two actions are platform-specific —
**audio** and **the desktop banner** — so the dispatcher isolates them behind two shell
functions (`play_sound`, `send_banner`) that branch on `uname -s`. Everything else is
shared.

| Action | macOS | Linux (CachyOS) |
|---|---|---|
| play sound | `afplay <file>` | `pw-play` → `paplay` → `canberra-gtk-play -i <id>` (first available) |
| desktop banner | `osascript -e 'display notification …'` | `notify-send -u <urgency> -a <app> <title> <body>` |
| dep manager | Homebrew (`Brewfile`) | pacman (documented; soft runtime check) |

## Non-goals

- No routing notifications *through* Ghostty (OSC 9/777 + tmux passthrough). Hooks are
  shell scripts with full system access, so they act directly via the platform's own
  tools (`afplay`/`osascript` on macOS, `pw-play`/`notify-send` on Linux, `tmux` on
  both). Ghostty stays a passive display surface.
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
- **Structure:** a shared entry point plus two platform-branched helpers,
  `play_sound <event>` and `send_banner <event> <app>`, selected once via `uname -s`.
- **Behavior:**
  1. **tmux visual** (portable) — if `$TMUX` is set:
     `tmux set-option -w -t "$TMUX_PANE" @notify_state "$event"`
     (`-w` sets the window *containing* that pane).
     If `$TMUX` is unset, skip silently.
  2. **audio** (`play_sound`, backgrounded so the hook never blocks):
     - **macOS:** `afplay "<sound-for-event>" &`
     - **Linux:** first available of `pw-play` / `paplay` (on a sound file) or
       `canberra-gtk-play -i "<event-sound-id>"` (freedesktop theme lookup). If none
       present, skip audio silently.
  3. **OS banner** (`send_banner`):
     - **macOS:** `osascript -e 'display notification …'` with a per-event title.
     - **Linux:** `notify-send -a "<app>" -u <urgency> "<title>" "<body>"`
       (`-u critical` for approval so it persists until dismissed; `-u normal` for
       complete). If `notify-send` is absent, skip banner silently.
- **Failure policy:** each action is independent and best-effort; a missing `$TMUX` or a
  failed `afplay` must not abort the others and must not return non-zero to the caller
  (a failing hook must never wedge the agent). Let real errors surface in logs, but do
  not swallow-with-`or {}` in a way that hides a broken install — see Testing.

### Component 2 — Sensory mapping

| Event | tmux color | Motion | macOS sound | Linux sound (freedesktop id) | Banner title | Linux urgency |
|---|---|---|---|---|---|---|
| **approval** | red / orange | blink | `Sosumi` (sharp) | `dialog-warning` | `🔴 Needs approval — <app>` | `critical` |
| **complete** | green | steady | `Glass` (soft) | `complete` | `✅ Done — <app>` | `normal` |

**Sound strategy — per-OS native (chosen).** macOS uses its system sounds
(`/System/Library/Sounds/<name>.aiff`); Linux uses freedesktop theme sounds
(`/usr/share/sounds/freedesktop/stereo/<id>.oga`, or by id via `canberra-gtk-play -i`).
The exact *timbre* differs between machines, but the **semantic contrast is preserved**
on each: sharp/urgent for approval, soft for complete. This avoids shipping binary audio
in the repo and depending on a sound theme being present cross-platform.

  *Alternative considered:* ship two identical WAV files in `sounds/` and play them on
  both OSes for byte-identical sound everywhere. Rejected for MVP (adds binaries, and
  identical cross-machine timbre isn't a stated requirement). Easy to switch to later —
  only `play_sound` changes.

Colors, sound names/ids, and urgencies are single-line constants in the script,
trivially editable per platform.

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
  (creating `~/.local/bin` if needed). Portable across both OSes.
- Add an idempotent **`jq` merge** step (new function in `install`) that injects the
  notify `hooks` block into `~/.claude/settings.json`, preserving all existing keys, and
  creates/merges `~/.cursor/hooks.json`. Re-running `install` re-merges without
  duplicating. `jq` itself is the only hard install-time dependency.
- **Dependencies by platform:**
  - **macOS:** `osascript` + `afplay` are built in; only `jq` is needed (add to
    `macos/Brewfile` if not already present).
  - **Linux/CachyOS:** needs `jq`, `libnotify` (`notify-send`), and a PipeWire/Pulse
    player (`pipewire`/`pipewire-pulse` provide `pw-play`/`paplay`; `libcanberra`
    provides `canberra-gtk-play`). Document the pacman package names; the existing
    `detect_os` already branches, so add a `linux_setup()` that **checks** for these and
    prints a warning if missing (non-invasive — no auto `sudo pacman`). The dispatcher
    also degrades gracefully at runtime if a tool is absent.
- The tmux change ships via the already-symlinked `tmux.conf` (portable).

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
4. **Linux (CachyOS) tooling** — confirm on the actual machine which audio player is
   present/works (`pw-play` vs `paplay` vs `canberra-gtk-play`), that the freedesktop
   `dialog-warning`/`complete` sounds resolve, and that the notification daemon honors
   `-u critical` (persist-until-dismissed) under the running desktop environment. This
   Mac can't verify the Linux path — it's checked when installing on CachyOS.

## Testing plan

- **Unit-ish, manual:** in a tmux pane, run `agent-notify approval claude` → verify
  red/blink window highlight + Sosumi + banner; switch to the window → verify it clears.
  Repeat `agent-notify complete claude` → green/steady + Glass + banner.
- **No-tmux:** run outside tmux → verify sound + banner, no error.
- **Cross-platform:** run the same manual checks on CachyOS → verify `notify-send`
  banner (approval persists under `critical`, complete auto-expires) and the selected
  audio player fires; verify graceful skip if a tool is missing.
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

---

## Addendum (2026-07-02) — changes from the original design

Live verification on macOS changed several decisions above. The body of this
document is the original design; this addendum records what actually shipped.

1. **Palette is colorblind-safe, not red/green.** The user is red-green
   colorblind, for which red (approval) / green (complete) is the worst possible
   pairing. Shipped palette: **approval = orange, complete = cyan** — a pair that
   stays distinguishable across the common colorblindness types.

2. **No blink; a symbol marker carries urgency instead.** A blinking status entry
   rendered steady in testing. The root cause was not isolated — it could be
   Ghostty, tmux, or config — so rather than chase it or fall back to `reverse`,
   the design simply does not depend on blink. Each state shows a **symbol** —
   `‼` for approval, `✓` for complete — so it reads without depending on hue or
   motion, which also matters for the colorblindness.

3. **On-screen notifications are fully suppressed.** The "Error handling" note
   called active-pane suppression an optional non-MVP refinement; live use proved
   it essential (the `Stop` hook fired a chime + banner on every turn while the
   user was watching the agent window). `agent-notify` now exits early — no state,
   sound, or banner — when its target pane's window is the **active window of its
   session** (`#{window_active}`). Notifications still fire for a window the user
   has switched away from.
   - **Known limitation:** this is tmux-window-based. If the terminal app itself
     is unfocused (user switched to another macOS app) while the agent's window
     is still the active tmux window, the notification is suppressed — tmux cannot
     observe terminal-app focus. Acceptable for a window-switching workflow.

4. **Cursor ask-list uses word-boundary matching.** The gate matches ask-patterns
   at a left word boundary (start-of-string or a non-alphanumeric char), not raw
   substring, so benign commands that merely contain a pattern (`xterm` → `rm `,
   `add data` → `dd `) do not trigger a false `ask`.

5. **Cursor `stop` hook always exits 0** (`... && notify || true`), honoring the
   best-effort constraint even when status is `aborted`/`error`. Cursor's hook
   schema (Risk #3) was verified against the docs: stdin `.command`, output
   `{"permission":"allow"|"ask"}`, stop `.status` — all match.

6. **Theme prerequisite.** `tokyo-night-tmux` was declared in `tmux.conf` but had
   never been fetched on this machine (TPM only installs on `prefix + I`), so the
   status bar fell back to tmux's default green. Installing the plugin is a
   prerequisite for the intended appearance. Its right-side widgets default OFF;
   `datetime` and `battery` are now enabled explicitly, and
   `@tokyo-night-tmux_transparent 0` is set to silence a stderr warning.
