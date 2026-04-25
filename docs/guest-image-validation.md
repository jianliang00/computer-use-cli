# Guest Image Validation

Latest run: 2026-04-25.

## Setup

- Built the release `bootstrap-agent` and packaged `ComputerUseAgent.app` with:

  ```sh
  scripts/prepare-computer-use-image-context.sh
  ```

- Verified generated launchd plists and app `Info.plist` with `plutil -lint`.
- Used an existing local macOS VM image directory as an APFS clone under `/tmp/computer-use-guest-validate-image`.
- Used `/tmp/computer-use-guest-validate-seed` as the VM shared seed directory.
- Promoted the validated clone into a stable local base image directory:
  `~/Library/Application Support/com.jianliang.OpenBox/macos-images/local-macos-base-latest`.
- Packaged that stable base directory as `/tmp/local-macos-base-latest.oci.tar`,
  loaded it as `local/macos-base:latest`, then removed the intermediate tar and
  stable image directory to reclaim disk space.
- Built the product image with:

  ```sh
  container build --platform darwin/arm64 \
    -f .build/computer-use-image-context/Dockerfile \
    -t local/computer-use:product \
    --progress plain \
    .build/computer-use-image-context
  ```

## Results

- `container macos start-vm --image /tmp/computer-use-guest-validate-image --share /tmp/computer-use-guest-validate-seed` booted the guest.
- The control socket `probe` returned `ok guest-agent ready on port 27000`.
- The base image guest-agent accepted `probe`, but `exec`/`sh` failed with a host/guest protocol decode error, so in-guest validation used the GUI session and shared folder.
- Running the installer from inside the guest installed:
  - `/Applications/ComputerUseAgent.app`
  - `/usr/local/libexec/computer-use/bootstrap-agent`
  - `/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist`
  - `/Library/LaunchAgents/io.github.jianliang00.computer-use.agent.plist`
- Installed files had launchd-compatible ownership and modes:
  - app executable: `root:wheel 755`
  - bootstrap executable: `root:wheel 755`
  - LaunchDaemon plist: `root:wheel 644`
  - LaunchAgent plist: `root:wheel 644`
- `launchctl print system/io.github.jianliang00.computer-use.bootstrap` showed the LaunchDaemon loaded with `last exit code = 0`.
- `launchctl print gui/501/io.github.jianliang00.computer-use.agent` showed the LaunchAgent `state = running`.
- `GET /health` returned `HTTP 200` with `{"ok":true,"version":"0.1.0"}`.
- `/var/run/computer-use/bootstrap-status.json` refreshed to:

  ```json
  {
    "agentInstalled": true,
    "agentPort": 7777,
    "agentRunning": true,
    "bootstrapped": true,
    "sessionReady": true,
    "user": "admin"
  }
  ```

- `GET /permissions` returned `HTTP 200` with Accessibility and Screen Recording both `false`.
- `GET /apps` returned `HTTP 200` and listed running GUI apps including Terminal, Finder, Dock, and SystemUIServer.
- `POST /state` returned `HTTP 403` with `permission_denied` and message `Missing permissions: accessibility, screenRecording`, which is the expected pre-authorization behavior.
- The stable base directory booted successfully with `container macos start-vm --agent-probe`; the guest agent reported ready on vsock port `27000`.
- The original `/tmp/computer-use-guest-validate-image` source clone and other temporary probe files were removed after the stable base directory was validated.
- `container image list --verbose` now shows:
  - `local/macos-base:latest` as a `darwin/arm64` image.
  - `local/computer-use:product` as a `darwin/arm64` image with full size
    about 31.64 GB and digest prefix `e0e95d4`.
- `container image inspect local/computer-use:product` returned an OCI image
  with `os = darwin`, `architecture = arm64`, and command
  `/usr/bin/tail -f /dev/null`.
- `container run --publish 127.0.0.1:47777:7777/tcp local/computer-use:product`
  failed with `--publish is not supported for --os darwin`; the current macOS
  runtime cannot validate the host-side TCP publish path.
- `container run -d --gui --name cu-product-verify local/computer-use:product`
  successfully started the product OCI image.
- Inside the running product container:
  - Installed app, bootstrap binary, and launchd plists were present.
  - `/usr/local/libexec/computer-use`, the bootstrap binary, the app executable,
    and both launchd plists had root-owned launchd-compatible modes.
  - LaunchDaemon `io.github.jianliang00.computer-use.bootstrap` was loaded with
    `last exit code = 0`.
  - `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`
    returned `admin`.
  - `/etc/kcpassword` was not present.
  - `launchctl print gui/501/io.github.jianliang00.computer-use.agent` failed
    because no `gui/501` domain existed.
  - `GET /health` on `127.0.0.1:7777` failed with connection refused.
  - `/var/run/computer-use/bootstrap-status.json` reported
    `sessionReady: false`, `agentRunning: false`, and `user: "root"`.
- The temporary `cu-product-verify` container and `com.apple.container` rebuild
  cache were removed after validation.
- `computer-use machine create/start` was validated against
  `local/computer-use:product`; creation falls back after the darwin
  `--publish` rejection, start succeeds, and metadata is updated with
  `agentTransport: "container_exec"`.
- `computer-use agent ping` now attempts
  `container exec <sandbox> /usr/bin/curl http://127.0.0.1:7777/health`.
  Against the pre-authorization product image this failed with connection
  refused because no logged-in `admin` GUI session existed yet.
- Auto-login is now seeded in the product image by running
  `configure-autologin.sh admin admin` during the image build. In a fresh product
  guest, `/etc/kcpassword` was present as `root:wheel` with mode `600` and size
  `12`, `autoLoginUser` was `admin`, `/dev/console` was owned by `admin` uid
  `501`, and `GET /health` returned `{"ok":true,"version":"0.1.0"}`.
- The product guest was authorized in the GUI by adding
  `/Applications/ComputerUseAgent.app` under System Settings privacy controls
  and enabling Screen & System Audio Recording. After restarting the LaunchAgent,
  `GET /permissions` returned
  `{"accessibility":true,"screen_recording":true}` and `POST /state` returned a
  PNG screenshot plus AX nodes.
- The authorized guest directory was packaged and loaded with:

  ```sh
  container macos package \
    --input "$HOME/Library/Application Support/com.jianliang.OpenBox/container/containers/cu-product-authorize" \
    --output /tmp/computer-use-authorized.oci.tar \
    --reference local/computer-use:authorized
  container image load --input /tmp/computer-use-authorized.oci.tar
  ```

- The loaded authorized image was inspected as `local/computer-use:authorized`
  for `darwin/arm64`, size `31583519795`, platform manifest digest
  `sha256:fce8effdfa3803e7317f02d954100020e1f353c054b40d63b0b8a0ffdbaff469`.
- A fresh `cu-authorized-verify` guest created from
  `local/computer-use:authorized` validated the persisted state:
  - `/etc/kcpassword`: `root 0 wheel 0 600 12`
  - `autoLoginUser`: `admin`
  - `/dev/console`: `admin 501`
  - LaunchAgent: `io.github.jianliang00.computer-use.agent` running as `admin`
  - `GET /health`: `{"ok":true,"version":"0.1.0"}`
  - `GET /permissions`: `{"accessibility":true,"screen_recording":true}`
  - `GET /apps`: 21 GUI applications listed
  - `POST /state` for Finder: `image/png` screenshot with base64 length
    `4808020` and 270 AX nodes
- A real CLI smoke against the authorized image was run with machine name
  `authorized-smoke`:
  - `machine create` recorded `local/computer-use:authorized`.
  - `machine start` succeeded and fell back to
    `agentTransport: "container_exec"` for darwin.
  - `agent ping` returned `{"ok":true,"version":"0.1.0"}`.
  - `agent doctor` reported `sandbox_running: true`,
    `session_agent_ready: true`, `agent_transport: "container_exec"`, and both
    permissions true.
  - `permissions get` returned both permissions true.
  - `apps list` returned 22 GUI applications.
  - `state get --bundle-id com.apple.finder` returned a Finder snapshot with
    PNG screenshot base64 length about `4003636` and 270 AX nodes.
  - `action scroll` and coordinate `action click` returned `{"ok":true}`.
- The first CLI `state get` attempt exposed a transport issue: large screenshot
  responses could exceed the macOS runtime attachment buffer when Swift waited
  for `container exec` to exit before reading stdout. `ProcessContainerCommandRunner`
  now drains stdout/stderr concurrently while the subprocess runs, and the
  Finder `state get` command passes through the CLI.
- The TextEdit foreground/app discovery gap was fixed in a live authorized
  guest updated with the latest `ComputerUseAgent.app` build:
  - `/apps` listed `com.apple.TextEdit` with the launched `admin` PID.
  - `POST /state` with `{"bundle_id":"com.apple.TextEdit"}` returned a
    TextEdit snapshot with a PNG screenshot (base64 length about `4445288`)
    and 360 AX nodes.
  - `POST /actions/type` updated the `AXTextArea` value to
    `Hello from codex`.
  - The fix combines a process-table fallback for `/apps` and a `/state`
    implementation that targets the requested bundle id instead of always
    walking the frontmost app.
  - `POST /permissions/request` and
    `computer-use permissions request --machine <name>` were added to re-open
    TCC prompts after replacing `/Applications/ComputerUseAgent.app`.

## Notes

- Offline installation into a mounted Data volume initially produced launchd ownership errors because the host-mounted APFS volume reported `Owners: Disabled`. The installer now verifies launchd-owned files and warns for offline installs where root ownership cannot be observed.
- Live installs now bootstrap both the system LaunchDaemon and the current `admin` GUI LaunchAgent when an `admin` console session is active.
- Product image build and host-side product machine start are now validated.
  Agent access uses `container_exec` for darwin images without published ports.
- Authorized image validation is complete for auto-login, persisted Accessibility
  and Screen Recording permissions, agent health, apps, and state capture.
- Host CLI validation is complete through Finder state and basic actions over
  the darwin `container_exec` transport. The TextEdit discovery/state/type fix
  is validated in a live authorized guest; the remaining follow-up is
  regenerating the local `authorized` OCI artifact from a clean source image
  directory and rerunning the fresh-guest smoke.
- If `container image load` appears idle after packaging, verify
  `container system status` is using the OpenBox app root
  `~/Library/Application Support/com.jianliang.OpenBox/container/`. Restarting
  with explicit `--app-root` and `--install-root` restored image loading during
  this run.
