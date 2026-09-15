#ifndef HN_PROVIDERS_PROVIDER
#define HN_PROVIDERS_PROVIDER

/* The provider interface. Nothing below this line knows about MCP or
 * JSON-RPC; nothing above it knows about Google endpoints. */

class ImageRequest
{
  U8 *prompt;
  U8 *model;         /* alias or raw model id */
  U8 *aspect_ratio;  /* optional, e.g. "16:9" */
  U8 *image_size;    /* optional, e.g. "2K" */
  U8 *mime_type;     /* desired output mime, optional */
  U8 *input_b64;     /* edit input, base64; NULL for generation */
  U8 *input_mime;
  U8 *system_prompt;        /* house style; filled in by the prompts layer */
  U8 *system_prompt_source; /* the file it came from, for reporting */
};

ImageRequest *ImageRequestNew()
{
  ImageRequest *r = MAlloc(sizeof(ImageRequest));
  r->prompt = NULL;
  r->model = NULL;
  r->aspect_ratio = NULL;
  r->image_size = NULL;
  r->mime_type = NULL;
  r->input_b64 = NULL;
  r->input_mime = NULL;
  r->system_prompt = NULL;
  r->system_prompt_source = NULL;
  return r;
}

U0 ImageRequestRelease(ImageRequest *r)
{
  if (!r) return;
  if (r->prompt) Free(r->prompt);
  if (r->model) Free(r->model);
  if (r->aspect_ratio) Free(r->aspect_ratio);
  if (r->image_size) Free(r->image_size);
  if (r->mime_type) Free(r->mime_type);
  if (r->input_b64) Free(r->input_b64);
  if (r->input_mime) Free(r->input_mime);
  if (r->system_prompt) Free(r->system_prompt);
  if (r->system_prompt_source) Free(r->system_prompt_source);
  Free(r);
}

class ImageResult
{
  Bool ok;
  I64 error_code;
  U8 *error;
  U8 *mime_type;
  U8 *data_base64;
  I64 width;
  I64 height;
  U8 *model;        /* resolved model id actually used */
  U8 *text;         /* accompanying model text, if any */
  U8 *output_path;  /* filled in by the image layer after saving */
};

ImageResult *ImageResultNew()
{
  ImageResult *r = MAlloc(sizeof(ImageResult));
  r->ok = FALSE;
  r->error_code = HN_OK;
  r->error = NULL;
  r->mime_type = NULL;
  r->data_base64 = NULL;
  r->width = 0;
  r->height = 0;
  r->model = NULL;
  r->text = NULL;
  r->output_path = NULL;
  return r;
}

ImageResult *ImageResultErr(I64 code, U8 *message)
{
  ImageResult *r = ImageResultNew();
  r->error_code = code;
  r->error = StrDup(message);
  return r;
}

U0 ImageResultRelease(ImageResult *r)
{
  if (!r) return;
  if (r->error) Free(r->error);
  if (r->mime_type) Free(r->mime_type);
  if (r->data_base64) Free(r->data_base64);
  if (r->model) Free(r->model);
  if (r->text) Free(r->text);
  if (r->output_path) Free(r->output_path);
  Free(r);
}

class AIProvider;
class AIProvider
{
  U8 *name;
  HnConfig *config;
  ImageResult *(*GenerateImage)(AIProvider *self, ImageRequest *req);
  ImageResult *(*EditImage)(AIProvider *self, ImageRequest *req);
  U8 *(*GetModelInfo)(AIProvider *self);
  HnResult *(*ValidateConfig)(AIProvider *self);
};

AIProvider *ProviderNew(U8 *name, HnConfig *config)
{
  AIProvider *p = MAlloc(sizeof(AIProvider));
  p->name = name;
  p->config = config;
  p->GenerateImage = NULL;
  p->EditImage = NULL;
  p->GetModelInfo = NULL;
  p->ValidateConfig = NULL;
  return p;
}

/* Default model listing - the alias table is provider independent today. */
U8 *ProviderDefaultModelInfo(AIProvider *self)
{
  return ModelsListJson();
}

#endif
