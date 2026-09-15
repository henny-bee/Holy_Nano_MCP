#ifndef HN_PROVIDERS_VERTEX
#define HN_PROVIDERS_VERTEX

/* Vertex AI.
 *
 * Three auth modes:
 *   api_key         express mode, no project/location in the URL
 *   access_token    a bearer token supplied in config
 *   service_account / adc
 *                   a bearer token minted by the gcloud CLI, which owns the
 *                   RS256 JWT signing that HolyC has no crypto for
 *
 * Vertex exposes generateContent, not the Interactions surface, so the wire
 * shape is fixed regardless of api_style. */

#define VERTEX_GLOBAL_HOST "https://aiplatform.googleapis.com"

U8 *VertexHost(HnConfig *c)
{
  if (c->endpoint != NULL && c->endpoint[0] != 0) return StrDup(c->endpoint);
  if (c->location == NULL || StrEq(c->location, "global")) {
    return StrDup(VERTEX_GLOBAL_HOST);
  }
  return StrPrint(NULL, "https://%s-aiplatform.googleapis.com", c->location);
}

/* Express mode (API key) addresses publishers directly; project-scoped auth
 * goes through projects/locations. */
U8 *VertexUrl(HnConfig *c, U8 *model_id, Bool express)
{
  U8 *host = VertexHost(c);
  U8 *url = NULL;
  if (express) {
    url = StrPrint(NULL, "%s/v1/publishers/google/models/%s:generateContent",
                   host, model_id);
  } else {
    U8 *location = c->location;
    if (!location) location = "global";
    url = StrPrint(NULL,
      "%s/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent",
      host, c->project_id, location, model_id);
  }
  Free(host);
  return url;
}

/* Mints an OAuth access token via gcloud. Returns NULL and sets `*err` when
 * gcloud is unavailable or refuses. */
U8 *VertexGcloudToken(Credential *cred, U8 **err)
{
  *err = NULL;
  if (System("command -v gcloud >/dev/null 2>&1") != 0) {
    *err = StrDup("gcloud CLI not found - needed to exchange a service account or ADC for an access token");
    return NULL;
  }

  U8 *cmd = NULL;
  if (cred->type == CRED_SERVICE_ACCOUNT && cred->credentials_file != NULL) {
    /* Scoping the env var to the child keeps it out of this process. */
    cmd = StrPrint(NULL,
      "GOOGLE_APPLICATION_CREDENTIALS=%s gcloud auth application-default print-access-token",
      cred->credentials_file);
  } else {
    cmd = StrPrint(NULL, "gcloud auth print-access-token");
  }

  /* ShellCapture, not Shlurp: the token must not land in a shared temp file. */
  I64 raw_len = 0;
  U8 *raw = ShellCapture(cmd, &raw_len);
  Free(cmd);
  if (!raw) {
    *err = StrDup("gcloud produced no access token");
    return NULL;
  }
  U8 *token = StrTrimDup(raw);
  Free(raw);
  if (token[0] == 0) {
    Free(token);
    *err = StrDup("gcloud produced no access token - try 'gcloud auth application-default login'");
    return NULL;
  }
  return token;
}

HnResult *VertexValidate(AIProvider *self)
{
  HnConfig *c = self->config;
  if (!CfgHasCredential(c)) {
    return ResErr(HN_ERR_CREDENTIALS,
      "no credentials found - set an api_key, access_token, or service account in MCP settings, ./service-account.json, or the environment");
  }
  Credential *cred = c->credential;
  Bool express = cred->type == CRED_API_KEY;
  if (!express) {
    if (c->project_id == NULL || c->project_id[0] == 0) {
      return ResErr(HN_ERR_CONFIG,
        "vertex with non-express auth needs project_id (config, --project-id, or GOOGLE_CLOUD_PROJECT)");
    }
  }
  if (!HttpClientAvailable()) {
    return ResErr(HN_ERR_HTTP, "curl not found on PATH - required for HTTPS");
  }
  return ResOk();
}

ImageResult *VertexCall(AIProvider *self, ImageRequest *req)
{
  HnConfig *c = self->config;
  HnResult *valid = VertexValidate(self);
  if (!ResIsOk(valid)) {
    ImageResult *bad = ImageResultErr(valid->code, valid->message);
    ResRelease(valid);
    return bad;
  }
  ResRelease(valid);

  Credential *cred = c->credential;
  Bool express = cred->type == CRED_API_KEY;

  U8 *bearer = NULL;
  if (cred->type == CRED_ACCESS_TOKEN) {
    bearer = StrDup(cred->access_token);
  } else if (cred->type == CRED_SERVICE_ACCOUNT || cred->type == CRED_ADC) {
    U8 *err = NULL;
    bearer = VertexGcloudToken(cred, &err);
    if (!bearer) {
      ImageResult *bad = ImageResultErr(HN_ERR_CREDENTIALS, err);
      Free(err);
      return bad;
    }
  }

  U8 *model_id = ModelResolve(req->model);
  U8 *url = VertexUrl(c, model_id, express);
  U8 *body = GBuildGenerateBody(req);

  HttpRequest *http = HttpNew("POST", url);
  http->timeout_secs = c->http_timeout;
  HttpAddHeader(http, "Content-Type", "application/json");
  if (express) {
    HttpAddHeader(http, "x-goog-api-key", cred->api_key);
  } else {
    U8 *auth = StrPrint(NULL, "Bearer %s", bearer);
    HttpAddHeader(http, "Authorization", auth);
    Free(auth);
    if (c->project_id) HttpAddHeader(http, "x-goog-user-project", c->project_id);
  }
  HttpSetBody(http, body, StrLen(body));

  LogInfo("vertex generate_content model=%s auth=%s", model_id, CredTypeName(cred->type));
  HttpResponse *res = HttpSend(http);
  ImageResult *out = GParseImageResponse(res, model_id);

  HttpResponseRelease(res);
  HttpRequestRelease(http);
  Free(url);
  if (bearer) Free(bearer);
  return out;
}

ImageResult *VertexGenerate(AIProvider *self, ImageRequest *req)
{
  return VertexCall(self, req);
}

ImageResult *VertexEdit(AIProvider *self, ImageRequest *req)
{
  if (req->input_b64 == NULL) {
    return ImageResultErr(HN_ERR_ARGS, "edit_image requires an input image");
  }
  return VertexCall(self, req);
}

AIProvider *VertexProviderNew(HnConfig *c)
{
  AIProvider *p = ProviderNew("vertex", c);
  p->GenerateImage = &VertexGenerate;
  p->EditImage = &VertexEdit;
  p->GetModelInfo = &ProviderDefaultModelInfo;
  p->ValidateConfig = &VertexValidate;
  return p;
}

#endif
