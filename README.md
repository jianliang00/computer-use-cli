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

## Remaining Work

- Implement the guest `ComputerUseAgent.app` HTTP server.
- Implement real Accessibility and Screen Recording permission checks.
- Implement real running app enumeration, screenshots, AX tree capture, snapshot
  cache, and UI input/action execution.
- Implement bootstrap status refresh/persistence.
- Add macOS image build/install assets, authorized image flow, and end-to-end
  validation.
