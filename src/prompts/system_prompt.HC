#ifndef HN_PROMPTS_SYSTEM_PROMPT
#define HN_PROMPTS_SYSTEM_PROMPT

/* System prompts, one Markdown file per call shape.
 *
 *   text_to_image.md             generate_image  (prompt only)
 *   image_and_text_to_image.md   edit_image      (prompt + source image)
 *
 * The file is chosen from the shape of the call, never from a tool argument,
 * so a client cannot talk its way past the house style. Files are re-read per
 * call: an image request is already a multi-second HTTPS round trip, so one
 * small read costs nothing and means editing the Markdown takes effect without
 * restarting the server. */

#define SYS_PROMPT_T2I  0
#define SYS_PROMPT_IT2I 1

#define SYS_PROMPT_DEFAULT_DIR "./system_prompts"

U8 *SysPromptKindName(I64 kind)
{
  if (kind == SYS_PROMPT_IT2I) return "image_and_text_to_image";
  return "text_to_image";
}

U8 *SysPromptFileName(I64 kind)
{
  if (kind == SYS_PROMPT_IT2I) return "image_and_text_to_image.md";
  return "text_to_image.md";
}

U8 *g_sysprompt_dir = NULL;

/* Resolves the folder once.
 *
 * A configured path wins outright. Otherwise ./system_prompts, which is right
 * whenever the server is launched from the repository - and when it is not,
 * the folder that sits beside the config file's directory, because the config
 * path is the one absolute location a client always hands us. */
U8 *SysPromptDir(HnConfig *c)
{
  if (g_sysprompt_dir) return g_sysprompt_dir;

  if (c != NULL && c->system_prompt_dir != NULL && c->system_prompt_dir[0] != 0) {
    g_sysprompt_dir = StrDup(c->system_prompt_dir);
    return g_sysprompt_dir;
  }

  if (PathExists(SYS_PROMPT_DEFAULT_DIR)) {
    g_sysprompt_dir = StrDup(SYS_PROMPT_DEFAULT_DIR);
    return g_sysprompt_dir;
  }

  if (c != NULL && c->config_path != NULL) {
    U8 *cfg_dir = PathParent(c->config_path);
    if (cfg_dir) {
      U8 *repo = PathParent(cfg_dir);
      Free(cfg_dir);
      if (repo) {
        U8 *candidate = StrPrint(NULL, "%s/system_prompts", repo);
        Free(repo);
        if (PathExists(candidate)) {
          g_sysprompt_dir = candidate;
          return g_sysprompt_dir;
        }
        Free(candidate);
      }
    }
  }

  g_sysprompt_dir = StrDup(SYS_PROMPT_DEFAULT_DIR);
  return g_sysprompt_dir;
}

U8 *SysPromptPath(HnConfig *c, I64 kind)
{
  return StrPrint(NULL, "%s/%s", SysPromptDir(c), SysPromptFileName(kind));
}

Bool SysPromptEnabled(HnConfig *c)
{
  if (!c) return FALSE;
  return c->system_prompts_enabled != 0;
}

/* Drops a leading YAML front matter block, so a prompt file can carry notes
 * that are never sent to the model. Without a closing marker there is no front
 * matter, only a file that happens to start with a rule - which is left alone
 * rather than silently swallowed. */
U8 *SysPromptStripFrontMatter(U8 *raw)
{
  if (!raw) return NULL;

  U8 *p = raw;
  while (p[0] == ' ' || p[0] == 0x09 || p[0] == 0x0D || p[0] == 0x0A) p++;

  Bool opens = p[0] == '-' && p[1] == '-' && p[2] == '-';
  if (opens) opens = p[3] == 0x0A || p[3] == 0x0D;
  if (!opens) return StrTrimDup(p);

  I64 i = 3;
  while (p[i] != 0) {
    if (p[i] == 0x0A) {
      I64 j = i + 1;
      if (p[j] == '-' && p[j + 1] == '-' && p[j + 2] == '-') {
        I64 k = j + 3;
        while (p[k] == ' ' || p[k] == 0x09 || p[k] == 0x0D) k++;
        if (p[k] == 0x0A || p[k] == 0) return StrTrimDup(p + k);
      }
    }
    i++;
  }
  return StrTrimDup(p);
}

/* The prompt text for `kind`, or NULL when there is none to send. A missing or
 * blank file is a supported way to say "no system prompt", not an error, so it
 * never fails a generation. `out_path` receives an owned copy of the file that
 * was used, and is only written on success. */
U8 *SysPromptLoad(HnConfig *c, I64 kind, U8 **out_path)
{
  if (!SysPromptEnabled(c)) return NULL;

  U8 *path = SysPromptPath(c, kind);
  if (!PathExists(path)) {
    LogDebug("no system prompt for %s at %s", SysPromptKindName(kind), path);
    Free(path);
    return NULL;
  }

  I64 len = 0;
  U8 *raw = ReadFdFile(path, &len);
  if (raw == NULL || len <= 0) {
    if (raw) Free(raw);
    Free(path);
    return NULL;
  }

  U8 *text = SysPromptStripFrontMatter(raw);
  Free(raw);
  if (text == NULL || text[0] == 0) {
    if (text) Free(text);
    Free(path);
    return NULL;
  }

  if (out_path) *out_path = path;
  else Free(path);
  return text;
}

/* Attaches the system prompt for `kind` to a request. An instruction already
 * on the request wins, so a caller that sets one by hand - the test suite,
 * today - is not overridden. */
U0 SysPromptApply(HnConfig *c, ImageRequest *req, I64 kind)
{
  if (!req) return;
  if (req->system_prompt != NULL) return;

  U8 *path = NULL;
  U8 *text = SysPromptLoad(c, kind, &path);
  if (!text) return;

  req->system_prompt = text;
  req->system_prompt_source = path;
  LogInfo("system prompt %s from %s (%d chars)",
          SysPromptKindName(kind), path, StrLen(text));
}

/* One status line per mode, for `--status`. Reports size rather than content:
 * a prompt file is long, and the question being asked is "is it loaded". */
U0 SysPromptStatusLine(StrBuf *sb, HnConfig *c, I64 kind)
{
  U8 *path = SysPromptPath(c, kind);
  SbCat(sb, "\n  ");
  SbCat(sb, SysPromptKindName(kind));
  SbCat(sb, " -> ");
  SbCat(sb, SysPromptFileName(kind));
  SbCat(sb, " ");

  if (!PathExists(path)) {
    SbCat(sb, "(missing)");
  } else {
    U8 *text = SysPromptLoad(c, kind, NULL);
    if (text == NULL) {
      SbCat(sb, "(empty)");
    } else {
      SbCatCh(sb, '(');
      SbCatI64(sb, StrLen(text));
      SbCat(sb, " chars)");
      Free(text);
    }
  }
  Free(path);
}

U0 SysPromptStatus(StrBuf *sb, HnConfig *c)
{
  SbCat(sb, "\nSystem prompts: ");
  if (!SysPromptEnabled(c)) {
    SbCat(sb, "disabled");
    return;
  }
  SbCat(sb, SysPromptDir(c));
  SysPromptStatusLine(sb, c, SYS_PROMPT_T2I);
  SysPromptStatusLine(sb, c, SYS_PROMPT_IT2I);
}

#endif
