//! xeneon-license-webhook - turn a purchase into a signed Pro key, automatically.
//!
//! A Lemon Squeezy `order_created` webhook lands here; this service verifies the
//! signature, mints an `XE1` key for the buyer (reusing the SAME signing code as
//! the CLI, so the key is byte-identical to a hand-minted one and to what the app
//! verifies), and e-mails it.
//!
//! It holds two secrets, BOTH from the environment, never on the command line:
//!   XENEON_LICENSE_SEED       the private signing seed (base64url) - the crown jewel
//!   LEMONSQUEEZY_WEBHOOK_SECRET   the webhook signing secret (verifies authenticity)
//! Delivery (optional - if unset, the key is logged so you can send it by hand):
//!   SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS  MAIL_FROM  [MAIL_BCC]
//! And:
//!   PORT (default 8787)
//!
//! Design: the security-critical core - signature verification, order parsing,
//! minting - is pure and unit-tested. The HTTP loop and SMTP send are thin shells
//! around it. Smoke-test with a real Lemon Squeezy TEST webhook before going live
//! (see README).

use hmac::{Hmac, Mac};
use sha2::Sha256;
use xeneon_license_tool::{mint_pro, seed_from_b64};

type HmacSha256 = Hmac<Sha256>;

/// What we need from an order to mint a key.
struct Buyer {
    name: String,
    email: String,
    id: String,
}

/// Verify Lemon Squeezy's `X-Signature` (hex HMAC-SHA256 of the RAW body with the
/// webhook secret). Constant-time via HMAC's own `verify_slice`. A missing or
/// malformed signature is a rejection, never a pass.
fn signature_ok(body: &[u8], sig_header: Option<&str>, secret: &[u8]) -> bool {
    let Some(sig_hex) = sig_header else {
        return false;
    };
    let Ok(sig) = hex::decode(sig_hex.trim()) else {
        return false;
    };
    let Ok(mut mac) = HmacSha256::new_from_slice(secret) else {
        return false;
    };
    mac.update(body);
    mac.verify_slice(&sig).is_ok()
}

/// Pull the buyer out of an `order_created` payload. Returns None for any other
/// event or a shape we do not recognise - we mint ONLY for a real order.
fn parse_order(body: &[u8]) -> Option<Buyer> {
    let v: serde_json::Value = serde_json::from_slice(body).ok()?;
    if v["meta"]["event_name"].as_str()? != "order_created" {
        return None;
    }
    let attrs = &v["data"]["attributes"];
    let name = attrs["user_name"].as_str().unwrap_or("").trim().to_string();
    let email = attrs["user_email"].as_str()?.trim().to_string();
    // The order identifier is the stable, unique licence id (survives refunds/
    // support lookups). Fall back to the order number if absent.
    let id = attrs["identifier"]
        .as_str()
        .map(str::to_string)
        .or_else(|| attrs["order_number"].as_i64().map(|n| format!("LS-{n}")))?;
    if email.is_empty() || id.is_empty() {
        return None;
    }
    Some(Buyer {
        name: if name.is_empty() { email.clone() } else { name },
        email,
        id,
    })
}

struct MailCfg {
    host: String,
    port: u16,
    user: String,
    pass: String,
    from: String,
    bcc: Option<String>,
}

fn mail_cfg() -> Option<MailCfg> {
    Some(MailCfg {
        host: std::env::var("SMTP_HOST").ok()?,
        port: std::env::var("SMTP_PORT").ok()?.parse().ok()?,
        user: std::env::var("SMTP_USER").ok()?,
        pass: std::env::var("SMTP_PASS").ok()?,
        from: std::env::var("MAIL_FROM").ok()?,
        bcc: std::env::var("MAIL_BCC").ok(),
    })
}

fn send_key(cfg: &MailCfg, buyer: &Buyer, key: &str) -> Result<(), String> {
    use lettre::transport::smtp::authentication::Credentials;
    use lettre::{Message, SmtpTransport, Transport};

    let body = format!(
        "Thank you for supporting Xeneon Edge!\n\n\
         Your Pro licence key:\n\n  {key}\n\n\
         To activate: open the Xeneon Edge Manager, go to About, click Activate Pro,\n\
         and paste the key. It verifies on your device - nothing is sent anywhere.\n\n\
         Keep this e-mail; the key works on any machine and after a reinstall.\n"
    );
    let mut msg = Message::builder()
        .from(
            cfg.from
                .parse()
                .map_err(|e| format!("bad MAIL_FROM: {e}"))?,
        )
        .to(format!("{} <{}>", buyer.name, buyer.email)
            .parse()
            .map_err(|e| format!("bad buyer address: {e}"))?)
        .subject("Your Xeneon Edge Pro licence key");
    if let Some(bcc) = &cfg.bcc {
        msg = msg.bcc(bcc.parse().map_err(|e| format!("bad MAIL_BCC: {e}"))?);
    }
    let email = msg.body(body).map_err(|e| format!("build message: {e}"))?;

    let mailer = SmtpTransport::relay(&cfg.host)
        .map_err(|e| format!("smtp relay: {e}"))?
        .port(cfg.port)
        .credentials(Credentials::new(cfg.user.clone(), cfg.pass.clone()))
        .build();
    mailer.send(&email).map_err(|e| format!("send: {e}"))?;
    Ok(())
}

fn main() {
    // Load the two secrets up front - refuse to start without them, so the
    // service can never run in a state where it accepts webhooks but cannot mint.
    let seed_b64 = std::env::var("XENEON_LICENSE_SEED")
        .expect("XENEON_LICENSE_SEED (base64url signing seed) is required");
    let seed = seed_from_b64(&seed_b64).expect("XENEON_LICENSE_SEED is not a valid 32-byte seed");
    let secret = std::env::var("LEMONSQUEEZY_WEBHOOK_SECRET")
        .expect("LEMONSQUEEZY_WEBHOOK_SECRET is required")
        .into_bytes();
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8787);
    let mail = mail_cfg();
    if mail.is_none() {
        eprintln!("NOTE: no SMTP_* env - keys will be LOGGED, not e-mailed. Send them by hand.");
    }

    let server = tiny_http::Server::http(("0.0.0.0", port))
        .unwrap_or_else(|e| panic!("cannot bind :{port}: {e}"));
    eprintln!("xeneon-license-webhook listening on :{port} (POST /webhook)");

    for mut request in server.incoming_requests() {
        // Health check for the deploy platform.
        if request.method() == &tiny_http::Method::Get {
            let _ = request.respond(tiny_http::Response::from_string("ok"));
            continue;
        }
        let mut body = Vec::new();
        if request.as_reader().read_to_end(&mut body).is_err() {
            let _ =
                request.respond(tiny_http::Response::from_string("bad body").with_status_code(400));
            continue;
        }
        let sig = request
            .headers()
            .iter()
            .find(|h| h.field.equiv("X-Signature"))
            .map(|h| h.value.as_str().to_string());

        if !signature_ok(&body, sig.as_deref(), &secret) {
            eprintln!("rejected: bad or missing signature");
            let _ = request
                .respond(tiny_http::Response::from_string("bad signature").with_status_code(401));
            continue;
        }
        let Some(buyer) = parse_order(&body) else {
            // A signed event we don't act on (not an order) - acknowledge so
            // Lemon Squeezy does not retry forever.
            let _ =
                request.respond(tiny_http::Response::from_string("ignored").with_status_code(200));
            continue;
        };

        let key = mint_pro(&seed, &buyer.name, &buyer.id);
        match &mail {
            Some(cfg) => match send_key(cfg, &buyer, &key) {
                Ok(()) => eprintln!("minted + emailed to <{}> (id {})", buyer.email, buyer.id),
                Err(e) => {
                    // Do NOT lose the sale: log the key so it can be sent by hand,
                    // and 500 so Lemon Squeezy retries.
                    eprintln!(
                        "MINTED but email FAILED for <{}> (id {}): {e}\n  KEY: {key}",
                        buyer.email, buyer.id
                    );
                    let _ = request.respond(
                        tiny_http::Response::from_string("mail failed").with_status_code(500),
                    );
                    continue;
                }
            },
            None => eprintln!(
                "minted for <{}> (id {}) - SEND BY HAND:\n  KEY: {key}",
                buyer.email, buyer.id
            ),
        }
        let _ = request.respond(tiny_http::Response::from_string("ok").with_status_code(200));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sign(body: &[u8], secret: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret).unwrap();
        mac.update(body);
        hex::encode(mac.finalize().into_bytes())
    }

    #[test]
    fn signature_must_match_the_secret_over_the_exact_body() {
        let body = br#"{"hello":"world"}"#;
        let secret = b"whsec_test";
        let good = sign(body, secret);
        assert!(
            signature_ok(body, Some(&good), secret),
            "a correct sig verifies"
        );
        assert!(
            !signature_ok(body, Some(&good), b"wrong"),
            "wrong secret fails"
        );
        assert!(
            !signature_ok(b"tampered", Some(&good), secret),
            "tampered body fails"
        );
        assert!(!signature_ok(body, None, secret), "no signature fails");
        assert!(
            !signature_ok(body, Some("nothex"), secret),
            "garbage signature fails"
        );
    }

    #[test]
    fn parses_an_order_created_and_ignores_everything_else() {
        let order = br#"{
            "meta": {"event_name": "order_created"},
            "data": {"attributes": {
                "user_name": "Ada Lovelace",
                "user_email": "ada@example.com",
                "identifier": "ORD-abc-123"
            }}
        }"#;
        let b = parse_order(order).expect("an order_created yields a buyer");
        assert_eq!(b.name, "Ada Lovelace");
        assert_eq!(b.email, "ada@example.com");
        assert_eq!(b.id, "ORD-abc-123");

        // A different event is not acted on.
        let sub = br#"{"meta":{"event_name":"subscription_created"},"data":{"attributes":{"user_email":"x@y.z","identifier":"i"}}}"#;
        assert!(parse_order(sub).is_none(), "non-order events mint nothing");
        // A missing email is not a mintable order.
        let noemail =
            br#"{"meta":{"event_name":"order_created"},"data":{"attributes":{"identifier":"i"}}}"#;
        assert!(parse_order(noemail).is_none());
    }

    #[test]
    fn a_nameless_order_falls_back_to_the_email_and_still_mints() {
        let order = br#"{"meta":{"event_name":"order_created"},"data":{"attributes":{"user_email":"solo@x.io","order_number":42}}}"#;
        let b = parse_order(order).unwrap();
        assert_eq!(
            b.name, "solo@x.io",
            "no name → use the email so the key still names someone"
        );
        assert_eq!(b.id, "LS-42", "order_number is the id fallback");
        // And it mints a real Pro key.
        let seed: [u8; 32] = std::array::from_fn(|i| i as u8);
        assert!(mint_pro(&seed, &b.name, &b.id).starts_with("XE1."));
    }
}
