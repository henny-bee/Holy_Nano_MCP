/* JSON serialisation, accessors and base64. */

#include "../src/utils/os.HC"
#include "../src/utils/strings.HC"
#include "../src/utils/errors.HC"
#include "../src/utils/logging.HC"
#include "../src/utils/json_util.HC"
#include "../src/image/base64.HC"
#include "./harness.HC"

U0 TestStrBuf()
{
  StrBuf *sb = SbNew(4);
  SbCat(sb, "abc");
  SbCatCh(sb, '-');
  SbCatI64(sb, -42);
  SbCatLen(sb, "xyz!!", 3);
  TEqStr(sb->buf, "abc--42xyz", "StrBuf appends and grows");
  TEqI64(sb->len, 10, "StrBuf tracks length");
  SbRelease(sb);
}

U0 TestJsonEscape()
{
  StrBuf *sb = SbNew();
  SbCatJson(sb, "plain");
  TEqStr(sb->buf, "\"plain\"", "escapes a plain string");
  SbRelease(sb);

  sb = SbNew();
  SbCatJson(sb, "a\"b");
  TEqStr(sb->buf, "\"a\\\"b\"", "escapes a double quote");
  SbRelease(sb);

  sb = SbNew();
  U8 backslash[4];
  backslash[0] = 'a'; backslash[1] = CH_BACKSLASH; backslash[2] = 'b'; backslash[3] = 0;
  SbCatJson(sb, backslash);
  TEqI64(sb->len, 6, "escaped backslash is two characters");
  SbRelease(sb);

  sb = SbNew();
  SbCatJson(sb, "line\nbreak\ttab");
  TEqStr(sb->buf, "\"line\\nbreak\\ttab\"", "escapes control characters");
  SbRelease(sb);

  sb = SbNew();
  U8 ctrl[3];
  ctrl[0] = 'a'; ctrl[1] = 0x01; ctrl[2] = 0;
  SbCatJson(sb, ctrl);
  TEqStr(sb->buf, "\"a\\u0001\"", "escapes low control bytes as \\u");
  SbRelease(sb);

  sb = SbNew();
  SbCatJson(sb, NULL);
  TEqStr(sb->buf, "\"\"", "NULL serialises as an empty string");
  SbRelease(sb);
}

U0 TestJsonRoundTrip()
{
  /* Anything SbCatJson emits must survive the parser unchanged. */
  U8 *nasty = "quote \" backslash and\nnewline\ttab";
  StrBuf *sb = SbNew();
  SbCat(sb, "{\"v\":");
  SbCatJson(sb, nasty);
  SbCatCh(sb, '}');
  Json *doc = JsonParse(sb->buf, sb->len);
  TCheck(doc != NULL, "escaped payload re-parses");
  if (doc) {
    TEqStr(JStr(doc, "v", NULL), nasty, "escaped payload round-trips");
    JsonRelease(doc);
  }
  SbRelease(sb);
}

U0 TestJsonAccessors()
{
  U8 *raw = "{\"s\":\"str\",\"i\":42,\"b\":true,\"o\":{\"n\":{\"deep\":7}},\"a\":[1,2,3]}";
  Json *doc = JsonParse(raw, StrLen(raw));
  TCheck(doc != NULL, "parses a nested document");
  if (!doc) return;

  TEqStr(JStr(doc, "s", "x"), "str", "JStr reads a string");
  TEqStr(JStr(doc, "missing", "fallback"), "fallback", "JStr falls back");
  TEqI64(JInt(doc, "i", 0), 42, "JInt reads an int");
  TEqI64(JInt(doc, "missing", 9), 9, "JInt falls back");
  TCheck(JBool(doc, "b", FALSE), "JBool reads a bool");
  TCheck(JObjField(doc, "o") != NULL, "JObjField finds an object");
  TCheck(JObjField(doc, "s") == NULL, "JObjField rejects a non-object");
  TCheck(JArrField(doc, "a") != NULL, "JArrField finds an array");

  Json *deep = JPath(doc, "o.n.deep");
  TCheck(deep != NULL, "JPath walks nested objects");
  if (deep) TEqI64(deep->i64, 7, "JPath reaches the leaf value");
  TCheck(JPath(doc, "o.nope.deep") == NULL, "JPath stops at a missing segment");

  I64 count = 0;
  Json *el = JArrFirst(JArrField(doc, "a"));
  while (el) { count++; el = el->next; }
  TEqI64(count, 3, "array iteration visits every element");

  JsonRelease(doc);
}

U0 TestJsonMalformed()
{
  Json *doc = JsonParse("{not json", 9);
  Bool bad = doc == NULL;
  if (doc != NULL && !JsonOk(doc)) bad = TRUE;
  TCheck(bad, "malformed JSON is rejected");
  if (doc) JsonRelease(doc);
}

U0 TestBase64()
{
  I64 n = 0;
  U8 *d = B64Decode("aGVsbG8=", 8, &n);
  TEqI64(n, 5, "decodes with one pad byte");
  TEqStr(d, "hello", "decodes ASCII");
  Free(d);

  d = B64Decode("aGVsbG8h", 8, &n);
  TEqI64(n, 6, "decodes with no padding");
  Free(d);

  d = B64Decode("aGVsbG9v", 8, &n);
  TEqI64(n, 6, "decodes a full quad");
  Free(d);

  d = B64Decode("aGVs\nbG8=", 9, &n);
  TEqI64(n, 5, "skips embedded newlines");
  Free(d);

  d = B64Decode("_-8=", 4, &n);
  TCheck(d != NULL, "accepts the URL-safe alphabet");
  if (d) Free(d);

  d = B64Decode("not base64 !!", 13, &n);
  TCheck(d == NULL, "rejects invalid characters");

  d = B64Decode("aGVsbG", 6, &n);
  TCheck(d == NULL, "rejects a truncated quad");

  U8 *enc = B64Encode("hello", 5);
  TEqStr(enc, "aGVsbG8=", "encodes with padding");
  Free(enc);

  enc = B64Encode("hi", 2);
  TEqStr(enc, "aGk=", "encodes a two-byte tail");
  Free(enc);

  /* Binary round trip including a NUL and a high byte. */
  U8 bin[5];
  bin[0] = 0x89; bin[1] = 'P'; bin[2] = 0x00; bin[3] = 0xFF; bin[4] = 'G';
  enc = B64Encode(bin, 5);
  d = B64Decode(enc, StrLen(enc), &n);
  TEqI64(n, 5, "binary round trip keeps its length");
  Bool same = TRUE;
  I64 i = 0;
  while (i < 5) { if (d[i] != bin[i]) same = FALSE; i++; }
  TCheck(same, "binary round trip preserves every byte");
  Free(enc);
  Free(d);
}

I64 Main()
{
  TBanner("test_json");
  TestStrBuf();
  TestJsonEscape();
  TestJsonRoundTrip();
  TestJsonAccessors();
  TestJsonMalformed();
  TestBase64();
  exit(TSummary("test_json"));
  return 0;
}

Main;
