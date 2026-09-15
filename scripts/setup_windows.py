#!/usr/bin/env python3
"""
Holy Nano MCP - Automated Windows One-Click Installer & Configurator
"""
import os, sys, json, subprocess, platform, shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

def print_header(text: str):
    print("\n" + "=" * 55)
    print(f"  {text}")
    print("=" * 55)

def print_step(step: int, text: str):
    print(f"\n[{step}] {text}")

def get_wsl_path(win_path: Path) -> str:
    path_str = str(win_path.resolve()).replace("\\", "/")
    if len(path_str) > 1 and path_str[1] == ":":
        return f"/mnt/{path_str[0].lower()}{path_str[2:]}"
    return path_str

def run_cmd(cmd, check=False, shell=True, capture=False):
    if capture:
        res = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    return subprocess.run(cmd, shell=shell).returncode

def ensure_build():
    print_step(1, "Checking HolyC Binary...")
    bin_path = REPO_ROOT / "build" / "holy-nano-mcp"
    if bin_path.exists():
        print("  [OK] HolyC binary found at build/holy-nano-mcp")
        return True

    print("  [*] Building HolyC binary in WSL...")
    rc = run_cmd("powershell.exe -ExecutionPolicy Bypass -File .\\scripts\\build.ps1")
    if rc != 0 or not bin_path.exists():
        print("  [!] Failed to build HolyC binary. Please ensure WSL Ubuntu is installed.")
        return False
    print("  [OK] Build complete!")
    return True

def setup_credentials():
    print_step(2, "Configuring AI Credentials...")
    cfg_dir = REPO_ROOT / "config"
    cfg_dir.mkdir(exist_ok=True)
    vertex_cfg = cfg_dir / "vertex.json"
    gemini_cfg = cfg_dir / "gemini.json"
    sa_cfg = cfg_dir / "gcp-service-account.json"

    has_sa = sa_cfg.exists() and sa_cfg.stat().st_size > 50
    has_gemini = gemini_cfg.exists() and gemini_cfg.stat().st_size > 20

    if has_sa or has_gemini:
        print("  [OK] Active credentials already found in config directory.")
        return

    print("\n  Choose your preferred authentication method:")
    print("  [1] Google Gemini API Key (AI Studio - Easiest)")
    print("  [2] Google Cloud Vertex AI (Service Account JSON)")

    sel = input("  Enter choice [1 or 2] (default 1): ").strip()
    if sel == "2":
        print("\n  Paste your GCP Service Account JSON file path OR JSON content:")
        val = input("  File path / JSON: ").strip()
        if os.path.exists(val):
            shutil.copy(val, str(sa_cfg))
            print(f"  [OK] Copied {val} -> {sa_cfg}")
        else:
            try:
                parsed = json.loads(val)
                with open(sa_cfg, "w", encoding="utf-8") as f:
                    json.dump(parsed, f, indent=2)
                print(f"  [OK] Saved GCP Service Account to {sa_cfg}")
            except Exception:
                print("  [!] Invalid JSON or file path.")

        project_id = input("  Enter GCP Project ID (press Enter to auto-detect): ").strip()
        v_data = {
            "provider": "vertex",
            "project_id": project_id if project_id else "auto",
            "location": "global",
            "model": { "default": "gemini-3-pro-image" },
            "output": { "directory": "./generated" },
            "credentials": { "source": "auto" },
            "auth": { "type": "service_account", "credentials_file": "config/gcp-service-account.json" }
        }
        with open(vertex_cfg, "w", encoding="utf-8") as f:
            json.dump(v_data, f, indent=2)
        print("  [OK] Saved config/vertex.json")
    else:
        key = input("  Enter your Gemini API Key (e.g. AIzaSy...): ").strip()
        if key:
            g_data = {
                "provider": "gemini",
                "api_key": key,
                "model": { "default": "gemini-3-pro-image" },
                "output": { "directory": "./generated" },
                "credentials": { "source": "auto" }
            }
            with open(gemini_cfg, "w", encoding="utf-8") as f:
                json.dump(g_data, f, indent=2)
            print("  [OK] Saved config/gemini.json")

def get_mcp_config_entries():
    return {
        "url": "http://localhost:4392/holy-nano",
        "timeout": 180,
        "autoApprove": [
            "generate_image",
            "edit_image",
            "list_models",
            "provider_status",
            "security_check"
        ]
    }

def inject_mcp_settings():
    print_step(3, "Auto-Injecting MCP Settings into AI Clients...")
    home = Path.home()
    appdata = Path(os.environ.get("APPDATA", str(home / "AppData" / "Roaming")))
    
    target_files = [
        home / ".cline" / "data" / "settings" / "cline_mcp_settings.json",
        appdata / "Code" / "User" / "globalStorage" / "saoudrizwan.claude-dev" / "settings" / "cline_mcp_settings.json",
        appdata / "Code" / "User" / "globalStorage" / "rooveterinaryinc.roo-cline" / "settings" / "cline_mcp_settings.json",
        appdata / "Claude" / "claude_desktop_config.json",
        home / ".cursor" / "mcp.json",
    ]

    injected_count = 0
    server_entry = get_mcp_config_entries()

    for target in target_files:
        if not target.parent.exists():
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            data = {}
            if target.exists():
                try:
                    with open(target, "r", encoding="utf-8") as f:
                        data = json.load(f)
                except Exception:
                    data = {}

            if "mcpServers" not in data:
                data["mcpServers"] = {}

            data["mcpServers"]["holy-nano"] = server_entry

            with open(target, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)

            print(f"  [OK] Injected holy-nano into: {target}")
            injected_count += 1
        except Exception as e:
            print(f"  [!] Failed to update {target}: {e}")

    if injected_count == 0:
        default_target = home / ".cline" / "data" / "settings" / "cline_mcp_settings.json"
        default_target.parent.mkdir(parents=True, exist_ok=True)
        with open(default_target, "w", encoding="utf-8") as f:
            json.dump({"mcpServers": {"holy-nano": server_entry}}, f, indent=2)
        print(f"  [OK] Created default MCP config at: {default_target}")

def verify_status():
    print_step(4, "Testing Holy Nano Status...")
    rc, out, err = run_cmd(f'wsl.exe -d Ubuntu -e bash -lc "cd {get_wsl_path(REPO_ROOT)} && ./build/holy-nano-mcp --status --config config/vertex.json 2>/dev/null || ./build/holy-nano-mcp --status"', check=False, capture=True)
    if rc == 0 and ("Provider:" in out or "Status:" in out):
        print(f"  [OK] Server verification passed!\n")
        for line in out.splitlines():
            if line.startswith("Provider:") or line.startswith("Model:") or line.startswith("Status:"):
                print(f"       {line}")
    else:
        print("  [*] Note: Server compiled. You can verify at any time with start_sse.bat.")

def main():
    print_header("Holy Nano MCP - Windows One-Click Installer")
    print("This will setup Holy Nano MCP server and configure your MCP clients.")
    
    if not ensure_build():
        sys.exit(1)
        
    setup_credentials()
    inject_mcp_settings()
    verify_status()

    print_header("INSTALLATION COMPLETE")
    print("To start the server anytime, just run:")
    print("  -> start_sse.bat  (or holy-nano start)")
    print("\nYour MCP client (Cline / Claude Desktop / Cursor) is now fully configured!")

    start_now = input("\nDo you want to start the Holy Nano SSE Server right now? (Y/n): ").strip().lower()
    if start_now != 'n':
        print("\nStarting SSE server on http://localhost:4392/holy-nano ...\n")
        subprocess.run([sys.executable, str(REPO_ROOT / "scripts" / "holy_server.py")])

if __name__ == "__main__":
    main()
