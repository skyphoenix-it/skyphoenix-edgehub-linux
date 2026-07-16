# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x: (pre-release)  |

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to:

**security@xeneon-edge-hub.dev** (placeholder — update before release)

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

1. **No root required** — The application runs with normal user privileges.
2. **Deny by default** — Widget permissions are opt-in, reviewed by the user.
3. **Sandbox community widgets** — Third-party widgets run in isolated WASM sandboxes (Phase 7+).
4. **No arbitrary command execution** — Custom commands require explicit user approval.
5. **Secure secret storage** — API keys and tokens use the system secret service (D-Bus).
6. **Input validation** — All external data (D-Bus, /proc, /sys, user config) is validated.
7. **Minimal dependencies** — We audit and pin all dependencies.
8. **Reproducible builds** — Release artifacts are verifiable.

## Security Features by Trust Level

| Trust Level | Widget Type | Sandbox | Resource Limits | Permissions |
|-------------|-------------|---------|-----------------|-------------|
| 0 | Built-in native | None (trusted) | Timeout guards | Full |
| 1 | First-party QML | None (trusted) | Timeout guards | Full |
| 2 | Trusted third-party | QML context restriction | Timeout guards | Declared |
| 3 | Community WASM | wasmtime sandbox | CPU, memory, execution | Enforced |

## Known Security Limitations (MVP)

- **No widget sandboxing in MVP (Phases 1-6):** All widgets run in-process as trusted code. Community widget sandboxing is planned for Phase 7.
- **No encrypted secret storage in MVP:** API keys stored in config files with user file permissions. Secret Service integration planned for post-MVP.
- **No Content Security Policy for web widgets:** Web content widget not included in MVP; CSP will be enforced when it is added.

## Dependency Security

- All Rust dependencies are pinned via `Cargo.lock`
- CI runs `cargo audit` on every commit
- CI runs `cargo deny` for license compliance and duplicate detection
- Dependencies are reviewed before addition (popularity, maintenance, security history)
- SBOM generated for every release

## Security Contacts

- **Security Lead:** TBD (placeholder)
- **Maintainer Team:** See [CODEOWNERS](.github/CODEOWNERS) (to be created)

## Hall of Fame

We appreciate and acknowledge security researchers who responsibly disclose vulnerabilities. Names will be listed here with permission.

