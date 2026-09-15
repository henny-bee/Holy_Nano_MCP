#ifndef HN_IMAGE_FILES
#define HN_IMAGE_FILES

/* Output-path handling: extension from MIME type, parent directories,
 * and overwrite protection. */

U8 *MimeToExt(U8 *mime)
{
  if (StrEq(mime, "image/png"))  return "png";
  if (StrEq(mime, "image/jpeg")) return "jpg";
  if (StrEq(mime, "image/jpg"))  return "jpg";
  if (StrEq(mime, "image/webp")) return "webp";
  if (StrEq(mime, "image/gif"))  return "gif";
  return "bin";
}

U8 *ExtToMime(U8 *path)
{
  U8 *lower = StrLower(path);
  U8 *mime = "image/png";
  if (StrEnds(lower, ".jpg") || StrEnds(lower, ".jpeg")) mime = "image/jpeg";
  else if (StrEnds(lower, ".webp")) mime = "image/webp";
  else if (StrEnds(lower, ".gif")) mime = "image/gif";
  Free(lower);
  return mime;
}

/* Everything before the last '/', or NULL when the path has no directory. */
U8 *PathParent(U8 *path)
{
  if (!path) return NULL;
  I64 last = -1;
  I64 i = 0;
  while (path[i] != 0) {
    if (path[i] == '/') last = i;
    i++;
  }
  if (last <= 0) return NULL;
  return StrDupN(path, last);
}

Bool EnsureParentDir(U8 *path)
{
  U8 *parent = PathParent(path);
  if (!parent) return TRUE;
  Bool ok = TRUE;
  if (!PathExists(parent)) ok = MkDir(parent, MODE_0755, TRUE);
  Free(parent);
  return ok;
}

/* Appends -1, -2, ... until the name is free. Caller frees. */
U8 *UniquePath(U8 *path)
{
  if (!PathExists(path)) return StrDup(path);

  U8 *base = StrDup(path);
  U8 *ext = StrDup("");
  I64 i = StrLen(base) - 1;
  while (i >= 0) {
    if (base[i] == '/') break;
    if (base[i] == '.') {
      Free(ext);
      ext = StrDup(base + i);
      base[i] = 0;
      break;
    }
    i--;
  }

  I64 n = 1;
  U8 *candidate = NULL;
  while (n < 10000) {
    candidate = StrPrint(NULL, "%s-%d%s", base, n, ext);
    if (!PathExists(candidate)) break;
    Free(candidate);
    candidate = NULL;
    n++;
  }
  Free(base);
  Free(ext);
  if (!candidate) return StrDup(path);
  return candidate;
}

/* Resolves the destination for a generated image.
 *
 * `requested` wins when given; otherwise a timestamped name is placed in
 * `output_dir`. When `overwrite` is false an existing file is stepped around
 * rather than replaced. */
U8 *ResolveOutputPath(U8 *requested, U8 *output_dir, U8 *mime,
                      U8 *stem, Bool overwrite)
{
  U8 *path = NULL;
  if (requested != NULL && requested[0] != 0) {
    path = StrDup(requested);
  } else {
    U8 *dir = output_dir;
    if (!dir) dir = "./generated";
    path = StrPrint(NULL, "%s/%s.%s", dir, stem, MimeToExt(mime));
  }

  if (!overwrite) {
    U8 *unique = UniquePath(path);
    Free(path);
    path = unique;
  }
  return path;
}

/* Writes decoded image bytes. Returns NULL on success, else an owned message. */
U8 *WriteImageFile(U8 *path, U8 *data, I64 len)
{
  if (!EnsureParentDir(path)) {
    return StrPrint(NULL, "could not create directory for %s", path);
  }
  if (!FileWrite(path, data, len)) {
    return StrPrint(NULL, "could not write %s", path);
  }
  return NULL;
}

/* Loads an image from disk as base64. Returns NULL when unreadable. */
U8 *ReadImageAsBase64(U8 *path, U8 **out_mime)
{
  if (!PathExists(path)) return NULL;
  I64 len = 0;
  U8 *raw = FileRead(path, &len);
  if (!raw) return NULL;
  if (len <= 0) { Free(raw); return NULL; }
  U8 *b64 = B64Encode(raw, len);
  Free(raw);
  if (out_mime) *out_mime = ExtToMime(path);
  return b64;
}

#endif
