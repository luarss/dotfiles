# Generate a profile's settings.json from the shared base + a provider entry.
# Inputs (all via --argjson/--arg):
#   $base  : contents of settings.base.json
#   $p     : the provider's entry from providers.json
#   $token : the auth-token value (may be empty string)
#
# Layering: base  *  provider env additions  *  freeform overrides.

def models_env($m):
  if $m == null then {}
  elif ($m | type) == "string" then {
    "ANTHROPIC_MODEL": $m,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": $m,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": $m,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": $m
  }
  else
    (if $m.default then { "ANTHROPIC_MODEL": $m.default } else {} end)
    + (if $m.haiku  then { "ANTHROPIC_DEFAULT_HAIKU_MODEL":  $m.haiku  } else {} end)
    + (if $m.sonnet then { "ANTHROPIC_DEFAULT_SONNET_MODEL": $m.sonnet } else {} end)
    + (if $m.opus   then { "ANTHROPIC_DEFAULT_OPUS_MODEL":   $m.opus   } else {} end)
  end;

$base
* { env:
    ( (if $p.token then { "ANTHROPIC_AUTH_TOKEN": $token } else {} end)
      + (if $p.thirdParty then {
           "ANTHROPIC_BASE_URL": $p.baseUrl,
           "API_TIMEOUT_MS": "3000000",
           "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
           "DISABLE_TELEMETRY": "1",
           "CLAUDE_CODE_ENABLE_TELEMETRY": "0",
           "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1"
         } else {} end)
      + models_env($p.models // null)
    )
  }
* ($p.overrides // {})
