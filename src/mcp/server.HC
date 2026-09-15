#ifndef HN_MCP_SERVER
#define HN_MCP_SERVER

/* stdio transport: newline-delimited JSON-RPC in on fd 0, out on fd 1. */

#define LR_CHUNK 8192

class LineReader
{
  U8 *buf;
  I64 len;
  I64 cap;
  I64 pos;
  Bool eof;
};

LineReader *LrNew()
{
  LineReader *lr = MAlloc(sizeof(LineReader));
  lr->cap = LR_CHUNK * 2;
  lr->buf = MAlloc(lr->cap);
  lr->len = 0;
  lr->pos = 0;
  lr->eof = FALSE;
  return lr;
}

U0 LrCompact(LineReader *lr)
{
  if (lr->pos == 0) return;
  I64 remaining = lr->len - lr->pos;
  if (remaining > 0) MemCpy(lr->buf, lr->buf + lr->pos, remaining);
  lr->len = remaining;
  lr->pos = 0;
}

U0 LrReserve(LineReader *lr, I64 extra)
{
  if (lr->len + extra <= lr->cap) return;
  I64 cap = lr->cap;
  while (cap < lr->len + extra) cap = cap * 2;
  U8 *nb = MAlloc(cap);
  if (lr->len > 0) MemCpy(nb, lr->buf, lr->len);
  Free(lr->buf);
  lr->buf = nb;
  lr->cap = cap;
}

/* Returns one line without its terminator, or NULL at end of input.
 * `*out_len` receives the line length. Caller frees. */
U8 *LrNextLine(LineReader *lr, I64 *out_len)
{
  while (TRUE) {
    I64 i = lr->pos;
    while (i < lr->len) {
      if (lr->buf[i] == '\n') {
        I64 start = lr->pos;
        I64 end = i;
        if (end > start && lr->buf[end - 1] == '\r') end--;
        U8 *line = StrDupN(lr->buf + start, end - start);
        *out_len = end - start;
        lr->pos = i + 1;
        return line;
      }
      i++;
    }

    if (lr->eof) {
      /* Trailing data with no newline still counts as a message. */
      if (lr->pos < lr->len) {
        U8 *line = StrDupN(lr->buf + lr->pos, lr->len - lr->pos);
        *out_len = lr->len - lr->pos;
        lr->pos = lr->len;
        return line;
      }
      return NULL;
    }

    LrCompact(lr);
    LrReserve(lr, LR_CHUNK);
    I64 n = read(FD_STDIN, lr->buf + lr->len, LR_CHUNK);
    if (n <= 0) { lr->eof = TRUE; continue; }
    lr->len += n;
  }
}

U0 LrRelease(LineReader *lr)
{
  if (!lr) return;
  Free(lr->buf);
  Free(lr);
}

U0 ServerWrite(U8 *msg)
{
  I64 len = StrLen(msg);
  StrBuf *sb = SbNew(len + 2);
  SbCatLen(sb, msg, len);
  SbCatCh(sb, '\n');
  /* One write per message keeps frames intact for the client. */
  I64 written = 0;
  while (written < sb->len) {
    I64 n = write(FD_STDOUT, sb->buf + written, sb->len - written);
    if (n <= 0) break;
    written += n;
  }
  SbRelease(sb);
}

/* Blocks until stdin closes. Returns a process exit code. */
I64 ServerRun()
{
  LineReader *lr = LrNew();
  LogInfo("listening on stdio");

  while (TRUE) {
    I64 len = 0;
    U8 *line = LrNextLine(lr, &len);
    if (!line) break;

    /* Blank keep-alive lines are legal and ignored. */
    if (len == 0) { Free(line); continue; }

    RpcRequest *req = RpcParse(line, len);
    U8 *resp = McpDispatch(req);
    if (resp) {
      ServerWrite(resp);
      Free(resp);
    }
    RpcRequestRelease(req);
    Free(line);
  }

  LrRelease(lr);
  LogInfo("stdin closed, shutting down");
  return 0;
}

#endif
