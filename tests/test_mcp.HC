/* JSON-RPC framing, MCP dispatch and the tool registry. */

#include "../src/utils/os.HC"
#include "../src/utils/strings.HC"
#include "../src/utils/errors.HC"
#include "../src/utils/logging.HC"
#include "../src/utils/json_util.HC"
#include "../src/mcp/jsonrpc.HC"
#include "../src/mcp/tools.HC"
#include "../src/mcp/protocol.HC"
#include "./harness.HC"

RpcRequest *RpcParseStr(U8 *line)
{
  return RpcParse(line, StrLen(line));
}

U8 *StubTool(Json *args, Bool *is_error)
{
  U8 *mode = JStr(args, "mode", "ok");
  if (StrEq(mode, "fail")) {
    *is_error = TRUE;
    return StrDup("stub failed");
  }
  return StrPrint(NULL, "stub ran with mode=%s", mode);
}

/* Parses `line`, dispatches it, and returns the response (or NULL). */
U8 *Roundtrip(U8 *line)
{
  RpcRequest *req = RpcParse(line, StrLen(line));
  U8 *resp = McpDispatch(req);
  RpcRequestRelease(req);
  return resp;
}

U0 TestParse()
{
  RpcRequest *r = RpcParseStr("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}");
  TCheck(r->ok, "parses a well formed request");
  TEqStr(r->method, "ping", "reads the method");
  TCheck(!RpcIsNotification(r), "a request with an id is not a notification");
  RpcRequestRelease(r);

  r = RpcParseStr("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
  TCheck(r->ok, "parses a notification");
  TCheck(RpcIsNotification(r), "a request without an id is a notification");
  RpcRequestRelease(r);

  r = RpcParseStr("this is not json");
  TCheck(!r->ok, "rejects non-JSON");
  TCheck(r->doc == NULL, "non-JSON produces no document");
  RpcRequestRelease(r);

  r = RpcParseStr("{\"jsonrpc\":\"2.0\",\"id\":1}");
  TCheck(!r->ok, "rejects a request with no method");
  RpcRequestRelease(r);
}

U0 TestIdEcho()
{
  U8 *resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}");
  THas(resp, "\"id\":7", "echoes a numeric id");
  Free(resp);

  resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":\"abc-1\",\"method\":\"ping\"}");
  THas(resp, "\"id\":\"abc-1\"", "echoes a string id");
  Free(resp);
}

U0 TestInitialize()
{
  U8 *resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}");
  THas(resp, "\"protocolVersion\":\"2025-06-18\"", "echoes a supported protocol version");
  THas(resp, "\"holy-nano-mcp\"", "reports the server name");
  THas(resp, "\"tools\"", "advertises the tools capability");
  Free(resp);

  resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"1999-01-01\"}}");
  THas(resp, "\"protocolVersion\":\"2025-06-18\"", "falls back for an unknown protocol version");
  Free(resp);

  resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}");
  THas(resp, "\"protocolVersion\"", "initialize works without params");
  Free(resp);
}

U0 TestToolsList()
{
  U8 *resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}");
  THas(resp, "\"name\":\"stub\"", "lists the registered tool");
  THas(resp, "\"inputSchema\"", "includes an input schema");
  THas(resp, "\"description\":\"A stub.\"", "includes the description");
  Free(resp);
}

U0 TestToolsCall()
{
  U8 *resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"stub\",\"arguments\":{\"mode\":\"ok\"}}}");
  THas(resp, "stub ran with mode=ok", "runs a tool and returns its text");
  THas(resp, "\"isError\":false", "marks a successful call");
  Free(resp);

  resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"stub\",\"arguments\":{\"mode\":\"fail\"}}}");
  THas(resp, "\"isError\":true", "reports a tool failure inside the result");
  THas(resp, "\"result\"", "a tool failure is not a JSON-RPC error");
  Free(resp);

  resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"stub\"}}");
  THas(resp, "stub ran with mode=ok", "missing arguments object is tolerated");
  Free(resp);

  resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"nope\"}}");
  THas(resp, "-32602", "unknown tool is an invalid params error");
  Free(resp);

  resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\"}");
  THas(resp, "-32602", "tools/call without params is an invalid params error");
  Free(resp);
}

U0 TestErrors()
{
  U8 *resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"does/not/exist\"}");
  THas(resp, "-32601", "unknown method returns method not found");
  Free(resp);

  resp = Roundtrip("not json at all");
  TCheck(resp != NULL, "unparseable input still gets a response");
  THas(resp, "-32700", "unparseable input returns a parse error");
  THas(resp, "\"id\":null", "a parse error carries a null id");
  Free(resp);

  resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
  TCheck(resp == NULL, "notifications get no response");

  resp = Roundtrip("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{}}");
  TCheck(resp == NULL, "unknown notifications get no response");
}

U0 TestEscapingInResults()
{
  /* A tool returning quotes must not be able to break the frame. */
  U8 *resp = Roundtrip(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"stub\",\"arguments\":{\"mode\":\"a\\\"b\"}}}");
  Json *doc = JsonParse(resp, StrLen(resp));
  TCheck(doc != NULL, "a result containing quotes is still valid JSON");
  if (doc) JsonRelease(doc);
  Free(resp);
}

I64 Main()
{
  TBanner("test_mcp");
  McpVersionsInit();
  ToolRegister("stub", "Stub", "A stub.",
    "{\"type\":\"object\",\"properties\":{\"mode\":{\"type\":\"string\"}}}", &StubTool);

  TestParse();
  TestIdEcho();
  TestInitialize();
  TestToolsList();
  TestToolsCall();
  TestErrors();
  TestEscapingInResults();
  exit(TSummary("test_mcp"));
  return 0;
}

Main;
