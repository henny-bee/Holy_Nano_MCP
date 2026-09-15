# Configuration Guide

Holy Nano MCP supports configuration via JSON files, environment variables, and CLI flags.

## Configuration Precedence

Settings are resolved in the following priority order (highest to lowest):
1. Command-line flags
2. MCP client configuration / settings file
3. Environment variables
4. Repository config files (`config/vertex.json`, `config/gemini.json`)
5. Built-in defaults

---

## Configuration Files

Config files are located in the `config/` directory.

### 1. Vertex AI (`config/vertex.json`)

Used when authenticating via Google Cloud Vertex AI and a Service Account key:

```json
{
  "provider": "vertex",
  "project_id": "your-gcp-project-id",
  "location": "global",
  "model": {
    "default": "nano-banana-pro"
  },
  "output": {
    "directory": "./generated",
    "overwrite": false
  },
  "system_prompts": {
    "directory": "./system_prompts",
    "enabled": true
  },
  "http_timeout": 180,
  "credentials": {
    "source": "auto"
  },
  "auth": {
    "type": "service_account",
    "credentials_file": "config/gcp-service-account.json"
  }
}
```

### 2. Gemini API (`config/gemini.json`)

Used when authenticating via Google AI Studio API Key:

```json
{
  "provider": "gemini",
  "api_key": "YOUR_GEMINI_API_KEY",
  "model": {
    "default": "nano-banana-2"
  },
  "output": {
    "directory": "./generated",
    "overwrite": false
  },
  "system_prompts": {
    "directory": "./system_prompts",
    "enabled": true
  },
  "http_timeout": 180,
  "credentials": {
    "source": "auto"
  }
}
```

---

## CLI Flags and Environment Variables

| Flag | Config Key | Environment Variable | Default | Description |
|---|---|---|---|---|
| `--config <path>` | - | `HOLY_NANO_MCP_CONFIG` | `~/.config/holy-nano-mcp/config.json` | Path to JSON config file |
| `--provider <name>` | `provider` | `HOLY_NANO_MCP_PROVIDER` | `gemini` | Provider: `gemini`, `vertex`, `fake` |
| `--model <alias>` | `model.default` | `HOLY_NANO_MCP_MODEL` | `nano-banana-2` | Default image model alias |
| `--output-dir <path>` | `output.directory` | `HOLY_NANO_MCP_OUTPUT_DIR` | `./generated` | Directory for generated images |
| `--overwrite` | `output.overwrite` | - | `false` | Overwrite existing output files |
| `--project-id <id>` | `project_id` | `GOOGLE_CLOUD_PROJECT` | - | Google Cloud Project ID |
| `--location <loc>` | `location` | `GOOGLE_CLOUD_LOCATION` | `global` | Vertex AI region/location |
| `--api-style <style>` | `api_style` | `HOLY_NANO_API_STYLE` | `interactions` | `interactions` or `generate_content` |
| `--api-version <ver>` | `api_version` | `HOLY_NANO_API_VERSION` | `v1beta` | API endpoint version |
| `--http-timeout <s>` | `http_timeout` | `HOLY_NANO_HTTP_TIMEOUT` | `180` | Request timeout in seconds |
| `--log-level <lvl>` | `log_level` | `HOLY_NANO_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error`, `off` |
| `--system-prompt-dir <path>` | `system_prompts.directory` | `HOLY_NANO_MCP_SYSTEM_PROMPT_DIR` | `./system_prompts` | Folder holding the per-mode `.md` prompts |
| `--no-system-prompts` | `system_prompts.enabled` | - | `true` | Send no system prompt at all |
| `--status` | - | - | - | Print resolved settings and exit |
| `--help` | - | - | - | Print usage information and exit |

---

## System Prompts

Each image call is sent with a system prompt chosen from the shape of the call,
never from a tool argument:

| Call | File read from the prompt folder |
|---|---|
| `generate_image` (text -> image) | `text_to_image.md` |
| `edit_image` (image + text -> image) | `image_and_text_to_image.md` |

The file is read on every call, so an edit takes effect on the next image
without restarting the server. A leading YAML front matter block is stripped;
the remainder is sent verbatim - as `systemInstruction` on `generateContent`, or
as the leading `input` text block on the Interactions API. A missing or blank
file is not an error: the call goes out with no system prompt.

### Folder resolution

1. `--system-prompt-dir`, then `system_prompts.directory`, then
   `HOLY_NANO_MCP_SYSTEM_PROMPT_DIR`.
2. `./system_prompts`, when the server was launched from the repository.
3. `system_prompts/` beside the directory holding `--config`, which is how the
   folder is still found when an MCP client launches the binary from elsewhere.

`--status` prints the folder that won and the size of each prompt, and every
successful `generate_image` / `edit_image` result reports the file it used in
its `system_prompt` field.
