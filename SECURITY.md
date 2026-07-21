# Security Policy

## Supported Versions

| Version        | Supported          |
|----------------|--------------------|
| 1.0.0-alpha.x  | :white_check_mark: |
| 0.1.x          | :x: (superseded)   |

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Instead, use **GitHub private vulnerability reporting**, which opens a private
advisory visible only to the maintainers:

**<https://github.com/skyphoenix-it/skyphoenix-edgehub-linux/security/advisories/new>**

(This replaced a `security@…` address on a domain that was never registered.
Mail to it bounced, so any report sent there was lost - and the domain was
free for anyone to claim and receive vulnerability reports for this product.
A GitHub-native channel cannot be squatted that way and needs no mailbox.)

Please include:

- A description of the vulnerability
- Steps to reproduce
- Affected versions
- Any potential mitigations you've identified

### Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial assessment:** Within 5 business days
- **Fix timeline:**
  - Critical (remote code execution, sandbox escape): 7 days
  - High (privilege escalation, data exposure): 30 days
  - Medium (DoS, information leak): 90 days
  - Low (best practice violations): Next release

### Disclosure Policy

We follow coordinated disclosure:

1. Reporter submits vulnerability privately.
2. We acknowledge and assess.
3. We develop and test a fix.
4. We release the fix.
5. We publish a security advisory after the fix is available.
6. Credit is given to the reporter (unless they wish to remain anonymous).

## Security Design Principles

1. **No root required** - The application runs with normal user privileges.
2. **Deny by default** - Widget permissions are opt-in, reviewed by the user.
3. **Sandbox community widgets** - Third-party widgets run in isolated WASM sandboxes (Phase 7+).
4. **No arbitrary command execution** - Custom commands require explicit user approval.
5. **Secrets are referenced, not stored** - config holds `${env:VAR}` / `file:/path`
   *references*, resolved per-request and never written back to `config.toml`.
   (OS-keyring `secret://` refs are Phase B and **not implemented** - see Known
   Limitations. Do not read this line as keyring support.)
6. **Input validation** - All external data (D-Bus, /proc, /sys, user config) is validated.
7. **Minimal dependencies** - We audit and pin all dependencies.
8. **Reproducible builds** - Release artifacts are verifiable.

## Security Features by Trust Level

| Trust Level | Widget Type | Sandbox | Resource Limits | Permissions |
|-------------|-------------|---------|-----------------|-------------|
| 0 | Built-in native | None (trusted) | Timeout guards | Full |
| 1 | First-party QML | None (trusted) | Timeout guards | Full |
| 2 | Trusted third-party | QML context restriction | Timeout guards | Declared |
| 3 | Community WASM | wasmtime sandbox | CPU, memory, execution | Enforced |

## Known Security Limitations (MVP)

- **No widget sandboxing in MVP (Phases 1-6):** All widgets run in-process as trusted code. Community widget sandboxing is planned for Phase 7.
- **No encrypted secret storage:** use `${env:VAR}` / `file:/path` refs so the
  secret lives outside `config.toml` (resolved per-request, never persisted).
  A literal secret typed into config is stored in plain text with user file
  permissions. OS-keyring `secret://` support (E7 Phase B) is **parked**, not
  shipped, and there is no date for it.
- **No Content Security Policy for web widgets:** Web content widget not included in MVP; CSP will be enforced when it is added.

## Dependency Security

- All Rust dependencies are pinned via `Cargo.lock`
- CI runs `cargo deny check` - advisories (RUSTSEC), licenses, bans, and source
  pinning - in `.github/workflows/supply-chain.yml`, on pushes that touch code
  plus a **weekly** cron, because new advisories land without anyone pushing.
  (There is no separate `cargo audit` job: it was redundant with deny's
  advisories check and was removed when CI cost was cut.)
- Dependencies are reviewed before addition (popularity, maintenance, security history)
- SBOM generated for every release

## Security Contacts

Reports go through [private vulnerability reporting](https://github.com/skyphoenix-it/skyphoenix-edgehub-linux/security/advisories/new),
which reaches the maintainers directly. The repository is maintained by
**@skyphoenix-it**. There is deliberately no role mailbox to keep stale - the
last one pointed at an unregistered domain for the whole alpha.

## Hall of Fame

We appreciate and acknowledge security researchers who responsibly disclose vulnerabilities. Names will be listed here with permission.

