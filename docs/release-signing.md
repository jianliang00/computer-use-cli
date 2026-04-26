# Release Signing

Release builds use Apple Developer ID signing and notarization for macOS
distribution outside the Mac App Store.

## Published Artifacts

The release workflow keeps the existing tarballs and also publishes directly
installable packages:

- `computer-use-<version>-macos-arm64.pkg`
  - Installs `/usr/local/bin/computer-use`.
- `computer-use-guest-kit-<version>-macos-arm64.pkg`
  - Installs `/Applications/ComputerUseAgent.app`.
  - Installs `/usr/local/libexec/computer-use/bootstrap-agent`.
  - Installs the LaunchDaemon and LaunchAgent plists.
  - Runs a `postinstall` script that fixes ownership, validates plists, and
    loads launchd jobs when possible.

The app bundle id is:

- `com.jianliang00.computer-use-cli`

The launchd labels remain:

- `io.github.jianliang00.computer-use.bootstrap`
- `io.github.jianliang00.computer-use.agent`

## Apple Developer Setup

Create these assets in the Apple developer account used for this project:

1. Register the bundle id `com.jianliang00.computer-use-cli`.
2. Create a `Developer ID Application` certificate and export it as a `.p12`.
3. Create a `Developer ID Installer` certificate and export it as a `.p12`.
4. Create an App Store Connect API key for notarization and download the `.p8`
   private key.

The `.p12` exports must include the private key. Keep the certificate passwords
and `.p8` private key out of the repository.

## GitHub Actions Secrets

Configure these repository secrets:

- `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY`
- `APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPER_ID_INSTALLER_IDENTITY`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`

The identity secrets should be the certificate common names, for example:

- `Developer ID Application: Example Name (TEAMID)`
- `Developer ID Installer: Example Name (TEAMID)`

Base64 encode local files before pasting them into GitHub secrets:

```bash
base64 < DeveloperIDApplication.p12 | tr -d '\n' | pbcopy
base64 < DeveloperIDInstaller.p12 | tr -d '\n' | pbcopy
base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy
```

## Workflow Behavior

`.github/workflows/release.yml` imports the certificates into a temporary
keychain, builds release artifacts with signing enabled, notarizes the app and
packages, staples the app and packages, publishes the GitHub release, then
deletes the temporary keychain.

The packaging script signs these Mach-O artifacts before packaging:

- `computer-use`
- `bootstrap-agent`
- `ComputerUseAgent.app`

The `.pkg` artifacts are signed with the Developer ID Installer certificate,
submitted to Apple's notary service, stapled, and validated with `spctl`.
