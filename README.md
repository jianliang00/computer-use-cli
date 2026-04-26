# Computer Use CLI

[![Version](https://img.shields.io/github/v/release/jianliang00/computer-use-cli?sort=semver&label=version)](https://github.com/jianliang00/computer-use-cli/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/jianliang00/computer-use-cli/release.yml?label=build)](https://github.com/jianliang00/computer-use-cli/actions/workflows/release.yml)
![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple)
![Architecture](https://img.shields.io/badge/architecture-Apple%20silicon-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

Run computer-use automation against a macOS guest from your Mac terminal.

`computer-use` lets you create a disposable macOS guest, inspect what is
running in that guest, capture screen and accessibility state, and send UI
actions such as click, type, key, drag, scroll, and accessibility actions.

## When To Use It

Use this project when you want to:

- Drive macOS apps in an isolated guest instead of your main desktop.
- Inspect app UI state as screenshot plus accessibility tree data.
- Run repeatable UI automation commands from a terminal or higher-level agent.

## What You Need

- Apple silicon Mac.
- macOS 15 or newer.
- A prepared macOS guest image, for example `ghcr.io/jianliang00/computer-use:v0.1`.
- Swift 6 only if you are building from source.

The guest image must already be prepared for computer-use and authorized for
Accessibility and Screen Recording. See [Guest Image](docs/guest-image.md) if
you need to build that image.

## Install

Download `computer-use-<version>-macos-arm64.pkg` from a GitHub release.

Manual install:

1. Open the `.pkg` file in Finder.
2. Follow the macOS Installer prompts.
3. Verify the install:

```bash
computer-use --help
```

Command-line install:

```bash
sudo installer -pkg computer-use-<version>-macos-arm64.pkg -target /
computer-use --help
```

This installs:

```text
/usr/local/bin/computer-use
```

You do not need to install any additional command-line tools before using
`computer-use`.

## Quick Start

Create and start a guest:

```bash
computer-use machine create --name demo --image ghcr.io/jianliang00/computer-use:v0.1
computer-use machine start --machine demo
```

Check that the guest is ready:

```bash
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
```

List running apps and capture UI state:

```bash
computer-use apps list --machine demo
computer-use state get --machine demo --app TextEdit
```

Send basic actions:

```bash
computer-use action click --machine demo --app TextEdit --x 120 --y 240
computer-use action type --machine demo --app TextEdit --text "hello"
computer-use action key --machine demo --app TextEdit --key cmd+a
```

`state get` returns a `snapshot_id`, element IDs, and element indexes. Use
element indexes for plugin-style element-targeted actions:

```bash
computer-use action click --machine demo \
  --app TextEdit \
  --element-index <element-index>
```

## Common Commands

Manage guests:

```bash
computer-use machine list
computer-use machine inspect --machine demo
computer-use machine logs --machine demo
computer-use machine stop --machine demo
computer-use machine rm --machine demo
```

Inspect guest readiness:

```bash
computer-use agent ping --machine demo
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
```

Run UI actions:

```bash
computer-use action drag --machine demo --app TextEdit --from-x 100 --from-y 100 --to-x 400 --to-y 300
computer-use action scroll --machine demo --app TextEdit --element-index <element-index> --direction down --pages 0.5
computer-use action set-value --machine demo --app TextEdit --element-index <element-index> --value "new value"
computer-use action action --machine demo --app TextEdit --element-index <element-index> --name AXPress
```

## Which Release File Should I Download?

- `computer-use-<version>-macos-arm64.pkg`: install this on the host Mac.
- `computer-use-guest-kit-<version>-macos-arm64.pkg`: use this only when
  building or repairing a macOS guest image.
- `*.tar.gz`: raw payload archives for advanced packaging workflows.

Normal users should not install the guest kit inside every guest. They should
run against a prepared authorized image.

## Build From Source

```bash
swift build
swift test
swift run computer-use --help
```

## Documentation

- [Usage](docs/usage.md): command reference and normal workflows.
- [Guest Image](docs/guest-image.md): build the prepared macOS guest image.
- [Releasing](docs/releasing.md): signed and notarized release packages.
- [Development](docs/development.md): local development and validation.
- [Architecture](docs/architecture.md): technical design.
