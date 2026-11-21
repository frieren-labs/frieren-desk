#!/usr/bin/env python3
"""OpenCode account helper for Frieren.

The pet never stores API keys itself. This helper reads a key from stdin and
uses opencode's own credential commands, so opencode keeps owning its store and
the pet only sees the connection status.

Usage:

    auth.py --bin /path/to/opencode status <provider>
    auth.py --bin /path/to/opencode login <provider>   (API key on stdin)

Both actions print one JSON object on stdout:

    {"ok": true, "provider": "...", "connected": true, "methods": ["Frieren"]}

On failure they print {"ok": false, "error": "..."} and exit 1. The key is
never included in the output or in argv.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import subprocess
import sys

PROVIDER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
LABEL = "Frieren"
PREFIX = "cred_frieren_"
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


class HelperError(Exception):
    pass


def opencode_bin(path: str) -> str:
    if path:
        return path
    return shutil.which("opencode") or "opencode"


def run(command: list[str], input_text: str | None = None, timeout: int = 60) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    kwargs = {
        "capture_output": True,
        "text": True,
        "timeout": timeout,
        "env": env,
    }
    if input_text is None:
        kwargs["stdin"] = subprocess.DEVNULL
        return subprocess.run(command, **kwargs)
    return subprocess.run(command, input=input_text, **kwargs)


def clean_output(proc: subprocess.CompletedProcess, key: str = "") -> str:
    text = (proc.stderr or "") + "\n" + (proc.stdout or "")
    if key:
        text = text.replace(key, "***")
    text = ANSI_RE.sub("", text)
    lines = []
    for line in text.splitlines():
        line = line.strip(" \t│┌└◇■")
        if line:
            lines.append(line)
    message = lines[-1] if lines else "opencode command failed"
    return message[:240]


def parse_provider(provider: str) -> str:
    provider = (provider or "").strip()
    if not PROVIDER_RE.match(provider):
        raise HelperError("Invalid provider id.")
    return provider


def integration_list(binary: str) -> list[dict]:
    proc = run([binary, "auth", "list", "--format", "json"], timeout=30)
    if proc.returncode != 0:
        raise HelperError(clean_output(proc))
    try:
        data = json.loads(proc.stdout or "[]")
    except ValueError:
        raise HelperError("Unexpected response from opencode auth list.")
    if not isinstance(data, list):
        raise HelperError("Unexpected response from opencode auth list.")
    return data


def find_integration(data: list[dict], provider: str) -> dict | None:
    for item in data:
        if item.get("id") == provider:
            return item
    return None


def status(binary: str, provider: str) -> dict:
    data = integration_list(binary)
    item = find_integration(data, provider)
    connections = item.get("connections", []) if item else []
    methods = []
    credentials = []
    for connection in connections:
        label = connection.get("label") or connection.get("name") or connection.get("method")
        if label:
            methods.append(str(label))
        if connection.get("type") == "credential":
            credentials.append({
                "id": str(connection.get("id", "")),
                "label": str(connection.get("label", "")),
                "method": str(connection.get("method", "")),
            })
    return {
        "ok": True,
        "provider": provider,
        "connected": len(connections) > 0,
        "methods": methods,
        "credentials": credentials,
    }


def login(binary: str, provider: str, key: str) -> dict:
    key = key.strip()
    if not key:
        raise HelperError("The API key is empty.")

    current = status(binary, provider)
    old_credentials = [
        credential for credential in current.get("credentials", [])
        if credential.get("label") == LABEL or credential.get("id", "").startswith(PREFIX)
    ]

    credential_id = PREFIX + secrets.token_hex(8)
    payload = [{
        "id": credential_id,
        "integrationID": provider,
        "label": LABEL,
        "active": True,
        "value": {"type": "key", "key": key},
    }]
    proc = run([binary, "auth", "import"], input_text=json.dumps(payload), timeout=60)
    if proc.returncode != 0:
        raise HelperError(clean_output(proc, key))

    proc = run([binary, "auth", "switch", provider, credential_id], timeout=60)
    if proc.returncode != 0:
        raise HelperError(clean_output(proc, key))

    result = status(binary, provider)
    ids = [credential.get("id") for credential in result.get("credentials", [])]
    if credential_id not in ids:
        raise HelperError("opencode did not keep the new credential.")

    # Only after the new key is active, drop the credentials this helper
    # created before. A failed import must not remove a working account.
    for credential in old_credentials:
        if credential.get("id") == credential_id:
            continue
        try:
            run([binary, "auth", "logout", provider, credential["id"]], timeout=30)
        except (OSError, subprocess.SubprocessError):
            pass

    if old_credentials:
        result = status(binary, provider)
    return result


def main(argv: list[str]) -> int:
    bin_path = ""
    args: list[str] = []
    index = 1
    while index < len(argv):
        if argv[index] == "--bin":
            index += 1
            bin_path = argv[index] if index < len(argv) else ""
        else:
            args.append(argv[index])
        index += 1

    if len(args) < 2:
        print("usage: auth.py [--bin PATH] status|login <provider>", file=sys.stderr)
        return 2

    action, provider = args[0], args[1]
    binary = opencode_bin(bin_path)

    try:
        provider = parse_provider(provider)
        if action == "status":
            result = status(binary, provider)
        elif action == "login":
            result = login(binary, provider, sys.stdin.read())
        else:
            raise HelperError(f"Unknown action: {action}")
        print(json.dumps(result))
        return 0
    except HelperError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    except FileNotFoundError:
        print(json.dumps({"ok": False, "error": "opencode was not found."}))
        return 1
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "error": "opencode did not answer in time."}))
        return 1
    except OSError as exc:
        print(json.dumps({"ok": False, "error": f"opencode failed: {exc.strerror or exc}"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
