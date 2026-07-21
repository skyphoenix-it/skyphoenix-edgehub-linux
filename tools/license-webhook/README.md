# xeneon-license-webhook

Turns a Lemon Squeezy purchase into a signed Pro key, automatically. Deploy it
somewhere private - it holds your signing seed.

## What it does

1. Receives Lemon Squeezy's `order_created` webhook.
2. Verifies the `X-Signature` (HMAC-SHA256 of the raw body with your webhook
   secret). Bad/missing signature → 401, mints nothing.
3. Mints an `XE1` Pro key for the buyer, using the **same** signing code as the
   `xeneon-license` CLI (so the key is byte-identical and verifies in the app).
4. E-mails it (SMTP), or - if no SMTP is configured - logs it so you can send it
   by hand. If e-mail fails it logs the key and returns 500 so Lemon Squeezy
   retries; a sale is never silently lost.

The security-critical core (signature check, order parse, minting) is unit-tested
(`cargo test`). The HTTP loop and SMTP send are thin shells - **smoke-test with a
real Lemon Squeezy _test_ webhook before going live** (dashboard → your webhook →
"Send test").

## Environment (all secrets via env, never argv)

| Var | Required | What |
|-----|----------|------|
| `XENEON_LICENSE_SEED` | yes | your base64url signing seed (the crown jewel) |
| `LEMONSQUEEZY_WEBHOOK_SECRET` | yes | must equal the secret you set on the webhook |
| `PORT` | no | default 8787 |
| `SMTP_HOST` `SMTP_PORT` `SMTP_USER` `SMTP_PASS` `MAIL_FROM` | for e-mail | omit all to log-only |
| `MAIL_BCC` | no | bcc yourself a copy of every key |

## Run / deploy

```
cargo build --release --manifest-path tools/license-webhook/Cargo.toml
XENEON_LICENSE_SEED=… LEMONSQUEEZY_WEBHOOK_SECRET=… \
  SMTP_HOST=… SMTP_PORT=587 SMTP_USER=… SMTP_PASS=… MAIL_FROM='Xeneon Edge <sales@…>' \
  ./target/release/xeneon-license-webhook
```

Put it behind TLS (a reverse proxy or your platform's HTTPS) - Lemon Squeezy
requires an `https://` URL. A `GET /` returns `ok` for health checks. Then register
the webhook: `python3 scripts/setup-lemonsqueezy.py --url https://…/webhook --apply`.

A minimal systemd unit:

```ini
[Service]
EnvironmentFile=/etc/xeneon-license-webhook.env   # chmod 600 - holds the seed
ExecStart=/opt/xeneon/xeneon-license-webhook
Restart=always
DynamicUser=yes
```

## If the seed leaks

Rotate: `keygen` a new pair, ship the new public key in an app update, put the new
seed in this service's env, and re-issue current customers' keys. See
`docs/LICENSING.md`.
