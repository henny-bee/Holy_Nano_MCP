#ifndef HN_HTTP_CLIENT
#define HN_HTTP_CLIENT

/* HolyC has no TLS stack, so HTTPS is delegated to the curl binary.
 *
 * Everything sensitive travels through a 0600 config file inside a 0700
 * private directory: the API key never appears in argv (where any process
 * could read it out of /proc) and never appears in a log line. */

I64 g_http_seq = 0;

Bool HttpClientAvailable()
{
  return System("command -v curl >/dev/null 2>&1") == 0;
}

U8 *HttpClientVersion()
{
  I64 len = 0;
  U8 *out = ShellCapture("curl --version | head -1", &len);
  if (!out) return StrDup("unknown");
  U8 *trimmed = StrTrimDup(out);
  Free(out);
  if (trimmed[0] == 0) { Free(trimmed); return StrDup("unknown"); }
  return trimmed;
}

/* Escapes a value for a curl config file, which understands the same
 * backslash escapes as C for quoted strings. */
U0 SbCatCurlValue(StrBuf *sb, U8 *value)
{
  SbCatCh(sb, CH_DQUOTE);
  if (value) {
    I64 i = 0;
    while (value[i] != 0) {
      U8 c = value[i];
      if (c == CH_DQUOTE)         SbCatEsc(sb, CH_DQUOTE);
      else if (c == CH_BACKSLASH) SbCatEsc(sb, CH_BACKSLASH);
      else if (c == 0x0A)         SbCatEsc(sb, 'n');
      else if (c == 0x0D)         SbCatEsc(sb, 'r');
      else if (c == 0x09)         SbCatEsc(sb, 't');
      else                        SbCatCh(sb, c);
      i++;
    }
  }
  SbCatCh(sb, CH_DQUOTE);
}

U8 *HttpTempDir()
{
  g_http_seq++;
  U8 *dir = StrPrint(NULL, "/tmp/holy-nano-mcp-http-%d-%d", getpid(), g_http_seq);
  MkDir(dir, MODE_0700, TRUE);
  chmod(dir, MODE_0700);
  return dir;
}

U0 HttpCleanupDir(U8 *dir)
{
  if (!dir) return;
  U8 *cmd = StrPrint(NULL, "rm -rf %s", dir);
  System(cmd);
  Free(cmd);
}

/* Performs the request. Always returns a response object; check HttpIsOk. */
HttpResponse *HttpSend(HttpRequest *req)
{
  HttpResponse *res = HttpResponseNew();

  if (!HttpClientAvailable()) {
    res->error = StrDup("curl not found on PATH - required for HTTPS (see docs/PHASE0.md)");
    return res;
  }

  U8 *dir = HttpTempDir();
  U8 *cfg_path    = StrPrint(NULL, "%s/curl.cfg", dir);
  U8 *body_path   = StrPrint(NULL, "%s/request.bin", dir);
  U8 *out_path    = StrPrint(NULL, "%s/response.bin", dir);
  U8 *status_path = StrPrint(NULL, "%s/status.txt", dir);
  U8 *err_path    = StrPrint(NULL, "%s/error.txt", dir);

  StrBuf *cfg = SbNew(1024);
  SbCat(cfg, "url = ");        SbCatCurlValue(cfg, req->url);      SbCatCh(cfg, '\n');
  SbCat(cfg, "request = ");    SbCatCurlValue(cfg, req->method);   SbCatCh(cfg, '\n');
  SbCat(cfg, "output = ");     SbCatCurlValue(cfg, out_path);      SbCatCh(cfg, '\n');
  SbCat(cfg, "write-out = ");  SbCatCurlValue(cfg, "%{http_code}"); SbCatCh(cfg, '\n');
  SbCat(cfg, "silent\nshow-error\nfail-with-body\nlocation\n");
  SbCat(cfg, "max-time = ");   SbCatI64(cfg, req->timeout_secs);   SbCatCh(cfg, '\n');

  HttpHeader *h = req->headers;
  while (h) {
    U8 *line = StrPrint(NULL, "%s: %s", h->name, h->value);
    SbCat(cfg, "header = ");
    SbCatCurlValue(cfg, line);
    SbCatCh(cfg, '\n');
    Free(line);
    h = h->next;
  }

  if (req->body != NULL && req->body_len > 0) {
    WriteFdFile(body_path, req->body, req->body_len, MODE_0600);
    chmod(body_path, MODE_0600);
    U8 *ref = StrPrint(NULL, "@%s", body_path);
    SbCat(cfg, "data-binary = ");
    SbCatCurlValue(cfg, ref);
    SbCatCh(cfg, '\n');
    Free(ref);
  }

  WriteFdFile(cfg_path, cfg->buf, cfg->len, MODE_0600);
  chmod(cfg_path, MODE_0600);
  SbRelease(cfg);

  LogDebug("%s %s (%d byte body)", req->method, req->url, req->body_len);

  U8 *cmd = StrPrint(NULL, "curl --config %s > %s 2> %s",
                     cfg_path, status_path, err_path);
  I64 rc = System(cmd);
  Free(cmd);

  I64 status_len = 0;
  U8 *status_raw = ReadFdFile(status_path, &status_len);
  if (status_raw != NULL && status_len > 0) {
    U8 *trimmed = StrTrimDup(status_raw);
    res->status = Atoi(trimmed);
    Free(trimmed);
  }
  if (status_raw) Free(status_raw);

  I64 body_len = 0;
  U8 *body = ReadFdFile(out_path, &body_len);
  if (body != NULL) {
    res->body = body;
    res->body_len = body_len;
  } else {
    res->body = StrDup("");
    res->body_len = 0;
  }

  if (res->status == 0) {
    I64 err_len = 0;
    U8 *err = ReadFdFile(err_path, &err_len);
    U8 *detail = NULL;
    if (err != NULL && err_len > 0) detail = StrTrimDup(err);
    else detail = StrPrint(NULL, "curl exited with %d", rc);
    res->error = StrPrint(NULL, "transport failure: %s", detail);
    Free(detail);
    if (err) Free(err);
  }

  HttpCleanupDir(dir);
  Free(cfg_path);
  Free(body_path);
  Free(out_path);
  Free(status_path);
  Free(err_path);
  Free(dir);
  return res;
}

#endif
