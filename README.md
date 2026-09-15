# Holy Nano MCP

An MCP (Model Context Protocol) server written in HolyC for Google's Nano Banana image-generation models, supporting both Google Cloud Vertex AI (Service Account) and Gemini API (AI Studio).


<img width="1089" height="432" alt="image" src="https://github.com/user-attachments/assets/d84f4af0-bc17-4f44-99f0-ef5002d6ecc7" />



---

## Requirements

WSL2 with Ubuntu and `curl` (Windows hosts), `hcc` for building (`make toolchain`), and Python 3.8+ with `aiohttp` (`pip install aiohttp`) for the SSE bridge only.

---

## Quick Setup

### Windows (Automated CLI)

Open a terminal **in the project root** and run the installer:

| Your shell | Command |
|---|---|
| Command Prompt (`cmd.exe`) | `holy-nano setup` |
| PowerShell | `.\holy-nano setup` |

This automatically:
1. Builds the HolyC binary in WSL (with zero Hyper-V background overhead).
2. Sets up your preferred credentials (Vertex AI or Gemini).
3. Automatically injects MCP settings into Cline, Claude Desktop, Cursor, and Roo Code.
4. Verifies provider connectivity.

Then start the server:

| Your shell | Command |
|---|---|
| Command Prompt (`cmd.exe`) | `holy-nano start` |
| PowerShell | `.\holy-nano start` |

*(No terminal? Just double-click `setup.bat`, then `start_sse.bat`.)*

#### Why the `.\` in PowerShell?

PowerShell never runs a program from the current folder, so typing `holy-nano start`
there fails with:

```
holy-nano : The term 'holy-nano' is not recognized as the name of a cmdlet,
function, script file, or operable program.
```

That is not an error in Holy Nano - the `.\` prefix is what tells PowerShell to look
in the current folder. To type `holy-nano` anywhere without the prefix, add the repo
to your PATH once:

```powershell
[Environment]::SetEnvironmentVariable(
  "Path", $env:Path + ";C:\path\to\HOLY_NANO_MCP", "User")
```

Then reopen your terminal.

---

### Linux / macOS / WSL (Manual)

1. **Install compiler & build:**
   ```bash
   make toolchain     # First time only (installs holyc-lang hcc compiler)
   make build         # Builds to build/holy-nano-mcp
   make test          # Runs test suite
   ```

2. **Configure credentials:**
   - **Vertex AI:** Place GCP Service Account JSON at `config/gcp-service-account.json` and adjust `config/vertex.json`.
   - **Gemini API:** Set your key in `config/gemini.json` or export `GEMINI_API_KEY="YOUR_KEY"`.

---

## MCP Client Configuration

### Method 1: HTTP / SSE (Recommended)

Start the server bridge:
```cmd
holy-nano start
```

Add to your MCP settings file (`cline_mcp_settings.json` or `claude_desktop_config.json`):

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

### Method 2: Direct Stdio Command

On Windows both paths are read by WSL, so they must be WSL paths (`/mnt/d/projects/HOLY_NANO_MCP/...`), not `D:\...`.

```json
{
  "mcpServers": {
    "holy-nano": {
      "command": "wsl.exe",
      "args": [
        "-d", "Ubuntu",
        "-e", "/path/to/HOLY_NANO_MCP/build/holy-nano-mcp",
        "--config", "/path/to/HOLY_NANO_MCP/config/vertex.json"
      ],
      "timeout": 180
    }
  }
}
```

---

## Available MCP Tools

| Tool | Description | Required Arguments |
|---|---|---|
| `generate_image` | Generate an image from a text prompt and save to disk | `prompt` |
| `edit_image` | Edit an existing image with text instructions | `prompt`, `input_image` |
| `list_models` | List supported model aliases and mapped Google model IDs | None |
| `provider_status` | Check active provider, model, auth status, and curl backend | None |
| `security_check` | Audit credential security, file permissions, and git tracking | None |

---

## Windows CLI Commands

| Command | Purpose |
|---|---|
| `holy-nano setup` | Run interactive installer and auto-inject MCP settings |
| `holy-nano start` | Start the localhost SSE server bridge |
| `holy-nano status` | Display resolved provider and credential status |
| `holy-nano test` | Run HolyC unit and integration tests |

Run these from the project root. In PowerShell, prefix them with `.\` (e.g.
`.\holy-nano start`) - see [Why the `.\` in PowerShell?](#why-the--in-powershell).

---

## Documentation

For detailed technical references, see the documentation in `docs/`:

- [Configuration Guide](docs/CONFIGURATION.md) - Detailed options, precedence, and CLI flags
- [Supported Models](docs/MODELS.md) - Model matrix, latency, and tool parameter specs
- [Security & Privacy](docs/SECURITY.md) - Credential isolation, secret hygiene, and permissions
- [Architecture & Foundation](docs/PHASE0.md) - System architecture and compiler design

---

## License

MIT. See [LICENSE](LICENSE).
