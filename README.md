# Holy Nano MCP

An MCP server written in **HolyC** for Google's Nano Banana image-generation
models, with support for both the Gemini API / AI Studio and Vertex AI.

```
        MCP client                    HolyC MCP server                Google
    ┌────────────────┐            ┌──────────────────────┐        ┌───────────┐
    │ Claude / agent │──stdio────▶│ protocol → tools     │        │ Gemini    │
    │ IDE / MCP host │◀──JSON-RPC─│ → config → provider  │──curl─▶│ or Vertex │
    └────────────────┘            └──────────────────────┘        └───────────┘
```

The MCP layer knows tools and JSON-RPC and nothing about Google. The provider
layer knows endpoints, auth and schemas and nothing about MCP. That separation
is the point of the design, and it is what makes `FakeProvider` — and therefore
the test suite — possible without a network or a key.

## Tools

| Tool | What it does |
|---|---|
| `generate_image` | Generate an image from a prompt and save it to disk |
| `edit_image` | Edit an image on disk with a prompt |
| `list_models` | List model aliases and the Google model ids they map to |
| `provider_status` | Report provider, model, credential source and HTTPS backend |
| `security_check` | Check repo-local credentials are present, valid and not exposed |

```jsonc
// generate_image
{
  "prompt": "A futuristic cyberpunk city",
  "model": "nano-banana-2",
  "aspect_ratio": "16:9",
  "image_size": "2K",
  "output_path": "./generated/city.png"
}
// → {"success":true,"path":"./generated/city.png","mime_type":"image/png",
//    "model":"gemini-3.1-flash-image","provider":"gemini","width":1920,"height":1080}
```

```jsonc
// edit_image
{
  "prompt": "Add rain and neon reflections",
  "input_image": "./generated/city.png",
  "output_path": "./generated/edited.png"
}
```

Only `prompt` is required for `generate_image`; `prompt` and `input_image` for
`edit_image`. Everything else falls back to configuration.

## Models

| Alias | Google model | Notes |
|---|---|---|
| `nano-banana-2` | `gemini-3.1-flash-image` | Default. Generalist workhorse. |
| `nano-banana-2-lite` | `gemini-3.1-flash-lite-image` | Fastest and cheapest. |
| `nano-banana-pro` | `gemini-3-pro-image` | Highest quality and control. |
| `nano-banana` | `gemini-2.5-flash-image` | Legacy. |

An unrecognised name is passed through to the API unchanged, so a new model
works before this table is updated. The mapping lives in
`src/providers/models.HC`.

## Install

The compiler is [holyc-lang](https://github.com/Jamesbarford/holyc-lang)
(`hcc`). On Windows everything runs inside WSL2 — see
[docs/PHASE0.md](docs/PHASE0.md) for why.

**Linux / macOS / WSL2**

```sh
make toolchain     # installs hcc (needs git, cmake, make, a C compiler)
make build         # → build/holy-nano-mcp
make test          # unit tests + mock-API integration tests
```

**Windows PowerShell**

```powershell
.\scripts\build.ps1 -Toolchain   # first time only
.\scripts\build.ps1
.\scripts\build.ps1 -Test
```

`curl` must be on `PATH` at runtime: it provides TLS, which HolyC does not
have. `provider_status` reports whether it was found.

## Configure

### Credentials

Resolution order, stopping at the first hit:

```
1. explicit MCP configuration   --config <file>, $HOLY_NANO_MCP_CONFIG,
                                ~/.config/holy-nano-mcp/config.json
        │
2. ./service-account.json       repository-local
        │
3. environment variables        GEMINI_API_KEY, GOOGLE_API_KEY,
                                HOLY_NANO_MCP_API_KEY,
                                GOOGLE_APPLICATION_CREDENTIALS
        │
4. error                        reported by the tool that needed it
```

Pin the search to one layer with `--credentials-source mcp|repo|env`, or
`"credentials": {"source": "repo"}` in a config file. `auto` is the default.

**`service-account.json` means two different things.** It may hold this
project's configuration, or a real Google Cloud service-account key. The server
tells them apart by shape — a real key has `type: "service_account"`,
`private_key` and `client_email` — and models them as different credential
types. `security_check` and `provider_status` both report which one it found.

### Gemini API / AI Studio

```json
{ "provider": "gemini", "api_key": "AIza...", "model": { "default": "nano-banana-2" } }
```

Or leave the key out of the file entirely and export `GEMINI_API_KEY`.

### Vertex AI

```json
{
  "provider": "vertex",
  "project_id": "my-project",
  "location": "global",
  "auth": { "type": "service_account", "credentials_file": "./gcp-service-account.json" }
}
```

Three auth modes:

- **`api_key`** — Vertex express mode. No `project_id` or `location` needed.
- **`access_token`** — a bearer token you supply.
- **`service_account` / `adc`** — the token is minted by `gcloud auth
  print-access-token`. HolyC has no RS256 signing, so the gcloud CLI does that
  work; it must be installed and authenticated. `project_id` is required.

### MCP client

```json
{
  "mcpServers": {
    "holy-nano": {
      "command": "wsl.exe",
      "args": ["-d", "Ubuntu", "-e", "/mnt/d/projects/HOLY_NANO_MCP/build/holy-nano-mcp",
               "--output-dir", "./generated"],
      "env": { "GEMINI_API_KEY": "AIza..." }
    }
  }
}
```

On Linux, drop the `wsl.exe` wrapper and point `command` at the binary.

### Options

| Flag | Config key | Env | Default |
|---|---|---|---|
| `--provider` | `provider` | `HOLY_NANO_MCP_PROVIDER` | `gemini` |
| `--model` | `model.default` | `HOLY_NANO_MCP_MODEL` | `nano-banana-2` |
| `--output-dir` | `output.directory` | `HOLY_NANO_MCP_OUTPUT_DIR` | `./generated` |
| `--overwrite` | `output.overwrite` | — | off |
| `--project-id` | `project_id` | `GOOGLE_CLOUD_PROJECT` | — |
| `--location` | `location` | `GOOGLE_CLOUD_LOCATION` | `global` |
| `--api-style` | `api_style` | — | `interactions` |
| `--api-version` | `api_version` | — | `v1beta` |
| `--endpoint` | `endpoint` | — | — |
| `--credentials-source` | `credentials.source` | — | `auto` |
| `--log-level` | `log_level` | `HOLY_NANO_MCP_LOG_LEVEL` | `info` |
| `--config` | — | `HOLY_NANO_MCP_CONFIG` | `~/.config/holy-nano-mcp/config.json` |
| `--status` | — | — | — |

Without `--overwrite`, writing to an existing path picks `name-1.png`,
`name-2.png` and so on instead of replacing it.

There is deliberately **no `--api-key` flag**. Command lines are readable by
every process on the machine.

## Security

- The key never reaches `argv`. It travels to `curl` through a `0600` config
  file in a `0700` directory, which is deleted after the request.
- The key never reaches a log line or an MCP response. `Redact()` returns at
  most a 4-character prefix, and nothing at all for short secrets.
- Logs go to **stderr** only; stdout is the JSON-RPC transport.
- `.gitignore` covers `service-account.json`, `*.key`, `*.pem` and `.env`.
- `security_check` verifies the credential file is present, parses, is not
  tracked by git, and is covered by `.gitignore`.

`scripts/run-tests.sh` asserts each of these rather than trusting them.

## Layout

```
src/
  main.HC              include order = dependency order; the whole build
  mcp/                 jsonrpc, protocol, tool registry, tool handlers, stdio server
  providers/           provider interface, model aliases, gemini, vertex, fake
  auth/                credentials, service-account inspection, config loading
  http/                request, response, curl-backed client
  image/               base64, output paths, generate and edit pipelines
  utils/               strings and JSON output, logging, errors, argv, libc
tests/                 HolyC unit suites + a mock Google API
scripts/               build, test, toolchain install
docs/PHASE0.md         target, TLS strategy, compiler gotchas
```

## Tests

```sh
make unit   # HolyC unit tests only, no network
make test   # + stdio integration against tests/mock_google.py
```

The mock serves both the Interactions and `generateContent` response shapes,
plus forced API errors and text-only replies, and records every request so the
tests can assert on the headers and body the server actually sent.

## Adding a provider

1. Write `src/providers/yours.HC` exposing `YoursProviderNew(HnConfig *c)` that
   fills in `GenerateImage`, `EditImage`, `GetModelInfo` and `ValidateConfig`.
2. Add one branch to `ProviderResolve` in `src/providers/resolve.HC`.
3. Add the include to `src/main.HC`.

Nothing in `src/mcp/` changes.

## License

MIT. See [LICENSE](LICENSE).
