# WhatsApp Cloud API sandbox boundary

## Purpose

MarketBrain may mirror controlled test notifications through Meta's automatically provided `+1` WhatsApp test
number. This is a development integration, not the dependable production notification path. Telegram remains the
authoritative daily channel.

The sandbox can be used to verify:

- outbound template delivery to the owner's verified test-recipient number;
- Meta webhook verification and signed delivery callbacks;
- interactive button callback parsing;
- duplicate-delivery protection and audit evidence.

It cannot create a signal, paper fill, broker order, or live trading action.

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

## Current activation state

The callback code and database ledger are present but remain inert while
`MARKETBRAIN_WHATSAPP_ENABLED=false`. Public HTTPS ingress, Meta webhook registration, outbound message delivery,
template approval, and action execution are separate future gates.
