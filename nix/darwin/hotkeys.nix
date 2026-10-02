{ ... }:
let
  standard = enabled: parameters: {
    inherit enabled;
    value = {
      inherit parameters;
      type = "standard";
    };
  };
in
{
  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
    "32" = standard true [ 32 49 1048576 ];
    "34" = standard true [ 32 49 1179648 ];
    "60" = standard false [ 32 49 262144 ];
    "64" = standard true [ 65535 44 1048576 ];
    "79" = standard true [ 104 4 1310720 ];
    "80" = standard true [ 104 4 1441792 ];
    "81" = standard true [ 108 37 1310720 ];
    "82" = standard true [ 108 37 1441792 ];
  };
}
