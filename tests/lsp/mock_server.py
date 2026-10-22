"""Deterministic stdio peer for the experimental Lean client. No dependencies."""

import json
import sys
import threading
import time

write_lock = threading.Lock()
chatter = {}
held = None
client_request = None
mode = None


def send(message):
    data = json.dumps({"jsonrpc": "2.0", **message}, ensure_ascii=False).encode()
    with write_lock:
        sys.stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode() + data)
        sys.stdout.buffer.flush()


def reply(request_id, result):
    send({"id": request_id, "result": result})


def diagnostics(uri, version, message=None):
    items = [] if message is None else [{
        "range": {"start": {"line": 0, "character": 0},
                  "end": {"line": 0, "character": 1}},
        "severity": 2, "message": message,
    }]
    send({"method": "textDocument/publishDiagnostics", "params": {
        "uri": uri, "version": version, "diagnostics": items,
    }})


def chat(request_id, stopped):
    while not stopped.wait(0.003):
        send({"method": "window/logMessage", "params": {"type": 3, "message": "busy"}})
    # A late response must never answer the next operation.
    reply(request_id, "late")


while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line == b"\r\n":
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    message = json.loads(sys.stdin.buffer.read(int(headers["content-length"])))
    method = message.get("method")
    request_id = message.get("id")
    params = message.get("params", {})
    if method == "initialize":
        mode = (params.get("initializationOptions") or {}).get("mode")
        reply(request_id, {"capabilities": {
            "positionEncoding": "utf-8" if mode == "wrong-encoding" else "utf-16",
            "textDocumentSync": 1,
            "definitionProvider": True, "hoverProvider": True,
        }})
    elif method == "textDocument/didOpen":
        document = params["textDocument"]
        diagnostics(document["uri"], 1, "old warning")
        diagnostics(document["uri"], 1)
        diagnostics(document["uri"], 0, "stale warning")
    elif method == "textDocument/didChange":
        document = params["textDocument"]
        diagnostics(document["uri"], 1, "stale after edit")
        diagnostics(document["uri"], document["version"], "current warning")
    elif method == "test/barrier":
        reply(request_id, True)
    elif method == "test/error":
        send({"id": request_id, "error": {"code": -32097, "message": "server-specific"}})
    elif method == "test/first":
        held = request_id
        send({"method": "test/held", "params": {}})
    elif method == "test/second":
        reply(request_id, "second")
        reply(held, "first")
    elif method == "test/client-request":
        client_request = request_id
        send({"id": "server-unsupported", "method": "client/registerCapability", "params": {}})
    elif method is None and request_id == "server-unsupported":
        reply(client_request, message.get("error", {}).get("code") == -32601)
    elif method == "test/chatter":
        stopped = threading.Event()
        chatter[request_id] = stopped
        threading.Thread(target=chat, args=(request_id, stopped), daemon=True).start()
    elif method == "$/cancelRequest":
        if params["id"] in chatter:
            chatter[params["id"]].set()
    elif method == "test/unversioned":
        send({"method": "textDocument/publishDiagnostics", "params": {
            "uri": params["uri"], "diagnostics": [],
        }})
        reply(request_id, True)
    elif method == "test/die":
        sys.stderr.write("intentional mock exit\n")
        sys.stderr.flush()
        sys.exit(7)
    elif method == "shutdown":
        if mode != "ignore-shutdown":
            reply(request_id, None)
    elif method == "exit":
        if mode != "ignore-shutdown":
            sys.exit(0)
