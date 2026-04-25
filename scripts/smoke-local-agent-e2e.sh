#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-7777}"
BASE_URL="http://127.0.0.1:$PORT"
MARKER="cu-cli-smoke-$(date +%s)"
SET_VALUE_MARKER="$MARKER-set-value"
AGENT_LOG="${AGENT_LOG:-/tmp/computer-use-agent-e2e.log}"

cd "$ROOT_DIR"
swift build --product computer-use-agent >/dev/null

.build/debug/computer-use-agent >"$AGENT_LOG" 2>&1 &
agent_pid=$!

cleanup() {
  kill "$agent_pid" 2>/dev/null || true
  wait "$agent_pid" 2>/dev/null || true
  osascript -e 'tell application "TextEdit" to if (count of documents) > 0 then close front document saving no' >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..40}; do
  if curl -fsS "$BASE_URL/health" >/tmp/cu-e2e-health.json 2>/dev/null; then
    break
  fi
  sleep 0.25
done

curl -fsS "$BASE_URL/health" >/tmp/cu-e2e-health.json
curl -fsS "$BASE_URL/permissions" >/tmp/cu-e2e-permissions.json
curl -fsS "$BASE_URL/apps" >/tmp/cu-e2e-apps.json

osascript \
  -e 'tell application "TextEdit" to activate' \
  -e 'tell application "TextEdit" to make new document' >/dev/null
sleep 1

curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  -d '{"bundle_id":"com.apple.TextEdit"}' \
  "$BASE_URL/state" >/tmp/cu-e2e-textedit-state-before.json

python3 - "$BASE_URL" "$MARKER" "$SET_VALUE_MARKER" <<'PY'
import json
import subprocess
import sys
import time

base_url, marker, set_value_marker = sys.argv[1:4]

def post(path, payload):
    print(f"POST {path}", flush=True)
    result = subprocess.run(
        [
            "curl",
            "-fsS",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            json.dumps(payload),
            base_url + path,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout or "{}")

def load(path):
    with open(path) as file:
        return json.load(file)

state = load("/tmp/cu-e2e-textedit-state-before.json")
nodes = state["ax_tree"]["nodes"]

def node_text(node):
    return " ".join(
        str(node.get(key) or "")
        for key in ("role", "title", "value", "description")
    )

text_node = next(
    (
        node
        for node in nodes
        if "AXText" in str(node.get("role")) and node.get("bounds")
    ),
    None,
)
if text_node is None:
    text_node = next((node for node in nodes if node.get("bounds")), None)
if text_node is None:
    raise SystemExit("no clickable TextEdit AX node with bounds found")

window_node = next(
    (node for node in nodes if node.get("role") == "AXWindow"),
    None,
)

snapshot_id = state["snapshot_id"]
element_id = text_node["id"]
post("/actions/click", {"snapshot_id": snapshot_id, "element_id": element_id})
post("/actions/type", {"text": marker})
post("/actions/key", {"key": "Return"})
post("/actions/type", {"text": "-after-return"})
post(
    "/actions/set-value",
    {
        "snapshot_id": snapshot_id,
        "element_id": element_id,
        "value": set_value_marker,
    },
)
if window_node is not None:
    post(
        "/actions/action",
        {
            "snapshot_id": snapshot_id,
            "element_id": window_node["id"],
            "name": "AXRaise",
        },
    )

time.sleep(1)
post("/state", {"bundle_id": "com.apple.TextEdit"})
PY

curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  -d '{"bundle_id":"com.apple.TextEdit"}' \
  "$BASE_URL/state" >/tmp/cu-e2e-textedit-state-after.json

python3 - "$SET_VALUE_MARKER" <<'PY'
import json
import sys

marker = sys.argv[1]
with open("/tmp/cu-e2e-textedit-state-after.json") as file:
    state = json.load(file)

values = []
for node in state.get("ax_tree", {}).get("nodes", []):
    for key in ("value", "title", "description"):
        value = node.get(key)
        if isinstance(value, str):
            values.append(value)

summary = {
    "textedit_marker_found": any(marker in value for value in values),
    "textedit_app": state.get("app", {}).get("name"),
    "textedit_snapshot_id": state.get("snapshot_id"),
    "textedit_ax_nodes": len(state.get("ax_tree", {}).get("nodes", [])),
    "textedit_screenshot_base64_len": len(state.get("screenshot", {}).get("base64", "")),
}
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
if not summary["textedit_marker_found"]:
    raise SystemExit("TextEdit marker was not found in AX tree")
PY

osascript -e 'tell application "Finder" to activate' >/dev/null
sleep 1
curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  -d '{"bundle_id":"com.apple.finder"}' \
  "$BASE_URL/state" >/tmp/cu-e2e-finder-state.json

python3 - "$BASE_URL" <<'PY'
import json
import subprocess
import sys

base_url = sys.argv[1]

def post(path, payload):
    result = subprocess.run(
        [
            "curl",
            "-fsS",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            json.dumps(payload),
            base_url + path,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout or "{}")

with open("/tmp/cu-e2e-finder-state.json") as file:
    state = json.load(file)

nodes = state["ax_tree"]["nodes"]
target = next((node for node in nodes if node.get("bounds")), None)
if target is None:
    raise SystemExit("no Finder AX node with bounds found")

bounds = target["bounds"]
post(
    "/actions/click",
    {
        "x": bounds["x"] + min(bounds["width"] / 2, 20),
        "y": bounds["y"] + min(bounds["height"] / 2, 20),
    },
)
post(
    "/actions/scroll",
    {
        "snapshot_id": state["snapshot_id"],
        "element_id": target["id"],
        "direction": "down",
        "pages": 1,
    },
)
post(
    "/actions/drag",
    {
        "from": {"x": bounds["x"] + 10, "y": bounds["y"] + 10},
        "to": {"x": bounds["x"] + 20, "y": bounds["y"] + 20},
    },
)
print(json.dumps({
    "finder_app": state.get("app", {}).get("name"),
    "finder_snapshot_id": state.get("snapshot_id"),
    "finder_ax_nodes": len(nodes),
    "finder_actions_ok": True,
}, ensure_ascii=False, sort_keys=True))
PY

echo "local agent e2e smoke passed"
