#ifndef HN_PROVIDERS_MODELS
#define HN_PROVIDERS_MODELS

/* Model aliases live here rather than in the provider code so they can be
 * updated without touching request building.
 *
 * Verified against Google's Nano Banana documentation on 2026-09-14. */

class ModelAlias
{
  U8 *alias;
  U8 *model_id;
  U8 *label;
  U8 *notes;
  ModelAlias *next;
};

ModelAlias *g_models = NULL;
ModelAlias *g_models_tail = NULL;

U0 ModelRegister(U8 *alias, U8 *model_id, U8 *label, U8 *notes)
{
  ModelAlias *m = MAlloc(sizeof(ModelAlias));
  m->alias = alias;
  m->model_id = model_id;
  m->label = label;
  m->notes = notes;
  m->next = NULL;
  if (g_models_tail) g_models_tail->next = m;
  else g_models = m;
  g_models_tail = m;
}

U0 ModelsInit()
{
  if (g_models) return;
  ModelRegister("nano-banana-2", "gemini-3.1-flash-image",
    "Nano Banana 2",
    "Generalist image model. Balances speed with 4K generation and text rendering.");
  ModelRegister("nano-banana-2-lite", "gemini-3.1-flash-lite-image",
    "Nano Banana 2 Lite",
    "Fastest and cheapest. Not tuned for multi-reference or sequential editing.");
  ModelRegister("nano-banana-pro", "gemini-3-pro-image",
    "Nano Banana Pro",
    "Highest world knowledge, brand consistency and creative control.");
  ModelRegister("nano-banana", "gemini-2.5-flash-image",
    "Nano Banana (legacy)",
    "The original. Superseded by Nano Banana 2 Lite.");
}

/* Maps an alias to a Google model id. An unrecognised name is passed through
 * unchanged, so new models work before this table is updated. */
U8 *ModelResolve(U8 *name)
{
  ModelsInit();
  if (!name) return "gemini-3.1-flash-image";
  ModelAlias *m = g_models;
  while (m) {
    if (StrEq(m->alias, name)) return m->model_id;
    m = m->next;
  }
  return name;
}

Bool ModelIsAlias(U8 *name)
{
  ModelsInit();
  ModelAlias *m = g_models;
  while (m) {
    if (StrEq(m->alias, name)) return TRUE;
    m = m->next;
  }
  return FALSE;
}

U8 *ModelsListJson()
{
  ModelsInit();
  StrBuf *sb = SbNew(1024);
  SbCat(sb, "[");
  ModelAlias *m = g_models;
  Bool first = TRUE;
  while (m) {
    if (!first) SbCatCh(sb, ',');
    first = FALSE;
    SbCat(sb, "{\"alias\":");      SbCatJson(sb, m->alias);
    SbCat(sb, ",\"model_id\":");   SbCatJson(sb, m->model_id);
    SbCat(sb, ",\"label\":");      SbCatJson(sb, m->label);
    SbCat(sb, ",\"notes\":");      SbCatJson(sb, m->notes);
    SbCatCh(sb, '}');
    m = m->next;
  }
  SbCat(sb, "]");
  return SbSteal(sb);
}

#endif
