# Computer Use Plugin Parity Plan

This document tracks the work needed for the `computer-use` CLI to align with
the currently exposed Computer Use plugin capabilities. The goal is parity for
core app-scoped inspection and interaction commands, not higher-level workflow
shortcuts.

## Scope

Target plugin capabilities:

- `list_apps`
- `get_app_state`
- `click`
- `type_text`
- `press_key`
- `scroll`
- `drag`
- `set_value`
- `perform_secondary_action`

Non-goals for this parity pass:

- Do not add browser-specific convenience commands such as `browser search`,
  `open url`, or `google search`.
- Do not rely on low-level runtime escape hatches for normal workflows.
- Do not remove the existing `snapshot_id` and `element_id` automation surface.

## P0: App-Scoped Control

- [x] Add a shared `--app <name-or-bundle-id>` argument for `state get` and all
  `action` subcommands.
- [x] Add guest-agent app resolution for bundle identifiers, app names, and
  localized names.
- [x] Return a structured ambiguity error when an app target matches multiple
  candidates.
- [x] Add an app activation endpoint that activates a running app or launches it
  when it is not running.
- [x] Poll for the target app to become frontmost and expose a window after
  launch or activation, with a fallback for apps that do not expose one.
- [x] Make `state get --app ...` ensure the target app is active before
  capturing state.
- [x] Make `action * --app ...` ensure the target app is active before sending
  input.
- [x] Keep `--bundle-id` compatibility for existing `state get` scripts while
  documenting `--app` as the preferred user-facing target.

## P0: Element Indexes

- [x] Add stable element indexes to `state get` output for the current snapshot.
- [x] Preserve the existing `snapshot_id` and `element_id` fields in JSON output.
- [x] Add CLI support for `--element-index <index>` wherever an element target is
  currently accepted.
- [x] Resolve `--element-index` to the corresponding `element_id` from the most
  recent unexpired snapshot.
- [x] Scope latest `--element-index` lookup by app when app metadata is
  available.
- [x] Support explicit `--snapshot-id` with `--element-index` for deterministic
  scripts.
- [x] Return a clear error when an element index is unknown or expired.
- [x] Return a clear error when an element index belongs to a different app
  snapshot.

## P0: Keyboard Parity

- [x] Extend the public protocol `KeyActionRequest` to include key modifiers.
- [x] Reuse the existing guest core modifier support for command, shift, option,
  and control.
- [x] Parse plugin-style key combinations such as `super+c`, `cmd+shift+g`,
  `ctrl+a`, `Return`, and `Escape`.
- [x] Treat `super`, `cmd`, and `meta` as aliases for the macOS command key.
- [x] Keep plain key input compatible with the current `action key --key Return`
  behavior.

## P1: Action Parity

- [x] Add `action click --app ... --element-index ...` in addition to coordinate
  clicks.
- [x] Confirm mouse button naming and support `middle` as a compatibility alias
  for the current `center` value.
- [x] Add `action scroll --app ... --element-index ... --pages <number>` with
  fractional page support.
- [x] Add `action set-value --app ... --element-index ... --value ...`.
- [x] Add `action action --app ... --element-index ... --name <AXAction>` for
  secondary accessibility actions.
- [x] Keep coordinate click, drag, and type actions available without an element
  target.
- [x] Make all app-scoped actions return consistent JSON receipts.

## P1: State Output

- [x] Make `state get --app ...` output a readable indexed accessibility tree in
  addition to machine-readable JSON fields.
- [x] Include focused element metadata when available.
- [x] Keep screenshot payloads available for automation clients.
- [x] Document how snapshot expiration interacts with element indexes.

## P2: App History

- [x] Keep `apps list` output stable for currently running guest apps.
- [x] Add a lightweight guest-side app usage store for parity with plugin
  `last-used` and `uses` fields.
- [x] Record usage when an app is launched, activated, or inspected through the
  CLI.
- [x] Add a retention window matching the plugin-style recent app list.
- [x] Clearly distinguish running apps from recently used but not currently
  running apps.

## Tests

- [x] Add protocol round-trip tests for app targets, key modifiers, scroll
  numbers, and element index metadata.
- [x] Add CLI parser tests for `--app`, `--element-index`, key combinations, and
  fractional pages.
- [x] Add guest core tests for app resolution and ambiguous matches.
- [x] Add guest core tests for activation, inspection usage recording, app
  history merging, and retention.
- [x] Add state snapshot tests for index generation, lookup, and expiration.
- [x] Add state snapshot tests for app mismatch errors.
- [x] Add local GUI smoke coverage for launching or activating a simple app,
  reading state, typing text, pressing a modifier key combination, clicking an
  indexed element, setting a value, and invoking an AX action.
- [x] Add real guest smoke coverage for launching or activating a simple app,
  reading state, typing text, pressing a modifier key combination, clicking an
  indexed element, setting a value, and invoking an AX action.

## Documentation

- [x] Update `README.md` quick start examples to use app-scoped commands.
- [x] Update `docs/usage.md` with plugin-style state and action workflows.
- [x] Document compatibility between `--app`, `--bundle-id`, `--snapshot-id`,
  `--element-id`, and `--element-index`.
- [x] Document current non-goals so users do not expect browser-specific
  shortcuts in this parity pass.
