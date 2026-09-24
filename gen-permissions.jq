# Transform canonical file-permissions.json into tool-specific configurations.
# Supports being imported as a library or executed directly:
#   jq -n --argjson perms "$(<file-permissions.json)" --arg target <claude|agy_cli|antigravity_desktop> -f gen-permissions.jq

def claude_permissions($p):
  {
    permissions: (
      {
        deny: (
          (($p.deny.commands // []) | map("Bash(\(.))"))
          + (($p.deny.claude_rtk // []) | map("Bash(rtk " + . + ")"))
          + (($p.deny.files // []) | map("Read(\(.))"))
        ),
        defaultMode: "default"
      }
      + (if (($p.allow.commands // []) + ($p.allow.files // [])) | length > 0 then
          {
            allow: (
              (($p.allow.commands // []) | map("Bash(\(.))"))
              + (($p.allow.files // []) | map("Read(\(.))"))
            )
          }
         else {} end)
    )
  }
  + (if ($p.ignorePatterns // []) | length > 0 then
      { ignorePatterns: $p.ignorePatterns }
     else {} end);

def agy_cli_permissions($p):
  {
    permissions: (
      {
        deny: (
          (($p.deny.commands // []) | map("command(\(sub(":\\*$"; "")))"))
          + (($p.deny.files // []) | map("read_file(\(.))"))
        )
      }
      + (if (($p.allow.commands // []) + ($p.allow.files // [])) | length > 0 then
          {
            allow: (
              (($p.allow.commands // []) | map("command(\(sub(":\\*$"; "")))"))
              + (($p.allow.files // []) | map("read_file(\(.))"))
            )
          }
         else {} end)
    )
  }
  + ($p.gitignoreAccess // {});

def antigravity_desktop_grants($p):
  {
    userSettings: {
      globalPermissionGrants: (
        {
          deny: (
            (($p.deny.commands // []) | map("command(\(sub(":\\*$"; "")))"))
            + (($p.deny.files // []) | map("read_file(\(.))"))
          )
        }
        + (if (($p.allow.commands // []) + ($p.allow.files // [])) | length > 0 then
            {
              allow: (
                (($p.allow.commands // []) | map("command(\(sub(":\\*$"; "")))"))
                + (($p.allow.files // []) | map("read_file(\(.))"))
              )
            }
           else {} end)
      )
    }
  };

# If executed directly with $target and $perms:
if $target == "claude" then
  claude_permissions($perms // .)
elif $target == "agy_cli" then
  agy_cli_permissions($perms // .)
elif $target == "antigravity_desktop" then
  antigravity_desktop_grants($perms // .)
else
  empty
end
