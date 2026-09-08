# Developing Surf

Use Xcode 26.3 or later on a Mac supported by that Xcode version. Development has
been checked with Xcode 26.4.1 on Apple silicon, and CI selects Xcode 26.3. The app
targets macOS 14 and later; older systems still need hardware testing.

```sh
brew install xcodegen just
just run     # generate the Xcode project, build, and launch
just test    # build the app and run unit tests
just log     # follow the app's log
just open    # generate the project and open it in Xcode
just clean   # remove the generated project and build artifacts
```

Debug builds use ad hoc signing, so you don't need a paid Apple developer account
or the maintainer's certificate. macOS may ask you to grant Accessibility,
Microphone, and Bluetooth permissions again after rebuilding or changing signatures.
Remove an old Accessibility entry and add the new app if input stops working.

To use your own signing identity, set it in Xcode or pass build settings directly:

```sh
just gen
xcodebuild -project Surf.xcodeproj -scheme Surf -configuration Debug \
  -derivedDataPath .build CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM=YOUR_TEAM build
```

The unit tests compile the model and dictation code in a standalone test bundle.
They use a fake microphone and recognizer. They don't launch Surf, download speech
models, request permissions, or send keystrokes.

Dependencies are pinned in `project.yml`: a specific FluidAudio commit and an exact
Sparkle version. Update these deliberately and run `just test`. The generated
`Package.resolved` can be deleted with the Xcode project without losing the pins.

## Releasing

A public source repository doesn't require a binary release. Keep the README's
source-build instructions until a signed download is available.

Release builds use Left Shift Logical's Developer ID. `SIGN_IDENTITY` overrides
the certificate fingerprint used when packaging. To release under another team,
update the Release signing settings and bundle identifier too.

```sh
just pkg       # build and sign a DMG; requires create-dmg and Developer ID
just notarize  # build, submit for notarization, and staple the DMG
```

Local notarization uses a Keychain profile named `notary`, configurable with
`NOTARY_PROFILE`. Configure it with `xcrun notarytool store-credentials`.

The tag workflow builds and notarizes the DMG, creates the Sparkle update and
appcast, publishes a GitHub release, and updates `fcjr/homebrew-fcjr`.
It needs these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID certificate and private key export |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that export |
| `APP_STORE_CONNECT_API_KEY` | Contents of the notarization API `.p8` key |
| `APP_STORE_CONNECT_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer ID |
| `SPARKLE_PRIVATE_KEY` | Sparkle signing key matching the app's public key |
| `RELEASER_APP_ID` | GitHub App ID for the Homebrew tap publisher |
| `RELEASER_APP_PRIVATE_KEY` | GitHub App private key |

Keep credentials in Keychain and GitHub Actions secrets. Don't commit exports or
paste them into issues. The PR test workflow needs none of these credentials.

After the secrets are configured and a packaged build has been tested:

```sh
just bump patch
# Review and push the version commit, then:
just release
```

Before announcing a release, check a fresh DMG installation, Gatekeeper,
permissions, pairing, dictation, and a Sparkle upgrade from the previous version.
The first release has no previous version, so schedule that upgrade check for the
second release. Test turning dictation off and disconnecting the remote while a
button is held. Check the claimed macOS versions and remote models on hardware.
