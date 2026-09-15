#ifndef HN_AUTH_SETTINGS
#define HN_AUTH_SETTINGS

/* Configuration assembly. Every string in HnConfig is owned by the config. */

#define CFG_SRC_AUTO 0
#define CFG_SRC_MCP  1
#define CFG_SRC_REPO 2
#define CFG_SRC_ENV  3

class HnConfig
{
  U8 *provider_name;      /* gemini | vertex | fake */
  U8 *project_id;
  U8 *location;
  U8 *api_version;
  U8 *api_style;          /* interactions | generate_content */
  U8 *endpoint;           /* full override, optional */
  U8 *default_model;
  U8 *output_dir;
  Bool overwrite;
  I64 credentials_source;
  Credential *credential;
  U8 *config_path;        /* config file actually loaded, if any */
  U8 *repo_cred_path;
  I64 repo_cred_kind;
  I64 http_timeout;
  U8 *log_level;
};

U0 CfgSet(U8 **slot, U8 *value)
{
  if (!value) return;
  if (*slot) Free(*slot);
  *slot = StrDup(value);
}

/* Only fills a slot that is still unset, so lower-priority sources merge in
 * underneath higher-priority ones. */
U0 CfgFill(U8 **slot, U8 *value)
{
  if (*slot != NULL) return;
  CfgSet(slot, value);
}

HnConfig *CfgNew()
{
  HnConfig *c = MAlloc(sizeof(HnConfig));
  c->provider_name = NULL;
  c->project_id = NULL;
  c->location = NULL;
  c->api_version = NULL;
  c->api_style = NULL;
  c->endpoint = NULL;
  c->default_model = NULL;
  c->output_dir = NULL;
  c->overwrite = FALSE;
  c->credentials_source = CFG_SRC_AUTO;
  c->credential = NULL;
  c->config_path = NULL;
  c->repo_cred_path = NULL;
  c->repo_cred_kind = SA_KIND_MISSING;
  c->http_timeout = 180;
  c->log_level = NULL;
  return c;
}

I64 CfgSourceFromName(U8 *name)
{
  if (StrEq(name, "mcp"))  return CFG_SRC_MCP;
  if (StrEq(name, "repo")) return CFG_SRC_REPO;
  if (StrEq(name, "env"))  return CFG_SRC_ENV;
  return CFG_SRC_AUTO;
}

U8 *CfgSourceName(I64 src)
{
  switch (src) {
    case CFG_SRC_MCP:  return "mcp";
    case CFG_SRC_REPO: return "repo";
    case CFG_SRC_ENV:  return "env";
    default:           return "auto";
  }
}

/* Pulls a credential out of a parsed config document, honouring both the flat
 * api_key form and an explicit auth block. */
Credential *CfgCredentialFromDoc(Json *doc, U8 *origin)
{
  if (!doc) return NULL;

  Json *auth = JObjField(doc, "auth");
  if (!auth) auth = JObjField(doc, "credentials");
  if (auth) {
    U8 *type = JStr(auth, "type", NULL);
    U8 *file = JStr(auth, "credentials_file", NULL);
    if (StrEq(type, "service_account") && file != NULL) {
      Credential *sa = CredNew(CRED_SERVICE_ACCOUNT, origin);
      sa->credentials_file = StrDup(file);
      return sa;
    }
    if (StrEq(type, "adc")) return CredNew(CRED_ADC, origin);
    U8 *auth_key = JStr(auth, "api_key", NULL);
    if (auth_key) return CredApiKey(auth_key, origin);
    U8 *token = JStr(auth, "access_token", NULL);
    if (token) {
      Credential *at = CredNew(CRED_ACCESS_TOKEN, origin);
      at->access_token = StrDup(token);
      return at;
    }
  }

  U8 *key = JStr(doc, "api_key", NULL);
  if (key) return CredApiKey(key, origin);
  return NULL;
}

/* Applies non-credential settings from a config document. Higher-priority
 * sources run first, so this only fills gaps. */
U0 CfgApplyDoc(HnConfig *c, Json *doc)
{
  if (!doc) return;
  CfgFill(&c->provider_name, JStr(doc, "provider", NULL));
  CfgFill(&c->project_id,    JStr(doc, "project_id", NULL));
  CfgFill(&c->location,      JStr(doc, "location", NULL));
  CfgFill(&c->api_version,   JStr(doc, "api_version", NULL));
  CfgFill(&c->api_style,     JStr(doc, "api_style", NULL));
  CfgFill(&c->endpoint,      JStr(doc, "endpoint", NULL));
  CfgFill(&c->log_level,     JStr(doc, "log_level", NULL));

  Json *model = JField(doc, "model");
  if (model) {
    if (model->type == JSON_STRING) CfgFill(&c->default_model, model->str);
    else if (model->type == JSON_OBJECT) CfgFill(&c->default_model, JStr(model, "default", NULL));
  }

  Json *output = JObjField(doc, "output");
  if (output) {
    CfgFill(&c->output_dir, JStr(output, "directory", NULL));
    if (JBool(output, "overwrite", FALSE)) c->overwrite = TRUE;
  }
  CfgFill(&c->output_dir, JStr(doc, "output_dir", NULL));

  Json *creds = JObjField(doc, "credentials");
  if (creds) {
    U8 *src = JStr(creds, "source", NULL);
    if (src != NULL && c->credentials_source == CFG_SRC_AUTO) {
      c->credentials_source = CfgSourceFromName(src);
    }
  }

  I64 timeout = JInt(doc, "http_timeout", 0);
  if (timeout > 0) c->http_timeout = timeout;
}

/* Reads and parses a config file. NULL when absent or unparseable. */
Json *CfgReadFile(U8 *path)
{
  if (!path) return NULL;
  if (!PathExists(path)) return NULL;
  I64 size = 0;
  U8 *raw = ReadFdFile(path, &size);
  if (!raw) return NULL;
  if (size <= 0) { Free(raw); return NULL; }
  Json *doc = JsonParse(raw, size);
  Free(raw);
  if (doc == NULL) return NULL;
  if (!JsonOk(doc)) { JsonRelease(doc); return NULL; }
  if (doc->type != JSON_OBJECT) { JsonRelease(doc); return NULL; }
  return doc;
}

U8 *CfgGlobalPath()
{
  U8 *from_env = EnvOrNull("HOLY_NANO_MCP_CONFIG");
  if (from_env) return StrDup(from_env);
  U8 *home = EnvOrNull("HOME");
  if (!home) return NULL;
  return StrPrint(NULL, "%s/.config/holy-nano-mcp/config.json", home);
}

Credential *CfgCredentialFromEnv()
{
  U8 *k = EnvOrNull("GEMINI_API_KEY");
  if (k) return CredApiKey(k, "env:GEMINI_API_KEY");
  k = EnvOrNull("GOOGLE_API_KEY");
  if (k) return CredApiKey(k, "env:GOOGLE_API_KEY");
  k = EnvOrNull("HOLY_NANO_MCP_API_KEY");
  if (k) return CredApiKey(k, "env:HOLY_NANO_MCP_API_KEY");
  k = EnvOrNull("GOOGLE_APPLICATION_CREDENTIALS");
  if (k) {
    Credential *sa = CredNew(CRED_SERVICE_ACCOUNT, "env:GOOGLE_APPLICATION_CREDENTIALS");
    sa->credentials_file = StrDup(k);
    return sa;
  }
  return NULL;
}

/* Builds the effective configuration.
 *
 * Credential precedence:
 *   1. explicit MCP configuration   2. ./service-account.json
 *   3. environment variables        4. none (reported as an error on use)
 *
 * Non-credential settings follow the same order but merge instead of stopping. */
HnConfig *CfgLoad()
{
  HnConfig *c = CfgNew();

  /* 1. explicit MCP configuration: CLI flags */
  CfgSet(&c->provider_name, ArgValue("provider"));
  CfgSet(&c->default_model, ArgValue("model"));
  CfgSet(&c->output_dir,    ArgValue("output-dir"));
  CfgSet(&c->project_id,    ArgValue("project-id"));
  CfgSet(&c->location,      ArgValue("location"));
  CfgSet(&c->api_version,   ArgValue("api-version"));
  CfgSet(&c->api_style,     ArgValue("api-style"));
  CfgSet(&c->endpoint,      ArgValue("endpoint"));
  CfgSet(&c->log_level,     ArgValue("log-level"));
  if (ArgFlag("overwrite")) c->overwrite = TRUE;
  U8 *src_flag = ArgValue("credentials-source");
  if (src_flag) c->credentials_source = CfgSourceFromName(src_flag);

  /* 1b. explicit MCP configuration: config file */
  U8 *cfg_path = ArgValue("config");
  Json *mcp_doc = NULL;
  if (cfg_path) {
    mcp_doc = CfgReadFile(cfg_path);
    if (mcp_doc) CfgSet(&c->config_path, cfg_path);
    else LogWarn("config file could not be read as JSON: %s", cfg_path);
  }
  if (!mcp_doc) {
    U8 *global = CfgGlobalPath();
    if (global) {
      mcp_doc = CfgReadFile(global);
      if (mcp_doc) CfgSet(&c->config_path, global);
      Free(global);
    }
  }
  CfgApplyDoc(c, mcp_doc);

  /* 1c. explicit MCP configuration: environment overrides */
  CfgFill(&c->provider_name, EnvOrNull("HOLY_NANO_MCP_PROVIDER"));
  CfgFill(&c->default_model, EnvOrNull("HOLY_NANO_MCP_MODEL"));
  CfgFill(&c->output_dir,    EnvOrNull("HOLY_NANO_MCP_OUTPUT_DIR"));
  CfgFill(&c->log_level,     EnvOrNull("HOLY_NANO_MCP_LOG_LEVEL"));
  CfgFill(&c->project_id,    EnvOrNull("GOOGLE_CLOUD_PROJECT"));
  CfgFill(&c->location,      EnvOrNull("GOOGLE_CLOUD_LOCATION"));

  /* 2. repository-local credential file */
  U8 *repo_path = ArgValue("service-account");
  if (!repo_path) repo_path = SA_DEFAULT_FILE;
  CfgSet(&c->repo_cred_path, repo_path);

  Json *repo_doc = NULL;
  c->repo_cred_kind = SaInspect(repo_path, &repo_doc);
  SaWarnIfExposed(repo_path, c->repo_cred_kind);
  if (c->repo_cred_kind == SA_KIND_CONFIG) CfgApplyDoc(c, repo_doc);

  /* credential resolution, strictly ordered */
  I64 want = c->credentials_source;

  if (c->credential == NULL) {
    if (want == CFG_SRC_AUTO || want == CFG_SRC_MCP) {
      U8 *origin = "mcp settings";
      if (c->config_path) origin = c->config_path;
      c->credential = CfgCredentialFromDoc(mcp_doc, origin);
    }
  }

  if (c->credential == NULL) {
    if (want == CFG_SRC_AUTO || want == CFG_SRC_REPO) {
      if (c->repo_cred_kind == SA_KIND_CONFIG) {
        c->credential = CfgCredentialFromDoc(repo_doc, repo_path);
      } else if (c->repo_cred_kind == SA_KIND_GCP_SA) {
        Credential *sa = CredNew(CRED_SERVICE_ACCOUNT, repo_path);
        sa->credentials_file = StrDup(repo_path);
        c->credential = sa;
      }
    }
  }

  if (c->credential == NULL) {
    if (want == CFG_SRC_AUTO || want == CFG_SRC_ENV) {
      c->credential = CfgCredentialFromEnv();
    }
  }

  if (mcp_doc) JsonRelease(mcp_doc);
  if (repo_doc) JsonRelease(repo_doc);

  /* defaults */
  if (c->provider_name == NULL) {
    U8 *use_vertex = EnvOrNull("GOOGLE_GENAI_USE_VERTEXAI");
    if (use_vertex) {
      U8 *lowered = StrLower(use_vertex);
      if (StrEq(lowered, "true") || StrEq(lowered, "1")) CfgSet(&c->provider_name, "vertex");
      Free(lowered);
    }
  }
  CfgFill(&c->provider_name, "gemini");
  CfgFill(&c->default_model, "nano-banana-2");
  CfgFill(&c->output_dir,    "./generated");
  CfgFill(&c->location,      "global");
  CfgFill(&c->api_version,   "v1beta");
  CfgFill(&c->api_style,     "interactions");

  if (c->log_level) LogSetLevelName(c->log_level);
  return c;
}

Bool CfgHasCredential(HnConfig *c)
{
  if (!c) return FALSE;
  if (!c->credential) return FALSE;
  return c->credential->type != CRED_NONE;
}

#endif
