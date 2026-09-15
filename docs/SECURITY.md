# Security and Credential Isolation

Holy Nano MCP is designed with strict secret handling and process isolation standards.

## Principles

1. **No Secrets in Process Arguments (`argv`)**
   Command line arguments are readable by other processes on the host via `/proc` or process management tools. API keys and service account tokens are never passed as CLI arguments.

2. **Secure Temporary Storage**
   When invoking backend HTTP transport commands (`curl`), headers and sensitive payload data are written to temporary configuration files with `0600` permissions (owner read/write only) inside a private `0700` directory. Files are removed immediately upon completion.

3. **Stderr-Only Logging & Automatic Redaction**
   All diagnostic and server logs are directed strictly to standard error (`stderr`), leaving standard output (`stdout`) clean for MCP JSON-RPC protocol frames. Any key patterns in logs are masked using internal redaction routines.

4. **Repository and Git Protection**
   The repository `.gitignore` explicitly prevents accidental commit of credentials:
   - `config/gcp-service-account.json`
   - `config/vertex.json`
   - `config/gemini.json`
   - `*.key`, `*.pem`, `.env*`

5. **Built-in Security Audit Tool**
   The server includes a `security_check` tool that can be invoked through MCP to verify file permissions, credential validity, and git tracking status without leaking secret values.
