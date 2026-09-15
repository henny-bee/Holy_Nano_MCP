# System Prompts

Each file here is a system prompt. Holy Nano picks one automatically from the
shape of the call - you never pass it as a tool argument.

| File | Mode | Sent with |
|---|---|---|
| `text_to_image.md` | text -> image | `generate_image` |
| `image_and_text_to_image.md` | image + text -> image | `edit_image` |

## Editing one

Open the file, change the words, save. The server re-reads the file on every
call, so the next image already uses the new text - no rebuild, no restart.

Everything between the opening `---` and the closing `---` at the top of the
file is stripped and never sent to the model, so that block is a good place for
notes. The rest of the file is sent verbatim, Markdown and all.

To send nothing for a mode, empty the file (or delete it). A missing or blank
file is not an error - the call simply goes out without a system prompt.

## Where it ends up on the wire

| API surface | Field |
|---|---|
| `generateContent` (Vertex, and Gemini with `api_style: generate_content`) | `systemInstruction` |
| `interactions` (Gemini default) | a leading text block in `input` |

## Checking it is being used

```
holy-nano status
```

prints which folder was resolved and the size of each prompt. Every successful
`generate_image` / `edit_image` result also reports the file it used in its
`system_prompt` field.

## Pointing somewhere else

| Where | How |
|---|---|
| Config file | `"system_prompts": { "directory": "./my-prompts", "enabled": true }` |
| Environment | `HOLY_NANO_MCP_SYSTEM_PROMPT_DIR=/path/to/prompts` |
| CLI | `--system-prompt-dir <path>`, or `--no-system-prompts` to turn them off |

The file names inside the folder stay the same.
