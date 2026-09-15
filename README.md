# Holy Nano MCP

An MCP (Model Context Protocol) server written in **HolyC** for Google's Nano Banana image-generation models, supporting both **Vertex AI** (GCP Service Account) and **Gemini API** (AI Studio).

```
        MCP Client                    HolyC MCP Server                Google
    ┌────────────────┐            ┌──────────────────────┐        ┌───────────┐
    │ Claude / Cline │──stdio────▶│ Protocol → Tools     │        │ Vertex AI │
    │ VS Code / IDE  │◀──JSON-RPC─│ → Config → Provider  │──curl─▶│    or     │
    └────────────────┘            └──────────────────────┘        │ Gemini    │
                                                                  └───────────┘
```

---

## ⚡ Quick Setup Guide

### 🪟 Windows One-Command Setup (Automated)
Run this single command from the project root:
```cmd
holy-nano setup
```
*(Or double-click `setup.bat`)*

**What this does automatically:**
1. ✅ Checks and compiles the HolyC binary in WSL (0% Hyper-V overhead).
2. ✅ Guides you to configure Vertex AI or Gemini API key.
3. ✅ **Auto-injects** MCP settings directly into Cline, Claude Desktop, Cursor, and Roo Code!
4. ✅ Verifies credentials and server readiness.

To start the server anytime:
```cmd
holy-nano start
```
*(Or run `start_sse.bat`)*

---

### 🐧 Manual Setup (Linux / macOS / WSL)

### 1. Build the Binary

- **Linux / macOS / WSL:**
  ```bash
  make toolchain     # First time only (installs hcc compiler)
  make build         # Compiles to build/holy-nano-mcp
  make test          # Runs tests
  ```

- **Windows (PowerShell):**
  ```powershell
  .\scripts\build.ps1 -Toolchain   # First time only (installs inside WSL2)
  .\scripts\build.ps1
  .\scripts\build.ps1 -Test
  ```

---

### 2. Configure Credentials

Choose either **Option A** (Google Cloud Vertex AI) or **Option B** (Gemini API Key):

#### Option A: Vertex AI (Google Cloud Service Account) — *Recommended*
1. Place your GCP Service Account JSON key at `config/gcp-service-account.json`.
2. Edit `config/vertex.json` and set your GCP `project_id`:
   ```json
   {
     "provider": "vertex",
     "project_id": "your-gcp-project-id",
     "location": "global",
     "model": {
       "default": "nano-banana-pro"
     },
     "output": {
       "directory": "./generated"
     },
     "auth": {
       "type": "service_account",
       "credentials_file": "config/gcp-service-account.json"
     }
   }
   ```

#### Option B: Gemini API Key (Google AI Studio)
Set the `GEMINI_API_KEY` environment variable in your MCP client config, or specify it in `config/gemini.json`:
```json
{
  "provider": "gemini",
  "api_key": "your-gemini-api-key",
  "model": {
    "default": "nano-banana-2"
  },
  "output": {
    "directory": "./generated"
  }
}
```

---

### 3. Add to MCP Client (Cline / Claude Desktop / VS Code)

You can connect via **HTTP / SSE** (simple `localhost:4392` URL) or **Direct Stdio Command**:

#### Option 1: HTTP / SSE Transport (`localhost:4392/holy-nano`) — *Easiest & Cleanest*

1. Start the SSE server bridge (in PowerShell / Command Prompt / Terminal):
   ```cmd
   start_sse.bat
   # or: python scripts/holy_server.py
   ```
2. Configure your MCP settings (`cline_mcp_settings.json`):
   ```json
   {
     "mcpServers": {
       "holy-nano": {
         "url": "http://localhost:4392/holy-nano",
         "timeout": 180,
         "autoApprove": [
           "generate_image",
           "edit_image",
           "list_models",
           "provider_status",
           "security_check"
         ]
       }
     }
   }
   ```

#### Option 2: Direct Stdio Command (WSL2 / Linux)

- **On Windows (via WSL2)**:
  ```json
  {
    "mcpServers": {
      "holy-nano": {
        "command": "wsl.exe",
        "args": [
          "-d", "Ubuntu",
          "-e", "/mnt/d/projects/HOLY_NANO_MCP/build/holy-nano-mcp",
          "--config", "/mnt/d/projects/HOLY_NANO_MCP/config/vertex.json"
        ],
        "timeout": 180,
        "autoApprove": [
          "generate_image",
          "edit_image",
          "list_models",
          "provider_status",
          "security_check"
        ]
      }
    }
  }
  ```

- **On Linux / macOS**:
  ```json
  {
    "mcpServers": {
      "holy-nano": {
        "command": "/path/to/HOLY_NANO_MCP/build/holy-nano-mcp",
        "args": ["--config", "/path/to/HOLY_NANO_MCP/config/vertex.json"],
        "timeout": 180
      }
    }
  }
  ```

---

### 4. Verify Installation

Check connection and credentials directly from terminal:

```bash
# WSL / Linux
./build/holy-nano-mcp --status --config config/vertex.json
```

Output should report `Status: OK`.

---

## 🛠️ MCP Tools

| Tool | Description | Required Parameters |
|---|---|---|
| `generate_image` | Generate an image from a prompt and save to disk | `prompt` |
| `edit_image` | Edit an existing image with text instructions | `prompt`, `input_image` |
| `list_models` | List supported model aliases and mapped Google IDs | *None* |
| `provider_status`| Check active provider, model, auth status, and curl backend | *None* |
| `security_check` | Audit credential security, file permissions, and `.gitignore` | *None* |

### Example Tool Calls

**Generate Image:**
```jsonc
{
  "prompt": "A futuristic cyberpunk car driving through rain in Tokyo",
  "model": "nano-banana-pro",
  "aspect_ratio": "16:9",
  "image_size": "2K"
}
```

**Edit Image:**
```jsonc
{
  "input_image": "./generated/car.png",
  "prompt": "Change the lighting to golden hour sunset and add lens flare",
  "output_path": "./generated/car-sunset.png"
}
```

---

## 🎨 Supported Models

| Alias | Google Model ID | Best For |
|---|---|---|
| `nano-banana-2` | `gemini-3.1-flash-image` | Default. Fast general image generation & text rendering. |
| `nano-banana-2-lite` | `gemini-3.1-flash-lite-image` | Fastest and cheapest. |
| `nano-banana-pro` | `gemini-3-pro-image` | Highest fidelity, world knowledge & creative control. |
| `nano-banana` | `gemini-2.5-flash-image` | Legacy compatibility. |

---

## ⚙️ CLI Options & Flags

| Flag | Config Key | Environment Variable | Default |
|---|---|---|---|
| `--config` | — | `HOLY_NANO_MCP_CONFIG` | `~/.config/holy-nano-mcp/config.json` |
| `--provider` | `provider` | `HOLY_NANO_MCP_PROVIDER` | `gemini` |
| `--model` | `model.default` | `HOLY_NANO_MCP_MODEL` | `nano-banana-2` |
| `--output-dir` | `output.directory` | `HOLY_NANO_MCP_OUTPUT_DIR` | `./generated` |
| `--overwrite` | `output.overwrite` | — | `false` |
| `--project-id` | `project_id` | `GOOGLE_CLOUD_PROJECT` | — |
| `--location` | `location` | `GOOGLE_CLOUD_LOCATION` | `global` |
| `--status` | — | — | (Prints status and exits) |

---

## 🔒 Security & Privacy

- **Safe Secret Handling**: Secrets are never passed via command-line arguments (`argv`). Auth tokens are sent to `curl` through temporary secure `0600` config files in a `0700` directory, deleted immediately after use.
- **No Leaks in Logs**: API keys and tokens are automatically redacted from logs and MCP responses (`Redact()`).
- **Standard Stdio Isolation**: Logs go to **stderr** only; standard stdout is reserved purely for MCP JSON-RPC messages.
- **Git Protection**: `.gitignore` ensures credentials (`config/gcp-service-account.json`, `*.key`, `*.pem`, `.env`) are never tracked.
- **Audit Tool**: The `security_check` tool verifies local credentials exist, parse correctly, and are properly protected.

---

## 🧪 Testing

```bash
make unit   # Run HolyC unit test suite (198 tests)
make test   # Run unit tests + mock stdio integration tests
```

---

## 📁 Project Structure

```
src/
  main.HC              Main entrypoint & dependency includes
  mcp/                 JSON-RPC 2.0 protocol, tool handlers, stdio server
  providers/           Gemini, Vertex AI, and fake test providers
  auth/                Credentials, GCP Service Account parser, config loader
  http/                CURL-backed HTTPS client
  image/               Base64 encoder/decoder, output file managers
  utils/               JSON formatting, logging, string helpers
tests/                 HolyC unit tests & mock Google API server
```

---

## 📄 License

MIT. See [LICENSE](LICENSE).
