//! Secret-reference resolution (E7 Phase A).
//!
//! A widget's `authToken` (and any future credential) is stored in `ui_state`,
//! which is serialised verbatim into `config.toml`. A literal token there is a
//! plaintext secret on disk — so instead the config should hold only a
//! *reference*, resolved to the real value at request time and never persisted:
//!
//! | form                  | meaning                                      |
//! |-----------------------|----------------------------------------------|
//! | `${env:VAR}`          | read environment variable `VAR`              |
//! | `file:/path/to/token` | read the file's contents (trimmed)           |
//! | `secret://svc/key`    | OS keyring — Phase B, not yet implemented    |
//! | anything else         | a legacy plaintext literal (still honoured)  |
//!
//! Plaintext is deliberately still honoured: E1 shipped a token field, so real
//! users may already have one typed in, and silently breaking their widget is
//! worse than the exposure they already have. `is_plaintext` lets the UI flag it
//! so they can migrate. See [`resolve`].
//!
//! NOTHING in this module may log a secret's value — only its *kind* and, on
//! failure, the reference (which is a variable name or path, not the secret).

use std::fs;
use std::path::Path;

/// What a stored credential string denotes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SecretRef<'a> {
    /// `${env:VAR}` — resolved from the process environment.
    Env(&'a str),
    /// `file:/path` — resolved by reading the file.
    File(&'a str),
    /// `secret://service/key` — OS keyring (Phase B).
    Keyring(&'a str),
    /// A bare literal: the legacy plaintext form.
    Plaintext(&'a str),
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum SecretError {
    #[error("environment variable `{0}` is not set")]
    EnvMissing(String),
    #[error("secret file `{0}` could not be read: {1}")]
    FileUnreadable(String, String),
    #[error("secret file `{0}` is empty")]
    FileEmpty(String),
    #[error("`secret://` references need the keyring backend, which this build does not have")]
    KeyringUnsupported,
    #[error("`{0}` is not a usable reference")]
    Malformed(String),
}

/// Classify a stored credential string without resolving it.
///
/// Note the ordering: the `${env:}`/`file:`/`secret://` prefixes are checked
/// first, so a literal that merely *starts* with something similar (e.g. a
/// token that happens to begin "file") only matches when the full prefix is
/// present.
pub fn classify(raw: &str) -> SecretRef<'_> {
    let t = raw.trim();
    if let Some(rest) = t.strip_prefix("${env:") {
        if let Some(var) = rest.strip_suffix('}') {
            return SecretRef::Env(var.trim());
        }
        // "${env:FOO" with no closing brace — the user meant a ref, so treat it
        // as one (and fail loudly) rather than send a malformed literal as a
        // Bearer token to a remote host.
        return SecretRef::Env(rest.trim());
    }
    if let Some(rest) = t.strip_prefix("file:") {
        return SecretRef::File(rest.trim());
    }
    if let Some(rest) = t.strip_prefix("secret://") {
        return SecretRef::Keyring(rest.trim());
    }
    SecretRef::Plaintext(raw)
}

/// True when the stored value is a bare secret sitting in `config.toml`.
///
/// An empty value is NOT plaintext — nothing is stored, so there is nothing to
/// warn about (that is just an unconfigured widget).
pub fn is_plaintext(raw: &str) -> bool {
    !raw.trim().is_empty() && matches!(classify(raw), SecretRef::Plaintext(_))
}

/// Resolve a stored credential to the value to actually send.
///
/// Errors carry the *reference* (a var name or path), never the secret.
pub fn resolve(raw: &str) -> Result<String, SecretError> {
    match classify(raw) {
        SecretRef::Env(var) => {
            if var.is_empty() {
                return Err(SecretError::Malformed(raw.trim().to_string()));
            }
            std::env::var(var).map_err(|_| SecretError::EnvMissing(var.to_string()))
        }
        SecretRef::File(path) => {
            if path.is_empty() {
                return Err(SecretError::Malformed(raw.trim().to_string()));
            }
            let contents = fs::read_to_string(Path::new(path))
                .map_err(|e| SecretError::FileUnreadable(path.to_string(), e.to_string()))?;
            // Trim: a token file almost always ends in a newline, and sending
            // that in an Authorization header breaks the request in a way that
            // is very hard to see.
            let trimmed = contents.trim();
            if trimmed.is_empty() {
                return Err(SecretError::FileEmpty(path.to_string()));
            }
            Ok(trimmed.to_string())
        }
        SecretRef::Keyring(_) => Err(SecretError::KeyringUnsupported),
        SecretRef::Plaintext(v) => Ok(v.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_each_form() {
        assert_eq!(classify("${env:CI_TOKEN}"), SecretRef::Env("CI_TOKEN"));
        assert_eq!(classify("file:/run/tok"), SecretRef::File("/run/tok"));
        assert_eq!(classify("secret://edge/ci"), SecretRef::Keyring("edge/ci"));
        assert_eq!(classify("ghp_literal"), SecretRef::Plaintext("ghp_literal"));
    }

    #[test]
    fn classify_tolerates_surrounding_whitespace() {
        assert_eq!(classify("  ${env:TOK}  "), SecretRef::Env("TOK"));
        assert_eq!(classify(" file: /run/tok "), SecretRef::File("/run/tok"));
    }

    // A token that merely starts with letters resembling a scheme must stay a
    // literal — otherwise a real token could be silently reinterpreted as a path.
    #[test]
    fn a_literal_resembling_a_scheme_is_still_a_literal() {
        assert_eq!(
            classify("filesystem-token"),
            SecretRef::Plaintext("filesystem-token")
        );
        assert_eq!(classify("secretive"), SecretRef::Plaintext("secretive"));
        assert_eq!(classify("${envelope}"), SecretRef::Plaintext("${envelope}"));
    }

    #[test]
    fn is_plaintext_flags_only_bare_literals() {
        assert!(is_plaintext("ghp_abc123"));
        assert!(!is_plaintext("${env:TOK}"));
        assert!(!is_plaintext("file:/run/tok"));
        assert!(!is_plaintext("secret://a/b"));
        // Nothing stored → nothing to warn about.
        assert!(!is_plaintext(""));
        assert!(!is_plaintext("   "));
    }

    #[test]
    fn resolves_env_ref() {
        let _g = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        std::env::set_var("XENEON_TEST_SECRET", "s3cr3t");
        assert_eq!(resolve("${env:XENEON_TEST_SECRET}").unwrap(), "s3cr3t");
        std::env::remove_var("XENEON_TEST_SECRET");
    }

    #[test]
    fn missing_env_ref_errors_and_names_the_var_not_a_value() {
        let _g = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        std::env::remove_var("XENEON_TEST_ABSENT");
        let err = resolve("${env:XENEON_TEST_ABSENT}").unwrap_err();
        assert_eq!(err, SecretError::EnvMissing("XENEON_TEST_ABSENT".into()));
        assert!(err.to_string().contains("XENEON_TEST_ABSENT"));
    }

    #[test]
    fn resolves_file_ref_and_trims_the_trailing_newline() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("tok");
        // The newline is the realistic case: `echo tok > file` leaves one, and
        // sending it in a header breaks auth confusingly.
        fs::write(&p, "file-token\n").unwrap();
        let r = resolve(&format!("file:{}", p.display())).unwrap();
        assert_eq!(r, "file-token");
    }

    #[test]
    fn unreadable_file_errors_with_the_path() {
        let err = resolve("file:/nonexistent/xeneon/tok").unwrap_err();
        assert!(
            matches!(err, SecretError::FileUnreadable(ref p, _) if p == "/nonexistent/xeneon/tok")
        );
    }

    #[test]
    fn empty_file_is_an_error_not_an_empty_token() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("empty");
        fs::write(&p, "\n  \n").unwrap();
        let err = resolve(&format!("file:{}", p.display())).unwrap_err();
        assert!(matches!(err, SecretError::FileEmpty(_)));
    }

    #[test]
    fn keyring_ref_is_unsupported_in_phase_a() {
        assert_eq!(
            resolve("secret://edge/ci").unwrap_err(),
            SecretError::KeyringUnsupported
        );
    }

    #[test]
    fn plaintext_still_resolves_to_itself() {
        // Legacy values must keep working — breaking a user's widget is worse
        // than the exposure they already have; the UI warns instead.
        assert_eq!(resolve("ghp_literal").unwrap(), "ghp_literal");
    }

    #[test]
    fn empty_ref_forms_are_malformed_not_silently_empty() {
        assert!(matches!(resolve("${env:}"), Err(SecretError::Malformed(_))));
        assert!(matches!(resolve("file:"), Err(SecretError::Malformed(_))));
    }
}
