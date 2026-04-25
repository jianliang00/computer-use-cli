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
- The session agent implements:
  - `GET /health`
  - `GET /permissions` using macOS Accessibility and Screen Recording checks
  - `GET /apps` using `NSWorkspace`
  - `POST /state` using ScreenCaptureKit for PNG screenshots and AX APIs for
    a basic accessibility tree
  - snapshot cache with 8-snapshot capacity and 60-second TTL
  - `click`, `type`, `key`, `drag`, and `scroll` through CoreGraphics
  - `set-value` and AX `action` through cached snapshot elements

## Remaining Work

- Build the product image once a local darwin/arm64 macOS base image tag is
  available to `container build`.
- Seed auto-login and complete the authorized image flow for Accessibility and
  Screen Recording.
- Validate the full host-side macOS machine lifecycle against the product or
  authorized image.
