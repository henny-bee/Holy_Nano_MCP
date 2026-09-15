#ifndef HN_MCP_JSONRPC
#define HN_MCP_JSONRPC

/* JSON-RPC 2.0 framing. Knows nothing about MCP semantics or Google APIs. */

class RpcRequest
{
  Json *doc;      /* owned - release with RpcRequestRelease */
  U8 *method;     /* borrowed */
  Json *id;       /* borrowed; NULL for notifications */
  Json *params;   /* borrowed; may be NULL */
  Bool ok;
  U8 *parse_error;/* owned when ok == FALSE */
};

RpcRequest *RpcParse(U8 *line, I64 len)
{
  RpcRequest *r = MAlloc(sizeof(RpcRequest));
  r->doc = NULL; r->method = NULL; r->id = NULL; r->params = NULL;
  r->ok = FALSE; r->parse_error = NULL;

  Json *doc = JsonParse(line, len);
  if (doc == NULL) {
    r->parse_error = StrDup("invalid JSON");
    return r;
  }
  if (!JsonOk(doc)) {
    r->parse_error = StrDup("invalid JSON");
    JsonRelease(doc);
    return r;
  }
  r->doc = doc;

  if (doc->type != JSON_OBJECT) {
    r->parse_error = StrDup("request must be a JSON object");
    return r;
  }

  Json *m = JField(doc, "method");
  if (!m || m->type != JSON_STRING) {
    r->parse_error = StrDup("missing or non-string 'method'");
    r->id = JField(doc, "id");
    return r;
  }

  r->method = m->str;
  r->id = JField(doc, "id");
  r->params = JField(doc, "params");
  r->ok = TRUE;
  return r;
}

Bool RpcIsNotification(RpcRequest *r)
{
  return r != NULL && r->id == NULL;
}

U0 RpcRequestRelease(RpcRequest *r)
{
  if (!r) return;
  if (r->doc) JsonRelease(r->doc);
  if (r->parse_error) Free(r->parse_error);
  Free(r);
}

/* `result_json` must already be a serialised JSON value. */
U8 *RpcResult(Json *id, U8 *result_json)
{
  StrBuf *sb = SbNew(512);
  SbCat(sb, "{\"jsonrpc\":\"2.0\",\"id\":");
  SbCatRpcId(sb, id);
  SbCat(sb, ",\"result\":");
  SbCat(sb, result_json);
  SbCatCh(sb, '}');
  return SbSteal(sb);
}

U8 *RpcError(Json *id, I64 code, U8 *message)
{
  StrBuf *sb = SbNew(256);
  SbCat(sb, "{\"jsonrpc\":\"2.0\",\"id\":");
  SbCatRpcId(sb, id);
  SbCat(sb, ",\"error\":{\"code\":");
  SbCatI64(sb, code);
  SbCat(sb, ",\"message\":");
  SbCatJson(sb, message);
  SbCat(sb, "}}");
  return SbSteal(sb);
}

#endif
