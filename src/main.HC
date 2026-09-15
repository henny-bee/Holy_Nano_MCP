/* Holy Nano MCP - an MCP server in HolyC for Google's Nano Banana image models.
 *
 * hcc compiles one translation unit, so this file is the whole build: the
 * include order below is the dependency order.
 *
 *   utils      -> no dependencies
 *   http       -> utils
 *   auth       -> utils
 *   image      -> utils
 *   providers  -> auth, http, image
 *   mcp        -> providers, image
 */

#include "./utils/os.HC"
#include "./utils/strings.HC"
#include "./utils/errors.HC"
#include "./utils/logging.HC"
#include "./utils/json_util.HC"
#include "./utils/args.HC"

#include "./http/request.HC"
#include "./http/response.HC"
#include "./http/client.HC"

#include "./auth/credentials.HC"
#include "./auth/service_account.HC"
#include "./auth/settings.HC"

#include "./image/base64.HC"
#include "./image/files.HC"

#include "./providers/models.HC"
#include "./providers/provider.HC"
#include "./providers/google_common.HC"
#include "./providers/gemini.HC"
#include "./providers/vertex.HC"
#include "./providers/fake.HC"
#include "./providers/resolve.HC"

#include "./image/generate.HC"
#include "./image/edit.HC"

#include "./mcp/jsonrpc.HC"
#include "./mcp/tools.HC"
#include "./mcp/tool_impl.HC"
#include "./mcp/protocol.HC"
#include "./mcp/server.HC"

U8 *USAGE =
  "holy-nano-mcp - MCP server for Google Nano Banana image models\n"
  "\n"
  "Usage: holy-nano-mcp [options]\n"
  "\n"
  "Speaks JSON-RPC over stdio. Run it from an MCP client, not by hand.\n"
  "\n"
  "Options:\n"
  "  --config <path>             Config file (default: $HOLY_NANO_MCP_CONFIG,\n"
  "                              then ~/.config/holy-nano-mcp/config.json)\n"
  "  --service-account <path>    Repo-local credential file (default ./service-account.json)\n"
  "  --provider <name>           gemini | vertex | fake\n"
  "  --model <alias|id>          Default model (default nano-banana-2)\n"
  "  --output-dir <path>         Where images are written (default ./generated)\n"
  "  --overwrite                 Replace existing files instead of suffixing\n"
  "  --project-id <id>           Vertex project\n"
  "  --location <region>         Vertex location (default global)\n"
  "  --api-style <style>         interactions | generate_content\n"
  "  --api-version <v>           Gemini API version (default v1beta)\n"
  "  --endpoint <url>            Override the API host\n"
  "  --credentials-source <s>    auto | mcp | repo | env\n"
  "  --log-level <level>         debug | info | warn | error | off\n"
  "  --status                    Print provider status and exit\n"
  "  --help                      Print this message\n"
  "\n"
  "API keys are never accepted as command-line arguments: argv is readable by\n"
  "any process on the machine. Use a config file or an environment variable.\n";

U0 PrintUsage()
{
  write(FD_STDOUT, USAGE, StrLen(USAGE));
}

U0 PrintStatus()
{
  Bool is_error = FALSE;
  U8 *status = ToolProviderStatus(NULL, &is_error);
  write(FD_STDOUT, status, StrLen(status));
  Free(status);
}

I64 Main()
{
  ArgsLoad();
  McpVersionsInit();
  ModelsInit();

  if (ArgFlag("help") || ArgFlag("h")) {
    PrintUsage();
    return 0;
  }

  g_config = CfgLoad();
  g_provider = ProviderResolve(g_config);
  ToolsRegisterAll();

  LogInfo("provider=%s model=%s output=%s",
          g_config->provider_name, g_config->default_model, g_config->output_dir);
  if (!CfgHasCredential(g_config)) {
    LogWarn("no credential resolved yet - tools will report this until one is configured");
  }

  if (ArgFlag("status")) {
    PrintStatus();
    return 0;
  }

  return ServerRun();
}

Main;
