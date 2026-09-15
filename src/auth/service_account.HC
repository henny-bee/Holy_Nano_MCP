#ifndef HN_AUTH_SERVICE_ACCOUNT
#define HN_AUTH_SERVICE_ACCOUNT

/* Inspection of repo-local credential files. */

#define SA_KIND_MISSING   0
#define SA_KIND_INVALID   1
#define SA_KIND_CONFIG    2 /* this project's config container */
#define SA_KIND_GCP_SA    3 /* a real Google Cloud service-account key */

#define SA_DEFAULT_FILE "./service-account.json"

U8 *SaKindName(I64 kind)
{
  switch (kind) {
    case SA_KIND_CONFIG: return "holy-nano-mcp config";
    case SA_KIND_GCP_SA: return "google cloud service account key";
    case SA_KIND_INVALID: return "invalid json";
    default: return "missing";
  }
}

/* Classifies a credential file. `*out_doc` receives the parsed document when
 * the file parses; the caller releases it. */
I64 SaInspect(U8 *path, Json **out_doc)
{
  if (out_doc) *out_doc = NULL;
  if (!PathExists(path)) return SA_KIND_MISSING;

  I64 size = 0;
  U8 *raw = FileRead(path, &size);
  if (!raw || size <= 0) return SA_KIND_INVALID;

  Json *doc = JsonParse(raw, size);
  Free(raw);
  if (doc == NULL) return SA_KIND_INVALID;
  if (!JsonOk(doc)) { JsonRelease(doc); return SA_KIND_INVALID; }
  if (doc->type != JSON_OBJECT) { JsonRelease(doc); return SA_KIND_INVALID; }

  U8 *type = JStr(doc, "type", NULL);
  Bool has_private_key = JField(doc, "private_key") != NULL;
  Bool has_client_email = JField(doc, "client_email") != NULL;

  I64 kind = SA_KIND_CONFIG;
  if (StrEq(type, "service_account") && has_private_key && has_client_email) {
    kind = SA_KIND_GCP_SA;
  }

  if (out_doc) *out_doc = doc;
  else JsonRelease(doc);
  return kind;
}

/* TRUE when git would ignore `path`. Also TRUE when git is unavailable, so a
 * missing git never blocks startup - the caller warns either way. */
Bool SaIsGitIgnored(U8 *path)
{
  U8 *cmd = StrPrint(NULL,
    "git check-ignore -q %s >/dev/null 2>&1", path);
  I64 rc = System(cmd);
  Free(cmd);
  return rc == 0;
}

Bool SaIsTrackedByGit(U8 *path)
{
  U8 *cmd = StrPrint(NULL,
    "git ls-files --error-unmatch %s >/dev/null 2>&1", path);
  I64 rc = System(cmd);
  Free(cmd);
  return rc == 0;
}

/* Warns, on stderr only, that a credential file is present. Never prints
 * anything from inside the file. */
U0 SaWarnIfExposed(U8 *path, I64 kind)
{
  if (kind == SA_KIND_MISSING || kind == SA_KIND_INVALID) return;
  if (SaIsTrackedByGit(path)) {
    LogError("%s is tracked by git and contains credentials - remove it from the index", path);
    return;
  }
  if (!SaIsGitIgnored(path)) {
    LogWarn("%s contains credentials and is not covered by .gitignore - do not commit it", path);
  }
}

#endif
