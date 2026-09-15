#ifndef HN_UTILS_LOGGING
#define HN_UTILS_LOGGING

#define LOG_DEBUG 0
#define LOG_INFO  1
#define LOG_WARN  2
#define LOG_ERROR 3
#define LOG_OFF   4

I64 g_log_level = LOG_INFO;

U0 LogSetLevelName(U8 *name)
{
  if (!name) return;
  U8 *l = StrLower(name);
  if (StrEq(l, "debug"))      g_log_level = LOG_DEBUG;
  else if (StrEq(l, "info"))  g_log_level = LOG_INFO;
  else if (StrEq(l, "warn"))  g_log_level = LOG_WARN;
  else if (StrEq(l, "error")) g_log_level = LOG_ERROR;
  else if (StrEq(l, "off"))   g_log_level = LOG_OFF;
  Free(l);
}

/* Returns a display-safe description of a secret. Never returns enough of the
 * value to be useful: at most a 4-char prefix, and nothing at all for short
 * secrets. HolyC printf has no `%.Ns` precision, so the prefix is cut by hand. */
U8 *Redact(U8 *secret)
{
  if (!secret || secret[0] == 0) return StrDup("(not set)");
  I64 n = StrLen(secret);
  if (n < 12) return StrPrint(NULL, "(redacted, %d chars)", n);
  U8 head[5];
  I64 i = 0;
  while (i < 4) { head[i] = secret[i]; i++; }
  head[4] = 0;
  return StrPrint(NULL, "%s... (redacted, %d chars)", head, n);
}

U0 LogEmit(I64 level, U8 *tag, U8 *msg)
{
  if (level < g_log_level) return;
  StrBuf *sb = SbNew(256);
  SbCat(sb, "[holy-nano-mcp] ");
  SbCat(sb, tag);
  SbCat(sb, " ");
  SbCat(sb, msg);
  SbCatCh(sb, '\n');
  /* stderr only - stdout is the JSON-RPC transport. */
  write(FD_STDERR, sb->buf, sb->len);
  SbRelease(sb);
}

U8 *LogFormat(U8 *fmt, I64 argc, I64 *argv)
{
  if (argc == 0) return StrDup(fmt);
  return StrPrintJoin(NULL, fmt, argc, argv);
}

U0 LogDebug(U8 *fmt, ...)
{
  if (LOG_DEBUG < g_log_level) return;
  U8 *m = LogFormat(fmt, argc, argv);
  LogEmit(LOG_DEBUG, "DEBUG", m);
  Free(m);
}

U0 LogInfo(U8 *fmt, ...)
{
  if (LOG_INFO < g_log_level) return;
  U8 *m = LogFormat(fmt, argc, argv);
  LogEmit(LOG_INFO, "INFO", m);
  Free(m);
}

U0 LogWarn(U8 *fmt, ...)
{
  if (LOG_WARN < g_log_level) return;
  U8 *m = LogFormat(fmt, argc, argv);
  LogEmit(LOG_WARN, "WARN", m);
  Free(m);
}

U0 LogError(U8 *fmt, ...)
{
  if (LOG_ERROR < g_log_level) return;
  U8 *m = LogFormat(fmt, argc, argv);
  LogEmit(LOG_ERROR, "ERROR", m);
  Free(m);
}

#endif
