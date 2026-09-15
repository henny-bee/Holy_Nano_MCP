#ifndef HN_HTTP_RESPONSE
#define HN_HTTP_RESPONSE

class HttpResponse
{
  I64 status;      /* 0 when the request never reached the server */
  U8 *body;        /* owned; NUL terminated */
  I64 body_len;
  U8 *error;       /* owned; transport-level failure, else NULL */
};

HttpResponse *HttpResponseNew()
{
  HttpResponse *r = MAlloc(sizeof(HttpResponse));
  r->status = 0;
  r->body = NULL;
  r->body_len = 0;
  r->error = NULL;
  return r;
}

Bool HttpIsOk(HttpResponse *r)
{
  if (!r) return FALSE;
  if (r->error) return FALSE;
  return r->status >= 200 && r->status < 300;
}

U0 HttpResponseRelease(HttpResponse *r)
{
  if (!r) return;
  if (r->body) Free(r->body);
  if (r->error) Free(r->error);
  Free(r);
}

#endif
