# Local Agent E2E Validation

Run:

```sh
scripts/smoke-local-agent-e2e.sh
```

Latest verified result:

- `swift build --product computer-use-agent` succeeded.
- `GET /health`, `GET /permissions`, and `GET /apps` succeeded against `127.0.0.1:7777`.
- TextEdit flow succeeded:
  - opened a temporary document
  - captured `/state`
  - clicked a cached AX text element
  - typed text
  - sent `Return`
  - used `set-value`
  - executed `AXRaise`
  - captured `/state` again and found the marker in the AX tree
- Finder flow succeeded:
  - captured `/state`
  - sent coordinate click
  - sent scroll
  - sent drag

Scope:

- This validates the session agent in the local host GUI session.
- It does not validate guest image installation, authorized image creation, or guest bootstrapping.
