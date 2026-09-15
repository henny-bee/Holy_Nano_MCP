#ifndef HN_IMAGE_GENERATE
#define HN_IMAGE_GENERATE

/* Orchestration: provider call -> base64 decode -> disk. Isolated from both
 * the MCP layer and the provider layer. */

extern "c" I64 time(I64 *t);

I64 g_image_seq = 0;

/* PNG carries its dimensions in the IHDR chunk at a fixed offset. Other
 * formats are left at 0 rather than guessed. */
Bool PngSize(U8 *data, I64 len, I64 *w, I64 *h)
{
  if (!data || len < 24) return FALSE;
  if (data[0] != 0x89) return FALSE;
  if (data[1] != 'P' || data[2] != 'N' || data[3] != 'G') return FALSE;
  if (data[12] != 'I' || data[13] != 'H' || data[14] != 'D' || data[15] != 'R') return FALSE;
  *w = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];
  *h = (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23];
  return TRUE;
}

U8 *ImageNameStem(U8 *prefix)
{
  g_image_seq++;
  I64 now = time(NULL);
  return StrPrint(NULL, "%s-%d-%d", prefix, now, g_image_seq);
}

/* Decodes the result and writes it to disk, filling output_path, width and
 * height. Returns NULL on success or an owned error message. */
U8 *ImagePersist(ImageResult *r, HnConfig *c, U8 *requested_path, U8 *stem)
{
  if (!r->data_base64) return StrDup("provider returned no image data");

  I64 raw_len = 0;
  U8 *raw = B64Decode(r->data_base64, StrLen(r->data_base64), &raw_len);
  if (!raw) return StrDup("image payload was not valid base64");
  if (raw_len <= 0) { Free(raw); return StrDup("image payload decoded to zero bytes"); }

  U8 *mime = r->mime_type;
  if (!mime) mime = "image/png";

  U8 *path = ResolveOutputPath(requested_path, c->output_dir, mime, stem, c->overwrite);
  U8 *err = WriteImageFile(path, raw, raw_len);
  if (err) {
    Free(raw);
    Free(path);
    return err;
  }

  I64 w = 0, h = 0;
  if (PngSize(raw, raw_len, &w, &h)) {
    r->width = w;
    r->height = h;
  }

  r->output_path = path;
  Free(raw);
  LogInfo("wrote %s (%d bytes)", path, raw_len);
  return NULL;
}

/* Runs a generation end to end. The returned result always needs releasing. */
ImageResult *ImageGenerate(AIProvider *p, HnConfig *c, ImageRequest *req,
                           U8 *requested_path)
{
  ImageResult *r = p->GenerateImage(p, req);
  if (!r->ok) return r;

  U8 *stem = ImageNameStem("image");
  U8 *err = ImagePersist(r, c, requested_path, stem);
  Free(stem);
  if (err) {
    r->ok = FALSE;
    r->error_code = HN_ERR_IO;
    if (r->error) Free(r->error);
    r->error = err;
  }
  return r;
}

#endif
