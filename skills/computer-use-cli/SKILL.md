---
name: computer-use-cli
description: "Use when an agent needs to help a user use the `computer-use` CLI for isolated macOS guest automation: installing or verifying the CLI, bootstrapping the project-owned guest runtime, creating/starting/inspecting/stopping/removing macOS guest machines, checking agent readiness and macOS privacy permissions, listing guest apps, capturing screenshots plus accessibility state, transferring files, sending click/type/key/drag/scroll/set-value/AX actions, preparing or validating an authorized guest image, and troubleshooting runtime, permission, snapshot, or UI-action issues."
---

# Computer Use CLI

## Overview

Use this skill to help users operate macOS applications inside an isolated guest through the host-side `computer-use` command. Prefer the documented CLI surface over low-level runtime escape hatches, and keep normal workflows centered on prepared, already-authorized guest images.

Default image: use `ghcr.io/jianliang00/computer-use:v0.1.6` unless the user provides a different authorized image.

## Workflow

1. Decide which reference to load:
   - Load [usage.md](references/usage.md) for installation, runtime, machine lifecycle, app state, file transfer, and UI actions.
   - Load [guest-image.md](references/guest-image.md) only when the user needs to prepare, authorize, validate, package, or troubleshoot a macOS guest image.
2. Verify the execution context:
   - Use the installed `computer-use` command for normal workflows.
   - If the user is in this repository and has not installed the package, use `swift run computer-use ...` only as a way to invoke the CLI.
   - Expect JSON output from normal `computer-use` commands.
3. For guest automation, follow the loop:
   - Create/start a machine from an authorized image.
   - Run `agent doctor` and `permissions get`.
   - Capture state with `state get`, preferably scoped by `--app`.
   - Choose coordinates or element indexes from the returned state.
   - Run actions and re-capture state when the UI may have changed.
4. For element-targeted actions, prefer `--element-index` from the latest `state get` result. Use `--snapshot-id` plus `--element-id` when writing deterministic scripts that must bind to an exact snapshot.

## Operating Guardrails

- Do not ask normal users to install the guest kit in every VM. Use a prepared authorized image for routine runs.
- Do not change guest app path, bundle id, launchd identifiers, guest user, code-signing identity, or agent port casually. These are part of the macOS privacy permission model.
- Do not modify the TCC database or rely on configuration-profile bypasses. Permissions are granted once in the product guest GUI, then packaged into an authorized image.
- Prefer `--app <name-or-bundle-id>` for user-facing automation. Keep `--bundle-id` for scripts that intentionally target a fixed bundle identifier.
- If an element action returns `snapshot_expired`, run `state get` again and use fresh indexes or IDs.
- If `machine start` encounters a runtime-root mismatch in a non-interactive context, stop the other runtime explicitly with `computer-use runtime container -- system stop` before retrying.

## Common Command Skeleton

```bash
computer-use machine create --name demo --image ghcr.io/jianliang00/computer-use:v0.1.6
computer-use machine start --machine demo
computer-use agent doctor --machine demo
computer-use permissions get --machine demo
computer-use apps list --machine demo
computer-use state get --machine demo --app TextEdit --screenshot-output ./textedit.png
computer-use action click --machine demo --app TextEdit --element-index <index>
computer-use action type --machine demo --app TextEdit --text "hello"
computer-use action key --machine demo --app TextEdit --key cmd+a
```
