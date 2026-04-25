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

The local `container image list` only contained Linux `ubuntu:24.04`; no local `local/macos-base:latest` OCI image was available. Because of that and limited free disk space, this run validated the installer and guest services directly against the cloned VM image instead of running `container build`.

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

## Notes

- Offline installation into a mounted Data volume initially produced launchd ownership errors because the host-mounted APFS volume reported `Owners: Disabled`. The installer now verifies launchd-owned files and warns for offline installs where root ownership cannot be observed.
- Live installs now bootstrap both the system LaunchDaemon and the current `admin` GUI LaunchAgent when an `admin` console session is active.
- Full product/authorized image validation still requires a darwin/arm64 base image tag available to `container build` and an authorized image flow that seeds auto-login plus Accessibility and Screen Recording permissions.
