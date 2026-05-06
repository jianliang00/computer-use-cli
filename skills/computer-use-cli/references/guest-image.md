# Guest Image Reference

Use this reference for building, authorizing, validating, packaging, or troubleshooting macOS guest images.

## Image Layers

The project uses three image layers:

1. Base image: clean macOS guest image that boots under the project-owned `container` runtime.
2. Product image: base image plus `ComputerUseAgent.app`, `bootstrap-agent`, launchd plists, auto-login, and no-sleep configuration.
3. Authorized image: product image booted once, granted macOS privacy permissions, validated, then packaged for reuse.

Normal non-debug use should run from:

```text
ghcr.io/jianliang00/computer-use:v0.1.6
```

Do not tell normal users to install the guest kit manually inside every guest VM.

## Fixed Guest Layout

Product and authorized images contain:

```text
/Applications/ComputerUseAgent.app
/usr/local/libexec/computer-use/bootstrap-agent
/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist
/Library/LaunchAgents/io.github.jianliang00.computer-use.agent.plist
/var/run/computer-use/bootstrap-status.json
```

Stable identities:

- App bundle id: `com.jianliang00.computer-use-cli`
- Bootstrap LaunchDaemon: `io.github.jianliang00.computer-use.bootstrap`
- Session LaunchAgent: `io.github.jianliang00.computer-use.agent`
- Guest user: `admin`
- Agent port: `127.0.0.1:7777`

Do not change these after producing an authorized image unless the image will be re-authorized and rebuilt. macOS privacy permissions are bound to stable app identity, path, user session, and signing identity.

## Build Product Image

Bootstrap the runtime:

```bash
computer-use runtime bootstrap
computer-use runtime container -- system status
```

Prepare or load a base image. The local Dockerfile reference is:

```text
local/macos-base:latest
```

If building an image from this checkout, generate the build context first:

```bash
scripts/prepare-computer-use-image-context.sh
```

Build the product image:

```bash
computer-use runtime container -- build \
  --platform darwin/arm64 \
  -f .build/computer-use-image-context/Dockerfile \
  -t local/computer-use:product \
  --progress plain \
  .build/computer-use-image-context
```

The Dockerfile installs the guest payload and configures:

- `admin/admin` auto-login.
- LaunchDaemon and LaunchAgent startup.
- Guest sleep, display sleep, and screensaver password prompts disabled.
- Keepalive command for runtimes that require a default process.

## Authorize Product Guest

Create and start a temporary authorization machine:

```bash
computer-use machine create --name computer-use-authorize \
  --image local/computer-use:product

computer-use machine start --machine computer-use-authorize
```

After the guest logs in as `admin`, check readiness:

```bash
computer-use agent ping --machine computer-use-authorize
computer-use agent doctor --machine computer-use-authorize
computer-use permissions get --machine computer-use-authorize
```

In the guest GUI, grant `/Applications/ComputerUseAgent.app`:

- Privacy & Security > Accessibility
- Privacy & Security > Screen & System Audio Recording

If the permission prompt needs to be reopened:

```bash
computer-use permissions request --machine computer-use-authorize
```

Expected permission state:

```json
{
  "accessibility": true,
  "screen_recording": true
}
```

## Validate Authorized Guest

Run a minimal smoke before packaging:

```bash
computer-use apps list --machine computer-use-authorize
computer-use state get --machine computer-use-authorize --bundle-id com.apple.finder
```

Validation criteria:

- `agent ping` returns `ok: true`.
- `agent doctor` reports `session_agent_ready: true`.
- `permissions get` reports both permissions as true.
- `apps list` returns GUI applications.
- `state get` returns a PNG screenshot and AX tree.
- At least one basic action returns `ok: true`.

## Package Authorized Image

Package the authorized container directory as a reusable image:

```bash
computer-use runtime container -- macos package \
  --input "$COMPUTER_USE_CONTAINER_APP_ROOT/containers/<authorized-container>" \
  --output /tmp/computer-use-authorized.oci.tar \
  --reference ghcr.io/jianliang00/computer-use:v0.1.6

computer-use runtime container -- image load \
  --input /tmp/computer-use-authorized.oci.tar
```

If `COMPUTER_USE_CONTAINER_APP_ROOT` is not set, read the default `app_root` from:

```bash
computer-use runtime info
```

Confirm the image exists:

```bash
computer-use runtime container -- image inspect ghcr.io/jianliang00/computer-use:v0.1.6
```

## Verify Fresh Guest

Create a new machine from the packaged image:

```bash
computer-use machine create --name authorized-smoke \
  --image ghcr.io/jianliang00/computer-use:v0.1.6

computer-use machine start --machine authorized-smoke
computer-use agent doctor --machine authorized-smoke
computer-use permissions get --machine authorized-smoke
computer-use apps list --machine authorized-smoke
computer-use state get --machine authorized-smoke --bundle-id com.apple.finder
```

The fresh guest must already be authorized. If either permission is false, do not publish that image.

## Troubleshooting

If the agent is unreachable:

- Confirm the guest booted and auto-logged in as `admin`.
- Check `/var/run/computer-use/bootstrap-status.json` inside the guest.
- Check `/Users/admin/Library/Logs/ComputerUseAgent.log` inside the guest.
- Run `computer-use machine inspect --machine <name>` and note whether transport is `published_tcp` or `container_exec`.

If state capture reports missing permissions:

- Confirm app path is `/Applications/ComputerUseAgent.app`.
- Confirm bundle id is `com.jianliang00.computer-use-cli`.
- Re-grant Accessibility and Screen & System Audio Recording in the guest GUI.
- Repackage the authorized image only after both permissions are true.

If the macOS guest agent crashes during container start:

- Ensure the image contains the guest agent from the same project-owned guest-runtime version used by the host CLI.
- Rebuild product and authorized images from a clean base if the image carries an older runtime agent.
