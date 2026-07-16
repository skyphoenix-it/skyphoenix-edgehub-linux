---
apply: by model decision
instructions: Apply when work affects plugins, widgets, MCP, external webpages, APIs, credentials, databases, processes, commands, files, networking, or updates.
---

# Security and Integration Requirements

- Deny permissions by default.
- Never expose arbitrary shell execution to untrusted widgets.
- Validate and normalize paths before file access.
- Validate command arguments without building shell strings.
- Treat external web content as untrusted.
- Do not expose privileged application APIs to arbitrary webpages.
- Keep secrets in the operating-system secret store where possible.
- Never log tokens, credentials, session cookies, or confidential payloads.
- Apply timeouts and cancellation to external calls.
- Bound retries, response sizes, queues, caches, and log growth.
- Use least-privilege database and service accounts.
- Separate read-only and write-capable integrations.
- Require confirmation for destructive operations.
- A failed integration must not crash or freeze the main application.
- Third-party widget failures must remain isolated from the main UI.