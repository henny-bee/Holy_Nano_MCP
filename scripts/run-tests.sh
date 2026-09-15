#!/usr/bin/env bash
# Builds and runs the whole suite: HolyC unit tests, then stdio integration
# tests against a mock Google API (tests/mock_google.py).
#
# Run inside Linux/WSL2. See docs/PHASE0.md.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="$ROOT/build/holy-nano-mcp"
PORT="${MOCK_PORT:-8787}"
FAILED=0

note() { printf '\n== %s\n' "$1"; }
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

command -v hcc >/dev/null 2>&1 || { echo "hcc not found - see docs/PHASE0.md" >&2; exit 1; }
mkdir -p build generated
rm -rf /tmp/holy-nano-mcp-fixtures /tmp/holy-nano-mcp-http-* /tmp/holy-nano-mcp-sh-*

note "build"
if ! hcc src/main.HC -o "$BIN" >build/build.log 2>&1; then
  grep -v WARNING build/build.log | tail -20
  echo "build failed" >&2
  exit 1
fi
pass "server builds"

note "unit tests"
for t in test_json test_mcp test_auth test_provider test_prompts; do
  if ! hcc "tests/$t.HC" -o "build/$t" >"build/$t.log" 2>&1; then
    grep -v WARNING "build/$t.log" | tail -20
    fail "$t compiles"
    continue
  fi
  if "./build/$t" 2>/dev/null | tail -1; then :; fi
  check "${PIPESTATUS[0]}" "$t"
done

# --- integration ------------------------------------------------------------

rm -f /tmp/mock_requests.jsonl
python3 tests/mock_google.py "$PORT" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null' EXIT
sleep 1

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}'
FAKE_KEY="AIzaSyINTEGRATIONTESTKEY00001"

# Runs a session and echoes the last response line.
session() {
  local call="$1"; shift
  printf '%s\n%s\n' "$INIT" "$call" \
    | GEMINI_API_KEY="$FAKE_KEY" "$BIN" "$@" 2>/dev/null | tail -1
}

note "stdio protocol"
OUT=$(printf '%s\n' "$INIT" | "$BIN" --provider fake 2>/dev/null | tail -1)
contains "$OUT" '"protocolVersion"'; check $? "initialize over stdio"

OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' --provider fake)
contains "$OUT" '"generate_image"'; check $? "tools/list advertises generate_image"
contains "$OUT" '"security_check"'; check $? "tools/list advertises security_check"

# Every response line must be exactly one JSON object.
OUT=$(printf '%s\n%s\n%s\n' "$INIT" '{"jsonrpc":"2.0","id":2,"method":"ping"}' 'garbage' \
  | "$BIN" --provider fake 2>/dev/null)
echo "$OUT" | python3 -c 'import json,sys
n=0
for line in sys.stdin:
    line=line.strip()
    if line:
        json.loads(line); n+=1
sys.exit(0 if n==3 else 1)'
check $? "every stdout line is one complete JSON object"

note "gemini via mock (interactions)"
OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"a cat","aspect_ratio":"16:9","image_size":"2K","output_path":"./generated/it-a.png"}}}' \
  --provider gemini --endpoint "http://127.0.0.1:$PORT" --api-style interactions)
contains "$OUT" '\"success\":true'; check $? "generate_image succeeds"
test -s generated/it-a.png; check $? "the image is written to disk"
python3 -c 'import sys;d=open("generated/it-a.png","rb").read();sys.exit(0 if d[:8]==b"\x89PNG\r\n\x1a\n" else 1)'
check $? "the written file is a real PNG"

note "gemini via mock (generateContent)"
OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"a dog","output_path":"./generated/it-b.png"}}}' \
  --provider gemini --endpoint "http://127.0.0.1:$PORT" --api-style generate_content)
contains "$OUT" '\"success\":true'; check $? "generateContent style succeeds"

note "vertex via mock"
OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"a bird","output_path":"./generated/it-c.png"}}}' \
  --provider vertex --endpoint "http://127.0.0.1:$PORT")
contains "$OUT" '\"success\":true'; check $? "vertex express mode succeeds"

note "edit round trip"
OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_image","arguments":{"prompt":"add rain","input_image":"./generated/it-a.png","output_path":"./generated/it-edit.png"}}}' \
  --provider gemini --endpoint "http://127.0.0.1:$PORT")
contains "$OUT" '\"success\":true'; check $? "edit_image succeeds"
python3 -c 'import json,sys
reqs=[json.loads(l) for l in open("/tmp/mock_requests.jsonl")]
last=reqs[-1]["body"]
blocks=last.get("input") or last["contents"][0]["parts"]
sys.exit(0 if any(b.get("type")=="image" or "inlineData" in b for b in blocks) else 1)'
check $? "the edit request carried the input image"

note "error handling"
OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"x"}}}' \
  --provider gemini --endpoint "http://127.0.0.1:$PORT/force-error")
contains "$OUT" '\"error_type\":\"api_error\"'; check $? "an API error is reported as api_error"
contains "$OUT" '"isError":true'; check $? "an API error sets isError"

OUT=$(session '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"x"}}}' \
  --provider gemini --endpoint "http://127.0.0.1:59999")
contains "$OUT" '\"error_type\":\"http_error\"'; check $? "an unreachable host is reported as http_error"

OUT=$(printf '%s\n%s\n' "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"x"}}}' \
  | env -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_APPLICATION_CREDENTIALS \
    "$BIN" --provider gemini --credentials-source env 2>/dev/null | tail -1)
contains "$OUT" '\"error_type\":\"credentials_error\"'; check $? "a missing credential is reported as credentials_error"

note "credential precedence"
TDIR=$(mktemp -d)
cp "$BIN" "$TDIR/holy-nano-mcp"
cd "$TDIR"
printf '{"provider":"gemini","api_key":"AIzaSyREPOFILEKEY000001"}' > service-account.json
OUT=$(GEMINI_API_KEY=AIzaSyENVKEY000000001 ./holy-nano-mcp --status 2>/dev/null)
contains "$OUT" "service-account.json"; check $? "the repo file outranks the environment"
contains "$OUT" "AIza"; check $? "status shows only a key prefix"
contains "$OUT" "REPOFILE"; RC=$?
if [ $RC -ne 0 ]; then pass "status never prints the full key"; else fail "status never prints the full key"; fi

printf '{"provider":"gemini","api_key":"AIzaSyMCPCONFIGKEY0001"}' > mcp.json
OUT=$(GEMINI_API_KEY=AIzaSyENVKEY000000001 ./holy-nano-mcp --config ./mcp.json --status 2>/dev/null)
contains "$OUT" "mcp.json"; check $? "explicit MCP config outranks the repo file"

rm -f service-account.json mcp.json
OUT=$(GEMINI_API_KEY=AIzaSyENVKEY000000001 ./holy-nano-mcp --status 2>/dev/null)
contains "$OUT" "env:GEMINI_API_KEY"; check $? "the environment is used when nothing else is configured"

OUT=$(env -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_APPLICATION_CREDENTIALS ./holy-nano-mcp --status 2>/dev/null)
contains "$OUT" "none found"; check $? "no credential anywhere is reported plainly"

printf '{"type":"service_account","project_id":"p","private_key":"-----BEGIN PRIVATE KEY-----","client_email":"x@p.iam.gserviceaccount.com"}' > service-account.json
OUT=$(env -u GEMINI_API_KEY -u GOOGLE_API_KEY ./holy-nano-mcp --provider vertex --project-id p --status 2>/dev/null)
contains "$OUT" "service account key"; check $? "a real service account key is classified correctly"
contains "$OUT" "Authentication: service_account"; check $? "a real service account key selects service_account auth"
note "security_check"
rm -f service-account.json
git init -q .
printf 'service-account.json\n' > .gitignore
printf '{"provider":"gemini","api_key":"AIzaSyREPOFILEKEY000001"}' > service-account.json

security_check() {
  printf '%s\n%s\n' "$INIT" \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"security_check","arguments":{}}}' \
    | ./holy-nano-mcp 2>/dev/null | tail -1
}

chmod 600 service-account.json
OUT=$(security_check)
contains "$OUT" 'Result: PASS'; check $? "a correctly protected credential file passes"
contains "$OUT" 'covered by .gitignore'; check $? "the gitignore check runs"

chmod 644 service-account.json
OUT=$(security_check)
contains "$OUT" 'mode 644'; check $? "loose file permissions are detected"
contains "$OUT" 'ATTENTION NEEDED'; check $? "loose file permissions fail the check"

chmod 600 service-account.json
git add -f service-account.json 2>/dev/null
OUT=$(security_check)
contains "$OUT" 'ATTENTION NEEDED'; check $? "a credential file committed to git fails the check"

contains "$OUT" "REPOFILEKEY"; RC=$?
if [ $RC -ne 0 ]; then pass "security_check never prints the key"; else fail "security_check never prints the key"; fi

cd "$ROOT"
rm -rf "$TDIR"

note "secret hygiene"
# The key must never reach argv, where any local process could read it.
(printf '%s\n%s\n' "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"generate_image","arguments":{"prompt":"slow"}}}' \
  | GEMINI_API_KEY="$FAKE_KEY" "$BIN" --provider gemini --endpoint "http://127.0.0.1:$PORT" >/dev/null 2>&1) &
SESSION=$!
LEAKED=0
for _ in $(seq 1 40); do
  if grep -aqs "$FAKE_KEY" /proc/[0-9]*/cmdline 2>/dev/null; then LEAKED=1; break; fi
  sleep 0.05
done
wait $SESSION 2>/dev/null
check "$LEAKED" "the API key never appears in any process command line"

ALL_LOGS=$(printf '%s\n%s\n' "$INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"provider_status","arguments":{}}}' \
  | GEMINI_API_KEY="$FAKE_KEY" "$BIN" --provider gemini --log-level debug --endpoint "http://127.0.0.1:$PORT" 2>&1)
contains "$ALL_LOGS" "$FAKE_KEY"; RC=$?
if [ $RC -ne 0 ]; then pass "the API key never appears in logs or responses"; else fail "the API key never appears in logs or responses"; fi

ls -d /tmp/holy-nano-mcp-http-* /tmp/holy-nano-mcp-sh-* >/dev/null 2>&1; RC=$?
if [ $RC -ne 0 ]; then pass "temporary credential files are cleaned up"; else fail "temporary credential files are cleaned up"; fi

note "summary"
if [ "$FAILED" -eq 0 ]; then
  echo "all integration checks passed"
  exit 0
fi
echo "$FAILED check(s) failed"
exit 1
