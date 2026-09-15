#ifndef HN_AUTH_CREDENTIALS
#define HN_AUTH_CREDENTIALS

/* A file called service-account.json may hold either this project's config
 * container or a real Google Cloud service-account key. The credential model
 * keeps those apart so the provider layer always knows what it was handed. */

#define CRED_NONE            0
#define CRED_API_KEY         1
#define CRED_SERVICE_ACCOUNT 2
#define CRED_ADC             3
#define CRED_ACCESS_TOKEN    4

class Credential
{
  I64 type;
  U8 *api_key;          /* CRED_API_KEY */
  U8 *credentials_file; /* CRED_SERVICE_ACCOUNT */
  U8 *access_token;     /* CRED_ACCESS_TOKEN */
  U8 *source;           /* provenance, e.g. "env:GEMINI_API_KEY" */
};

Credential *CredNew(I64 type, U8 *source)
{
  Credential *c = MAlloc(sizeof(Credential));
  c->type = type;
  c->api_key = NULL;
  c->credentials_file = NULL;
  c->access_token = NULL;
  c->source = StrDup(source);
  return c;
}

Credential *CredApiKey(U8 *key, U8 *source)
{
  Credential *c = CredNew(CRED_API_KEY, source);
  c->api_key = StrDup(key);
  return c;
}

U8 *CredTypeName(I64 type)
{
  switch (type) {
    case CRED_API_KEY:         return "api_key";
    case CRED_SERVICE_ACCOUNT: return "service_account";
    case CRED_ADC:             return "adc";
    case CRED_ACCESS_TOKEN:    return "access_token";
    default:                   return "none";
  }
}

U0 CredRelease(Credential *c)
{
  if (!c) return;
  if (c->api_key) Free(c->api_key);
  if (c->credentials_file) Free(c->credentials_file);
  if (c->access_token) Free(c->access_token);
  if (c->source) Free(c->source);
  Free(c);
}

/* Describes a credential without ever revealing it. */
U8 *CredDescribe(Credential *c)
{
  if (!c || c->type == CRED_NONE) return StrDup("none");
  U8 *detail = NULL;
  if (c->type == CRED_API_KEY)              detail = Redact(c->api_key);
  else if (c->type == CRED_ACCESS_TOKEN)    detail = Redact(c->access_token);
  else if (c->type == CRED_SERVICE_ACCOUNT) detail = StrDup(c->credentials_file);
  else                                      detail = StrDup("application default credentials");
  U8 *out = StrPrint(NULL, "%s (%s) via %s", CredTypeName(c->type), detail, c->source);
  Free(detail);
  return out;
}

#endif
