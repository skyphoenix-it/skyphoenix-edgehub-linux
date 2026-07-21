# Threat Model

**Version:** 0.1.0-draft
**Status:** Phase 0 - Discovery
**Last Updated:** 2026-07-11

---

## Scope

This threat model covers the Xeneon Edge Linux Hub application, including:

- Application binary and all bundled components
- Built-in widgets (Trust Levels 0-1)
- Configuration and data storage
- Integration adapters (system sensors, MPRIS, PipeWire)
- Inter-process communication (future community widgets)
- Update mechanism
- Build and supply chain

**Out of Scope:**
- Operating system security (assumed to be properly configured)
- Physical security of the device
- Network-level attacks (assumed handled by OS firewall)
- Third-party widget repository security (addressed in a future update)

---

## Trust Model

### Trusted
- The application binary (signed, verified)
- Built-in widgets (shipped with the application)
- The operating system's user isolation (the app runs as the user, not root)
- XDG directory permissions (user-owned, ~/.config, ~/.local)

### Untrusted
- Community widgets (future, Trust Level 3)
- External web content loaded by widgets
- User-provided configuration files from external sources
- D-Bus services (may be compromised or malicious)
- Downloaded updates from unverified sources

---

## Assets

| Asset | Sensitivity | Storage | Access Control |
|-------|------------|---------|----------------|
| Widget configuration | Low | XDG_CONFIG_HOME | User file permissions |
| User preferences | Low | XDG_CONFIG_HOME | User file permissions |
| API keys / tokens | High | Secret Service (future) | D-Bus secret service |
| Widget data (notes, goals, tasks) | Medium | XDG_DATA_HOME | User file permissions |
| System metrics (CPU, RAM, temps) | Low | In-memory only | Process memory |
| Display EDID data | Low | XDG_CONFIG_HOME | User file permissions |
| Log files | Medium | XDG_STATE_HOME | User file permissions |
| Crash reports | Medium | XDG_CACHE_HOME | User file permissions |
| Application binary | High | System package path | Root (installation), user (execution) |

---

## Threat Actors

| Actor | Motivation | Capability | Target |
|-------|-----------|------------|--------|
| Malicious community widget author | Data theft, system access | Can write arbitrary code in widget sandbox | User data, system access |
| Malicious website (in web widget) | Data theft, phishing | Web platform APIs | User tokens, local data |
| Local attacker (same machine) | Data theft, sabotage | Access to user's filesystem | Configuration, data files |
| Remote attacker (supply chain) | Malware distribution | Can compromise dependencies or build pipeline | Application binary, updates |
| Curious user | Accidental misconfiguration | Access to settings UI | Application stability |

---

## Threat Scenarios and Mitigations

### T-001: Malicious Community Widget Escapes Sandbox

**Severity:** Critical
**Likelihood:** Medium (once community widgets are supported)
**Attack Vector:** A community widget (.wasm) exploits a vulnerability in the WASM runtime or host API to escape the sandbox and execute arbitrary code.

**Mitigations:**
- Use hardened WASM runtime (wasmtime) with fuel metering and epoch interruption
- Restrict WASM system interface (WASI) to minimal capabilities
- Host API is capability-based: widgets can only call explicitly granted functions
- No filesystem, network, or process access by default
- Resource limits: max memory, max CPU time, max execution duration
- Regular wasmtime updates for security patches
- Widget permissions declared in manifest, reviewed by user

**Residual Risk:** Low. WASM sandboxing is well-proven. Zero-day in wasmtime is the primary concern.

---

### T-002: Malicious External Web Content Accesses Local APIs

**Severity:** High
**Likelihood:** Medium (when web content widget is implemented)
**Attack Vector:** A web content widget loads a malicious webpage that exploits browser engine vulnerabilities or attempts to access local resources.

**Mitigations:**
- Web content widget uses a restricted WebView (Qt WebEngine with disabled JavaScript APIs)
- No access to local filesystem (custom URL scheme only for approved resources)
- No access to application internals via JavaScript bridge (bridge is disabled)
- External URLs opened in system browser, not in widget
- Content security policy enforced where possible
- Widget clearly labeled as "External Web Content"

**Residual Risk:** Medium. Web engine vulnerabilities are regularly discovered. Regular Qt WebEngine updates required.

---

### T-003: Command Injection via Application Launcher Widget

**Severity:** High
**Likelihood:** Medium
**Attack Vector:** User (or imported configuration) specifies a malicious command in the application launcher widget. Command is executed with user's privileges.

**Mitigations:**
- Custom commands require explicit user approval with a clear warning dialog
- Commands are displayed in full before execution
- No shell interpretation - commands use direct `exec()` with argument list (no `/bin/sh -c`)
- Dangerous patterns are detected and warned about (`rm -rf`, `sudo`, `curl | sh`, etc.)
- Whitelist of approved .desktop entries is the primary launch mechanism
- Custom commands are clearly marked as "Custom (Unverified)" in UI
- Command execution is logged
- Permission `command.execution` must be explicitly granted

**Residual Risk:** Low-Medium. User can still approve dangerous commands, but the system makes it explicit and difficult to do accidentally.

---

### T-004: Configuration File Tampering

**Severity:** Medium
**Likelihood:** Low
**Attack Vector:** A local attacker (or malware running as the same user) modifies configuration files to change application behavior, redirect widget data, or inject malicious settings.

**Mitigations:**
- Configuration is in user-owned XDG directories (standard file permissions)
- Configuration schema is validated on load - invalid values are rejected
- Versioned schema with migration prevents legacy attack surfaces
- Human-readable format (TOML) makes tampering detectable
- Sensitive values (API keys) stored in system secret service, not config files

**Residual Risk:** Low. If an attacker has write access to user files, they already have equivalent access to the user's account.

---

### T-005: D-Bus Service Impersonation

**Severity:** Medium
**Likelihood:** Low
**Attack Vector:** A malicious D-Bus service impersonates an MPRIS player or other expected service, sending crafted data to trigger bugs or information leaks.

**Mitigations:**
- D-Bus messages are validated before use (type checking, bounds checking)
- MPRIS metadata is treated as untrusted - sanitized before display
- D-Bus method call timeouts prevent hanging
- Service name validation (well-known bus names)
- Errors from D-Bus are handled gracefully (no crash, no data corruption)

**Residual Risk:** Low. D-Bus is a local IPC mechanism; attacker would already need code execution as the user.

---

### T-006: Supply Chain Attack via Dependencies

**Severity:** Critical
**Likelihood:** Low
**Attack Vector:** A compromised dependency (crate, npm package, system library) introduces malicious code into the application binary.

**Mitigations:**
- Dependency pinning with lockfiles (Cargo.lock)
- Regular `cargo audit` and `cargo deny` scanning in CI
- SBOM generation for every release
- Signed releases with checksums
- Minimal dependency tree (avoid large dependency graphs)
- Prefer well-established, widely-used dependencies
- Regular dependency updates with changelog review
- Reproducible builds where possible

**Residual Risk:** Low-Medium. Supply chain attacks are an industry-wide problem. Our mitigations follow best practices but cannot eliminate the risk entirely.

---

### T-007: Unauthorized System Access via Sensors

**Severity:** Low
**Likelihood:** Low
**Attack Vector:** A widget reads system sensor data (/proc, /sys) and exfiltrates it. This is low-sensitivity data but could reveal usage patterns.

**Mitigations:**
- System metrics are read by trusted core adapters, not directly by widgets
- Metrics data is in-memory only and discarded on application exit
- Community widgets (Level 3) cannot read /proc or /sys directly - they go through the capability API
- Permission `system.metrics.read` required for community widgets
- Network access is not permitted for community widgets by default
- Exfiltration would require a separate vulnerability (e.g., network access granted)

**Residual Risk:** Very Low. System metrics are low-value data. Exfiltration requires multiple permission grants.

---

### T-008: Crash Report Contains Sensitive Data

**Severity:** Medium
**Likelihood:** Medium
**Attack Vector:** A crash report or diagnostics export contains sensitive information (API keys, file paths, personal data) that is exposed to developers or in logs.

**Mitigations:**
- Hub and Manager receive a structured diagnostics allowlist containing only
  fixed labels, booleans and aggregate counts; raw config, licence/identity,
  widget settings and opaque UI-state content never cross the Rust FFI boundary
- Crash reports are opt-in (user must explicitly send)
- Malformed-config logs contain only the TOML error position, never the parser's
  source snippet or offending value
- Config files and every canonical/corrupt backup are forced to mode `0600` on Unix
- New credentials use secret-service references; legacy inline values remain
  supported for migration but are treated as sensitive and never diagnosed/logged
- Diagnostics bundle is stored in user-owned directory before export
- Review of diagnostics output before release to ensure no sensitive leaks

**Residual Risk:** Low. The configuration summary is allowlisted rather than
pattern-redacted, so novel opaque UI fields are omitted by default.

---

### T-009: Autostart Hijacking

**Severity:** Low
**Likelihood:** Low
**Attack Vector:** A malicious actor modifies the autostart .desktop file to add malicious arguments or redirect the application.

**Mitigations:**
- Autostart .desktop file is in user's XDG autostart directory (standard permissions)
- Application validates its own command-line arguments at startup
- No sensitive operations triggered by command-line arguments
- --reset flag is the only significant CLI argument and it clears configuration safely

**Residual Risk:** Very Low. Modifying autostart requires user-level file access.

---

### T-010: Resource Exhaustion (Denial of Service by Widget)

**Severity:** Medium
**Likelihood:** Medium (post-MVP)
**Attack Vector:** A community widget consumes excessive CPU, memory, or file descriptors, degrading the dashboard or the entire system.

**Mitigations:**
- Built-in widgets (MVP): timeout guards on update calls; slow widgets are throttled
- Community widgets (Phase 7): WASM resource limits (memory cap, fuel metering)
- Widget disable-on-repeated-failure (3 errors in 5 minutes)
- User can manually disable any widget
- Safe mode disables all non-built-in widgets

**Residual Risk:** Low. Resource limits are effective for WASM. Built-in widgets are trusted by definition.

---

## Security Controls Summary

| Control | MVP (Phase 1-6) | Post-MVP (Phase 7+) |
|---------|-----------------|---------------------|
| Widget sandbox (WASM) | N/A (no community widgets) | ✅ wasmtime with resource limits |
| Permission system | N/A | ✅ Manifest-declared, user-approved, enforced |
| Secret storage | File-based (acceptable for MVP, no API keys in MVP) | Secret Service (D-Bus) |
| Command execution guard | ✅ Warning dialog + no shell | ✅ Enhanced with permission system |
| Input validation | ✅ All external data validated | ✅ |
| Dependency scanning | ✅ cargo audit in CI | ✅ |
| SBOM generation | ✅ | ✅ |
| Signed releases | ✅ GPG or minisign | ✅ |
| Diagnostics redaction | ✅ Pattern-based | ✅ Enhanced |
| Content Security Policy | N/A (no web content widget) | ✅ For web content widget |
| Log sanitization | ✅ tracing filter rules | ✅ |
| Safe mode | ✅ --reset and --safe-mode flags | ✅ |

---

## Vulnerability Reporting

Security vulnerabilities should be reported privately to the maintainers. See [SECURITY.md](../../SECURITY.md) for the full process.

**Response Timeline:**
- Acknowledgment: within 48 hours
- Initial assessment: within 5 business days
- Fix release: depends on severity (Critical: 7 days, High: 30 days, Medium: 90 days)

---

## Related Documents

- [Widget Permissions](widget-permissions.md) (to be created)
- [SECURITY.md](../../SECURITY.md)
- [ADR-0002: Widget Runtime](../adr/0002-widget-runtime.md)
