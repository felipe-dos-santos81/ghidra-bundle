# Starts ReVa's headless MCP server (random port) inside PyGhidra, with every installed
# extension on the class path, and sends an MCP initialize request over streamable HTTP.
# Prints "REVA OK port <n>" or "REVA FAIL <reason>".
# @category Bundle
# @runtime PyGhidra
import json
import urllib.error
import urllib.request

try:
    from reva.headless import RevaHeadlessLauncher
except ImportError:
    import jpype
    RevaHeadlessLauncher = jpype.JClass(
        "reva.headless.RevaHeadlessLauncher",
        loader=jpype.JClass("java.lang.ClassLoader").getSystemClassLoader())

INITIALIZE = {
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-06-18", "capabilities": {},
               "clientInfo": {"name": "sanity", "version": "0"}},
}

launcher = RevaHeadlessLauncher(None, True)  # in-memory config, random free port
launcher.start()
try:
    if not launcher.waitForServer(60000):
        print("REVA FAIL server did not start within 60 s")
    else:
        port = launcher.getPort()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/mcp/message", data=json.dumps(INITIALIZE).encode(),
            headers={"Content-Type": "application/json",
                     "Accept": "application/json, text/event-stream"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = resp.read().decode(errors="replace")
                status = resp.status
        except urllib.error.HTTPError as e:
            body, status = e.read().decode(errors="replace"), e.code
        if status == 200 and '"protocolVersion"' in body:
            print(f"REVA OK port {port}")
        else:
            print(f"REVA FAIL HTTP {status}: {body[:200]}")
finally:
    launcher.stop()
