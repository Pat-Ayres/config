{ config, lib, pkgs, ... }:
let
  homeDir = config.home.homeDirectory;
  agentNotify = "${homeDir}/.local/bin/agent-notify";
  cursorShellGate = "${homeDir}/.local/bin/cursor-shell-gate";

  cursorHooks = {
    version = 1;
    hooks = {
      beforeShellExecution = [ { command = cursorShellGate; } ];
      beforeMCPExecution = [ { command = cursorShellGate; } ];
      stop = [
        {
          command = "sh -c 'test \"$(jq -r .status)\" = completed && ${agentNotify} complete cursor || true'";
        }
      ];
    };
  };
in
{
  home.file.".cursor/hooks.json".source =
    (pkgs.formats.json { }).generate "cursor-hooks.json" cursorHooks;

  home.activation.mergeClaudeHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="${homeDir}/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || echo '{}' > "$settings"
    tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq \
      --arg notif "${agentNotify} approval claude" \
      --arg stop  "${agentNotify} complete claude" \
      '.hooks = (.hooks // {})
       | .hooks.Notification = [ { "hooks": [ { "type": "command", "command": $notif } ] } ]
       | .hooks.Stop         = [ { "hooks": [ { "type": "command", "command": $stop  } ] } ]' \
      "$settings" > "$tmp" && mv "$tmp" "$settings"
  '';
}
