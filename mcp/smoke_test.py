"""Checks the triage MCP Server without an MCP client.

Starts iris-mcp-server in the container over stdio, initializes the session and calls tools:
    python mcp/smoke_test.py                                  # lists the tools, then the summary
    python mcp/smoke_test.py mcp_triage_list_incidents '{"status": "PENDING_APPROVAL"}'
"""
import json
import subprocess
import sys

COMMAND = ["docker", "exec", "-i", "iris-triage", "/usr/irissys/bin/iris-mcp-server",
           "--config=/home/irisowner/dev/mcp/config.toml", "run"]


def main(pairs):
    server = subprocess.Popen(COMMAND, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True, encoding="utf-8")

    def request(id_, method, params=None):
        message = {"jsonrpc": "2.0", "id": id_, "method": method}
        if params is not None:
            message["params"] = params
        server.stdin.write(json.dumps(message) + "\n")
        server.stdin.flush()
        while True:
            line = server.stdout.readline()
            if not line:
                sys.exit("iris-mcp-server closed the connection")
            answer = json.loads(line)
            if answer.get("id") == id_:
                return answer

    request(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                              "clientInfo": {"name": "smoke-test", "version": "1"}})
    server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    server.stdin.flush()

    if not pairs:
        tools = request(2, "tools/list")["result"]["tools"]
        print(f"{len(tools)} tools:")
        for tool in tools:
            print(f"  {tool['name']}({', '.join(tool.get('inputSchema', {}).get('properties', {}))})")
        pairs = ["mcp_triage_get_triage_summary", "{}"]

    for n, (tool, arguments) in enumerate(zip(pairs[0::2], pairs[1::2]), start=3):
        result = request(n, "tools/call", {"name": tool, "arguments": json.loads(arguments)}).get("result", {})
        text = " ".join(part.get("text", "") for part in result.get("content", []))
        print(f"{tool} {arguments}\n  {'ERROR ' if result.get('isError') else ''}{text}")
    server.stdin.close()
    server.terminate()


if __name__ == "__main__":
    main(sys.argv[1:])
