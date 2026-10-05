# Existing contracts used by this client

Source of truth: sibling `typeflux-api` and `realtime-asr` repositories.

- Auth: `/api/v1/auth/{register,activate,resend-activation,login,refresh,logout,
  forgot-password,reset-password,change-password}` and `/api/v1/me`.
  Successful responses use `{code:"OK",data:...}`; token expiry is Unix seconds.
- Ask: `/api/v1/ask/conversations`, `/models`, `/:id`, `/:id/messages`,
  `/:id/cancel`, `/:id/regenerate`, and `/:id/events`.
  Sends contain UUID conversation/message/device identities and `tools: []`.
  Models use `cloud:<catalog-id>` references. Headers include
  `X-Typeflux-Model-Catalog: 1` and `X-Scenario: ask-anything`.
- SSE: named `snapshot`, `progress`, `unavailable` frames. Progress merges with
  existing messages. Older revisions are ignored; equal revisions may contain
  late usage updates. Server connections expire around 30 seconds. Reconnect
  retrieves current state, never replays tool execution or resends a prompt.
- ASR: core API `/api/v1/asr/token` returns a short-lived token and allowed server
  origins. The app maps HTTPS to WSS and connects to `/api/v1/asr/ws/default`.
  Start config specifies PCM/16000 Hz/mono and realtime input, followed by binary
  audio and a stop message. `partial` is provisional; sentence finals append;
  `meta.authoritative` replaces the whole transcript. The server closes after
  draining final results. A timeout is not treated as successful completion.

Reference files:

- `typeflux-api/internal/transport/http/dto/auth.go`
- `typeflux-api/internal/transport/http/handler/ask_events.go`
- `typeflux-api/internal/ask/model.go`, `attachments.go`, `STREAMING.md`
- `realtime-asr/internal/ws/asr_ws.go`, `internal/asr/types.go`

Contract tests use synthetic values only. No live account has been used yet.

## Approved account flow

- Registration sends email/password; activation sends email and a six-digit code.
  Activation is valid for 15 minutes. Resending includes email/password, with a
  60-second cooldown. Activation success is retained if subsequent login fails.
- Forgotten-password acknowledgement does not reveal account existence. Reset
  sends email/code/new_password, with a 30-minute code validity. The UI also
  applies a 60-second resend throttle and returns to login after success.
- Password validation requires 8+ characters, uppercase, lowercase and digits,
  with Unicode character classes matching the backend validation.
- Password changes send old_password when the account has password credentials.
  `/me` provider/providers indicates this; missing metadata is treated
  conservatively. Password change/reset revokes refresh tokens, so the client
  returns to login rather than assuming immediate invalidation of all access tokens.
- Only token-related 401 codes trigger refresh/replay; a wrong current password
  (`AUTH_INVALID_CREDENTIALS`) is displayed without repeating the mutation.
- Origin-scoped session writes and rollback are serialized. A canceled or failed
  login handoff must not overwrite or delete a newer session.

## Mobile v3 additions

- Model picker consumes public catalog `capabilities.reasoning`,
  `reasoning_efforts`, `vision`, `context_window_tokens`, `max_output_tokens`
  and `pricing.multiplier`; unsupported/unknown metadata is not invented.
- Automatic effort omits `reasoning_effort`. Changing models chooses the nearest
  supported effort, preferring the lower level on ties. Regenerate follows the
  server contract and inherits effort from the original question.
- Active runs accept `POST /ask/conversations/:id/steer` with the durable message
  ID and original run ID. Accepted steering is a receipt even before it appears
  in `messages`. A 409 triggers a receipt check; only an ended run with no receipt
  may move the same ID to a normal message request. Device-only models are kept
  as explicitly local drafts instead of starting unsupported inference.
- Account-scoped cache preserves accepted unread steering across cancellation,
  server queue cleanup, conversation changes and restart. Once the same ID is
  in `messages`, the local queued copy is removed. Logout clears local copies.
- Assistant usage comes from `conversation.usage.runs[run_id]`; pending, missing,
  estimated or external counts prevent a misleading finalized cost display.
- Tool projections read messages/results and live preview metadata only. They
  never execute a tool or interpret the model's prose as an authorization.
