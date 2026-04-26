# Releasing

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed
or when the workflow is run manually with a tag input.

## Published Artifacts

Each release publishes:

- `computer-use-<version>-macos-arm64.pkg`
- `computer-use-guest-kit-<version>-macos-arm64.pkg`
- `computer-use-<version>-macos-arm64.tar.gz`
- `computer-use-guest-kit-<version>-macos-arm64.tar.gz`
- `SHA256SUMS.txt`

The host package installs:

```text
/usr/local/bin/computer-use
```

The guest kit installs:

```text
/Applications/ComputerUseAgent.app
/usr/local/libexec/computer-use/bootstrap-agent
/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist
/Library/LaunchAgents/io.github.jianliang00.computer-use.agent.plist
```

The guest kit is used to build or repair a guest image. It is not the normal
per-user install path.

## Apple Developer Assets

Create these assets in the Apple developer account for the project:

1. Register bundle id `com.jianliang00.computer-use-cli`.
2. Create a `Developer ID Application` certificate and export it as `.p12`.
3. Create a `Developer ID Installer` certificate and export it as `.p12`.
4. Create an App Store Connect API key for notarization and download the `.p8`
   private key.

The `.p12` files must include private keys. Do not commit certificates,
passwords, or App Store Connect private keys.

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

Identity values are certificate common names, for example:

```text
Developer ID Application: Example Name (TEAMID)
Developer ID Installer: Example Name (TEAMID)
```

Encode binary assets before pasting them into GitHub secrets:

```bash
base64 < DeveloperIDApplication.p12 | tr -d '\n' | pbcopy
base64 < DeveloperIDInstaller.p12 | tr -d '\n' | pbcopy
base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy
```

## Workflow Behavior

The release workflow:

1. Checks out the tag.
2. Runs `swift test`.
3. Imports Apple signing assets into a temporary keychain.
4. Builds release artifacts with signing enabled.
5. Signs the CLI, bootstrap executable, and app bundle.
6. Notarizes and staples the app bundle and `.pkg` artifacts.
7. Publishes or updates the GitHub release.
8. Deletes the temporary keychain.

Signing and packaging are handled by:

```bash
scripts/import-apple-signing-assets.sh
scripts/package-release-artifacts.sh
```

## Manual Packaging

Unsigned local package artifacts:

```bash
scripts/package-release-artifacts.sh 0.0.0 /tmp/computer-use-release
```

Signed and notarized packaging requires the same environment variables used by
the GitHub Actions workflow:

- `MACOS_SIGNING_ENABLED=1`
- `MACOS_NOTARIZATION_ENABLED=1`
- `MACOS_CODE_SIGN_IDENTITY`
- `MACOS_INSTALLER_SIGN_IDENTITY`
- `MACOS_CODE_SIGN_KEYCHAIN`
- `NOTARYTOOL_KEY_PATH`
- `NOTARYTOOL_KEY_ID`
- `NOTARYTOOL_ISSUER_ID`

The bundle id defaults to `com.jianliang00.computer-use-cli` and can be
overridden with `MACOS_APP_BUNDLE_ID` for non-project builds.

## Tagging

Use semantic version tags with a leading `v`:

```bash
git tag v0.1.2
git push origin v0.1.2
```

The workflow rejects tags that do not match `v<semver>`.
