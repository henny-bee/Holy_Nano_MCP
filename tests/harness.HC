#ifndef HN_TEST_HARNESS
#define HN_TEST_HARNESS

/* Minimal assertion harness. Each test binary prints one line per check and
 * exits non-zero if any failed. */

I64 g_test_pass = 0;
I64 g_test_fail = 0;

U0 TOut(U8 *s)
{
  write(FD_STDOUT, s, StrLen(s));
}

U0 TCheck(Bool ok, U8 *name)
{
  if (ok) {
    g_test_pass++;
    U8 *l = StrPrint(NULL, "  ok   %s\n", name);
    TOut(l);
    Free(l);
  } else {
    g_test_fail++;
    U8 *l = StrPrint(NULL, "  FAIL %s\n", name);
    TOut(l);
    Free(l);
  }
}

U0 TEqStr(U8 *actual, U8 *expected, U8 *name)
{
  Bool ok = StrEq(actual, expected);
  TCheck(ok, name);
  if (!ok) {
    U8 *e = "(null)";
    U8 *a = "(null)";
    if (expected) e = expected;
    if (actual) a = actual;
    U8 *l = StrPrint(NULL, "       expected [%s]\n       actual   [%s]\n", e, a);
    TOut(l);
    Free(l);
  }
}

U0 TEqI64(I64 actual, I64 expected, U8 *name)
{
  Bool ok = actual == expected;
  TCheck(ok, name);
  if (!ok) {
    U8 *l = StrPrint(NULL, "       expected %d, actual %d\n", expected, actual);
    TOut(l);
    Free(l);
  }
}

/* TRUE when `needle` occurs in `haystack`. */
Bool TContains(U8 *haystack, U8 *needle)
{
  if (!haystack || !needle) return FALSE;
  I64 hl = StrLen(haystack), nl = StrLen(needle);
  if (nl == 0) return TRUE;
  I64 i = 0;
  while (i + nl <= hl) {
    if (StrNCmp(haystack + i, needle, nl) == 0) return TRUE;
    i++;
  }
  return FALSE;
}

U0 THas(U8 *haystack, U8 *needle, U8 *name)
{
  Bool ok = TContains(haystack, needle);
  TCheck(ok, name);
  if (!ok) {
    U8 *l = StrPrint(NULL, "       [%s]\n       did not contain [%s]\n", haystack, needle);
    TOut(l);
    Free(l);
  }
}

U0 TBanner(U8 *suite)
{
  U8 *l = StrPrint(NULL, "%s\n", suite);
  TOut(l);
  Free(l);
}

I64 TSummary(U8 *suite)
{
  U8 *l = StrPrint(NULL, "%s: %d passed, %d failed\n", suite, g_test_pass, g_test_fail);
  TOut(l);
  Free(l);
  if (g_test_fail > 0) return 1;
  return 0;
}

#endif
