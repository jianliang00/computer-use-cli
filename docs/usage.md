# Usage

This page covers the normal host-side workflow for `computer-use`.

## Install

Install the release package:

```bash
sudo installer -pkg computer-use-<version>-macos-arm64.pkg -target /
```

Or build from source and use the SwiftPM binary:

```bash
swift build -c release --product computer-use
.build/release/computer-use --help
```

## Runtime

`computer-use` owns an isolated macOS guest runtime. The first machine or
runtime command prepares it automatically; explicit preparation is also
available:

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

Advanced runtime overrides. The names match the current implementation
environment variables:

- `COMPUTER_USE_CONTAINER_SDK_VERSION`
- `COMPUTER_USE_CONTAINER_RUNTIME_ROOT`
- `COMPUTER_USE_CONTAINER_APP_ROOT`
- `COMPUTER_USE_CONTAINER_INSTALL_ROOT`
- `COMPUTER_USE_CONTAINER_BIN`
- `COMPUTER_USE_CONTAINER_SDK_PKG_URL`

If `runtime container -- system status` reports a root mismatch, another
container runtime is already running with different roots. Stop that runtime
before using this project.

The raw `runtime container -- ...` command is mainly for development and image
workflows. Normal users should not need to learn or install a separate
`container` CLI.

## Machine Lifecycle

Create a machine from an authorized guest image:

```bash
computer-use machine create --name demo --image local/computer-use:authorized
computer-use machine start --machine demo
```

Inspect and manage it:

```bash
computer-use machine inspect --machine demo
computer-use machine list
computer-use machine logs --machine demo
computer-use machine stop --machine demo
computer-use machine rm --machine demo
```

Machine metadata is stored under:

```text
~/.computer-use-cli/machines/<machine-name>/machine.json
```

Host agent ports are allocated from `46000...46999`. On macOS guest images that
do not support `--publish`, the CLI automatically falls back to
`container_exec` transport.

## Agent Diagnostics

```bash
computer-use agent ping --machine demo
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
computer-use permissions request --machine demo
```

`agent doctor` reports sandbox state, agent transport, session-agent readiness,
and Accessibility / Screen Recording permission state.

## State And Actions

List running GUI apps:

```bash
computer-use apps list --machine demo
```

Capture state for the frontmost app or a target bundle:

```bash
computer-use state get --machine demo
computer-use state get --machine demo --bundle-id com.apple.TextEdit
```

Run coordinate actions:

```bash
computer-use action click --machine demo --x 120 --y 240
computer-use action drag --machine demo --from-x 100 --from-y 100 --to-x 400 --to-y 300
computer-use action type --machine demo --text "hello"
computer-use action key --machine demo --key Return
```

Run element actions using IDs from `state get`:

```bash
computer-use action click --machine demo \
  --snapshot-id <snapshot-id> \
  --element-id <element-id>

computer-use action scroll --machine demo \
  --snapshot-id <snapshot-id> \
  --element-id <element-id> \
  --direction down \
  --pages 1

computer-use action set-value --machine demo \
  --snapshot-id <snapshot-id> \
  --element-id <element-id> \
  --value "new value"

computer-use action action --machine demo \
  --snapshot-id <snapshot-id> \
  --element-id <element-id> \
  --name AXPress
```

Snapshots are short-lived. If an element action returns `snapshot_expired`, call
`state get` again and use the new IDs.
