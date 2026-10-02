{ pkgs, ... }:
{
  home-manager.users.payres.home.activation.importRectangleConfig = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      # RectangleConfig.json is Rectangle's own Export-button format, NOT a
      # real plist — every value is wrapped in a type tag (e.g. {"bool":
      # true}), and it splits keys into "defaults"/"shortcuts" objects that
      # don't exist in the actual preference domain (confirmed via `defaults
      # read com.knollsoft.Rectangle` — shortcuts are flat top-level keys
      # like any other pref, e.g. `bottomLeft = { keyCode = 38; ... }`).
      # `defaults import` only understands real plists, so: flatten +
      # unwrap the type tags with jq, convert that to a real plist with
      # plutil, then import.
      ${pkgs.jq}/bin/jq '
        (.defaults | with_entries(select(.value != {}) | .value = (.value | to_entries[0].value)))
        * .shortcuts
      ' ${../../macos/RectangleConfig.json} \
        | /usr/bin/plutil -convert xml1 -o - - \
        | /usr/bin/defaults import com.knollsoft.Rectangle -
    '';
  };
}
