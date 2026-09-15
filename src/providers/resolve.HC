#ifndef HN_PROVIDERS_RESOLVE
#define HN_PROVIDERS_RESOLVE

/* Provider selection. Adding a provider means adding one branch here and one
 * file next to gemini.HC - no MCP-layer changes. */

AIProvider *ProviderResolve(HnConfig *c)
{
  U8 *name = c->provider_name;
  if (StrEq(name, "vertex")) return VertexProviderNew(c);
  if (StrEq(name, "fake"))   return FakeProviderNew(c);
  if (StrEq(name, "gemini")) return GeminiProviderNew(c);
  LogWarn("unknown provider '%s', falling back to gemini", name);
  return GeminiProviderNew(c);
}

U8 *ProviderNamesJson()
{
  return "[\"gemini\",\"vertex\",\"fake\"]";
}

#endif
