//! Shared minting logic for the licence issuer tooling. NOT part of the shipped
//! app - this is the SIGNING half, used by the `xeneon-license` CLI and the
//! purchase webhook. Reusing one implementation is the whole point: the webhook
//! that turns a sale into a key produces byte-identical output to a hand-minted
//! one, and to what `core/src/license.rs` verifies.

use ed25519_dalek::{Signer, SigningKey};
use xeneon_core::license::{b64url_decode, b64url_encode};

/// Decode a base64url seed into 32 raw bytes, or an error string.
pub fn seed_from_b64(s: &str) -> Result<[u8; 32], String> {
    let bytes = b64url_decode(s).ok_or_else(|| "seed is not valid base64url".to_string())?;
    if bytes.len() != 32 {
        return Err(format!("seed must decode to 32 bytes, got {}", bytes.len()));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

/// Minimal JSON string escaping for the free-text fields (name, id). Closes the
/// hole where a buyer-controlled name could break out of the JSON string and
/// forge a higher tier.
pub fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Build the licence payload JSON. `expires` is `"null"` (perpetual) or a Unix
/// timestamp as a decimal string - the caller has already validated it.
pub fn build_payload(tier: &str, expires: &str, issued_to: &str, id: &str) -> String {
    format!(
        r#"{{"tier":"{}","expires":{},"issued_to":"{}","id":"{}"}}"#,
        json_escape(tier),
        expires,
        json_escape(issued_to),
        json_escape(id)
    )
}

/// Sign a payload into a full `XE1.<b64(payload)>.<b64(sig)>` key. The signature
/// covers the ENCODED form - the exact bytes `license.rs` reconstructs and
/// verifies. Never sign the raw JSON.
pub fn sign_payload(seed: &[u8; 32], payload: &str) -> String {
    let sk = SigningKey::from_bytes(seed);
    let signed = format!("XE1.{}", b64url_encode(payload.as_bytes()));
    let sig = sk.sign(signed.as_bytes());
    format!("{}.{}", signed, b64url_encode(&sig.to_bytes()))
}

/// Mint a perpetual Pro key for a buyer - the one call the webhook needs.
pub fn mint_pro(seed: &[u8; 32], issued_to: &str, id: &str) -> String {
    sign_payload(seed, &build_payload("pro", "null", issued_to, id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mint_pro_is_deterministic_and_matches_the_reference() {
        // ed25519 is deterministic (RFC 8032): the same seed + message always
        // yields the same signature. This exact seed (bytes 0..31) + payload was
        // cross-checked against the `xeneon-license` CLI, which in turn shares
        // this code - so a drift here that changed the key would fail both this
        // and the app's verifier. The reference below is that CLI's output.
        let seed: [u8; 32] = std::array::from_fn(|i| i as u8);
        let key = mint_pro(&seed, "Ada", "XE-1");
        assert_eq!(
            key,
            "XE1.eyJ0aWVyIjoicHJvIiwiZXhwaXJlcyI6bnVsbCwiaXNzdWVkX3RvIjoiQWRhIiwiaWQiOiJYRS0xIn0.\
             0HKCGAvHxoCLdCs-bf98gNVHB7odz-FszAOLdNV8qeoGjcc_Zkacc61aLtc3IUAfbcNkGK-9SmSnf5Rvohi1AA"
        );
    }

    #[test]
    fn json_escape_blocks_tier_injection() {
        let esc = json_escape(r#"x","tier":"pro"#);
        assert!(
            !esc.contains(r#"","tier":"pro"#),
            "must not break out: {esc}"
        );
    }

    #[test]
    fn seed_from_b64_validates_length() {
        assert!(seed_from_b64("tooShort").is_err());
        assert!(seed_from_b64(&b64url_encode(&[0u8; 32])).is_ok());
    }
}
