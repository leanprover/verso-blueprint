"""Deterministic stdio peer for the experimental Lean client. No dependencies."""

import json
import os
import signal
import sys
import threading
import time

write_lock = threading.Lock()
chatter = {}
held = None
client_request = None
document_request = None
cancelled_requests = []
mode = None
source_uri = None
target_uri = None


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
        options = params.get("initializationOptions") or {}
        mode = options.get("mode")
        source_uri = options.get("sourceUri")
        target_uri = options.get("targetUri")
        if mode == "ignore-term":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        reply(request_id, {"capabilities": {
            "positionEncoding": "utf-8" if mode == "wrong-encoding" else "utf-16",
            "textDocumentSync": 1,
            "definitionProvider": True, "hoverProvider": True,
            **({"workspaceSymbolProvider": {"resolveProvider": True},
                "semanticTokensProvider": {"full": True, "range": True, "legend": {
                    "tokenTypes": ["keyword", "function", "number"],
                    "tokenModifiers": ["declaration"]}}} if mode == "workspace" else {}),
        }})
    elif method == "workspace/symbol":
        def symbol(name, container):
            return {"name": name, "kind": 12, "containerName": container,
                    "location": {"uri": source_uri, "range": {
                        "start": {"line": 0, "character": 0 if container == "Container" else 1},
                        "end": {"line": 0, "character": 5}}}}
        query = params["query"]
        if query == "measure":
            reply(request_id, [symbol("measure", "Container"), symbol("measure", "Container"),
                               symbol("measure", "Other"), symbol("measureMore", "Container")])
        elif query == "deferred":
            reply(request_id, [{"name": "deferred", "kind": 12,
                                "location": {"uri": source_uri}, "data": 7}])
        else:
            reply(request_id, [])
    elif method == "workspaceSymbol/resolve":
        assert params["data"] == 7
        params["location"]["range"] = {"start": {"line": 0, "character": 0},
                                        "end": {"line": 0, "character": 5}}
        reply(request_id, params)
    elif method == "textDocument/definition":
        reply(request_id, [{"targetUri": target_uri,
                            "targetRange": {"start": {"line": 0, "character": 2},
                                            "end": {"line": 0, "character": 20}},
                            "targetSelectionRange": {"start": {"line": 0, "character": 5},
                                                     "end": {"line": 0, "character": 12}}}])
    elif method in ("textDocument/semanticTokens/full", "textDocument/semanticTokens/range"):
        reply(request_id, {"data": [0, 2, 2, 0, 0, 0, 3, 7, 1, 1, 0, 12, 1, 2, 0]})
    elif method == "textDocument/didOpen":
        document = params["textDocument"]
        diagnostics(document["uri"], document["version"], "old warning")
        diagnostics(document["uri"], document["version"])
        diagnostics(document["uri"], document["version"] - 1, "stale warning")
    elif method == "textDocument/didChange":
        document = params["textDocument"]
        diagnostics(document["uri"], 1, "stale after edit")
        diagnostics(document["uri"], document["version"], "current warning")
    elif method == "test/barrier":
        reply(request_id, True)
    elif method == "test/hold-document":
        document_request = request_id
        send({"method": "test/held-" + params["tag"], "params": {}})
    elif method == "test/release-document":
        reply(document_request, "obsolete")
        document_request = None
        reply(request_id, True)
    elif method == "test/stop-reading":
        reply(request_id, True)
        while True:
            time.sleep(60)
    elif method == "test/stderr":
        sys.stderr.write("e" * 200000)
        sys.stderr.flush()
        reply(request_id, True)
    elif method in ("test/descendant", "test/escaped-descendant"):
        ready_read, ready_write = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(ready_read)
            if method == "test/escaped-descendant":
                os.setsid()
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            os.write(ready_write, b"r")
            os.close(ready_write)
            while True:
                time.sleep(60)
        os.close(ready_write)
        assert os.read(ready_read, 1) == b"r"
        os.close(ready_read)
        reply(request_id, pid)
        if method == "test/descendant":
            sys.exit(0)
    elif method == "test/bad-envelope":
        send({"id": request_id, "result": True, "error": {"code": -1, "message": "bad"}})
    elif method == "test/bad-error":
        send({"id": request_id, "error": {"code": "invalid", "message": "bad"}})
    elif method == "test/oversized":
        sys.stdout.buffer.write(b"Content-Length: 999999999\r\n\r\n")
        sys.stdout.buffer.flush()
    elif method == "test/partial":
        sys.stdout.buffer.write(b"Content-Length: 100\r\n\r\n{")
        sys.stdout.buffer.flush()
    elif method == "test/error":
        error = {"code": -32097, "message": "server-specific"}
        if isinstance(params, dict):
            error["code"] = params.get("code", error["code"])
            if "data" in params:
                error["data"] = params["data"]
        send({"id": request_id, "error": error})
    elif method == "test/null":
        reply(request_id, None)
    elif method == "test/cancellations":
        reply(request_id, cancelled_requests)
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
        cancelled_requests.append(params["id"])
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
        if mode not in ("ignore-shutdown", "ignore-term"):
            reply(request_id, None)
    elif method == "exit":
        if mode not in ("ignore-shutdown", "ignore-term"):
            sys.exit(0)
