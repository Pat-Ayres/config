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

# Plant a fake `tmux`: window_active answer is controllable via
# $FAKE_WINDOW_ACTIVE; set-option and everything else are no-ops.
_fake_tmux() {
  { echo '#!/usr/bin/env bash'
    echo 'case "$1" in'
    echo '  display-message) echo "${FAKE_WINDOW_ACTIVE:-0}" ;;'
    echo '  *) : ;;'
    echo 'esac'
    echo 'exit 0'
  } > "$FAKEBIN/tmux"
  chmod +x "$FAKEBIN/tmux"
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

@test "suppressed entirely when target window is on-screen (active)" {
  _force_uname Darwin
  _fake_tmux
  export TMUX="/tmp/fake,1,0" TMUX_PANE="%1" FAKE_WINDOW_ACTIVE=1
  run "$BIN" complete claude
  [ "$status" -eq 0 ]
  sleep 0.2
  [ ! -s "$LOG" ]   # no sound, no banner about a window you're looking at
}

@test "fires normally when target window is off-screen (inactive)" {
  _force_uname Darwin
  _fake_tmux
  export TMUX="/tmp/fake,1,0" TMUX_PANE="%1" FAKE_WINDOW_ACTIVE=0
  run "$BIN" complete claude
  [ "$status" -eq 0 ]
  sleep 0.2
  grep -q "afplay .*Glass.aiff" "$LOG"
  grep -q "osascript .*Done" "$LOG"
}
