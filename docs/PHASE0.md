# Phase 0 — Foundation

## Target

**holyc-lang (`hcc`) — Linux x86_64**  
Windows development uses **WSL2**.

TempleOS is not suitable as the runtime target because it lacks the networking, TLS, process, and stdio capabilities required by an MCP server.

| Area | Decision |
|---|---|
| Compiler | `holyc-lang` / `hcc` |
| Target | Linux x86_64 |
| Build | `hcc src/main.HC -o build/holy-nano-mcp` |
| JSON | stdlib `json.HC` + custom serializer |
| HTTP | `curl` binary |
| TLS | Delegated to `curl` |
| Build model | Single translation unit via `src/main.HC` |

## HTTP & TLS

HolyC has no native TLS. HTTP requests are delegated to `curl`.

**Security requirements:**
- API keys must never appear in `argv`.
- Temporary `curl` config/body files use `0600` permissions.
- Temporary directory uses `0700`.
- Credentials are removed after each request.
- Secrets must never appear in logs or MCP responses.

The HTTP implementation is isolated in `src/http/client.HC`, allowing future replacement with libcurl FFI or native TLS.

## JSON

- Parsing uses the holyc-lang standard `json.HC`.
- Serialization uses the project's own implementation.
- JSON escaping is explicitly tested to protect JSON-RPC output integrity.

## HolyC Compiler Notes

Important limitations:

- No ternary operator (`?:`).
- Avoid mixing pointers and booleans in `&&` / `||`.
- Array indexes must use `I64`.
- `Main` has no direct `argv`; arguments are recovered from `/proc/self/cmdline`.
- `/proc` files require raw descriptor reads.
- `printf` does not support `%.Ns` string precision.
- Protocol I/O uses libc `write`: stdout for JSON-RPC, stderr for logs.

## Verified Google Models

Verified against Google documentation on **2026-09-14**:

| Alias | Model |
|---|---|
| `nano-banana-2` | `gemini-3.1-flash-image` |
| `nano-banana-2-lite` | `gemini-3.1-flash-lite-image` |
| `nano-banana-pro` | `gemini-3-pro-image` |
| `nano-banana` | `gemini-2.5-flash-image` |

Gemini supports the **Interactions API** (`/v1beta/interactions`) while Vertex AI exposes `generateContent`. Both wire formats are implemented and selectable through `api_style`, with the response parser supporting either format.