/* Model aliases, request bodies, response parsing and the FakeProvider.
 *
 * No network: responses are fed in as literals, so this covers the exact
 * shapes the Google APIs return without needing a key. */

#include "../src/utils/os.HC"
#include "../src/utils/strings.HC"
#include "../src/utils/errors.HC"
#include "../src/utils/logging.HC"
#include "../src/utils/json_util.HC"
#include "../src/utils/args.HC"
#include "../src/http/request.HC"
#include "../src/http/response.HC"
#include "../src/http/client.HC"
#include "../src/auth/credentials.HC"
#include "../src/auth/service_account.HC"
#include "../src/auth/settings.HC"
#include "../src/image/base64.HC"
#include "../src/image/files.HC"
#include "../src/providers/models.HC"
#include "../src/providers/provider.HC"
#include "../src/prompts/system_prompt.HC"
#include "../src/providers/google_common.HC"
#include "../src/providers/gemini.HC"
#include "../src/providers/vertex.HC"
#include "../src/providers/fake.HC"
#include "../src/providers/resolve.HC"
#include "../src/image/generate.HC"
#include "../src/image/edit.HC"
#include "./harness.HC"

HttpResponse *FakeHttp(I64 status, U8 *body)
{
  HttpResponse *r = HttpResponseNew();
  r->status = status;
  r->body = StrDup(body);
  r->body_len = StrLen(body);
  return r;
}

U0 TestAliases()
{
  TEqStr(ModelResolve("nano-banana-2"), "gemini-3.1-flash-image", "nano-banana-2 alias");
  TEqStr(ModelResolve("nano-banana-2-lite"), "gemini-3.1-flash-lite-image", "nano-banana-2-lite alias");
  TEqStr(ModelResolve("nano-banana-pro"), "gemini-3-pro-image", "nano-banana-pro alias");
  TEqStr(ModelResolve("nano-banana"), "gemini-2.5-flash-image", "nano-banana alias");
  TEqStr(ModelResolve("gemini-9.9-future-image"), "gemini-9.9-future-image",
         "an unknown model passes through unchanged");
  TEqStr(ModelResolve(NULL), "gemini-3.1-flash-image", "NULL falls back to the default model");
  TCheck(ModelIsAlias("nano-banana-pro"), "known aliases are reported as aliases");
  TCheck(!ModelIsAlias("gemini-3-pro-image"), "raw model ids are not aliases");

  U8 *json = ModelsListJson();
  THas(json, "gemini-3.1-flash-image", "the model listing includes model ids");
  THas(json, "nano-banana-pro", "the model listing includes aliases");
  Free(json);
}

U0 TestInteractionsBody()
{
  ImageRequest *req = ImageRequestNew();
  req->prompt = StrDup("a cat with a \"hat\"");
  req->aspect_ratio = StrDup("16:9");
  req->image_size = StrDup("2K");

  U8 *body = GBuildInteractionsBody("gemini-3.1-flash-image", req);
  Json *doc = JsonParse(body, StrLen(body));
  TCheck(doc != NULL, "interactions body is valid JSON even with quotes in the prompt");
  if (doc) {
    TEqStr(JStr(doc, "model", NULL), "gemini-3.1-flash-image", "interactions body carries the model");
    Json *input = JArrField(doc, "input");
    TCheck(input != NULL, "interactions body has an input array");
    Json *first = JArrFirst(input);
    TEqStr(JStr(first, "type", NULL), "text", "text-only request sends one text block");
    TEqStr(JStr(first, "text", NULL), "a cat with a \"hat\"", "the prompt survives escaping");
    Json *fmt = JObjField(doc, "response_format");
    TEqStr(JStr(fmt, "type", NULL), "image", "response_format asks for an image");
    TEqStr(JStr(fmt, "aspect_ratio", NULL), "16:9", "aspect_ratio is passed through");
    TEqStr(JStr(fmt, "image_size", NULL), "2K", "image_size is passed through");
    JsonRelease(doc);
  }
  Free(body);

  /* An edit request puts the image first, then the instruction. */
  req->input_b64 = StrDup("QUJD");
  req->input_mime = StrDup("image/jpeg");
  body = GBuildInteractionsBody("gemini-3.1-flash-image", req);
  doc = JsonParse(body, StrLen(body));
  TCheck(doc != NULL, "edit body is valid JSON");
  if (doc) {
    Json *first = JArrFirst(JArrField(doc, "input"));
    TEqStr(JStr(first, "type", NULL), "image", "edit sends the image block first");
    TEqStr(JStr(first, "mime_type", NULL), "image/jpeg", "edit sends the input mime type");
    TEqStr(JStr(first, "data", NULL), "QUJD", "edit sends the base64 payload");
    JsonRelease(doc);
  }
  Free(body);
  ImageRequestRelease(req);
}

U0 TestGenerateBody()
{
  ImageRequest *req = ImageRequestNew();
  req->prompt = StrDup("a dog");
  req->aspect_ratio = StrDup("1:1");

  U8 *body = GBuildGenerateBody(req);
  Json *doc = JsonParse(body, StrLen(body));
  TCheck(doc != NULL, "generateContent body is valid JSON");
  if (doc) {
    Json *content = JArrFirst(JArrField(doc, "contents"));
    TEqStr(JStr(content, "role", NULL), "user", "generateContent sets the user role");
    Json *part = JArrFirst(JArrField(content, "parts"));
    TEqStr(JStr(part, "text", NULL), "a dog", "generateContent carries the prompt");
    Json *gc = JObjField(doc, "generationConfig");
    TCheck(JArrField(gc, "responseModalities") != NULL, "generationConfig requests IMAGE output");
    Json *ic = JObjField(gc, "imageConfig");
    TEqStr(JStr(ic, "aspectRatio", NULL), "1:1", "imageConfig uses camelCase keys");
    JsonRelease(doc);
  }
  Free(body);

  /* With no options there should be no imageConfig at all. */
  ImageRequest *bare = ImageRequestNew();
  bare->prompt = StrDup("x");
  body = GBuildGenerateBody(bare);
  doc = JsonParse(body, StrLen(body));
  if (doc) {
    TCheck(JObjField(JObjField(doc, "generationConfig"), "imageConfig") == NULL,
           "imageConfig is omitted when nothing was requested");
    JsonRelease(doc);
  }
  Free(body);
  ImageRequestRelease(bare);
  ImageRequestRelease(req);
}

U0 TestParseInteractionsResponse()
{
  U8 *raw =
    "{\"id\":\"int_1\",\"status\":\"completed\",\"steps\":["
    "{\"type\":\"user_input\",\"status\":\"done\",\"content\":[{\"type\":\"text\",\"text\":\"ignore me\"}]},"
    "{\"type\":\"model_output\",\"status\":\"done\",\"content\":["
    "{\"type\":\"text\",\"text\":\"here you go\"},"
    "{\"type\":\"image\",\"mime_type\":\"image/png\",\"data\":\"aGVsbG8=\"}]}]}";
  HttpResponse *res = FakeHttp(200, raw);
  ImageResult *r = GParseImageResponse(res, "gemini-3.1-flash-image");
  TCheck(r->ok, "extracts an image from an interactions response");
  TEqStr(r->data_base64, "aGVsbG8=", "extracts the base64 payload");
  TEqStr(r->mime_type, "image/png", "extracts the mime type");
  TEqStr(r->text, "here you go", "collects accompanying text");
  TCheck(!TContains(r->text, "ignore me"), "user_input steps are not treated as output");
  ImageResultRelease(r);
  HttpResponseRelease(res);
}

U0 TestParseGenerateResponse()
{
  U8 *raw =
    "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":["
    "{\"text\":\"done\"},"
    "{\"inlineData\":{\"mimeType\":\"image/jpeg\",\"data\":\"QUJD\"}}]},"
    "\"finishReason\":\"STOP\"}]}";
  HttpResponse *res = FakeHttp(200, raw);
  ImageResult *r = GParseImageResponse(res, "gemini-2.5-flash-image");
  TCheck(r->ok, "extracts an image from a generateContent response");
  TEqStr(r->data_base64, "QUJD", "reads inlineData.data");
  TEqStr(r->mime_type, "image/jpeg", "reads inlineData.mimeType");
  ImageResultRelease(r);
  HttpResponseRelease(res);

  /* snake_case variant of the same shape */
  raw = "{\"candidates\":[{\"content\":{\"parts\":["
        "{\"inline_data\":{\"mime_type\":\"image/webp\",\"data\":\"WA==\"}}]}}]}";
  res = FakeHttp(200, raw);
  r = GParseImageResponse(res, "m");
  TCheck(r->ok, "accepts the snake_case inline_data variant");
  TEqStr(r->mime_type, "image/webp", "reads inline_data.mime_type");
  ImageResultRelease(r);
  HttpResponseRelease(res);
}

U0 TestParseErrors()
{
  U8 *raw = "{\"error\":{\"code\":400,\"message\":\"API key not valid\",\"status\":\"INVALID_ARGUMENT\"}}";
  HttpResponse *res = FakeHttp(400, raw);
  ImageResult *r = GParseImageResponse(res, "m");
  TCheck(!r->ok, "an API error is not a success");
  TEqI64(r->error_code, HN_ERR_API, "an API error is classified as api_error");
  THas(r->error, "API key not valid", "the API message reaches the caller");
  THas(r->error, "INVALID_ARGUMENT", "the API status reaches the caller");
  ImageResultRelease(r);
  HttpResponseRelease(res);

  res = FakeHttp(500, "<html>gateway error</html>");
  r = GParseImageResponse(res, "m");
  TCheck(!r->ok, "a non-JSON error body is still an error");
  THas(r->error, "HTTP 500", "a non-JSON error body reports the status code");
  ImageResultRelease(r);
  HttpResponseRelease(res);

  res = FakeHttp(200, "{\"steps\":[{\"type\":\"model_output\",\"content\":"
                      "[{\"type\":\"text\",\"text\":\"I will not draw that\"}]}]}");
  r = GParseImageResponse(res, "m");
  TCheck(!r->ok, "a text-only response is an error for an image tool");
  THas(r->error, "I will not draw that", "a text-only response explains itself");
  ImageResultRelease(r);
  HttpResponseRelease(res);

  res = HttpResponseNew();
  res->error = StrDup("could not resolve host");
  r = GParseImageResponse(res, "m");
  TEqI64(r->error_code, HN_ERR_HTTP, "a transport failure is classified as http_error");
  ImageResultRelease(r);
  HttpResponseRelease(res);
}

U0 TestUrls()
{
  HnConfig *c = CfgNew();
  CfgSet(&c->api_version, "v1beta");

  U8 *u = GeminiUrl(c, API_STYLE_INTERACTIONS, "gemini-3.1-flash-image");
  TEqStr(u, "https://generativelanguage.googleapis.com/v1beta/interactions",
         "gemini interactions url");
  Free(u);

  u = GeminiUrl(c, API_STYLE_GENERATE, "gemini-3.1-flash-image");
  TEqStr(u, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent",
         "gemini generateContent url");
  Free(u);

  CfgSet(&c->location, "global");
  u = VertexUrl(c, "gemini-3-pro-image", TRUE);
  TEqStr(u, "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-3-pro-image:generateContent",
         "vertex express url has no project segment");
  Free(u);

  CfgSet(&c->project_id, "my-project");
  u = VertexUrl(c, "gemini-3-pro-image", FALSE);
  THas(u, "/projects/my-project/locations/global/", "vertex project url includes project and location");
  Free(u);

  CfgSet(&c->location, "us-central1");
  u = VertexUrl(c, "gemini-3-pro-image", FALSE);
  THas(u, "https://us-central1-aiplatform.googleapis.com/", "a regional location picks a regional host");
  Free(u);

  CfgSet(&c->endpoint, "http://127.0.0.1:8787");
  u = GeminiUrl(c, API_STYLE_INTERACTIONS, "m");
  TEqStr(u, "http://127.0.0.1:8787/v1beta/interactions", "an endpoint override is honoured");
  Free(u);
}

U0 TestApiStyle()
{
  TEqI64(ApiStyleFromName("generate_content"), API_STYLE_GENERATE, "generate_content style name");
  TEqI64(ApiStyleFromName("interactions"), API_STYLE_INTERACTIONS, "interactions style name");
  TEqI64(ApiStyleFromName("nonsense"), API_STYLE_INTERACTIONS, "unknown style names default to interactions");
}

U0 TestResolve()
{
  HnConfig *c = CfgNew();
  CfgSet(&c->provider_name, "vertex");
  TEqStr(ProviderResolve(c)->name, "vertex", "resolves the vertex provider");
  CfgSet(&c->provider_name, "fake");
  TEqStr(ProviderResolve(c)->name, "fake", "resolves the fake provider");
  CfgSet(&c->provider_name, "gemini");
  TEqStr(ProviderResolve(c)->name, "gemini", "resolves the gemini provider");
  CfgSet(&c->provider_name, "not-a-provider");
  TEqStr(ProviderResolve(c)->name, "gemini", "an unknown provider falls back to gemini");
}

U0 TestValidation()
{
  HnConfig *c = CfgNew();
  CfgSet(&c->provider_name, "gemini");
  AIProvider *g = GeminiProviderNew(c);

  HnResult *r = g->ValidateConfig(g);
  TCheck(!ResIsOk(r), "gemini without a credential does not validate");
  TEqI64(r->code, HN_ERR_CREDENTIALS, "a missing credential is a credentials error");
  ResRelease(r);

  c->credential = CredNew(CRED_ADC, "test");
  r = g->ValidateConfig(g);
  TCheck(!ResIsOk(r), "gemini rejects an ADC credential");
  THas(r->message, "vertex", "the rejection points at the vertex provider");
  ResRelease(r);

  c->credential = CredApiKey("AIzaSyTESTKEY000001", "test");
  r = g->ValidateConfig(g);
  TCheck(ResIsOk(r), "gemini with an api key validates");
  ResRelease(r);

  HnConfig *v = CfgNew();
  CfgSet(&v->provider_name, "vertex");
  CfgSet(&v->location, "global");
  v->credential = CredNew(CRED_ADC, "test");
  AIProvider *vp = VertexProviderNew(v);
  r = vp->ValidateConfig(vp);
  TCheck(!ResIsOk(r), "vertex with ADC but no project does not validate");
  THas(r->message, "project_id", "the rejection names project_id");
  ResRelease(r);

  CfgSet(&v->project_id, "my-project");
  r = vp->ValidateConfig(vp);
  TCheck(ResIsOk(r), "vertex with ADC and a project validates");
  ResRelease(r);
}

U0 TestFakeProviderPipeline()
{
  /* Overwrite protection renames around files that already exist, so a run
   * that inherits the previous run's output asserts against pipeline-2.png. */
  System("rm -rf /tmp/holy-nano-mcp-fixtures/out");

  HnConfig *c = CfgNew();
  CfgSet(&c->provider_name, "fake");
  CfgSet(&c->output_dir, "/tmp/holy-nano-mcp-fixtures/out");
  CfgSet(&c->default_model, "nano-banana-2");
  AIProvider *p = FakeProviderNew(c);

  ImageRequest *req = ImageRequestNew();
  req->prompt = StrDup("a test image");
  req->model = StrDup("nano-banana-pro");

  ImageResult *r = ImageGenerate(p, c, req, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png");
  TCheck(r->ok, "the fake provider runs the full pipeline");
  TEqStr(r->model, "gemini-3-pro-image", "the requested alias is resolved");
  TEqStr(r->output_path, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png", "the requested path is used");
  TEqI64(r->width, 16, "PNG width is read from the IHDR chunk");
  TEqI64(r->height, 16, "PNG height is read from the IHDR chunk");
  TCheck(PathExists(r->output_path), "the image is actually on disk");
  ImageResultRelease(r);
  ImageRequestRelease(req);

  /* Without overwrite the second write must not clobber the first. */
  ImageRequest *req2 = ImageRequestNew();
  req2->prompt = StrDup("again");
  ImageResult *r2 = ImageGenerate(p, c, req2, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png");
  TCheck(r2->ok, "a second generation succeeds");
  TCheck(!StrEq(r2->output_path, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png"),
         "overwrite protection picks a new name");
  ImageResultRelease(r2);
  ImageRequestRelease(req2);

  /* With overwrite on, the same path is reused. */
  c->overwrite = TRUE;
  ImageRequest *req3 = ImageRequestNew();
  req3->prompt = StrDup("third");
  ImageResult *r3 = ImageGenerate(p, c, req3, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png");
  TEqStr(r3->output_path, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png",
         "overwrite reuses the requested path");
  ImageResultRelease(r3);
  ImageRequestRelease(req3);

  /* Editing a file that is not there must fail cleanly. */
  ImageRequest *req4 = ImageRequestNew();
  req4->prompt = StrDup("edit");
  ImageResult *r4 = ImageEdit(p, c, req4, "/tmp/holy-nano-mcp-fixtures/out/missing.png", NULL);
  TCheck(!r4->ok, "editing a missing file fails");
  TEqI64(r4->error_code, HN_ERR_IO, "a missing input file is an io error");
  ImageResultRelease(r4);
  ImageRequestRelease(req4);

  /* Editing a real file round-trips through base64. */
  ImageRequest *req5 = ImageRequestNew();
  req5->prompt = StrDup("edit for real");
  ImageResult *r5 = ImageEdit(p, c, req5, "/tmp/holy-nano-mcp-fixtures/out/pipeline.png",
                              "/tmp/holy-nano-mcp-fixtures/out/edited.png");
  TCheck(r5->ok, "editing an existing file succeeds");
  TCheck(PathExists("/tmp/holy-nano-mcp-fixtures/out/edited.png"), "the edited image is written");
  ImageResultRelease(r5);
  ImageRequestRelease(req5);
}

U0 TestOutputPaths()
{
  TEqStr(MimeToExt("image/png"), "png", "png extension");
  TEqStr(MimeToExt("image/jpeg"), "jpg", "jpeg extension");
  TEqStr(MimeToExt("application/octet-stream"), "bin", "unknown mime falls back to .bin");
  TEqStr(ExtToMime("/a/b/c.JPG"), "image/jpeg", "extension to mime is case insensitive");
  TEqStr(PathParent("/a/b/c.png"), "/a/b", "parent directory is extracted");
  TCheck(PathParent("c.png") == NULL, "a bare filename has no parent");

  U8 *p = ResolveOutputPath(NULL, "./out", "image/png", "stem", TRUE);
  TEqStr(p, "./out/stem.png", "a default path is built from the output directory");
  Free(p);

  p = ResolveOutputPath("./explicit.jpg", "./out", "image/png", "stem", TRUE);
  TEqStr(p, "./explicit.jpg", "an explicit path wins");
  Free(p);
}

I64 Main()
{
  TBanner("test_provider");
  ModelsInit();
  TestAliases();
  TestInteractionsBody();
  TestGenerateBody();
  TestParseInteractionsResponse();
  TestParseGenerateResponse();
  TestParseErrors();
  TestUrls();
  TestApiStyle();
  TestResolve();
  TestValidation();
  TestOutputPaths();
  TestFakeProviderPipeline();
  exit(TSummary("test_provider"));
  return 0;
}

Main;
