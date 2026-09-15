#ifndef HN_PROVIDERS_GEMINI
#define HN_PROVIDERS_GEMINI

/* Gemini API / Google AI Studio.
 *
 * Auth is a single API key sent as x-goog-api-key. */

#define GEMINI_BASE "https://generativelanguage.googleapis.com"

U8 *GeminiBase(HnConfig *c)
{
  if (c->endpoint != NULL && c->endpoint[0] != 0) return c->endpoint;
  return GEMINI_BASE;
}

U8 *GeminiUrl(HnConfig *c, I64 style, U8 *model_id)
{
  if (style == API_STYLE_GENERATE) {
    return StrPrint(NULL, "%s/%s/models/%s:generateContent",
                    GeminiBase(c), c->api_version, model_id);
  }
  return StrPrint(NULL, "%s/%s/interactions", GeminiBase(c), c->api_version);
}

HnResult *GeminiValidate(AIProvider *self)
{
  HnConfig *c = self->config;
  if (!CfgHasCredential(c)) {
    return ResErr(HN_ERR_CREDENTIALS,
      "no credentials found - set an api_key in MCP settings, ./service-account.json, or GEMINI_API_KEY");
  }
  Credential *cred = c->credential;
  if (cred->type != CRED_API_KEY) {
    U8 *msg = StrPrint(NULL,
      "the gemini provider needs an api_key credential, found '%s' - use the vertex provider for service-account or ADC auth",
      CredTypeName(cred->type));
    HnResult *r = ResErr(HN_ERR_CREDENTIALS, msg);
    Free(msg);
    return r;
  }
  if (!HttpClientAvailable()) {
    return ResErr(HN_ERR_HTTP, "curl not found on PATH - required for HTTPS");
  }
  return ResOk();
}

ImageResult *GeminiCall(AIProvider *self, ImageRequest *req)
{
  HnConfig *c = self->config;
  HnResult *valid = GeminiValidate(self);
  if (!ResIsOk(valid)) {
    ImageResult *bad = ImageResultErr(valid->code, valid->message);
    ResRelease(valid);
    return bad;
  }
  ResRelease(valid);

  U8 *model_id = ModelResolve(req->model);
  I64 style = ApiStyleFromName(c->api_style);
  U8 *url = GeminiUrl(c, style, model_id);

  U8 *body = NULL;
  if (style == API_STYLE_GENERATE) body = GBuildGenerateBody(req);
  else body = GBuildInteractionsBody(model_id, req);

  HttpRequest *http = HttpNew("POST", url);
  http->timeout_secs = c->http_timeout;
  HttpAddHeader(http, "Content-Type", "application/json");
  HttpAddHeader(http, "x-goog-api-key", c->credential->api_key);
  HttpSetBody(http, body, StrLen(body));

  LogInfo("gemini %s model=%s", ApiStyleName(style), model_id);
  HttpResponse *res = HttpSend(http);
  ImageResult *out = GParseImageResponse(res, model_id);

  HttpResponseRelease(res);
  HttpRequestRelease(http);
  Free(url);
  return out;
}

ImageResult *GeminiGenerate(AIProvider *self, ImageRequest *req)
{
  return GeminiCall(self, req);
}

ImageResult *GeminiEdit(AIProvider *self, ImageRequest *req)
{
  if (req->input_b64 == NULL) {
    return ImageResultErr(HN_ERR_ARGS, "edit_image requires an input image");
  }
  return GeminiCall(self, req);
}

AIProvider *GeminiProviderNew(HnConfig *c)
{
  AIProvider *p = ProviderNew("gemini", c);
  p->GenerateImage = &GeminiGenerate;
  p->EditImage = &GeminiEdit;
  p->GetModelInfo = &ProviderDefaultModelInfo;
  p->ValidateConfig = &GeminiValidate;
  return p;
}

#endif
