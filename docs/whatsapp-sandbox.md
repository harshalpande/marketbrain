# WhatsApp Cloud API sandbox boundary

## Purpose

MarketBrain may mirror controlled notifications through Meta's automatically provided `+1` WhatsApp test number.
The sandbox can mirror the exact system-notification text sent to Telegram, but Meta's conversation-window rules mean
it is not yet a dependable out-of-window production notification path.

The sandbox can be used to verify:

- outbound template delivery to the owner's verified test-recipient number;
- Meta webhook verification and signed delivery callbacks;
- interactive button callback parsing;
- duplicate-delivery protection and audit evidence.
- independently idempotent mirroring of daily data, daily feature, and connectivity system notes.

It cannot create a signal, paper fill, broker order, or live trading action. A non-expiring System User token removes
routine token renewal but does not remove Meta's 24-hour free-form conversation restriction.

## Security boundary

Only the following application route may later be exposed through the reviewed public HTTPS ingress:

```text
GET  /api/v1/whatsapp/webhook
POST /api/v1/whatsapp/webhook
```

Two content-only public information routes support Meta's app transparency requirements:

```text
GET  /api/v1/whatsapp/privacy
GET  /api/v1/whatsapp/data-deletion
```

They perform no database access, accept no request content, load no third-party scripts, and expose no credentials or
runtime configuration. The Cloudflare tunnel must route only these two paths and the webhook path; the service root
and every unrelated API path remain private.

The `GET` route performs Meta's one-time verify-token challenge. The `POST` route verifies
`X-Hub-Signature-256` against the Meta App Secret before parsing the exact raw request bytes. It then requires the
configured WABA ID, phone-number ID, and personal recipient `wa_id`. Enter `wa_id` as country-code plus number,
using digits only and no `+`, spaces, or punctuation.

The database stores only keyed hashes of event identifiers and provider metadata for idempotency. It deliberately does not
store raw JSON, message text, telephone numbers, Meta IDs, access tokens, App Secrets, verify tokens, or raw button
payloads.

## Local-only configuration

Real values belong only in the spare laptop's ignored `.env` file:

```dotenv
MARKETBRAIN_WHATSAPP_ENABLED=false
MARKETBRAIN_WHATSAPP_SANDBOX_MODE=true
MARKETBRAIN_WHATSAPP_TEST_ALERTS_ENABLED=false
MARKETBRAIN_WHATSAPP_GRAPH_VERSION=
MARKETBRAIN_WHATSAPP_PHONE_NUMBER_ID=
MARKETBRAIN_WHATSAPP_WABA_ID=
MARKETBRAIN_WHATSAPP_ACCESS_TOKEN=
MARKETBRAIN_WHATSAPP_APP_SECRET=
MARKETBRAIN_WHATSAPP_VERIFY_TOKEN=
MARKETBRAIN_WHATSAPP_ALLOWED_WA_ID=
```

Never paste those values into source code, Git, logs, screenshots, or chat. The dashboard's temporary access token
is suitable only for short development tests. A reviewed System User token is required before unattended delivery
is considered.

## Interactive sandbox test

The local-only test endpoint can send one synthetic `TEST-EQ` BUY alert with `APPROVE`, `REJECT`, and `DETAILS`
quick-reply buttons. Each button carries a random opaque token whose SHA-256 hash is retained in the existing alert
audit tables. A signed callback must also match the configured WABA, phone-number ID, and allow-listed `wa_id`.

The chosen action is recorded once. `REJECT` records rejection, `DETAILS` returns test-only context, and `APPROVE`
is always recorded as `BLOCKED_PENDING_FRESH_QUOTE`. All three paths create zero signals, PAPER fills, broker orders,
or live trading actions. The test endpoint and its sanitized status endpoint remain localhost-only and must never be
added to the Cloudflare tunnel routes.

Free-form interactive messages require a current WhatsApp conversation window. If Meta rejects the send, first use
the portal to send its approved `hello_world` template and reply from the allow-listed phone before repeating the
local test.

After testing, restore `MARKETBRAIN_WHATSAPP_TEST_ALERTS_ENABLED=false` and recreate the backend. The webhook can
remain enabled for controlled sandbox validation.

## Current activation state

The callback, content-free webhook ledger, outbound sandbox sender, and one-time button audit are present but remain
inert while `MARKETBRAIN_WHATSAPP_ENABLED=false`. Interactive tests additionally require
`MARKETBRAIN_WHATSAPP_TEST_ALERTS_ENABLED=true`. Identical system-note mirroring separately requires
`MARKETBRAIN_WHATSAPP_NOTIFICATIONS_ENABLED=true`; the dual test endpoint also requires
`MARKETBRAIN_DUAL_NOTIFICATION_TEST_ENABLED=true`. The validated System User token supports unattended authentication,
while production sender registration, approved out-of-window templates, and every trading action remain separate gates.
