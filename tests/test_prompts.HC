/* System prompt selection: which .md file a call shape maps to, how a file is
 * turned into prompt text, and where it lands in each wire shape.
 *
 * No network and no real provider: the folder is a fixture under /tmp. */

#include "../src/utils/os.HC"
#include "../src/utils/strings.HC"
#include "../src/utils/errors.HC"
#include "../src/utils/logging.HC"
#include "../src/utils/json_util.HC"
#include "../src/utils/args.HC"
#include "../src/http/request.HC"
#include "../src/http/response.HC"
#include "../src/http/client.HC"
#include "../src/auth/credentials.HC"
#include "../src/auth/service_account.HC"
#include "../src/auth/settings.HC"
#include "../src/image/base64.HC"
#include "../src/image/files.HC"
#include "../src/providers/models.HC"
#include "../src/providers/provider.HC"
#include "../src/prompts/system_prompt.HC"
#include "../src/providers/google_common.HC"
#include "../src/providers/gemini.HC"
#include "../src/providers/vertex.HC"
#include "../src/providers/fake.HC"
#include "../src/providers/resolve.HC"
#include "../src/image/generate.HC"
#include "../src/image/edit.HC"
#include "./harness.HC"

#define FIX_DIR "/tmp/holy-nano-mcp-prompts"

U0 WriteFixture(U8 *name, U8 *contents)
{
  U8 *path = StrPrint(NULL, "%s/%s", FIX_DIR, name);
  WriteFdFile(path, contents, StrLen(contents));
  Free(path);
}

/* Each test points the resolver at a folder of its own, so the one-shot cache
 * has to be cleared between them. */
U0 UseDir(U8 *dir)
{
  if (g_sysprompt_dir) Free(g_sysprompt_dir);
  g_sysprompt_dir = NULL;
  if (dir) g_sysprompt_dir = StrDup(dir);
}

HnConfig *PromptCfg(U8 *dir, I64 enabled)
{
  HnConfig *c = CfgNew();
  c->provider_name = StrDup("fake");
  c->output_dir = StrDup(FIX_DIR);
  c->system_prompt_dir = NULL;
  if (dir) c->system_prompt_dir = StrDup(dir);
  c->system_prompts_enabled = enabled;
  return c;
}

U0 TestKindMapping()
{
  TEqStr(SysPromptFileName(SYS_PROMPT_T2I), "text_to_image.md",
         "text to image maps to text_to_image.md");
  TEqStr(SysPromptFileName(SYS_PROMPT_IT2I), "image_and_text_to_image.md",
         "image plus text maps to image_and_text_to_image.md");
  TEqStr(SysPromptKindName(SYS_PROMPT_T2I), "text_to_image",
         "the text to image mode is named");
  TEqStr(SysPromptKindName(SYS_PROMPT_IT2I), "image_and_text_to_image",
         "the image plus text mode is named");
}

U0 TestFrontMatter()
{
  U8 *a = SysPromptStripFrontMatter("---\nmode: t2i\n---\n\nBe brief.\n");
  TEqStr(a, "Be brief.", "front matter is stripped");
  Free(a);

  U8 *b = SysPromptStripFrontMatter("Be brief.\n");
  TEqStr(b, "Be brief.", "a file without front matter is unchanged");
  Free(b);

  /* No closing marker means no front matter - the rule is content. */
  U8 *c = SysPromptStripFrontMatter("---\nstill prose\n");
  TEqStr(c, "---\nstill prose", "an unclosed block is left alone");
  Free(c);

  U8 *d = SysPromptStripFrontMatter("---\nx: 1\n---\n\n\n");
  TEqStr(d, "", "front matter with no body leaves nothing");
  Free(d);

  U8 *e = SysPromptStripFrontMatter("# Heading\n\n- a rule\n");
  TEqStr(e, "# Heading\n\n- a rule", "markdown passes through verbatim");
  Free(e);
}

U0 TestLoading()
{
  MkDir(FIX_DIR, MODE_0700, TRUE);
  WriteFixture("text_to_image.md", "---\nmode: t2i\n---\nRender one image.\n");
  WriteFixture("image_and_text_to_image.md", "Edit locally.\n");

  UseDir(FIX_DIR);
  HnConfig *c = PromptCfg(FIX_DIR, 1);

  U8 *path = NULL;
  U8 *t2i = SysPromptLoad(c, SYS_PROMPT_T2I, &path);
  TEqStr(t2i, "Render one image.", "the text to image prompt loads");
  THas(path, "text_to_image.md", "the source file is reported");
  Free(t2i);
  Free(path);

  U8 *it2i = SysPromptLoad(c, SYS_PROMPT_IT2I, NULL);
  TEqStr(it2i, "Edit locally.", "the image plus text prompt loads");
  Free(it2i);

  /* A file with nothing under the front matter is a supported way to say
   * "send nothing", not an error. */
  WriteFixture("text_to_image.md", "---\nonly notes\n---\n\n");
  U8 *blank = SysPromptLoad(c, SYS_PROMPT_T2I, NULL);
  TCheck(blank == NULL, "a file with no body sends no system prompt");

  UseDir("/tmp/holy-nano-mcp-prompts-absent");
  U8 *missing = SysPromptLoad(c, SYS_PROMPT_T2I, NULL);
  TCheck(missing == NULL, "a missing folder sends no system prompt");
}

U0 TestApply()
{
  MkDir(FIX_DIR, MODE_0700, TRUE);
  WriteFixture("text_to_image.md", "House style: t2i.\n");
  WriteFixture("image_and_text_to_image.md", "House style: it2i.\n");
  UseDir(FIX_DIR);

  HnConfig *on = PromptCfg(FIX_DIR, 1);

  ImageRequest *gen = ImageRequestNew();
  gen->prompt = StrDup("a red bicycle");
  SysPromptApply(on, gen, SYS_PROMPT_T2I);
  TEqStr(gen->system_prompt, "House style: t2i.",
         "generation picks the text to image prompt");

  ImageRequest *ed = ImageRequestNew();
  ed->prompt = StrDup("make it blue");
  SysPromptApply(on, ed, SYS_PROMPT_IT2I);
  TEqStr(ed->system_prompt, "House style: it2i.",
         "editing picks the image plus text prompt");

  /* An instruction already on the request is never replaced. */
  ImageRequest *own = ImageRequestNew();
  own->prompt = StrDup("x");
  own->system_prompt = StrDup("caller supplied");
  SysPromptApply(on, own, SYS_PROMPT_T2I);
  TEqStr(own->system_prompt, "caller supplied", "an existing instruction wins");

  HnConfig *off = PromptCfg(FIX_DIR, 0);
  ImageRequest *none = ImageRequestNew();
  none->prompt = StrDup("x");
  SysPromptApply(off, none, SYS_PROMPT_T2I);
  TCheck(none->system_prompt == NULL, "disabling sends no system prompt");

  ImageRequestRelease(gen);
  ImageRequestRelease(ed);
  ImageRequestRelease(own);
  ImageRequestRelease(none);
}

U0 TestWireShapes()
{
  ImageRequest *req = ImageRequestNew();
  req->prompt = StrDup("a red bicycle");
  req->system_prompt = StrDup("Render one image.");

  U8 *gen = GBuildGenerateBody(req);
  THas(gen, "\"systemInstruction\":{\"parts\":[{\"text\":\"Render one image.\"}]}",
       "generateContent carries it as systemInstruction");
  THas(gen, "\"responseModalities\"", "generationConfig survives beside it");
  Free(gen);

  U8 *inter = GBuildInteractionsBody("gemini-3-pro-image", req);
  THas(inter, "\"input\":[{\"type\":\"text\",\"text\":\"Render one image.\"},",
       "interactions carries it as the leading input block");
  THas(inter, "a red bicycle", "the user prompt still follows it");
  Free(inter);

  /* Without one, neither body should grow a field. */
  ImageRequest *bare = ImageRequestNew();
  bare->prompt = StrDup("a red bicycle");

  U8 *gen2 = GBuildGenerateBody(bare);
  TCheck(!TContains(gen2, "systemInstruction"),
         "no system prompt means no systemInstruction field");
  Free(gen2);

  U8 *inter2 = GBuildInteractionsBody("gemini-3-pro-image", bare);
  THas(inter2, "\"input\":[{\"type\":\"text\",\"text\":\"a red bicycle\"}]",
       "no system prompt means the user prompt leads the input");
  Free(inter2);

  ImageRequestRelease(req);
  ImageRequestRelease(bare);
}

U0 TestConfigParsing()
{
  U8 *doc_src = "{\"system_prompts\":{\"directory\":\"./mine\",\"enabled\":false}}";
  Json *doc = JsonParse(doc_src, StrLen(doc_src));
  HnConfig *c = CfgNew();
  CfgApplyDoc(c, doc);
  TEqStr(c->system_prompt_dir, "./mine", "the folder is read from the config");
  TEqI64(c->system_prompts_enabled, 0, "enabled:false turns them off");
  JsonRelease(doc);

  /* An absent block must leave the field undecided, not off. */
  U8 *empty_src = "{\"provider\":\"fake\"}";
  Json *empty = JsonParse(empty_src, StrLen(empty_src));
  HnConfig *c2 = CfgNew();
  CfgApplyDoc(c2, empty);
  TEqI64(c2->system_prompts_enabled, -1, "no block leaves the default in place");
  TCheck(c2->system_prompt_dir == NULL, "no block leaves the folder unset");
  JsonRelease(empty);
}

U0 TestEndToEnd()
{
  MkDir(FIX_DIR, MODE_0700, TRUE);
  WriteFixture("text_to_image.md", "House style: t2i.\n");
  WriteFixture("image_and_text_to_image.md", "House style: it2i.\n");
  UseDir(FIX_DIR);

  HnConfig *c = PromptCfg(FIX_DIR, 1);
  AIProvider *p = FakeProviderNew(c);

  ImageRequest *req = ImageRequestNew();
  req->prompt = StrDup("a red bicycle");
  U8 *out = StrPrint(NULL, "%s/out.png", FIX_DIR);
  ImageResult *r = ImageGenerate(p, c, req, out);
  TCheck(r->ok, "the fake pipeline still succeeds");
  TEqStr(req->system_prompt, "House style: t2i.",
         "ImageGenerate applies the prompt without being asked");
  THas(req->system_prompt_source, "text_to_image.md",
       "the request records which file was used");
  ImageResultRelease(r);
  ImageRequestRelease(req);

  ImageRequest *ereq = ImageRequestNew();
  ereq->prompt = StrDup("make it blue");
  U8 *edited = StrPrint(NULL, "%s/edited.png", FIX_DIR);
  ImageResult *er = ImageEdit(p, c, ereq, out, edited);
  TCheck(er->ok, "the fake edit pipeline still succeeds");
  TEqStr(ereq->system_prompt, "House style: it2i.",
         "ImageEdit applies the image plus text prompt");
  ImageResultRelease(er);
  ImageRequestRelease(ereq);
  Free(out);
  Free(edited);
}

I64 Main()
{
  TBanner("test_prompts");
  ModelsInit();
  TestKindMapping();
  TestFrontMatter();
  TestLoading();
  TestApply();
  TestWireShapes();
  TestConfigParsing();
  TestEndToEnd();
  exit(TSummary("test_prompts"));
  return 0;
}

Main;
