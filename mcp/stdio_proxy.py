"""Runs iris-mcp-server for MCP clients that probe with server/discover first (Claude Code).

iris-mcp-server 2.0.0 (build 154) answers the probe with "Unsupported protocol version", as it should,
but then stays in stateless mode: after a normal initialize, tools/list still fails with
"request _meta is missing or has malformed required fields". This proxy answers the probe itself,
with the same error, and passes everything else through unchanged. It runs inside the container:
    docker exec -i iris-triage python3 /home/irisowner/dev/mcp/stdio_proxy.py
"""
import json
import subprocess
import sys
import threading

COMMAND = ["/usr/irissys/bin/iris-mcp-server", "--config=/home/irisowner/dev/mcp/config.toml", "run"]
SUPPORTED = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]


def probe_answer(line):
    """The error iris-mcp-server would give to a server/discover request, or None for other lines."""
    try:
        message = json.loads(line)
    except ValueError:
        return None
    if not isinstance(message, dict) or message.get("method") != "server/discover" or "id" not in message:
        return None
    requested = ((message.get("params") or {}).get("_meta") or {}).get("io.modelcontextprotocol/protocolVersion")
    return {"jsonrpc": "2.0", "id": message["id"],
            "error": {"code": -32022, "message": "Unsupported protocol version",
                      "data": {"requested": requested, "supported": SUPPORTED}}}


def main():
    server = subprocess.Popen(COMMAND, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    lock = threading.Lock()

    def to_client(data):
        with lock:
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()

    def from_server():
        for line in server.stdout:
            to_client(line)

    threading.Thread(target=from_server, daemon=True).start()
    for line in sys.stdin.buffer:
        answer = probe_answer(line)
        if answer is not None:
            to_client((json.dumps(answer) + "\n").encode("utf-8"))
            continue
        server.stdin.write(line)
        server.stdin.flush()
    server.stdin.close()
    server.wait()


if __name__ == "__main__":
    main()
