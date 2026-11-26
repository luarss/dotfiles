# Transform canonical file-permissions.json into tool-specific configurations.
# Supports being imported as a library or executed directly:
#   jq -n --arg home "$HOME" --argjson perms "$(<file-permissions.json)" --arg target <claude|agy_cli|antigravity_desktop> -f gen-permissions.jq

def claude_permissions($p):
  {
    permissions: (
      {
        deny: (
          (($p.deny.commands // []) | map("Bash(\(.))"))
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

# Antigravity's terminal sandbox (Seatbelt/nsjail) compiles every read_file /
# write_file grant into OS mount/deny rules and rejects:
#   1. Non-absolute paths ("non-absolute file path" — incl. relative `.env` and unexpanded `~`)
#   2. Wildcard globs ("globs not supported" — `*`, `?`, `[`)
# Directory targets match recursively in Antigravity, so trailing `/*` or `/**`
# collapses to the parent directory; `~` expands to $home; remaining relative or
# glob patterns (covered in repos by allowAgentAccessGitignoreFiles: false) are omitted.
def agy_paths($home):
  (($home // "") | sub("/+$"; "")) as $h
  | map(
      sub("/\\*\\*?$"; "")
      | if $h != "" then
          if . == "~" then $h
          elif startswith("~/") then ($h + .[1:])
          else . end
        else . end
      | select(startswith("/") and (test("[*?\\[]") | not))
    )
  | reduce .[] as $p ([]; if index($p) then . else . + [$p] end);

def agy_rules($p; $home):
  {
    deny: (
      (($p.deny.commands // []) | map("command(\(sub(":\\*$"; "")))"))
      + (((($p.deny.files // []) + ($p.deny.agy_files // [])) | agy_paths($home)) | map("read_file(\(.))"))
    )
  }
  + (
      (
        (($p.allow.commands // []) | map("command(\(sub(":\\*$"; "")))"))
        + (((($p.allow.files // []) + ($p.allow.agy_files // [])) | agy_paths($home)) | map("read_file(\(.))"))
        + ((($p.allow.agy_write_files // []) | agy_paths($home)) | map("write_file(\(.))"))
      ) as $allow
      | if ($allow | length) > 0 then { allow: $allow } else {} end
    );

def agy_rules($p):
  agy_rules($p; ($ARGS.named.home // env.HOME // ""));

def agy_cli_permissions($p; $home):
  { permissions: agy_rules($p; $home) }
  + ($p.gitignoreAccess // {});

def agy_cli_permissions($p):
  agy_cli_permissions($p; ($ARGS.named.home // env.HOME // ""));

def antigravity_desktop_grants($p; $home):
  {
    userSettings: {
      globalPermissionGrants: agy_rules($p; $home)
    }
  };

def antigravity_desktop_grants($p):
  antigravity_desktop_grants($p; ($ARGS.named.home // env.HOME // ""));

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
