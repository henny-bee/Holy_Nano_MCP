#ifndef HN_UTILS_STRINGS
#define HN_UTILS_STRINGS

/* Growable byte buffer. Always NUL terminated, but `len` is authoritative so
 * it can also carry binary payloads. */
class StrBuf
{
  U8 *buf;
  I64 len;
  I64 cap;
};

StrBuf *SbNew(I64 cap=256)
{
  StrBuf *sb = MAlloc(sizeof(StrBuf));
  if (cap < 32) cap = 32;
  sb->buf = MAlloc(cap);
  sb->buf[0] = '\0';
  sb->len = 0;
  sb->cap = cap;
  return sb;
}

U0 SbGrow(StrBuf *sb, I64 extra)
{
  I64 need = sb->len + extra + 1;
  if (need <= sb->cap) return;
  I64 cap = sb->cap;
  while (cap < need) cap = cap * 2;
  U8 *nb = MAlloc(cap);
  if (sb->len > 0) MemCpy(nb, sb->buf, sb->len);
  Free(sb->buf);
  sb->buf = nb;
  sb->cap = cap;
}

U0 SbCatLen(StrBuf *sb, U8 *s, I64 len)
{
  if (!s || len <= 0) return;
  SbGrow(sb, len);
  MemCpy(sb->buf + sb->len, s, len);
  sb->len += len;
  sb->buf[sb->len] = '\0';
}

U0 SbCat(StrBuf *sb, U8 *s)
{
  if (s) SbCatLen(sb, s, StrLen(s));
}

U0 SbCatCh(StrBuf *sb, U8 ch)
{
  SbGrow(sb, 1);
  sb->buf[sb->len] = ch;
  sb->len++;
  sb->buf[sb->len] = '\0';
}

U0 SbCatI64(StrBuf *sb, I64 v)
{
  U8 *s = StrPrint(NULL, "%d", v);
  SbCat(sb, s);
  Free(s);
}

#define CH_BACKSLASH 0x5C
#define CH_DQUOTE    0x22

/* Appends a two-byte JSON escape: backslash followed by `code`.
 * Written with byte constants because the HolyC lexer is fussy about
 * backslash literals. */
U0 SbCatEsc(StrBuf *sb, U8 code)
{
  SbCatCh(sb, CH_BACKSLASH);
  SbCatCh(sb, code);
}

/* Appends `s` as a quoted, escaped JSON string. */
U0 SbCatJson(StrBuf *sb, U8 *s)
{
  SbCatCh(sb, CH_DQUOTE);
  if (s) {
    I64 i = 0;
    while (s[i] != 0) {
      U8 c = s[i];
      if (c == CH_DQUOTE)         SbCatEsc(sb, CH_DQUOTE);
      else if (c == CH_BACKSLASH) SbCatEsc(sb, CH_BACKSLASH);
      else if (c == 0x0A)         SbCatEsc(sb, 'n');
      else if (c == 0x0D)         SbCatEsc(sb, 'r');
      else if (c == 0x09)         SbCatEsc(sb, 't');
      else if (c == 0x08)         SbCatEsc(sb, 'b');
      else if (c == 0x0C)         SbCatEsc(sb, 'f');
      else if (c < 0x20) {
        U8 *h = StrPrint(NULL, "u%04x", c);
        SbCatCh(sb, CH_BACKSLASH);
        SbCat(sb, h);
        Free(h);
      } else SbCatCh(sb, c);
      i++;
    }
  }
  SbCatCh(sb, CH_DQUOTE);
}

/* Hands the raw buffer over and frees the wrapper. Caller frees the buffer. */
U8 *SbSteal(StrBuf *sb)
{
  U8 *b = sb->buf;
  Free(sb);
  return b;
}

U0 SbRelease(StrBuf *sb)
{
  if (!sb) return;
  Free(sb->buf);
  Free(sb);
}

U8 *StrDupN(U8 *s, I64 len)
{
  if (!s) return NULL;
  U8 *d = MAlloc(len + 1);
  if (len > 0) MemCpy(d, s, len);
  d[len] = '\0';
  return d;
}

U8 *StrDup(U8 *s)
{
  if (!s) return NULL;
  return StrDupN(s, StrLen(s));
}

Bool StrEq(U8 *a, U8 *b)
{
  if (a == b) return TRUE;
  if (!a || !b) return FALSE;
  return StrCmp(a, b) == 0;
}

Bool StrStarts(U8 *s, U8 *prefix)
{
  if (!s || !prefix) return FALSE;
  I64 n = StrLen(prefix);
  if (StrLen(s) < n) return FALSE;
  return StrNCmp(s, prefix, n) == 0;
}

Bool StrEnds(U8 *s, U8 *suffix)
{
  if (!s || !suffix) return FALSE;
  I64 sl = StrLen(s), fl = StrLen(suffix);
  if (sl < fl) return FALSE;
  return StrNCmp(s + sl - fl, suffix, fl) == 0;
}

U8 *StrLower(U8 *s)
{
  if (!s) return NULL;
  U8 *d = StrDup(s);
  I64 i = 0;
  while (d[i] != '\0') { d[i] = ToLower(d[i]); i++; }
  return d;
}

/* Strips leading/trailing ASCII whitespace into a fresh allocation. */
U8 *StrTrimDup(U8 *s)
{
  if (!s) return NULL;
  I64 start = 0, end = StrLen(s);
  while (start < end && IsSpace(s[start])) start++;
  while (end > start && IsSpace(s[end - 1])) end--;
  return StrDupN(s + start, end - start);
}

#endif
