# Usage Reference

Use this reference for normal host-side `computer-use` workflows.

## Requirements

- Apple silicon Mac.
- macOS 15 or newer.
- Prepared macOS guest image. Default to `ghcr.io/jianliang00/computer-use:v0.1.6` unless the user provides another authorized image.
- Swift 6 only if invoking the CLI from a source checkout with `swift run`.

## Install Or Build

Install a release package:

```bash
sudo installer -pkg computer-use-<version>-macos-arm64.pkg -target /
computer-use --help
```

If the package is not installed but the user is inside this source checkout, invoke the CLI through SwiftPM:

```bash
swift run computer-use --help
```

## Runtime

The CLI owns a project-managed macOS guest runtime and does not require a global `/usr/local/bin/container`.

```bash
computer-use runtime info
computer-use runtime bootstrap
computer-use runtime container -- system status
```

Default runtime layout:

```text
~/Library/Application Support/computer-use-cli/container-sdk/0.0.4/
  app/
  install/
```

Runtime override environment variables:

```text
COMPUTER_USE_CONTAINER_SDK_VERSION
COMPUTER_USE_CONTAINER_RUNTIME_ROOT
COMPUTER_USE_CONTAINER_APP_ROOT
COMPUTER_USE_CONTAINER_INSTALL_ROOT
COMPUTER_USE_CONTAINER_BIN
COMPUTER_USE_CONTAINER_SDK_PKG_URL
```

If `machine start` reports another container runtime running with different roots, interactive runs prompt before restarting container services. In non-interactive runs, stop the existing runtime first:

```bash
computer-use runtime container -- system stop
```

## Machine Lifecycle

Create and start:

```bash
computer-use machine create --name demo --image ghcr.io/jianliang00/computer-use:v0.1.6
computer-use machine start --machine demo
```

Inspect and manage:

```bash
computer-use machine inspect --machine demo
computer-use machine list
computer-use machine logs --machine demo
computer-use machine stop --machine demo
computer-use machine rm --machine demo
```

`machine start --machine demo -- <command> [args...]` passes the command as the sandbox init process on first creation. If the sandbox already exists or is running, it starts/confirms the sandbox and then runs the command with `container exec`.

Machine metadata is stored under:

```text
~/.computer-use-cli/machines/<machine-name>/machine.json
```

Host agent ports are allocated from `46000...46999`. If a guest image does not support `--publish`, the CLI falls back to `container_exec` transport.

## Diagnostics

```bash
computer-use agent ping --machine demo
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
computer-use permissions request --machine demo
```

`agent doctor` reports sandbox state, agent transport, session-agent readiness, and Accessibility / Screen Recording permission state.

Expected permission success shape:

```json
{
  "accessibility": true,
  "screen_recording": true
}
```

## File Transfer

Push host file or directory into the guest:

```bash
computer-use files push \
  --machine demo \
  --src ./notes.txt \
  --dest ~/Desktop/notes.txt
```

Pull guest file or directory back to the host:

```bash
computer-use files pull \
  --machine demo \
  --src ~/Desktop/notes.txt \
  --dest ./notes-from-guest.txt
```

Transfers are chunked through the guest agent and verify byte count plus SHA-256. Default chunk size is 64 KiB; override with `--chunk-size <bytes>`.

By default, existing destination files are replaced and missing parent directories are created. Use `--overwrite false` or `--create-directories false` to fail instead. Guest paths may be under the guest user's home directory or `/tmp`.

## State Capture

List running GUI apps:

```bash
computer-use apps list --machine demo
```

Capture state for the frontmost app or a target app:

```bash
computer-use state get --machine demo
computer-use state get --machine demo --app TextEdit
computer-use state get --machine demo --bundle-id com.apple.TextEdit
computer-use state get --machine demo --app TextEdit --screenshot-output ./textedit.png
```

Prefer `--app` for user-facing workflows. Use `--bundle-id` when scripts intentionally target a stable bundle identifier.

`state get` returns:

- `snapshot_id`
- target `app` and optional `window`
- screenshot payload
- machine-readable `ax_tree`
- readable indexed `ax_tree_text`
- `focused_element` when available

Use `--screenshot-output <host-png>` to decode the screenshot base64 into a PNG while keeping the JSON response unchanged.

## Actions

Coordinate actions:

```bash
computer-use action click --machine demo --app TextEdit --x 120 --y 240
computer-use action drag --machine demo --app TextEdit --from-x 100 --from-y 100 --to-x 400 --to-y 300
computer-use action type --machine demo --app TextEdit --text "hello"
computer-use action key --machine demo --app TextEdit --key cmd+a
```

Element actions using indexes from `state get`:

```bash
computer-use action click --machine demo --app TextEdit --element-index <index>

computer-use action scroll --machine demo \
  --app TextEdit \
  --element-index <index> \
  --direction down \
  --pages 0.5

computer-use action set-value --machine demo \
  --app TextEdit \
  --element-index <index> \
  --value "new value"

computer-use action action --machine demo \
  --app TextEdit \
  --element-index <index> \
  --name AXPress
```

Supported key modifier aliases:

- Command: `super`, `cmd`, `command`, `meta`
- Shift: `shift`
- Option: `option`, `alt`
- Control: `control`, `ctrl`

Use combinations such as `cmd+shift+g`, `ctrl+a`, `Return`, and `Escape`.

Mouse button `middle` is accepted as a compatibility alias for `center`.

## Snapshot Rules

Element actions can use:

- `[--snapshot-id <id>] --element-index <n>`
- `--snapshot-id <id> --element-id <id>`

`--element-index` without `--snapshot-id` resolves against the latest unexpired snapshot for `--app` when an app target is provided; otherwise it resolves against the latest unexpired snapshot overall.

Snapshots are short-lived. The guest keeps up to 8 snapshots for roughly 60 seconds. If an element action returns `snapshot_expired`, run `state get` again and use fresh indexes or IDs. If a supplied `--snapshot-id` belongs to a different app than `--app`, the action fails rather than applying an index to the wrong app.
