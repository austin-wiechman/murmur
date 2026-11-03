# Contributing

Murmur is a hobby project I work on in my spare time, mostly with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Pull requests are welcome. I review them when I get the chance, which can take a while.

## Pull requests

- Keep each pull request to one change. In the description, say what it fixes or adds and how you tested it.
- Title it in the [Conventional Commits](https://www.conventionalcommits.org) format, such as `fix: keep the pill on the active screen`. The title becomes the commit on `main` and decides the next version number, so a check enforces the format.
- Run `swift test` before you open it. CI runs the tests and a release build on every pull request.
- For a UI change, attach before and after screenshots. `swift run Murmur --demo-gallery <dir>` renders every pill state, the menu, and each Settings section to PNG files in `<dir>`.
- For a larger feature, open an issue first so we can agree on the approach before you spend time on it.

## Work on the code

`Sources/MurmurCore` holds logic with no system dependencies, and `swift test` covers it. `Sources/MurmurEngine` holds audio capture, transcription, and the cleanup engines. `Sources/Murmur` is the app itself.

To try a change, run `./scripts/install.sh --dev`. It installs a development copy named Murmur Dev in `/Applications/Murmur Dev.app`, with its own bundle ID and no update feed. It gets its own permissions and never updates itself, so it can sit beside an installed release. Both copies answer the same shortcut, so installing one quits the other. To build `build/Murmur.app` without installing it, run `./scripts/build-app.sh`.

macOS ties the Accessibility and Microphone grants to the app's signature, and an ad hoc signature changes on every build. To keep the grants across rebuilds, create a self-signed certificate once:

1. In Keychain Access, choose **Keychain Access › Certificate Assistant › Create a Certificate…**
2. Name it `Local Code Signing`, set **Identity Type** to **Self-Signed Root**, and set **Certificate Type** to **Code Signing**.

`build-app.sh` signs with that certificate when it exists.

`murmur-bench` replays 16 kHz mono WAV recordings and JSONL transcripts through the real engine code. Run `swift run murmur-bench` to see its commands.

## Issues

A bug report helps most when it includes steps to reproduce, your macOS version, and your keyboard layout. I can't promise to fix every bug myself, so a pull request is the surest way to get one fixed.

## Forks

If you want Murmur to go in a direction I don't, fork it. The MIT License lets you do almost anything with the code. To publish signed releases of your fork, see [RELEASING.md](RELEASING.md).
