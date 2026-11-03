# Releasing

This page describes how Murmur's releases are built, and how to publish signed releases from your own fork.

## How a release is cut

After each merge to `main`, release-please updates an open pull request with a title such as `chore(main): release 0.2.0`. It picks the version from the Conventional Commits titles merged since the last release, and writes the changelog into `CHANGELOG.md`. Merge that pull request to release. Until `1.0.0`, a `feat:` bumps the minor version and a `fix:` bumps the patch version.

## How a release is built

Merging the release pull request tags the release and runs the release workflow, `.github/workflows/release.yml`. Pushing a tag such as `v0.2.0` by hand runs it too. The workflow:

1. Runs the tests.
2. Builds `Murmur.app` with version `0.2.0`, signed with the `Murmur Release Signing` certificate.
3. Zips the app and writes a Sparkle `appcast.xml` signed with the Sparkle update key.
4. Packs the app into a disk image for people downloading it by hand.
5. Publishes all three as a GitHub release. The app's update feed is the latest release's `appcast.xml`.
6. Updates the cask in the `<owner>/homebrew-tap` repository, if the `TAP_DEPLOY_KEY` secret exists.

The build number is the commit count, so Sparkle sees each release as newer than the last.

## Publish releases from a fork

Only I hold Murmur's signing certificate and Sparkle update key, so a fork needs its own.

1. In `Resources/Info.plist`, set `CFBundleIdentifier` to your own bundle ID and `SUFeedURL` to your repository. In `packaging/homebrew/murmur.rb`, change the preferences path under `zap` to match the bundle ID.
2. Generate a Sparkle update key. The command stores the key in your login keychain under the `murmur` account and prints its public half:

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account murmur
   ```

3. Put the public half in `SUPublicEDKey` in `Resources/Info.plist`.
4. Sign in with `gh auth login`, add the workflow scope with `gh auth refresh -s workflow`, and run the setup script:

   ```sh
   ./scripts/setup-github.sh
   ```

5. Push a tag for the first release:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

The setup script creates `<owner>/murmur` and `<owner>/homebrew-tap` if they don't exist, and lets GitHub Actions open pull requests so release-please can work. It stops if your Sparkle update key doesn't match `SUPublicEDKey`. It stores these secrets without printing them, and skips any that already exist:

| Secret | Contents |
| --- | --- |
| `SIGNING_CERT_P12` | A new self-signed `Murmur Release Signing` certificate. The script also adds it to your login keychain, which holds the only other copy. |
| `SIGNING_CERT_PASSWORD` | The password for that `.p12` file. |
| `SPARKLE_ED_PRIVATE_KEY` | The Sparkle update key from your login keychain. |
| `TAP_DEPLOY_KEY` | An SSH key with write access to the tap repository. |

## Keep the keys

- If you lose the signing certificate, the next release has a new signature, and every user grants Accessibility and Microphone again.
- If you lose the Sparkle update key, installed copies reject every later update, and users must reinstall by hand.

Both live in your login keychain, so back it up.
