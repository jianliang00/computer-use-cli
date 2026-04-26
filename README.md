# Computer Use CLI

SwiftPM implementation of a host-side CLI for managing macOS guest machines and
forwarding computer-use commands to a session agent running inside the guest.

## Verified Capabilities

- `swift build` and `swift test` pass.
- Machine metadata is stored under
  `~/.computer-use-cli/machines/<machine-name>/machine.json`.
- Host ports are allocated from `46000...46999` and duplicate requested ports
  are rejected.
- `ContainerBridge` wraps the `container` CLI for create, start, inspect, stop,
  delete, logs, and published port lookup.
- `ContainerBridge` no longer assumes a host-level `/usr/local/bin/container`.
  By default it bootstraps the published `jianliang00/container` SDK release into an
  isolated project-owned root under
  `~/Library/Application Support/computer-use-cli/container-sdk/0.0.4/` and
  starts `container-apiserver` with that app/install root.
- Machine lifecycle commands are implemented:
  - `computer-use machine create --name <name> --image <image> [--host-port <port>]`
  - `computer-use machine start --machine <name> [-- <command> [args...]]`
  - `computer-use machine inspect --machine <name>`
  - `computer-use machine stop --machine <name>`
  - `computer-use machine list`
  - `computer-use machine logs --machine <name>`
  - `computer-use machine rm --machine <name>`
- Agent protocol JSON models cover health, permissions, apps, state, actions,
  and protocol errors.
- Host-side agent forwarding commands are implemented:
  - `computer-use agent ping --machine <name>`
  - `computer-use agent doctor --machine <name>`
  - `computer-use permissions get --machine <name>`
  - `computer-use permissions request --machine <name>`
  - `computer-use apps list --machine <name>`
  - `computer-use state get --machine <name> [--bundle-id <bundle-id>]`
  - `computer-use action click --machine <name> (--x <x> --y <y> | --snapshot-id <id> --element-id <id>)`
  - `computer-use action type --machine <name> --text <text>`
  - `computer-use action key --machine <name> --key <key>`
  - `computer-use action drag --machine <name> --from-x <x> --from-y <y> --to-x <x> --to-y <y>`
  - `computer-use action scroll --machine <name> --snapshot-id <id> --element-id <id> --direction <up|down|left|right> [--pages <n>]`
  - `computer-use action set-value --machine <name> --snapshot-id <id> --element-id <id> --value <value>`
  - `computer-use action action --machine <name> --snapshot-id <id> --element-id <id> --name <AXAction>`
- `computer-use-agent` starts a guest-side HTTP server on port `7777`.
- `scripts/package-computer-use-agent-app.sh` builds `ComputerUseAgent.app`
  with bundle id `io.github.jianliang00.computer-use.agent`.
- `scripts/prepare-computer-use-image-context.sh` prepares a macOS image build
  context with the app bundle, bootstrap agent, launchd plists, installer
  scripts, and Dockerfile.
- `scripts/smoke-local-agent-e2e.sh` runs a local end-to-end smoke against the
  session agent. It verifies TextEdit input/state/action flows and Finder
  click/scroll/drag flows.
- `bootstrap-agent` refreshes and persists bootstrap status JSON.
- LaunchDaemon/LaunchAgent plist templates live under `images/macos/launchd/`.
- Guest live install validation is documented in
  `docs/guest-image-validation.md`; it verifies launchd ownership, LaunchDaemon
  and LaunchAgent registration, `GET /health`, `GET /permissions`, `GET /apps`,
  expected `/state` permission denial, and `bootstrap-status.json`
  `bootstrapped: true` inside a cloned macOS guest.
- The validated macOS base has been packaged and loaded as
  `local/macos-base:latest`.
- `local/computer-use:product` builds successfully from that base and can be
  started by the macOS container runtime. The product image seeds
  `autoLoginUser=admin` and `/etc/kcpassword` for the local `admin/admin`
  validation account, and disables guest sleep, display sleep, and screensaver
  password prompts so the automation session stays reachable.
- `local/computer-use:authorized` has been packaged from an authorized product
  guest and loaded locally. A fresh guest created from that image auto-logs in
  as `admin`, starts `ComputerUseAgent.app`, returns
  `{"accessibility":true,"screen_recording":true}`, and serves `/state` with a
  PNG screenshot plus Finder AX tree.
- macOS images that cannot use `--publish` are handled by falling back to
  `container exec` transport for agent HTTP requests.
- macOS images packaged without a default entrypoint are handled by retrying
  sandbox creation with a keepalive init command (`/usr/bin/tail -f /dev/null`), so
  fresh `machine start` no longer fails immediately with
  `command/entrypoint not specified for container process`.
- The `container_exec` transport drains subprocess stdout/stderr while commands
  are running, so large `/state` responses with screenshots can be returned
  without hitting the macOS runtime attachment buffer limit.
- A real CLI smoke against `local/computer-use:authorized` validates
  machine create/start, `agent ping`, `agent doctor`, permissions, apps,
  Finder state capture, and Finder scroll/click actions.
- A live authorized guest updated with the latest agent build validates the
  TextEdit workflow end to end: `/apps` lists `com.apple.TextEdit`,
  `state get --bundle-id com.apple.TextEdit` returns a TextEdit snapshot, and
  `action type` updates the `AXTextArea` value.
- The session agent implements:
  - `GET /health`
  - `GET /permissions` using macOS Accessibility and Screen Recording checks
  - `POST /permissions/request` to re-trigger TCC prompts after replacing the
    agent app bundle
  - `GET /apps` using `NSWorkspace` plus a process-table fallback for GUI apps
    that do not surface in the workspace list
  - `POST /state` using ScreenCaptureKit for PNG screenshots and AX APIs for
    a basic accessibility tree, targeting the requested bundle id when one is
    supplied
  - snapshot cache with 8-snapshot capacity and 60-second TTL
  - `click`, `type`, `key`, `drag`, and `scroll` through CoreGraphics
  - `set-value` and AX `action` through cached snapshot elements

## Remaining Work

- The current `local/computer-use:authorized` image was traced to a stale
  `/usr/local/bin/container-macos-guest-agent` (`c6e6d2...`). Updating the same
  stopped clone to the guest-agent from the active container SDK build
  (`fee5e8...`) makes `container start` succeed: both `__guest-agent-log__` and
  the workload pass `process.start` on the first attempt. The remaining image
  work is repackaging `local/computer-use:authorized` from a clean authorized
  guest with the project-owned container SDK guest-agent installed.

## Container Runtime

`computer-use-cli` owns its container runtime root. A normal user should not
need to install or configure `container` before running this project.

- Default SDK version: `0.0.4`
- Default runtime root:
  `~/Library/Application Support/computer-use-cli/container-sdk/0.0.4/`
- Default app root: `<runtime-root>/app`
- Default install root: `<runtime-root>/install`
- Default CLI binary: `<install-root>/bin/container`

The first real container command downloads
`https://github.com/jianliang00/container/releases/download/0.0.4/container-installer-unsigned.pkg`,
extracts it without installing into `/usr/local`, and copies the CLI, apiserver,
plugins, sidecar, VM manager, and guest-agent into the project-owned install
root. If another `container` apiserver is already running with a different root,
the command fails with a root mismatch instead of reusing that runtime.

Runtime overrides:

- `COMPUTER_USE_CONTAINER_SDK_VERSION`
- `COMPUTER_USE_CONTAINER_RUNTIME_ROOT`
- `COMPUTER_USE_CONTAINER_APP_ROOT`
- `COMPUTER_USE_CONTAINER_INSTALL_ROOT`
- `COMPUTER_USE_CONTAINER_BIN`
- `COMPUTER_USE_CONTAINER_SDK_PKG_URL`

Useful runtime commands:

- `swift run computer-use runtime info`
- `swift run computer-use runtime bootstrap`
- `swift run computer-use runtime container -- <container-args...>`

Use the `runtime container --` wrapper for raw SDK operations such as image
build, package, load, and list. It uses the same project-owned SDK root as
`machine` commands and does not require `container` to be installed on `PATH`.
