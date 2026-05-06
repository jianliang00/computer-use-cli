# Development

## Build And Test

```bash
swift build
swift test
```

Build individual products:

```bash
swift build -c release --product computer-use
swift build -c release --product computer-use-agent
swift build -c release --product bootstrap-agent
```

## Local Session-Agent Smoke

Run the local GUI-session smoke test:

```bash
scripts/smoke-local-agent-e2e.sh
```

This validates the session agent against the current host GUI session. It is a
developer check only; it does not validate guest image installation,
authorization persistence, or guest bootstrapping.

## Guest Plugin-Parity Smoke

Run the high-level CLI smoke test against an already started, authorized guest:

```bash
MACHINE=authorized-smoke scripts/smoke-guest-plugin-parity.sh
```

This uses `computer-use` commands only. It validates app-scoped state, indexed
element actions, modifier keys, text entry, set-value, AX actions, scroll, drag,
and the readable accessibility tree against the guest session.

## Package The Guest App

Create a local `ComputerUseAgent.app` bundle:

```bash
scripts/package-computer-use-agent-app.sh
```

Useful environment variables:

- `CONFIGURATION=debug|release`
- `APP_VERSION=<version>`
- `APP_BUILD=<build>`
- `MACOS_APP_BUNDLE_ID=<bundle-id>`

## Prepare Image Context

Generate a macOS image build context:

```bash
scripts/prepare-computer-use-image-context.sh
```

The generated context contains:

- `payload/ComputerUseAgent.app`
- `payload/bootstrap-agent`
- launchd plists
- guest install scripts
- a Dockerfile based on `local/macos-base:latest`

See [Guest Image](guest-image.md) for the full product and authorized image
flow.

## Release Artifacts

Build local release artifacts:

```bash
scripts/package-release-artifacts.sh 0.0.0 /tmp/computer-use-release
```

See [Releasing](releasing.md) for signing and notarization setup.

## Project Layout

```text
Sources/ComputerUseCLI/          Host commands and JSON output
Sources/ContainerBridge/         Guest runtime integration
Sources/AgentProtocol/           Shared protocol models
Sources/BootstrapAgent/          Guest boot diagnostics
Sources/ComputerUseAgentApp/     App bundle wrapper and HTTP server
Sources/ComputerUseAgentCore/    Permissions, apps, state, and actions
Tests/                           SwiftPM tests
images/macos/                    Guest image installation assets
scripts/                         Packaging and image helpers
```

## Validation Checklist

Before changing runtime, guest-agent, or packaging behavior:

```bash
swift test
scripts/package-release-artifacts.sh 0.0.0 /tmp/computer-use-release
```

For guest-image changes, also verify a fresh machine from the authorized image:

```bash
computer-use machine create --name authorized-smoke \
  --image ghcr.io/jianliang00/computer-use:v0.1.6
computer-use machine start --machine authorized-smoke
computer-use agent doctor --machine authorized-smoke
computer-use state get --machine authorized-smoke --app Finder
MACHINE=authorized-smoke scripts/smoke-guest-plugin-parity.sh
```

Do not treat a product image as user-ready until a fresh authorized-image guest
passes the permission and state checks.
