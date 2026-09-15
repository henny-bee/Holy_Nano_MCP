# Supported Image Models

Holy Nano MCP maps intuitive model aliases to Google's Nano Banana and Gemini image generation model IDs.

## Model Matrix

| Alias | Google Model ID | Typical Latency | Recommended Use Case |
|---|---|---|---|
| `nano-banana-2` | `gemini-3.1-flash-image` | Fast (~2-4s) | General purpose image generation, text rendering, diagrams. Default model. |
| `nano-banana-2-lite` | `gemini-3.1-flash-lite-image` | Very Fast (~1-2s) | High-throughput, rapid prototyping, lowest cost. |
| `nano-banana-pro` | `gemini-3-pro-image` | Standard (~5-8s) | Maximum fidelity, photorealism, complex multi-subject prompts. |
| `nano-banana` | `gemini-2.5-flash-image` | Fast (~3-5s) | Legacy compatibility. |

---

## Tool Parameter Reference

### 1. `generate_image`

Generates an image from a text description.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `prompt` | string | Yes | - | Detailed description of the image to generate |
| `model` | string | No | `nano-banana-2` | Model alias or Google model ID |
| `aspect_ratio` | string | No | `1:1` | Options: `1:1`, `3:4`, `4:3`, `9:16`, `16:9` |
| `image_size` | string | No | `1K` | Resolution option (e.g. `1K`, `2K`) |
| `output_path` | string | No | Auto-generated | Target file path (`.png`, `.jpg`, `.webp`) |
| `negative_prompt`| string | No | - | Elements to avoid in the generation |

### 2. `edit_image`

Applies modifications to an existing image using text instructions.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `input_image` | string | Yes | - | Path to the source image file on disk |
| `prompt` | string | Yes | - | Instructions describing the desired edits |
| `output_path` | string | No | Auto-generated | Target file path for the edited image |
| `model` | string | No | `nano-banana-2` | Model alias to perform the transformation |
