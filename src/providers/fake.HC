#ifndef HN_PROVIDERS_FAKE
#define HN_PROVIDERS_FAKE

/* Offline provider. Returns a real 16x16 PNG so the whole pipeline - decode,
 * path resolution, file write, MCP result - can be exercised without network
 * access or credentials. */

U8 *g_fake_png_b64 =
  "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAABlklEQVR42hXRURVEIQhFUSMYgQhGMAIRiGCEE8EIRiACEYhABCLMG7/ZrMt1jMEcyGAN9kAHNjgDBnfwBj6IQQ5q0IMxJnMikzXZE53Y5EyY3Mmb+CQmOalJzw8IUxBhCVtQwYQjIFzhCS6EkEIJLR9YzIUs1mIvdGGLs2BxF2/hi1jkoha9PrCZG9mszd7oxjZnw+Zu3sY3sclNbXp/QJmKKEvZiiqmHAXlKk9xJZRUSmn9gDENMZaxDTXMOAbGNZ7hRhhplNH2gcM8yGEd9kEPdjgHDvfwDn6IQx7q0OcD/wK/Sr4jv9hfkG/1N/x/Fx44BCQU9Pc94zIvclmXfdGLXc79j9/Lu/glLnmpS98PPOZDHuuxH/qwx3n/5ffxHv6IRz7q0e8DznTEWc521DHn+D/KdZ7jTjjplNP+gWAGEqxgBxpYcOIf/AYv8CCCDCro+EAyE0lWshNNLDn5P/MmL/Ekkkwq6fxAMQspVrELLaw49S/lFq/wIoosquj6QDMbaVazG22sOf2v8Dav8SaabKrp5geIAnAQC3NfwAAAAABJRU5ErkJggg==";

HnResult *FakeValidate(AIProvider *self)
{
  return ResOk();
}

ImageResult *FakeGenerate(AIProvider *self, ImageRequest *req)
{
  if (req->prompt == NULL || req->prompt[0] == 0) {
    return ImageResultErr(HN_ERR_ARGS, "prompt is required");
  }
  ImageResult *r = ImageResultNew();
  r->ok = TRUE;
  r->mime_type = StrDup("image/png");
  r->data_base64 = StrDup(g_fake_png_b64);
  r->model = StrDup(ModelResolve(req->model));
  r->text = StrPrint(NULL, "fake provider echoed prompt: %s", req->prompt);
  return r;
}

ImageResult *FakeEdit(AIProvider *self, ImageRequest *req)
{
  if (req->input_b64 == NULL) {
    return ImageResultErr(HN_ERR_ARGS, "edit_image requires an input image");
  }
  return FakeGenerate(self, req);
}

AIProvider *FakeProviderNew(HnConfig *c)
{
  AIProvider *p = ProviderNew("fake", c);
  p->GenerateImage = &FakeGenerate;
  p->EditImage = &FakeEdit;
  p->GetModelInfo = &ProviderDefaultModelInfo;
  p->ValidateConfig = &FakeValidate;
  return p;
}

#endif
