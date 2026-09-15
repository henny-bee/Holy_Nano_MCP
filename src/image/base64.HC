#ifndef HN_IMAGE_BASE64
#define HN_IMAGE_BASE64

/* Base64 with both alphabets: the API returns standard base64, but URL-safe
 * variants (-/_) show up often enough to be worth accepting. */

U8 g_b64_dec[256];
Bool g_b64_ready = FALSE;
U8 *g_b64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* Array subscripts must be I64 in HolyC - a U8 index is a type error. */
U0 B64Init()
{
  if (g_b64_ready) return;
  I64 i = 0;
  while (i < 256) { g_b64_dec[i] = 0xFF; i++; }
  i = 0;
  while (i < 64) {
    I64 slot = g_b64_alphabet[i];
    g_b64_dec[slot] = i;
    i++;
  }
  g_b64_dec[45] = 62; /* - */
  g_b64_dec[95] = 63; /* _ */
  g_b64_ready = TRUE;
}

/* Decodes `len` bytes of base64, skipping whitespace and newlines.
 * Returns a heap buffer and writes its length to `*out_len`, or NULL on a
 * malformed input. */
U8 *B64Decode(U8 *src, I64 len, I64 *out_len)
{
  B64Init();
  if (!src) return NULL;
  if (len < 0) len = StrLen(src);

  U8 *out = MAlloc(len / 4 * 3 + 4);
  I64 written = 0;
  I64 quad[4];
  I64 have = 0;
  I64 i = 0;
  I64 padding = 0;

  while (i < len) {
    U8 c = src[i];
    i++;
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') continue;
    if (c == '=') { padding++; quad[have] = 0; have++; }
    else {
      I64 slot = c;
      U8 v = g_b64_dec[slot];
      if (v == 0xFF) { Free(out); return NULL; }
      if (padding > 0) { Free(out); return NULL; } /* data after padding */
      quad[have] = v;
      have++;
    }

    if (have == 4) {
      I64 triple = (quad[0] << 18) | (quad[1] << 12) | (quad[2] << 6) | quad[3];
      out[written] = (triple >> 16) & 0xFF;
      out[written + 1] = (triple >> 8) & 0xFF;
      out[written + 2] = triple & 0xFF;
      written += 3;
      have = 0;
    }
  }

  if (have != 0) { Free(out); return NULL; }
  written -= padding;
  if (written < 0) { Free(out); return NULL; }

  out[written] = 0;
  *out_len = written;
  return out;
}

/* Encodes `len` bytes as standard base64. Caller frees. */
U8 *B64Encode(U8 *src, I64 len)
{
  B64Init();
  if (!src) return StrDup("");
  I64 out_cap = (len + 2) / 3 * 4 + 1;
  U8 *out = MAlloc(out_cap);
  I64 i = 0;
  I64 w = 0;

  while (i + 2 < len) {
    I64 triple = (src[i] << 16) | (src[i + 1] << 8) | src[i + 2];
    out[w] = g_b64_alphabet[(triple >> 18) & 0x3F];
    out[w + 1] = g_b64_alphabet[(triple >> 12) & 0x3F];
    out[w + 2] = g_b64_alphabet[(triple >> 6) & 0x3F];
    out[w + 3] = g_b64_alphabet[triple & 0x3F];
    w += 4;
    i += 3;
  }

  I64 remaining = len - i;
  if (remaining == 1) {
    I64 triple = src[i] << 16;
    out[w] = g_b64_alphabet[(triple >> 18) & 0x3F];
    out[w + 1] = g_b64_alphabet[(triple >> 12) & 0x3F];
    out[w + 2] = '=';
    out[w + 3] = '=';
    w += 4;
  } else if (remaining == 2) {
    I64 triple = (src[i] << 16) | (src[i + 1] << 8);
    out[w] = g_b64_alphabet[(triple >> 18) & 0x3F];
    out[w + 1] = g_b64_alphabet[(triple >> 12) & 0x3F];
    out[w + 2] = g_b64_alphabet[(triple >> 6) & 0x3F];
    out[w + 3] = '=';
    w += 4;
  }

  out[w] = 0;
  return out;
}

#endif
