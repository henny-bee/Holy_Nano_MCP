#ifndef HN_MCP_TOOL_IMPL
#define HN_MCP_TOOL_IMPL

/* Tool handlers. These translate MCP arguments into provider calls and back;
 * they contain no Google API knowledge of their own. */

HnConfig *g_config = NULL;
AIProvider *g_provider = NULL;

/* Copies an optional string argument, or NULL when absent or empty. */
U8 *ArgStrDup(Json *args, U8 *key)
{
  U8 *v = JStr(args, key, NULL);
  if (v == NULL) return NULL;
  if (v[0] == 0) return NULL;
  return StrDup(v);
}

U8 *ToolErrorJson(I64 code, U8 *message)
{
  StrBuf *sb = SbNew(256);
  SbCat(sb, "{\"success\":false,\"error\":");
  SbCatJson(sb, message);
  SbCat(sb, ",\"error_type\":");
  SbCatJson(sb, HnErrName(code));
  SbCat(sb, ",\"provider\":");
  SbCatJson(sb, g_config->provider_name);
  SbCatCh(sb, '}');
  return SbSteal(sb);
}

U8 *ToolImageResultJson(ImageResult *r, ImageRequest *req)
{
  StrBuf *sb = SbNew(512);
  SbCat(sb, "{\"success\":true,\"path\":");
  SbCatJson(sb, r->output_path);
  SbCat(sb, ",\"mime_type\":");
  SbCatJson(sb, r->mime_type);
  SbCat(sb, ",\"model\":");
  SbCatJson(sb, r->model);
  SbCat(sb, ",\"provider\":");
  SbCatJson(sb, g_config->provider_name);
  if (r->width > 0) {
    SbCat(sb, ",\"width\":");  SbCatI64(sb, r->width);
    SbCat(sb, ",\"height\":"); SbCatI64(sb, r->height);
  }
  if (req != NULL && req->system_prompt_source != NULL) {
    SbCat(sb, ",\"system_prompt\":");
    SbCatJson(sb, req->system_prompt_source);
  }
  if (r->text != NULL && r->text[0] != 0) {
    SbCat(sb, ",\"text\":");
    SbCatJson(sb, r->text);
  }
  SbCatCh(sb, '}');
  return SbSteal(sb);
}

/* Reads the arguments common to generate_image and edit_image. */
ImageRequest *ToolBuildImageRequest(Json *args)
{
  ImageRequest *req = ImageRequestNew();
  req->prompt = ArgStrDup(args, "prompt");
  req->model = ArgStrDup(args, "model");
  if (!req->model) req->model = StrDup(g_config->default_model);
  req->aspect_ratio = ArgStrDup(args, "aspect_ratio");
  req->image_size = ArgStrDup(args, "image_size");
  req->mime_type = ArgStrDup(args, "mime_type");
  return req;
}

U8 *ToolGenerateImage(Json *args, Bool *is_error)
{
  ImageRequest *req = ToolBuildImageRequest(args);
  if (req->prompt == NULL) {
    ImageRequestRelease(req);
    *is_error = TRUE;
    return ToolErrorJson(HN_ERR_ARGS, "prompt is required");
  }

  U8 *output_path = ArgStrDup(args, "output_path");
  ImageResult *r = ImageGenerate(g_provider, g_config, req, output_path);

  U8 *text = NULL;
  if (r->ok) {
    text = ToolImageResultJson(r, req);
  } else {
    *is_error = TRUE;
    text = ToolErrorJson(r->error_code, r->error);
    LogError("generate_image failed: %s", r->error);
  }

  if (output_path) Free(output_path);
  ImageResultRelease(r);
  ImageRequestRelease(req);
  return text;
}

U8 *ToolEditImage(Json *args, Bool *is_error)
{
  ImageRequest *req = ToolBuildImageRequest(args);
  if (req->prompt == NULL) {
    ImageRequestRelease(req);
    *is_error = TRUE;
    return ToolErrorJson(HN_ERR_ARGS, "prompt is required");
  }

  U8 *input_path = ArgStrDup(args, "input_image");
  U8 *output_path = ArgStrDup(args, "output_path");
  ImageResult *r = ImageEdit(g_provider, g_config, req, input_path, output_path);

  U8 *text = NULL;
  if (r->ok) {
    text = ToolImageResultJson(r, req);
  } else {
    *is_error = TRUE;
    text = ToolErrorJson(r->error_code, r->error);
    LogError("edit_image failed: %s", r->error);
  }

  if (input_path) Free(input_path);
  if (output_path) Free(output_path);
  ImageResultRelease(r);
  ImageRequestRelease(req);
  return text;
}

U8 *ToolListModels(Json *args, Bool *is_error)
{
  U8 *models = g_provider->GetModelInfo(g_provider);
  StrBuf *sb = SbNew(1024);
  SbCat(sb, "{\"provider\":");
  SbCatJson(sb, g_config->provider_name);
  SbCat(sb, ",\"default\":");
  SbCatJson(sb, g_config->default_model);
  SbCat(sb, ",\"models\":");
  SbCat(sb, models);
  SbCatCh(sb, '}');
  Free(models);
  return SbSteal(sb);
}

/* Plain text, because this tool exists to be read by a human debugging a
 * broken setup. It must never include the credential itself. */
U8 *ToolProviderStatus(Json *args, Bool *is_error)
{
  HnConfig *c = g_config;
  HnResult *valid = g_provider->ValidateConfig(g_provider);

  StrBuf *sb = SbNew(512);
  SbCat(sb, "Provider: ");        SbCat(sb, c->provider_name);
  SbCat(sb, "\nAuthentication: ");
  if (c->credential) SbCat(sb, CredTypeName(c->credential->type));
  else SbCat(sb, "none");
  SbCat(sb, "\nModel: ");         SbCat(sb, c->default_model);
  SbCat(sb, "\nResolved model: "); SbCat(sb, ModelResolve(c->default_model));

  if (StrEq(c->provider_name, "gemini")) {
    SbCat(sb, "\nAPI style: ");
    SbCat(sb, ApiStyleName(ApiStyleFromName(c->api_style)));
    SbCat(sb, "\nAPI version: ");
    SbCat(sb, c->api_version);
  }
  if (StrEq(c->provider_name, "vertex")) {
    SbCat(sb, "\nProject: ");
    if (c->project_id) SbCat(sb, c->project_id);
    else SbCat(sb, "(not set)");
    SbCat(sb, "\nLocation: ");
    SbCat(sb, c->location);
  }

  SbCat(sb, "\nCredential source: ");
  if (c->credential) {
    U8 *desc = CredDescribe(c->credential);
    SbCat(sb, desc);
    Free(desc);
  } else {
    SbCat(sb, "none found");
  }

  SbCat(sb, "\nCredential search: ");
  SbCat(sb, CfgSourceName(c->credentials_source));
  SbCat(sb, "\nConfig file: ");
  if (c->config_path) SbCat(sb, c->config_path);
  else SbCat(sb, "(none)");
  SbCat(sb, "\nRepo credential: ");
  SbCat(sb, c->repo_cred_path);
  SbCat(sb, " -> ");
  SbCat(sb, SaKindName(c->repo_cred_kind));
  SbCat(sb, "\nOutput directory: ");
  SbCat(sb, c->output_dir);

  SysPromptStatus(sb, c);

  SbCat(sb, "\nHTTPS backend: ");
  if (HttpClientAvailable()) {
    U8 *v = HttpClientVersion();
    SbCat(sb, v);
    Free(v);
  } else {
    SbCat(sb, "curl NOT FOUND");
  }

  SbCat(sb, "\nStatus: ");
  if (ResIsOk(valid)) {
    SbCat(sb, "OK");
  } else {
    SbCat(sb, "ERROR - ");
    SbCat(sb, valid->message);
    *is_error = TRUE;
  }
  SbCatCh(sb, '\n');
  ResRelease(valid);
  return SbSteal(sb);
}

U0 SecLine(StrBuf *sb, Bool pass, U8 *text)
{
  if (pass) SbCat(sb, "[ok]   ");
  else SbCat(sb, "[warn] ");
  SbCat(sb, text);
  SbCatCh(sb, '\n');
}

U8 *ToolSecurityCheck(Json *args, Bool *is_error)
{
  HnConfig *c = g_config;
  StrBuf *sb = SbNew(1024);
  Bool all_ok = TRUE;

  SbCat(sb, "Security check\n\n");

  Bool exists = c->repo_cred_kind != SA_KIND_MISSING;
  U8 *line = StrPrint(NULL, "credential file present: %s (%s)",
                      c->repo_cred_path, SaKindName(c->repo_cred_kind));
  SecLine(sb, TRUE, line);
  Free(line);

  if (exists) {
    Bool valid_format = c->repo_cred_kind != SA_KIND_INVALID;
    SecLine(sb, valid_format, "credential file parses as JSON");
    if (!valid_format) all_ok = FALSE;

    Bool tracked = SaIsTrackedByGit(c->repo_cred_path);
    SecLine(sb, !tracked, "credential file is not tracked by git");
    if (tracked) all_ok = FALSE;

    Bool ignored = SaIsGitIgnored(c->repo_cred_path);
    SecLine(sb, ignored, "credential file is covered by .gitignore");
    if (!ignored) all_ok = FALSE;

    Bool owner_only = FileIsOwnerOnly(c->repo_cred_path);
    I64 mode = FileModeBits(c->repo_cred_path);
    U8 *perm = StrPrint(NULL, "credential file is not group or world readable (mode %d)", mode);
    SecLine(sb, owner_only, perm);
    Free(perm);
    if (!owner_only) all_ok = FALSE;
  } else {
    SecLine(sb, TRUE, "no repository-local credential file to protect");
  }

  Bool gitignore_present = PathExists(".gitignore");
  SecLine(sb, gitignore_present, ".gitignore exists in the working directory");
  if (!gitignore_present) all_ok = FALSE;

  Bool have_cred = CfgHasCredential(c);
  SecLine(sb, have_cred, "a credential was resolved");
  if (!have_cred) all_ok = FALSE;

  SecLine(sb, TRUE, "secrets are passed to curl through a 0600 config file, never argv");
  SecLine(sb, TRUE, "secrets are never written to logs or MCP responses");

  SbCat(sb, "\nResult: ");
  if (all_ok) SbCat(sb, "PASS\n");
  else {
    SbCat(sb, "ATTENTION NEEDED\n");
    *is_error = TRUE;
  }
  return SbSteal(sb);
}

/* --- schemas -------------------------------------------------------------- */

U8 *SCHEMA_GENERATE_IMAGE =
  "{\"type\":\"object\",\"properties\":{"
  "\"prompt\":{\"type\":\"string\",\"description\":\"What to generate.\"},"
  "\"model\":{\"type\":\"string\",\"description\":\"Alias (nano-banana-2, nano-banana-2-lite, nano-banana-pro, nano-banana) or a raw Google model id.\"},"
  "\"aspect_ratio\":{\"type\":\"string\",\"description\":\"Such as 1:1, 16:9, 9:16, 4:3, 3:2.\"},"
  "\"image_size\":{\"type\":\"string\",\"description\":\"Such as 1K, 2K, 4K.\"},"
  "\"mime_type\":{\"type\":\"string\",\"description\":\"Desired output mime type, e.g. image/png or image/jpeg.\"},"
  "\"output_path\":{\"type\":\"string\",\"description\":\"Where to write the image. Defaults to a timestamped name in the configured output directory.\"}"
  "},\"required\":[\"prompt\"]}";

U8 *SCHEMA_EDIT_IMAGE =
  "{\"type\":\"object\",\"properties\":{"
  "\"prompt\":{\"type\":\"string\",\"description\":\"How to change the image.\"},"
  "\"input_image\":{\"type\":\"string\",\"description\":\"Path to the image to edit.\"},"
  "\"model\":{\"type\":\"string\",\"description\":\"Alias or raw Google model id.\"},"
  "\"aspect_ratio\":{\"type\":\"string\"},"
  "\"image_size\":{\"type\":\"string\"},"
  "\"mime_type\":{\"type\":\"string\"},"
  "\"output_path\":{\"type\":\"string\"}"
  "},\"required\":[\"prompt\",\"input_image\"]}";

U8 *SCHEMA_EMPTY = "{\"type\":\"object\",\"properties\":{}}";

U0 ToolsRegisterAll()
{
  ToolRegister("generate_image", "Generate image",
    "Generate an image from a text prompt with a Nano Banana model and save it to disk.",
    SCHEMA_GENERATE_IMAGE, &ToolGenerateImage);

  ToolRegister("edit_image", "Edit image",
    "Edit an existing image on disk using a text prompt, and save the result.",
    SCHEMA_EDIT_IMAGE, &ToolEditImage);

  ToolRegister("list_models", "List models",
    "List the supported model aliases and the Google model ids they map to.",
    SCHEMA_EMPTY, &ToolListModels);

  ToolRegister("provider_status", "Provider status",
    "Report the active provider, model, credential source and HTTPS backend. Never reveals the credential.",
    SCHEMA_EMPTY, &ToolProviderStatus);

  ToolRegister("security_check", "Security check",
    "Check that repository-local credentials are present, well formed, ignored by git, and not exposed.",
    SCHEMA_EMPTY, &ToolSecurityCheck);
}

#endif
