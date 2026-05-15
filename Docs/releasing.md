# Releasing VoicePen

Release builds are created only for GitHub releases.

## Update And Signing Secrets

Auto-update releases use two different kinds of signing:

- Sparkle EdDSA signing authenticates the downloaded update archive against the
  public key in `SUPublicEDKey`.
- macOS code signing gives `VoicePen.app` a stable signing identity so macOS
  privacy permissions, including Microphone and Accessibility, can stay attached
  to VoicePen across Sparkle updates.

GitHub Actions needs these repository secrets:

- `SPARKLE_PRIVATE_KEY`: private key printed by Sparkle's `generate_keys` tool.
- `MACOS_SIGNING_CERTIFICATE_BASE64`: base64 content of the exported `.p12`
  signing identity.
- `MACOS_SIGNING_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `MACOS_SIGNING_IDENTITY`: certificate identity name passed to `codesign`.

The Sparkle public key is stored in the app's `SUPublicEDKey`; keep the matching
private key only in GitHub Actions secrets.

## Self-Signed Release Identity

Create a self-signed macOS signing identity in Keychain Access:

1. Open `Keychain Access`.
2. Choose `Keychain Access` -> `Certificate Assistant` -> `Create a Certificate...`.
3. Set `Name` to `VoicePen Release Signing`.
4. Set `Identity Type` to `Self Signed Root`.
5. Set `Certificate Type` to `Code Signing`.
6. Enable `Let me override defaults`.
7. In `Key Usage Extension`, keep `Signature` enabled.
8. Finish the assistant and make sure the certificate has a private key under it.
9. If needed, open the certificate's trust settings and trust it for code signing.

Verify the identity is usable:

```bash
security find-identity -v -p codesigning
```

Export the certificate and private key from Keychain Access:

1. Select the `VoicePen Release Signing` certificate together with its private key.
2. Choose `Export...`.
3. Save it as a `.p12` file, for example `VoicePenReleaseSigning.p12`.
4. Set a password for the exported `.p12`.

Do not commit the `.p12` file or its password.

Upload the secrets to GitHub:

```bash
read -s P12_PASSWORD
gh secret set MACOS_SIGNING_CERTIFICATE_BASE64 --body "$(base64 -i VoicePenReleaseSigning.p12)"
gh secret set MACOS_SIGNING_CERTIFICATE_PASSWORD --body "$P12_PASSWORD"
gh secret set MACOS_SIGNING_IDENTITY --body "VoicePen Release Signing"
unset P12_PASSWORD
```

Check that the repository has the expected secrets:

```bash
gh secret list
```

Use the same `.p12` for every release. If the signing identity changes, macOS may
ask for Microphone and Accessibility permissions again after the next update.
After one transition to a stable identity, later updates signed with the same
identity should keep those permissions.

A self-signed Code Signing certificate is enough for local trust identity
stability. A paid Developer ID certificate and notarization are still
recommended for public distribution because they improve the first-install
Gatekeeper experience.

## Publish A Release

Prepare a release pull request:

```bash
make prepare-release VERSION=1.1.0
```

This creates a branch named `release/v1.1.0`, bumps the Xcode app version,
pushes the branch, and opens a pull request.

After checks pass on the release pull request, create and push the release tag
from the same release branch:

```bash
git checkout release/v1.1.0
git pull --ff-only origin release/v1.1.0
make publish-release VERSION=1.1.0
```

Before pushing the tag, `make publish-release` verifies that the release pull
request is open, non-draft, has completed green checks, the Xcode marketing
version matches `VERSION`, and the build number is higher than the previous
release build.

Pushing the tag starts the Release workflow from the version-bump branch:

```text
.github/workflows/release.yml
```

When the workflow finishes, download `VoicePen-macOS-unsigned.zip` from the
GitHub Release page. The same workflow signs the archive for Sparkle and
publishes `https://dot-sk.github.io/VoicePen/appcast.xml` through GitHub Pages.
After the Release workflow succeeds, merge the release pull request into `main`.

Local package build:

```bash
make package
```

The app is unsigned. First launch still requires **right-click -> Open**.
