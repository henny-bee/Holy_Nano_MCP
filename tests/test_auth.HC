/* Credential classification, redaction and precedence.
 *
 * The precedence cases run against real files under /tmp, because that is the
 * behaviour that actually matters and the loader reads from disk. */

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
#include "./harness.HC"

#define TDIR "/tmp/holy-nano-mcp-fixtures"

U0 WriteTestFile(U8 *path, U8 *body)
{
  FileWrite(path, body, StrLen(body));
}

U0 TestRedaction()
{
  U8 *r = Redact("AIzaSyABCDEFGHIJKLMNOPQRSTUV");
  TCheck(!TContains(r, "ABCDEFGHIJKLMNOP"), "redaction hides the body of a key");
  TCheck(!TContains(r, "QRSTUV"), "redaction hides the tail of a key");
  THas(r, "AIza", "redaction keeps a short prefix for identification");
  THas(r, "redacted", "redaction says it is redacted");
  Free(r);

  r = Redact("short");
  TCheck(!TContains(r, "short"), "a short secret is hidden entirely");
  Free(r);

  r = Redact(NULL);
  TEqStr(r, "(not set)", "an absent secret says so");
  Free(r);

  Credential *c = CredApiKey("AIzaSyABCDEFGHIJKLMNOPQRSTUV", "test");
  U8 *d = CredDescribe(c);
  TCheck(!TContains(d, "ABCDEFGHIJKLMNOP"), "CredDescribe never leaks the key");
  THas(d, "api_key", "CredDescribe names the credential type");
  THas(d, "test", "CredDescribe names the source");
  Free(d);
  CredRelease(c);
}

U0 TestServiceAccountKinds()
{
  MkDir(TDIR, MODE_0700, TRUE);

  U8 *cfg = TDIR "/config-shaped.json";
  WriteTestFile(cfg, "{\"provider\":\"gemini\",\"api_key\":\"AIzaSyTESTKEY000001\"}");
  TEqI64(SaInspect(cfg, NULL), SA_KIND_CONFIG, "a config container is recognised");

  U8 *sa = TDIR "/real-sa.json";
  WriteTestFile(sa,
    "{\"type\":\"service_account\",\"project_id\":\"p\","
    "\"private_key\":\"-----BEGIN PRIVATE KEY-----\","
    "\"client_email\":\"x@p.iam.gserviceaccount.com\"}");
  TEqI64(SaInspect(sa, NULL), SA_KIND_GCP_SA, "a real service account key is recognised");

  U8 *broken = TDIR "/broken.json";
  WriteTestFile(broken, "{not json");
  TEqI64(SaInspect(broken, NULL), SA_KIND_INVALID, "malformed JSON is reported as invalid");

  TEqI64(SaInspect(TDIR "/does-not-exist.json", NULL), SA_KIND_MISSING,
         "an absent file is reported as missing");

  /* A service-account-shaped file must not be mistaken for a config. */
  Json *doc = NULL;
  SaInspect(sa, &doc);
  Credential *c = CfgCredentialFromDoc(doc, "test");
  TCheck(c == NULL, "a real service account key yields no api_key credential");
  if (doc) JsonRelease(doc);
}

U0 TestCredentialFromDoc()
{
  U8 *raw = "{\"provider\":\"gemini\",\"api_key\":\"AIzaSyFLAT00000001\"}";
  Json *doc = JsonParse(raw, StrLen(raw));
  Credential *c = CfgCredentialFromDoc(doc, "flat");
  TCheck(c != NULL, "reads the flat api_key form");
  if (c) {
    TEqI64(c->type, CRED_API_KEY, "flat api_key is an api key credential");
    TEqStr(c->api_key, "AIzaSyFLAT00000001", "flat api_key is read verbatim");
    CredRelease(c);
  }
  JsonRelease(doc);

  raw = "{\"provider\":\"vertex\",\"auth\":{\"type\":\"service_account\","
        "\"credentials_file\":\"./gcp-service-account.json\"}}";
  doc = JsonParse(raw, StrLen(raw));
  c = CfgCredentialFromDoc(doc, "auth-block");
  TCheck(c != NULL, "reads the auth block form");
  if (c) {
    TEqI64(c->type, CRED_SERVICE_ACCOUNT, "auth block selects a service account");
    TEqStr(c->credentials_file, "./gcp-service-account.json", "auth block keeps the file path");
    CredRelease(c);
  }
  JsonRelease(doc);

  raw = "{\"provider\":\"vertex\",\"auth\":{\"type\":\"adc\"}}";
  doc = JsonParse(raw, StrLen(raw));
  c = CfgCredentialFromDoc(doc, "adc");
  TCheck(c != NULL, "reads the adc form");
  if (c) {
    TEqI64(c->type, CRED_ADC, "adc selects application default credentials");
    CredRelease(c);
  }
  JsonRelease(doc);

  raw = "{\"provider\":\"gemini\"}";
  doc = JsonParse(raw, StrLen(raw));
  c = CfgCredentialFromDoc(doc, "none");
  TCheck(c == NULL, "a config with no credential yields none");
  JsonRelease(doc);
}

U0 TestConfigShapes()
{
  HnConfig *c = CfgNew();
  U8 *raw = "{\"provider\":\"vertex\",\"project_id\":\"my-project\",\"location\":\"us-central1\","
            "\"model\":{\"default\":\"nano-banana-pro\"},"
            "\"output\":{\"directory\":\"./out\",\"overwrite\":true},"
            "\"credentials\":{\"source\":\"repo\"},\"http_timeout\":42}";
  Json *doc = JsonParse(raw, StrLen(raw));
  CfgApplyDoc(c, doc);
  TEqStr(c->provider_name, "vertex", "nested config reads the provider");
  TEqStr(c->project_id, "my-project", "nested config reads project_id");
  TEqStr(c->location, "us-central1", "nested config reads location");
  TEqStr(c->default_model, "nano-banana-pro", "nested model.default is read");
  TEqStr(c->output_dir, "./out", "nested output.directory is read");
  TCheck(c->overwrite, "output.overwrite is read");
  TEqI64(c->credentials_source, CFG_SRC_REPO, "credentials.source is read");
  TEqI64(c->http_timeout, 42, "http_timeout is read");
  JsonRelease(doc);

  /* The flat shape from the spec must work too. */
  HnConfig *f = CfgNew();
  raw = "{\"provider\":\"gemini\",\"model\":\"nano-banana\",\"output_dir\":\"./flat\"}";
  doc = JsonParse(raw, StrLen(raw));
  CfgApplyDoc(f, doc);
  TEqStr(f->provider_name, "gemini", "flat config reads the provider");
  TEqStr(f->default_model, "nano-banana", "flat model string is read");
  TEqStr(f->output_dir, "./flat", "flat output_dir is read");
  JsonRelease(doc);
}

U0 TestMergeOrder()
{
  /* CfgFill must never overwrite a value a higher-priority source already set. */
  HnConfig *c = CfgNew();
  CfgSet(&c->provider_name, "vertex");
  U8 *raw = "{\"provider\":\"gemini\",\"location\":\"europe-west4\"}";
  Json *doc = JsonParse(raw, StrLen(raw));
  CfgApplyDoc(c, doc);
  TEqStr(c->provider_name, "vertex", "a lower-priority source does not override");
  TEqStr(c->location, "europe-west4", "a lower-priority source still fills gaps");
  JsonRelease(doc);
}

U0 TestSourceNames()
{
  TEqI64(CfgSourceFromName("mcp"), CFG_SRC_MCP, "source name mcp");
  TEqI64(CfgSourceFromName("repo"), CFG_SRC_REPO, "source name repo");
  TEqI64(CfgSourceFromName("env"), CFG_SRC_ENV, "source name env");
  TEqI64(CfgSourceFromName("anything-else"), CFG_SRC_AUTO, "unknown source names mean auto");
  TEqStr(CredTypeName(CRED_SERVICE_ACCOUNT), "service_account", "credential type names round-trip");
}

I64 Main()
{
  TBanner("test_auth");
  TestRedaction();
  TestServiceAccountKinds();
  TestCredentialFromDoc();
  TestConfigShapes();
  TestMergeOrder();
  TestSourceNames();
  exit(TSummary("test_auth"));
  return 0;
}

Main;
