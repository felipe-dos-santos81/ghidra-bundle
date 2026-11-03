# Starts ReVa's headless MCP server (random port) inside PyGhidra, with every installed
# extension on the class path, and drives it over streamable HTTP: initialize, then
# tools/list with a short timeout. Also reports the jars the MCP SDK and Jackson classes
# were loaded from: GhidrAssist ships older copies of both, Ghidra's flat extension class
# path loads whichever extension sorts first, and ReVa's tool calls hang when it gets the
# old ones. Prints "REVA OK port <n> tools <k> mcp-sdk <jar> jackson <jar>" or
# "REVA FAIL <reason> (mcp-sdk <jar> jackson <jar>)".
# @category Bundle
# @runtime PyGhidra
import http.client
import json
import socket

import jpype

try:
    from reva.headless import RevaHeadlessLauncher
except ImportError:
    RevaHeadlessLauncher = jpype.JClass(
        "reva.headless.RevaHeadlessLauncher",
        loader=jpype.JClass("java.lang.ClassLoader").getSystemClassLoader())

HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def post(port, message, session=None, timeout=20):
    """POST one JSON-RPC message; return (status, JSON text of the reply, session id).

    The server answers requests after initialize with an event stream that stays open,
    so only the first data line is read. A timeout returns status 0.
    """
    headers = dict(HEADERS)
    if session:
        headers["Mcp-Session-Id"] = session
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request("POST", "/mcp/message", body=json.dumps(message), headers=headers)
        resp = conn.getresponse()
        sid = resp.getheader("Mcp-Session-Id")
        if "text/event-stream" in (resp.getheader("Content-Type") or ""):
            for raw in resp:
                line = raw.decode(errors="replace").strip()
                if line.startswith("data:"):
                    return resp.status, line[5:].strip(), sid
            return resp.status, "", sid
        return resp.status, resp.read().decode(errors="replace"), sid
    except (socket.timeout, TimeoutError):
        return 0, f"no reply within {timeout} s", None
    finally:
        conn.close()


def result(body):
    return json.loads(body).get("result") if body.lstrip().startswith("{") else None


def jar_of(class_name):
    """Base name of the jar a class was loaded from, through Ghidra's class loader."""
    loader = jpype.JClass("java.lang.ClassLoader").getSystemClassLoader()
    cls = jpype.JClass("java.lang.Class").forName(class_name, False, loader)
    return str(cls.getProtectionDomain().getCodeSource().getLocation().getPath()).rsplit("/", 1)[-1]


launcher = RevaHeadlessLauncher(None, True)  # in-memory config, random free port
launcher.start()
try:
    origins = (f"mcp-sdk {jar_of('io.modelcontextprotocol.spec.McpSchema')} "
               f"jackson {jar_of('com.fasterxml.jackson.databind.ObjectMapper')}")
    if not launcher.waitForServer(60000):
        print(f"REVA FAIL server did not start within 60 s ({origins})")
    else:
        port = int(launcher.getPort())
        status, body, session = post(port, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                       "clientInfo": {"name": "sanity", "version": "0"}}})
        init = result(body) if status == 200 else None
        if not init or "protocolVersion" not in init:
            print(f"REVA FAIL initialize HTTP {status}: {body[:200]} ({origins})")
        else:
            status, body, _ = post(port, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, session)
            tools = (result(body) or {}).get("tools") if status == 200 else None
            if tools:
                print(f"REVA OK port {port} tools {len(tools)} {origins}")
            else:
                print(f"REVA FAIL tools/list HTTP {status}: {body[:200]} ({origins})")
finally:
    launcher.stop()
