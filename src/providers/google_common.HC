#ifndef HN_PROVIDERS_GOOGLE_COMMON
#define HN_PROVIDERS_GOOGLE_COMMON

/* Request bodies and response parsing shared by the Gemini and Vertex
 * providers. Two wire shapes are supported:
 *
 *   interactions      POST {base}/{version}/interactions
 *   generate_content  POST {base}/{version}/.../models/{model}:generateContent
 *
 * The Interactions API is the current Gemini surface; generateContent remains
 * supported and is what Vertex AI exposes. */

#define API_STYLE_INTERACTIONS 0
#define API_STYLE_GENERATE     1

I64 ApiStyleFromName(U8 *name)
{
  if (StrEq(name, "generate_content")) return API_STYLE_GENERATE;
  if (StrEq(name, "generatecontent")) return API_STYLE_GENERATE;
  return API_STYLE_INTERACTIONS;
}

U8 *ApiStyleName(I64 style)
{
  if (style == API_STYLE_GENERATE) return "generate_content";
  return "interactions";
}

/* --- request bodies ------------------------------------------------------ */

U8 *GBuildInteractionsBody(U8 *model_id, ImageRequest *req)
{
  StrBuf *sb = SbNew(1024);
  SbCat(sb, "{\"model\":");
  SbCatJson(sb, model_id);
  SbCat(sb, ",\"input\":[");

  /* The Interactions surface has no separate system field, so the house style
   * leads the input as its own text block - which is what the model reads
   * first either way. */
  if (req->system_prompt != NULL && req->system_prompt[0] != 0) {
    SbCat(sb, "{\"type\":\"text\",\"text\":");
    SbCatJson(sb, req->system_prompt);
    SbCat(sb, "},");
  }

  if (req->input_b64 != NULL) {
    SbCat(sb, "{\"type\":\"image\",\"mime_type\":");
    U8 *mime = req->input_mime;
    if (!mime) mime = "image/png";
    SbCatJson(sb, mime);
    SbCat(sb, ",\"data\":");
    SbCatJson(sb, req->input_b64);
    SbCat(sb, "},");
  }

  SbCat(sb, "{\"type\":\"text\",\"text\":");
  SbCatJson(sb, req->prompt);
  SbCat(sb, "}]");

  SbCat(sb, ",\"response_format\":{\"type\":\"image\"");
  if (req->mime_type) {
    SbCat(sb, ",\"mime_type\":");
    SbCatJson(sb, req->mime_type);
  }
  if (req->aspect_ratio) {
    SbCat(sb, ",\"aspect_ratio\":");
    SbCatJson(sb, req->aspect_ratio);
  }
  if (req->image_size) {
    SbCat(sb, ",\"image_size\":");
    SbCatJson(sb, req->image_size);
  }
  SbCat(sb, "}}");
  return SbSteal(sb);
}

U8 *GBuildGenerateBody(ImageRequest *req)
{
  StrBuf *sb = SbNew(1024);
  SbCat(sb, "{\"contents\":[{\"role\":\"user\",\"parts\":[");

  if (req->input_b64 != NULL) {
    SbCat(sb, "{\"inlineData\":{\"mimeType\":");
    U8 *mime = req->input_mime;
    if (!mime) mime = "image/png";
    SbCatJson(sb, mime);
    SbCat(sb, ",\"data\":");
    SbCatJson(sb, req->input_b64);
    SbCat(sb, "}},");
  }

  SbCat(sb, "{\"text\":");
  SbCatJson(sb, req->prompt);
  SbCat(sb, "}]}]");

  if (req->system_prompt != NULL && req->system_prompt[0] != 0) {
    SbCat(sb, ",\"systemInstruction\":{\"parts\":[{\"text\":");
    SbCatJson(sb, req->system_prompt);
    SbCat(sb, "}]}");
  }

  SbCat(sb, ",\"generationConfig\":{\"responseModalities\":[\"IMAGE\"]");

  Bool has_image_config = FALSE;
  if (req->aspect_ratio != NULL || req->image_size != NULL || req->mime_type != NULL) {
    has_image_config = TRUE;
    SbCat(sb, ",\"imageConfig\":{");
    Bool first = TRUE;
    if (req->aspect_ratio) {
      SbCat(sb, "\"aspectRatio\":");
      SbCatJson(sb, req->aspect_ratio);
      first = FALSE;
    }
    if (req->image_size) {
      if (!first) SbCatCh(sb, ',');
      SbCat(sb, "\"imageSize\":");
      SbCatJson(sb, req->image_size);
      first = FALSE;
    }
    if (req->mime_type) {
      if (!first) SbCatCh(sb, ',');
      SbCat(sb, "\"mimeType\":");
      SbCatJson(sb, req->mime_type);
    }
    SbCatCh(sb, '}');
  }
  SbCat(sb, "}}");
  return SbSteal(sb);
}

/* --- response parsing ---------------------------------------------------- */

/* Pulls the first image block out of an Interactions `steps` timeline.
 * Returns TRUE when an image was found. */
Bool GScanInteractionSteps(Json *doc, ImageResult *out)
{
  Json *steps = JArrField(doc, "steps");
  if (!steps) return FALSE;

  Bool found = FALSE;
  StrBuf *text = SbNew(128);

  Json *step = JArrFirst(steps);
  while (step) {
    U8 *step_type = JStr(step, "type", "");
    if (!StrEq(step_type, "user_input")) {
      Json *content = JArrField(step, "content");
      Json *block = JArrFirst(content);
      while (block) {
        U8 *btype = JStr(block, "type", "");
        if (StrEq(btype, "image") && !found) {
          U8 *data = JStr(block, "data", NULL);
          if (data) {
            out->data_base64 = StrDup(data);
            U8 *mime = JStr(block, "mime_type", NULL);
            if (!mime) mime = JStr(block, "mimeType", "image/png");
            out->mime_type = StrDup(mime);
            found = TRUE;
          }
        } else if (StrEq(btype, "text")) {
          U8 *t = JStr(block, "text", NULL);
          if (t) {
            if (text->len > 0) SbCatCh(text, '\n');
            SbCat(text, t);
          }
        }
        block = block->next;
      }
    }
    step = step->next;
  }

  if (text->len > 0) out->text = StrDup(text->buf);
  SbRelease(text);
  return found;
}

/* Pulls the first inline image out of a generateContent response. */
Bool GScanCandidates(Json *doc, ImageResult *out)
{
  Json *candidates = JArrField(doc, "candidates");
  if (!candidates) return FALSE;

  Bool found = FALSE;
  StrBuf *text = SbNew(128);

  Json *cand = JArrFirst(candidates);
  while (cand) {
    Json *content = JObjField(cand, "content");
    Json *parts = JArrField(content, "parts");
    Json *part = JArrFirst(parts);
    while (part) {
      Json *inline_data = JObjField(part, "inlineData");
      if (!inline_data) inline_data = JObjField(part, "inline_data");
      if (inline_data != NULL && !found) {
        U8 *data = JStr(inline_data, "data", NULL);
        if (data) {
          out->data_base64 = StrDup(data);
          U8 *mime = JStr(inline_data, "mimeType", NULL);
          if (!mime) mime = JStr(inline_data, "mime_type", "image/png");
          out->mime_type = StrDup(mime);
          found = TRUE;
        }
      }
      U8 *t = JStr(part, "text", NULL);
      if (t) {
        if (text->len > 0) SbCatCh(text, '\n');
        SbCat(text, t);
      }
      part = part->next;
    }
    cand = cand->next;
  }

  if (text->len > 0) out->text = StrDup(text->buf);
  SbRelease(text);
  return found;
}

/* Renders a Google API error payload into a single line, or NULL when the
 * body does not carry one. */
U8 *GExtractApiError(Json *doc)
{
  Json *err = JObjField(doc, "error");
  if (!err) return NULL;
  U8 *message = JStr(err, "message", "no message");
  U8 *status = JStr(err, "status", NULL);
  I64 code = JInt(err, "code", 0);
  if (status) return StrPrint(NULL, "%s (%s, code %d)", message, status, code);
  return StrPrint(NULL, "%s (code %d)", message, code);
}

/* Turns an HTTP response into an ImageResult, whichever wire shape it uses. */
ImageResult *GParseImageResponse(HttpResponse *res, U8 *model_id)
{
  if (res->error) return ImageResultErr(HN_ERR_HTTP, res->error);

  Json *doc = NULL;
  if (res->body != NULL && res->body_len > 0) doc = JsonParse(res->body, res->body_len);
  if (doc != NULL && !JsonOk(doc)) { JsonRelease(doc); doc = NULL; }

  if (!HttpIsOk(res)) {
    U8 *detail = NULL;
    if (doc) detail = GExtractApiError(doc);
    if (!detail) detail = StrPrint(NULL, "HTTP %d", res->status);
    U8 *msg = StrPrint(NULL, "%s: %s", model_id, detail);
    Free(detail);
    if (doc) JsonRelease(doc);
    ImageResult *bad = ImageResultErr(HN_ERR_API, msg);
    Free(msg);
    return bad;
  }

  if (!doc) return ImageResultErr(HN_ERR_DECODE, "response was not valid JSON");

  ImageResult *out = ImageResultNew();
  out->model = StrDup(model_id);

  Bool found = GScanInteractionSteps(doc, out);
  if (!found) found = GScanCandidates(doc, out);

  if (!found) {
    U8 *detail = GExtractApiError(doc);
    if (!detail) {
      if (out->text != NULL && out->text[0] != 0) {
        detail = StrPrint(NULL, "model returned text instead of an image: %s", out->text);
      } else {
        detail = StrDup("response contained no image data");
      }
    }
    out->error_code = HN_ERR_API;
    out->error = detail;
    JsonRelease(doc);
    return out;
  }

  out->ok = TRUE;
  JsonRelease(doc);
  return out;
}

#endif
