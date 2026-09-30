#!/usr/bin/env python3
"""Runpod queue handler for the pinned ACE-Step ComfyUI worker."""

import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import runpod

COMFY_PORT = os.environ.get("COMFY_PORT") or os.environ.get("PORT") or "8188"
COMFY_HOST = f"127.0.0.1:{COMFY_PORT}"
STARTUP_TIMEOUT_S = int(os.environ.get("COMFY_STARTUP_TIMEOUT", "600"))
WORKFLOW_TIMEOUT_S = int(os.environ.get("COMFY_WORKFLOW_TIMEOUT", "600"))
MAX_INLINE_BYTES = int(os.environ.get("COMFY_MAX_INLINE_BYTES", "10000000"))


def _get(path, timeout=30):
    with urllib.request.urlopen(f"http://{COMFY_HOST}{path}", timeout=timeout) as response:
        return response.read()


def _get_json(path, timeout=30):
    return json.loads(_get(path, timeout))


def wait_for_comfy():
    deadline = time.time() + STARTUP_TIMEOUT_S
    last_error = None
    while time.time() < deadline:
        try:
            _get_json("/system_stats", timeout=5)
            return None
        except (urllib.error.URLError, OSError, ValueError) as error:
            last_error = error
            time.sleep(1)
    return f"ComfyUI did not respond within {STARTUP_TIMEOUT_S}s ({last_error})"


def queue_workflow(workflow, client_id):
    payload = json.dumps({"prompt": workflow, "client_id": client_id}).encode()
    request = urllib.request.Request(
        f"http://{COMFY_HOST}/prompt",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        raise ValueError(f"ComfyUI rejected the workflow: {detail}") from error


def collect_outputs(node_outputs):
    files = []
    for node_id, output in (node_outputs or {}).items():
        for kind, entries in (output or {}).items():
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict) or "filename" not in entry:
                    continue
                query = urllib.parse.urlencode({
                    "filename": entry.get("filename", ""),
                    "subfolder": entry.get("subfolder", ""),
                    "type": entry.get("type", "output"),
                })
                record = {
                    "node_id": node_id,
                    "kind": kind,
                    "filename": entry.get("filename"),
                    "subfolder": entry.get("subfolder", ""),
                    "type": entry.get("type", "output"),
                }
                blob = _get(f"/view?{query}", timeout=120)
                record["size_bytes"] = len(blob)
                if len(blob) <= MAX_INLINE_BYTES:
                    record["data"] = base64.b64encode(blob).decode()
                else:
                    record["error"] = "output exceeds COMFY_MAX_INLINE_BYTES"
                files.append(record)
    return files


def run_workflow(workflow):
    queued = queue_workflow(workflow, str(time.time_ns()))
    prompt_id = queued.get("prompt_id")
    if not prompt_id:
        return {"error": f"ComfyUI returned no prompt_id: {queued}"}

    deadline = time.time() + WORKFLOW_TIMEOUT_S
    while time.time() < deadline:
        entry = _get_json(f"/history/{prompt_id}").get(prompt_id)
        if entry:
            if (entry.get("status") or {}).get("status_str") == "error":
                return {"prompt_id": prompt_id, "error": "workflow failed", "status": entry.get("status")}
            if entry.get("outputs"):
                return {"prompt_id": prompt_id, "files": collect_outputs(entry["outputs"])}
        time.sleep(1)
    return {"prompt_id": prompt_id, "error": f"workflow did not finish within {WORKFLOW_TIMEOUT_S}s"}


def handler(job):
    error = wait_for_comfy()
    if error:
        return {"error": error}
    job_input = job.get("input") or {}
    workflow = job_input.get("workflow")
    if not workflow:
        return {"status": "ready", "comfyui": _get_json("/system_stats")}
    if not isinstance(workflow, dict):
        return {"error": "workflow must be a ComfyUI API-format object"}
    try:
        return run_workflow(workflow)
    except ValueError as error:
        return {"error": str(error)}


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
