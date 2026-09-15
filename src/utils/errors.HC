#ifndef HN_UTILS_ERRORS
#define HN_UTILS_ERRORS

/* JSON-RPC 2.0 reserved codes. */
#define RPC_PARSE_ERROR      -32700
#define RPC_INVALID_REQUEST  -32600
#define RPC_METHOD_NOT_FOUND -32601
#define RPC_INVALID_PARAMS   -32602
#define RPC_INTERNAL_ERROR   -32603

/* Application codes, surfaced in tool results rather than transport errors. */
#define HN_OK                0
#define HN_ERR_CONFIG        1
#define HN_ERR_CREDENTIALS   2
#define HN_ERR_PROVIDER      3
#define HN_ERR_HTTP          4
#define HN_ERR_API           5
#define HN_ERR_DECODE        6
#define HN_ERR_IO            7
#define HN_ERR_ARGS          8

class HnResult
{
  I64 code;
  U8 *message; /* owned; NULL when code == HN_OK */
};

HnResult *ResOk()
{
  HnResult *r = MAlloc(sizeof(HnResult));
  r->code = HN_OK;
  r->message = NULL;
  return r;
}

HnResult *ResErr(I64 code, U8 *message)
{
  HnResult *r = MAlloc(sizeof(HnResult));
  r->code = code;
  r->message = StrDup(message);
  return r;
}

Bool ResIsOk(HnResult *r)
{
  return r != NULL && r->code == HN_OK;
}

U0 ResRelease(HnResult *r)
{
  if (!r) return;
  if (r->message) Free(r->message);
  Free(r);
}

U8 *HnErrName(I64 code)
{
  switch (code) {
    case HN_OK:              return "ok";
    case HN_ERR_CONFIG:      return "config_error";
    case HN_ERR_CREDENTIALS: return "credentials_error";
    case HN_ERR_PROVIDER:    return "provider_error";
    case HN_ERR_HTTP:        return "http_error";
    case HN_ERR_API:         return "api_error";
    case HN_ERR_DECODE:      return "decode_error";
    case HN_ERR_IO:          return "io_error";
    case HN_ERR_ARGS:        return "invalid_arguments";
    default:                 return "unknown_error";
  }
}

#endif
