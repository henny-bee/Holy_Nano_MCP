#ifndef HN_IMAGE_EDIT
#define HN_IMAGE_EDIT

/* Editing differs from generation only in loading an input image first. */

ImageResult *ImageEdit(AIProvider *p, HnConfig *c, ImageRequest *req,
                       U8 *input_path, U8 *requested_path)
{
  if (input_path == NULL || input_path[0] == 0) {
    return ImageResultErr(HN_ERR_ARGS, "input_image is required");
  }
  if (!PathExists(input_path)) {
    U8 *msg = StrPrint(NULL, "input image not found: %s", input_path);
    ImageResult *bad = ImageResultErr(HN_ERR_IO, msg);
    Free(msg);
    return bad;
  }

  U8 *mime = NULL;
  U8 *b64 = ReadImageAsBase64(input_path, &mime);
  if (!b64) {
    U8 *msg = StrPrint(NULL, "could not read input image: %s", input_path);
    ImageResult *bad = ImageResultErr(HN_ERR_IO, msg);
    Free(msg);
    return bad;
  }
  req->input_b64 = b64;
  req->input_mime = StrDup(mime);

  ImageResult *r = p->EditImage(p, req);
  if (!r->ok) return r;

  U8 *stem = ImageNameStem("edit");
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
