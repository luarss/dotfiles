# Grok Bot Inference Hook — Cloud Run Handoff Spec

Status: **spec only, not implemented**. Source: https://docs.x.ai/grok-bot/inference-hooks (fetched 2026-11-04).

## 1. Goal

Before each Grok Bot model call, decide **allow** or **deny** for the conversation. This works alongside the local `grok/hooks/identity-guard.sh` (`PreToolUse`) and covers what it can't see. The identity guard runs on the receiving Mac and gates tool execution. The inference hook runs centrally and gates the *next model call* across every Mac signed in to the shared `NUSXGrok` account.

What it can't do: a deny stops the next model call. It does **not** undo actions that already ran. Keep tool-level guards as the main control, and treat this hook as defense in depth plus an audit trail.

## 2. Platform contract (from xAI docs)

### Request

- `POST` over HTTPS with a JSON body. Header names are lowercase, and `user-agent: cursor-inference-hooks/1`.
- One frame per model call. Each frame holds the **full conversation so far**, not a delta.
- The frame does **not** include model responses, system prompts, tool definitions or reasoning.

```json
{
  "type": "prompt",
  "request_id": "req_6b1f0c2e-4d7a-4f1e-9a53-2c8d7e41b9a0",
  "tenant_id": "team_4mQvT8yLcN2pR6",
  "actor": { "type": "user", "id": "user_8hJw3KzP5sXq1V7nB2cF9mD4tR", "email_address": null },
  "source": { "application": "grok-bot" },
  "session_id": "3f2c9a71-58e4-4b0d-9c6a-0d1e7b25a4f8",
  "model": "<model identifier>",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "..." },
        { "type": "attachment", "file_name": null, "media_type": "image/png", "size_bytes": 184320, "text": null }
      ]
    }
  ],
  "metadata": {}
}
```

- `type` is always `prompt`, and `metadata` is always `{}`.
- `actor.email_address` is always `null`, and `actor.id` is opaque.
- `source.application` is `grok-bot`, or `config-test` for a Test Connection frame.
- Roles are `user` and `assistant`.
- Block types are `text`, `tool_use`, `tool_result` and `attachment`.
- The docs give no field list for `tool_use` or `tool_result`. Prose describes a tool name plus `input`, an output, and `is_error`, which is unreliable (usually `false` even when the call failed). **Parse these blocks defensively**: walk every string value instead of depending on exact field names, and capture a real frame during Shadow mode to confirm the shape.

### Signing (Standard Webhooks)

- `webhook-id` holds the `request_id`, and `webhook-timestamp` holds Unix seconds.
- `webhook-signature` is `v1,<base64(HMAC-SHA256(key, "{id}.{timestamp}.{raw_body}"))>`, with exactly one signature.
- The signing secret looks like `whsec_<base64>`. Base64-decode the part after `whsec_` to get the HMAC key.
- Verify against the **raw bytes** of the body before parsing it, and compare in constant time.
- The docs give no timestamp tolerance. Use **±300 s**.

### Verdict

Respond with HTTP **200** and a JSON body:

```json
{ "action": "deny", "deny_reason": "…", "reference_id": "policy-7f3c21" }
```

- `action` must be `allow` or `deny`. Any other value counts as a failure.
- `deny_reason` is shown to the member and truncated at 500 characters.
- `reference_id` is optional and limited to 50 characters from `[A-Za-z0-9._:/-]`. A malformed value is dropped, but the deny still applies.
- Unknown fields are ignored, and only the first 64 KiB of the response is read.

### Failure modes, set in the admin console

| Mode | On deny | On failure (timeout, non-200, bad body, unreachable) |
|---|---|---|
| Shadow (default) | allowed, logged only | allowed |
| Allow | blocked | allowed (fails open) |
| Block | blocked | blocked (fails closed) |

- The verdict timeout can be 1–10,000 ms and defaults to 5,000 ms. It covers the whole exchange.
- On connection failure the platform retries **once**, with the same `webhook-id` and signature. The handler must therefore be **deterministic per request**: the same frame must always produce the same verdict.
- A circuit breaker trips on sustained failures. Automatic recovery tries again after 10 minutes, but any settings change disables automatic recovery.

### Endpoint constraints

- `https://` on port 443 only, with a public CA certificate.
- No redirects, no reverse tunnels, and no credentials, query string or fragment in the URL. The URL can be at most 2,048 characters.
- Up to 16 custom headers, stored encrypted and write-only.

## 3. Deployment (Cloud Run)

| Item | Value |
|---|---|
| GCP project | `nusx-enterprise` (same project as the Twingate tokens in `office-mac/init.sh`) |
| Region | `asia-southeast1` |
| Service name | `grok-inference-hook` |
| Ingress | `all`, with `--allow-unauthenticated`. The platform can't send Google IAM tokens, so the **HMAC signature is the authentication**. |
| URL | Default `https://grok-inference-hook-<hash>-as.a.run.app`. This already meets the public CA, port 443 and no-redirect rules. A custom domain is optional. |
| Runtime service account | `grok-inference-hook@nusx-enterprise.iam.gserviceaccount.com`, with only `roles/secretmanager.secretAccessor` on the one signing secret and `roles/logging.logWriter`. |
| Signing secret | Secret Manager secret `grok-inference-hook-signing-secret`, mounted as env var `GROK_HOOK_SIGNING_SECRET` (pinned version, not `latest`). It is generated in the Grok Bot console and pasted into Secret Manager, and it is never committed. |
| Scaling | `--min-instances=1` so a cold start can't use up the timeout. `--max-instances=10`. `--concurrency=80`. `--cpu=1 --memory=256Mi`. |
| Request timeout | Cloud Run `--timeout=10s`. The handler budget is **< 500 ms p99**, and the console verdict timeout is **3,000 ms**. |
| Image | Distroless or slim base, **pinned by digest** (`@sha256:…`). App dependencies use exact versions with a lockfile (see AGENTS.md "Dependency Locking"). Built in Cloud Build and stored in Artifact Registry `asia-southeast1-docker.pkg.dev/nusx-enterprise/grok/inference-hook`. |
| Custom headers | Optional: one static `x-nusx-hook-key` checked as a second factor. Not required. |

The deploy script lives at `grok/inference-hook/deploy.sh`. It must be idempotent and use `gcloud run deploy … --image=<digest>`. Like `office-mac/`, it is run by hand and is **not** called from `install.sh`.

## 4. Handler behaviour

Order of operations:

1. Accept only `POST /`, and only when the request body is ≤ **2 MiB**. Return 404 for other methods or paths, and 413 for a body over the limit.
2. Verify the timestamp skew and the signature. On failure return **401** and log `reason=bad_signature`. Never return `allow` for an unsigned request.
3. Parse the JSON. If it is malformed return **400**. In Allow mode that fails open, which is acceptable, and it is logged.
4. If `source.application == "config-test"`, return `{"action":"allow","reference_id":"nusx-hook:config-test"}`.
5. Run the policy rules (§5) over **every** message, newest first, and stop at the first deny.
6. Return 200 with the verdict. Set `reference_id` to `nusx-hook:<rule_id>:<short hash of request_id>`, which fits the 50-character limit.

Internal errors after signature verification return **500**. Those count as failures, so the console mode decides the outcome. The handler must not invent a deny.

## 5. Policy rules (v1)

Each rule has an id, a matcher, and a `deny_reason` that tells the member how to fix the problem. The rules mirror the existing local guards so the policy stays the same everywhere.

| id | Source of truth | Matches | Scope |
|---|---|---|---|
| `grok-self-modify` | `identity-guard.sh` (`.grok` deny) | Any `tool_use` input that references `.grok/` (hooks, `armed`). Stops a prompt-injected bot from re-arming itself through another Mac. | `tool_use` |
| `destructive-sql` | `.claude/hooks/db-guard.sh` | `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `DELETE` without `WHERE`, `ALTER TABLE … DROP` | `tool_use` |
| `destructive-rm` | `file-permissions.json` command deny list | Patterns from the deny list such as `rm -rf /` and `rm -rf ~` | `tool_use` |
| `protected-file-read` | `file-permissions.json` deny file globs | Tool input that reads `.env*`, `~/.ssh/*`, `~/.aws/*`, gcloud credentials, `*.pem`/`*.key`, `~/.my.cnf`, shell history | `tool_use` |
| `secret-leak` | new | Private key headers (`-----BEGIN … PRIVATE KEY-----`), `whsec_…`, AWS access key IDs (`AKIA[0-9A-Z]{16}`), GCP service-account JSON (`"type": "service_account"` + `private_key`), GitHub tokens (`gh[pousr]_…`), Twingate tokens | `text`, `tool_result`, attachment `text` |

Implementation notes:

- **Generate** the protected-file and rm patterns at build time from `file-permissions.json` (reuse `gen-permissions.jq` with a new `inference-hook` target that writes `policy.json` into the image). Don't hand-copy them, because the file must stay the single source of truth.
- Use regex matchers only, with no LLM classifier in v1, so verdicts stay deterministic, fast, and identical on retry.
- `deny_reason` must not echo the matched secret or path back to the member.

## 6. Logging and privacy

- Log one structured line per request to Cloud Logging. Include `request_id`, `session_id`, `actor.id`, `source.application`, `verdict`, `rule_id`, `latency_ms`, the message count, and `mode_hint` if a custom header provides one.
- **Never** log message content, tool inputs or outputs, the matched text, or the deny reason. That matches the platform's own audit rule ("identifiers and codes only").
- Set log retention to 30 days on a dedicated bucket.

## 7. Tests (must pass before deploy)

- Signature tests:
  - A valid signature passes.
  - An altered body, wrong key, missing header, `v2,` prefix, or skew over 300 s each return 401.
  - The `whsec_` prefix is stripped and the rest base64-decoded.
- Verdict shape tests:
  - `action` is in {allow, deny}.
  - `deny_reason` is ≤ 500 characters.
  - `reference_id` matches `^[A-Za-z0-9._:/-]{1,50}$`.
  - The response body is ≤ 64 KiB.
- Each rule has at least one positive and one negative fixture, including a `tool_use` block nested in an earlier assistant turn.
- Determinism: the same frame sent twice gives byte-identical verdicts.
- A `config-test` frame is allowed.
- The p99 latency budget holds on a 2 MiB, 200-message frame.
- A generated-policy test fails if `policy.json` drifts from `file-permissions.json`.

## 8. Rollout

1. Deploy. In the console, generate a signing secret, store it in Secret Manager, and redeploy with the new secret version.
2. Run **Test Connection** and expect `allow` with `config-test`.
3. Run **Shadow** mode at 100 % rollout for 1 week. Review the would-deny log lines for false positives, and capture a real `tool_use`/`tool_result` frame to confirm the block shapes (§2).
4. Switch to **Allow** mode (fails open), with the verdict timeout at 3,000 ms.
5. Consider **Block** mode only after 2 weeks without circuit-breaker trips. After any settings change, re-check the breaker by hand, because a change disables automatic recovery.

## 9. Open questions for the implementer

- Language: Python or Go. Both have Standard Webhooks libraries, but hand-rolled HMAC verification is about 15 lines and avoids adding a dependency.
- Should the deny list differ between office and non-office actors? `actor.id` is opaque and every Mac shares the `NUSXGrok` account, so the hook can't tell machines apart today. v1 applies one global policy.
- Alerting: add a log-based metric and alert on `verdict=deny`, and on a 5xx rate above 1 %.
