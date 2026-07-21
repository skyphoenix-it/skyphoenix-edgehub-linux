use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn binary() -> &'static str {
    env!("CARGO_BIN_EXE_xeneon-license")
}

fn test_seed() -> &'static str {
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
}

fn temp_dir(label: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "xeneon-license-{label}-{}-{nonce}",
        std::process::id()
    ));
    fs::create_dir(&path).expect("create test directory");
    path
}

#[test]
fn mint_reads_seed_from_stdin() {
    let mut child = Command::new(binary())
        .args(["mint", "--seed-stdin", "--to", "Ada", "--id", "XE-1"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn issuer tool");
    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(format!("{}\n", test_seed()).as_bytes())
        .expect("write seed");
    let output = child.wait_with_output().expect("issuer output");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let key = String::from_utf8(output.stdout).expect("UTF-8 key");
    assert!(key.trim().starts_with("XE1."));
    assert!(!key.contains(test_seed()));
}

#[test]
fn argv_seed_form_is_rejected_without_echoing_the_value() {
    let canary = "ARGV_SEED_CANARY_DO_NOT_ECHO";
    let output = Command::new(binary())
        .args(["mint", "--seed", canary, "--to", "Ada", "--id", "XE-1"])
        .output()
        .expect("run issuer tool");
    assert_eq!(output.status.code(), Some(2));
    let rendered = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(rendered.contains("--seed is disabled"));
    assert!(!rendered.contains(canary));
}

#[test]
fn wrapper_keeps_seed_out_of_cargo_argv_and_environment() {
    let capture = temp_dir("wrapper");
    let fake_cargo = capture.join("cargo");
    fs::write(
        &fake_cargo,
        r##"#!/bin/sh
set -eu
: "${XENEON_TEST_CAPTURE_DIR:?}"
printf '%s\n' "$@" > "$XENEON_TEST_CAPTURE_DIR/argv"
env > "$XENEON_TEST_CAPTURE_DIR/environment"
cat > "$XENEON_TEST_CAPTURE_DIR/stdin"
"##,
    )
    .expect("write fake cargo");
    fs::set_permissions(&fake_cargo, fs::Permissions::from_mode(0o700))
        .expect("make fake cargo executable");

    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repository root")
        .to_path_buf();
    let path = format!(
        "{}:{}",
        capture.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let output = Command::new(repo.join("scripts/mint-license.sh"))
        .args(["--to", "Ada", "--id", "XE-1"])
        .env("PATH", path)
        .env("XENEON_LICENSE_SEED", test_seed())
        .env("XENEON_TEST_CAPTURE_DIR", &capture)
        .output()
        .expect("run mint wrapper");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let argv = fs::read_to_string(capture.join("argv")).expect("captured argv");
    assert!(argv.lines().any(|line| line == "--seed-stdin"));
    assert!(!argv.contains(test_seed()));
    let environment =
        fs::read_to_string(capture.join("environment")).expect("captured environment");
    assert!(!environment.contains("XENEON_LICENSE_SEED="));
    assert!(!environment.contains(test_seed()));
    assert_eq!(
        fs::read_to_string(capture.join("stdin"))
            .expect("captured stdin")
            .trim(),
        test_seed()
    );

    fs::remove_dir_all(capture).expect("clean test directory");
}
