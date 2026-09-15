#ifndef HN_MCP_PROTOCOL
#define HN_MCP_PROTOCOL

#define MCP_SERVER_NAME    "holy-nano-mcp"
#define MCP_SERVER_TITLE   "Holy Nano MCP"
#define MCP_SERVER_VERSION "1.0.0"

/* Newest first. An `initialize` asking for one of these gets it echoed back;
 * anything else is answered with the first entry, per the MCP spec. */
U8 *g_mcp_versions[4];
I64 g_mcp_version_count = 4;

U0 McpVersionsInit()
{
  g_mcp_versions[0] = "2025-06-18";
  g_mcp_versions[1] = "2025-03-26";
  g_mcp_versions[2] = "2024-11-05";
  g_mcp_versions[3] = "2024-10-07";
}

Bool g_mcp_initialized = FALSE;

U8 *McpNegotiateVersion(U8 *requested)
{
  if (requested) {
    I64 i = 0;
    while (i < g_mcp_version_count) {
      if (StrEq(g_mcp_versions[i], requested)) return g_mcp_versions[i];
      i++;
    }
  }
  return g_mcp_versions[0];
}

U8 *McpInitializeResult(Json *params)
{
  U8 *requested = NULL;
  if (params) requested = JStr(params, "protocolVersion", NULL);
  U8 *version = McpNegotiateVersion(requested);

  StrBuf *sb = SbNew(512);
  SbCat(sb, "{\"protocolVersion\":");
  SbCatJson(sb, version);
  SbCat(sb, ",\"capabilities\":{\"tools\":{\"listChanged\":false}}");
  SbCat(sb, ",\"serverInfo\":{\"name\":");
  SbCatJson(sb, MCP_SERVER_NAME);
  SbCat(sb, ",\"title\":");
  SbCatJson(sb, MCP_SERVER_TITLE);
  SbCat(sb, ",\"version\":");
  SbCatJson(sb, MCP_SERVER_VERSION);
  SbCat(sb, "}}");
  return SbSteal(sb);
}

/* Runs a tools/call. Returns a serialised JSON-RPC response, or NULL when the
 * call should produce a protocol-level error instead (out param carries it). */
U8 *McpCallTool(Json *id, Json *params)
{
  if (!params) return RpcError(id, RPC_INVALID_PARAMS, "params required");
  U8 *name = JStr(params, "name", NULL);
  if (!name) return RpcError(id, RPC_INVALID_PARAMS, "params.name required");

  McpTool *tool = ToolFind(name);
  if (!tool) {
    U8 *m = StrPrint(NULL, "unknown tool: %s", name);
    U8 *resp = RpcError(id, RPC_INVALID_PARAMS, m);
    Free(m);
    return resp;
  }

  Json *args = JObjField(params, "arguments");
  Bool is_error = FALSE;
  U8 *text = tool->run(args, &is_error);
  if (!text) text = StrDup("tool returned no output");

  U8 *result = ToolResultJson(text, is_error);
  U8 *resp = RpcResult(id, result);
  Free(result);
  Free(text);
  return resp;
}

/* Dispatches one parsed request. Returns a response string to write, or NULL
 * when nothing should be sent (notifications). */
U8 *McpDispatch(RpcRequest *req)
{
  if (!req->ok) {
    /* A line that is not JSON at all has no id to answer with, but JSON-RPC
     * still wants a parse error rather than silence. */
    if (req->doc == NULL) return RpcError(NULL, RPC_PARSE_ERROR, req->parse_error);
    return RpcError(req->id, RPC_INVALID_REQUEST, req->parse_error);
  }

  U8 *m = req->method;

  if (StrEq(m, "initialize")) {
    U8 *result = McpInitializeResult(req->params);
    U8 *resp = RpcResult(req->id, result);
    Free(result);
    return resp;
  }

  if (StrEq(m, "notifications/initialized")) {
    g_mcp_initialized = TRUE;
    LogInfo("client initialized");
    return NULL;
  }

  if (StrStarts(m, "notifications/")) return NULL;

  if (StrEq(m, "ping")) return RpcResult(req->id, "{}");

  if (StrEq(m, "tools/list")) {
    U8 *result = ToolsListJson();
    U8 *resp = RpcResult(req->id, result);
    Free(result);
    return resp;
  }

  if (StrEq(m, "tools/call")) return McpCallTool(req->id, req->params);

  /* Optional MCP surfaces we deliberately do not implement. */
  if (StrEq(m, "resources/list"))  return RpcResult(req->id, "{\"resources\":[]}");
  if (StrEq(m, "prompts/list"))    return RpcResult(req->id, "{\"prompts\":[]}");

  if (RpcIsNotification(req)) return NULL;

  U8 *msg = StrPrint(NULL, "method not found: %s", m);
  U8 *resp = RpcError(req->id, RPC_METHOD_NOT_FOUND, msg);
  Free(msg);
  return resp;
}

#endif
