#ifndef HN_HTTP_REQUEST
#define HN_HTTP_REQUEST

class HttpHeader
{
  U8 *name;
  U8 *value;
  HttpHeader *next;
};

class HttpRequest
{
  U8 *method;
  U8 *url;
  HttpHeader *headers;
  HttpHeader *headers_tail;
  U8 *body;
  I64 body_len;
  I64 timeout_secs;
};

HttpRequest *HttpNew(U8 *method, U8 *url)
{
  HttpRequest *r = MAlloc(sizeof(HttpRequest));
  r->method = StrDup(method);
  r->url = StrDup(url);
  r->headers = NULL;
  r->headers_tail = NULL;
  r->body = NULL;
  r->body_len = 0;
  r->timeout_secs = 180;
  return r;
}

U0 HttpAddHeader(HttpRequest *r, U8 *name, U8 *value)
{
  HttpHeader *h = MAlloc(sizeof(HttpHeader));
  h->name = StrDup(name);
  h->value = StrDup(value);
  h->next = NULL;
  if (r->headers_tail) r->headers_tail->next = h;
  else r->headers = h;
  r->headers_tail = h;
}

/* Takes ownership of `body`. */
U0 HttpSetBody(HttpRequest *r, U8 *body, I64 len)
{
  if (r->body) Free(r->body);
  r->body = body;
  r->body_len = len;
}

U0 HttpRequestRelease(HttpRequest *r)
{
  if (!r) return;
  HttpHeader *h = r->headers;
  while (h) {
    HttpHeader *next = h->next;
    Free(h->name);
    Free(h->value);
    Free(h);
    h = next;
  }
  if (r->method) Free(r->method);
  if (r->url) Free(r->url);
  if (r->body) Free(r->body);
  Free(r);
}

#endif
