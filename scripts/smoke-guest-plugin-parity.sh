#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACHINE="${MACHINE:-${1:-authorized-smoke}}"
COMPUTER_USE_BIN="${COMPUTER_USE_BIN:-$ROOT_DIR/.build/debug/computer-use}"
MARKER="cu-cli-guest-smoke-$(date +%s)"
SET_VALUE_MARKER="$MARKER-set-value"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/computer-use-guest-smoke.XXXXXX")"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
if [[ ! -x "$COMPUTER_USE_BIN" ]]; then
  swift build --product computer-use >/dev/null
fi

cu() {
  "$COMPUTER_USE_BIN" "$@"
}

extract_textedit_indexes() {
  python3 - "$1" >"$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    state = json.load(file)

nodes = state.get("ax_tree", {}).get("nodes", [])
text_node = next(
    (
        node
        for node in nodes
        if "AXText" in str(node.get("role")) and node.get("bounds") and node.get("index") is not None
    ),
    None,
)
if text_node is None:
    text_node = next((node for node in nodes if node.get("bounds") and node.get("index") is not None), None)
if text_node is None:
    raise SystemExit("no indexed TextEdit AX node with bounds found")

window_node = next(
    (node for node in nodes if node.get("role") == "AXWindow" and node.get("index") is not None),
    None,
)

print(f"TEXT_INDEX={int(text_node['index'])}")
if window_node is not None:
    print(f"WINDOW_INDEX={int(window_node['index'])}")
PY
}

extract_finder_target() {
  python3 - "$1" >"$2" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    state = json.load(file)

target = next(
    (
        node
        for node in state.get("ax_tree", {}).get("nodes", [])
        if node.get("bounds") and node.get("index") is not None
    ),
    None,
)
if target is None:
    raise SystemExit("no indexed Finder AX node with bounds found")

bounds = target["bounds"]
x = bounds["x"] + min(bounds["width"] / 2, 20)
y = bounds["y"] + min(bounds["height"] / 2, 20)
print(f"FINDER_INDEX={int(target['index'])}")
print(f"FINDER_X={x}")
print(f"FINDER_Y={y}")
print(f"FINDER_TO_X={x + 10}")
print(f"FINDER_TO_Y={y + 10}")
PY
}

cu apps list --machine "$MACHINE" >"$WORK_DIR/apps.json"
cu state get --machine "$MACHINE" --app TextEdit >"$WORK_DIR/textedit-launch.json"
cu action key --machine "$MACHINE" --app TextEdit --key cmd+n >"$WORK_DIR/textedit-new-document.json"
sleep 1
cu state get --machine "$MACHINE" --app TextEdit >"$WORK_DIR/textedit-before.json"
extract_textedit_indexes "$WORK_DIR/textedit-before.json" "$WORK_DIR/textedit-indexes.env"
. "$WORK_DIR/textedit-indexes.env"

cu action click --machine "$MACHINE" --app TextEdit --element-index "$TEXT_INDEX" >"$WORK_DIR/textedit-click.json"
cu action type --machine "$MACHINE" --app TextEdit --text "$MARKER" >"$WORK_DIR/textedit-type.json"
cu action key --machine "$MACHINE" --app TextEdit --key cmd+a >"$WORK_DIR/textedit-key.json"

unset TEXT_INDEX WINDOW_INDEX
cu state get --machine "$MACHINE" --app TextEdit >"$WORK_DIR/textedit-before-set-value.json"
extract_textedit_indexes "$WORK_DIR/textedit-before-set-value.json" "$WORK_DIR/textedit-indexes.env"
. "$WORK_DIR/textedit-indexes.env"

cu action set-value \
  --machine "$MACHINE" \
  --app TextEdit \
  --element-index "$TEXT_INDEX" \
  --value "$SET_VALUE_MARKER" >"$WORK_DIR/textedit-set-value.json"

if [[ -n "${WINDOW_INDEX:-}" ]]; then
  cu action action \
    --machine "$MACHINE" \
    --app TextEdit \
    --element-index "$WINDOW_INDEX" \
    --name AXRaise >"$WORK_DIR/textedit-action.json"
fi

sleep 1
cu state get --machine "$MACHINE" --app TextEdit >"$WORK_DIR/textedit-after.json"

python3 - "$WORK_DIR/textedit-after.json" "$SET_VALUE_MARKER" <<'PY'
import json
import sys

state_path, marker = sys.argv[1:3]
with open(state_path) as file:
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
    "textedit_ax_tree_text": bool(state.get("ax_tree_text")),
    "textedit_has_focused_element": bool(state.get("focused_element")),
    "textedit_screenshot_base64_len": len(state.get("screenshot", {}).get("base64", "")),
}
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
if not summary["textedit_marker_found"]:
    raise SystemExit("TextEdit marker was not found in AX tree")
if not summary["textedit_ax_tree_text"]:
    raise SystemExit("TextEdit state did not include ax_tree_text")
PY

cu state get --machine "$MACHINE" --app Finder >"$WORK_DIR/finder-state.json"
extract_finder_target "$WORK_DIR/finder-state.json" "$WORK_DIR/finder-target.env"
. "$WORK_DIR/finder-target.env"

cu action click --machine "$MACHINE" --app Finder --x "$FINDER_X" --y "$FINDER_Y" >"$WORK_DIR/finder-click.json"

cu state get --machine "$MACHINE" --app Finder >"$WORK_DIR/finder-scroll-state.json"
extract_finder_target "$WORK_DIR/finder-scroll-state.json" "$WORK_DIR/finder-target.env"
. "$WORK_DIR/finder-target.env"

cu action scroll \
  --machine "$MACHINE" \
  --app Finder \
  --element-index "$FINDER_INDEX" \
  --direction down \
  --pages 0.5 >"$WORK_DIR/finder-scroll.json"
cu action drag \
  --machine "$MACHINE" \
  --app Finder \
  --from-x "$FINDER_X" \
  --from-y "$FINDER_Y" \
  --to-x "$FINDER_TO_X" \
  --to-y "$FINDER_TO_Y" >"$WORK_DIR/finder-drag.json"

echo "guest plugin parity smoke passed for machine $MACHINE"
