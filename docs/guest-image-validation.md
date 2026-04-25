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
  It still fails with connection refused until the authorized image flow creates
  a logged-in `admin` GUI session and starts the session LaunchAgent.

## Notes

- Offline installation into a mounted Data volume initially produced launchd ownership errors because the host-mounted APFS volume reported `Owners: Disabled`. The installer now verifies launchd-owned files and warns for offline installs where root ownership cannot be observed.
- Live installs now bootstrap both the system LaunchDaemon and the current `admin` GUI LaunchAgent when an `admin` console session is active.
- Product image build and host-side product machine start are now validated.
  Agent access uses `container_exec` for darwin images without published ports.
- Authorized image validation still requires seeding `/etc/kcpassword` and
  granting Accessibility plus Screen Recording permissions.
