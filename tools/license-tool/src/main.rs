//! xeneon-license — the issuer's key tool. NOT shipped in the app.
//!
//!   keygen                          generate the issuer keypair (once, ever)
//!   mint --seed-stdin --to <name> --id <id> [--expires <unix|never>] [--tier pro]
//!                                   sign one licence key; read seed from stdin
//!
//! All signing goes through the shared `xeneon_license_tool` lib, so the CLI, the
//! purchase webhook, and the app's verifier can never disagree about the format.

use ed25519_dalek::SigningKey;
use std::io::{self, Read};
use std::process::exit;
use xeneon_core::license::b64url_encode;
use xeneon_license_tool::{build_payload, seed_from_b64, sign_payload};

fn die(msg: &str) -> ! {
    eprintln!("error: {msg}");
    exit(2);
}

fn arg_val(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

const MAX_SEED_INPUT_BYTES: u64 = 256;

/// Read one base64url signing seed without ever accepting it as an argument.
/// The small cap also prevents an accidentally redirected file from being read
/// wholesale into the issuer process.
fn read_seed<R: Read>(reader: R) -> Result<String, String> {
    let mut bytes = Vec::new();
    reader
        .take(MAX_SEED_INPUT_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "could not read the signing seed from stdin".to_string())?;
    if bytes.len() as u64 > MAX_SEED_INPUT_BYTES {
        return Err("signing seed input is too large".to_string());
    }
    let text = String::from_utf8(bytes)
        .map_err(|_| "signing seed input is not valid UTF-8".to_string())?;
    let seed = text.trim();
    if seed.is_empty() {
        return Err("signing seed input is empty".to_string());
    }
    Ok(seed.to_string())
}

fn keygen() {
    let mut seed = [0u8; 32];
    getrandom::getrandom(&mut seed).unwrap_or_else(|_| die("no OS randomness available"));
    let sk = SigningKey::from_bytes(&seed);
    let pk = sk.verifying_key();

    println!("Xeneon Edge licence keypair — generate this ONCE.\n");
    println!("1) PUBLIC key — paste into core/src/license.rs, replacing the all-zero");
    println!("   ISSUER_PUBLIC_KEY placeholder (this is what arms verification):\n");
    print!("const ISSUER_PUBLIC_KEY: [u8; 32] = [");
    for (i, b) in pk.to_bytes().iter().enumerate() {
        if i % 12 == 0 {
            print!("\n    ");
        }
        print!("{b}, ");
    }
    println!("\n];\n");
    println!("2) PRIVATE seed — the SECRET. Store it in your password manager and");
    println!("   NEVER commit it. Feed it to `mint --seed-stdin` to sign keys.");
    println!("   Anyone with this seed can issue Pro licences:\n");
    println!("   {}\n", b64url_encode(&seed));
    println!("If this seed ever leaks: generate a new keypair, ship the new public");
    println!("key in an app update, and every key signed with the old seed stops");
    println!("verifying (fails soft to free).");
}

fn mint(args: &[String]) {
    if args.iter().any(|arg| arg == "--seed") {
        die("--seed is disabled because process arguments are observable; use --seed-stdin");
    }
    if !args.iter().any(|arg| arg == "--seed-stdin") {
        die("--seed-stdin is required");
    }
    let seed_b64 = read_seed(io::stdin().lock()).unwrap_or_else(|e| die(&e));
    let issued_to = arg_val(args, "--to").unwrap_or_else(|| die("--to <name/email> is required"));
    let id = arg_val(args, "--id").unwrap_or_else(|| die("--id <licence id> is required"));
    let tier = arg_val(args, "--tier").unwrap_or_else(|| "pro".to_string());
    // --expires: a Unix timestamp, or "never" for perpetual. Perpetual is the
    // default so a one-time purchase does not silently expire.
    let expires = match arg_val(args, "--expires").as_deref() {
        None | Some("never") | Some("none") => "null".to_string(),
        Some(v) => v
            .parse::<i64>()
            .map(|n| n.to_string())
            .unwrap_or_else(|_| die("--expires must be a Unix timestamp or 'never'")),
    };

    let seed = seed_from_b64(&seed_b64).unwrap_or_else(|e| die(&e));
    println!(
        "{}",
        sign_payload(&seed, &build_payload(&tier, &expires, &issued_to, &id))
    );
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("keygen") => keygen(),
        Some("mint") => mint(&args),
        _ => {
            eprintln!("usage:");
            eprintln!("  xeneon-license keygen");
            eprintln!("  xeneon-license mint --seed-stdin --to <name> --id <id> \\");
            eprintln!("                      [--tier pro] [--expires <unix|never>]");
            exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seed_reader_trims_one_line_without_echoing_it() {
        let value = "A".repeat(43);
        assert_eq!(read_seed(format!(" {value}\n").as_bytes()).unwrap(), value);
    }

    #[test]
    fn seed_reader_rejects_empty_invalid_and_oversized_input() {
        assert!(read_seed("  \n".as_bytes()).is_err());
        assert!(read_seed([0xff].as_slice()).is_err());
        assert!(read_seed(vec![b'A'; MAX_SEED_INPUT_BYTES as usize + 1].as_slice()).is_err());
    }
}
