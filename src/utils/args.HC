#ifndef HN_UTILS_ARGS
#define HN_UTILS_ARGS

/* hcc gives `Main` no argv, so the command line is recovered from
 * /proc/self/cmdline (NUL-separated). Absent /proc, the server simply runs
 * with no flags, which is a supported configuration. */

#define ARGS_MAX 64

U8 *g_argv[ARGS_MAX];
I64 g_argc = 0;

U0 ArgsLoad()
{
  g_argc = 0;
  I64 size = 0;
  U8 *raw = ReadFdFile("/proc/self/cmdline", &size);
  if (!raw || size <= 0) return;

  I64 start = 0, i = 0;
  while (i <= size && g_argc < ARGS_MAX) {
    if (i == size || raw[i] == 0) {
      if (i > start) {
        g_argv[g_argc] = StrDupN(raw + start, i - start);
        g_argc++;
      }
      start = i + 1;
    }
    i++;
  }
  Free(raw);
}

/* Value of `--name <value>` or `--name=<value>`; NULL when absent. */
U8 *ArgValue(U8 *name)
{
  U8 *flag = StrPrint(NULL, "--%s", name);
  U8 *eq = StrPrint(NULL, "--%s=", name);
  U8 *found = NULL;
  I64 i = 1;
  while (i < g_argc) {
    if (StrEq(g_argv[i], flag)) {
      if (i + 1 < g_argc) found = g_argv[i + 1];
      break;
    }
    if (StrStarts(g_argv[i], eq)) {
      found = g_argv[i] + StrLen(eq);
      break;
    }
    i++;
  }
  Free(flag);
  Free(eq);
  return found;
}

Bool ArgFlag(U8 *name)
{
  U8 *flag = StrPrint(NULL, "--%s", name);
  Bool found = FALSE;
  I64 i = 1;
  while (i < g_argc) {
    if (StrEq(g_argv[i], flag)) { found = TRUE; break; }
    i++;
  }
  Free(flag);
  return found;
}

#endif
