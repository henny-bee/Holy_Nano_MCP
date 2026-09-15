#ifndef HN_MCP_TOOLS
#define HN_MCP_TOOLS

/* Tool registry. A tool handler receives the raw `arguments` object and
 * returns heap-allocated text; set `*is_error` for a tool-level failure
 * (which is reported inside the result, not as a JSON-RPC error). */

class McpTool
{
  U8 *name;
  U8 *title;
  U8 *description;
  U8 *schema; /* serialised JSON Schema for `inputSchema` */
  U8 *(*run)(Json *args, Bool *is_error);
  McpTool *next;
};

McpTool *g_tools = NULL;
McpTool *g_tools_tail = NULL;

U0 ToolRegister(U8 *name, U8 *title, U8 *description, U8 *schema,
                U8 *(*run)(Json *args, Bool *is_error))
{
  McpTool *t = MAlloc(sizeof(McpTool));
  t->name = name;
  t->title = title;
  t->description = description;
  t->schema = schema;
  t->run = run;
  t->next = NULL;
  if (g_tools_tail) g_tools_tail->next = t;
  else g_tools = t;
  g_tools_tail = t;
}

McpTool *ToolFind(U8 *name)
{
  McpTool *t = g_tools;
  while (t) {
    if (StrEq(t->name, name)) return t;
    t = t->next;
  }
  return NULL;
}

/* `{"tools":[...]}` for tools/list. */
U8 *ToolsListJson()
{
  StrBuf *sb = SbNew(4096);
  SbCat(sb, "{\"tools\":[");
  McpTool *t = g_tools;
  Bool first = TRUE;
  while (t) {
    if (!first) SbCatCh(sb, ',');
    first = FALSE;
    SbCat(sb, "{\"name\":");
    SbCatJson(sb, t->name);
    SbCat(sb, ",\"title\":");
    SbCatJson(sb, t->title);
    SbCat(sb, ",\"description\":");
    SbCatJson(sb, t->description);
    SbCat(sb, ",\"inputSchema\":");
    SbCat(sb, t->schema);
    SbCatCh(sb, '}');
    t = t->next;
  }
  SbCat(sb, "]}");
  return SbSteal(sb);
}

/* Wraps tool output in the MCP CallToolResult shape. */
U8 *ToolResultJson(U8 *text, Bool is_error)
{
  StrBuf *sb = SbNew(1024);
  SbCat(sb, "{\"content\":[{\"type\":\"text\",\"text\":");
  SbCatJson(sb, text);
  SbCat(sb, "}],\"isError\":");
  if (is_error) SbCat(sb, "true");
  else SbCat(sb, "false");
  SbCatCh(sb, '}');
  return SbSteal(sb);
}

#endif
