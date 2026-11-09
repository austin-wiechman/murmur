# AGENTS.md

- Test with `swift test`. Build the app bundle with `./scripts/build-app.sh`.
- `Sources/MurmurCore` holds logic with no system dependencies, and `Tests/MurmurCoreTests` covers it.
  Put new testable logic there and keep system calls in thin adapters in `Sources/Murmur`.
  `Sources/MurmurEngine` holds audio capture, transcription, and the Claude cleanup engine.
- `ClaudeCodeRunner`, `TranscriptCleanup`, and `SpeechModels` are library products that other apps
  pin by tag. They must not depend on Sparkle or the app targets, and `ClaudeCodeRunner` takes no
  package dependencies.
- Avoid putting windows in front of the user. `swift run Murmur --demo-gallery <dir>` renders every
  screen to PNG files behind other windows; check UI changes there before launching the app.
- `build-app.sh` and `install.sh --dev` build "Murmur Dev", a separate bundle ID with no update feed,
  so it never touches an installed release. `MURMUR_RELEASE=1` builds the real app; only
  `install.sh` without `--dev` and the release workflow set it.
- Pull request titles follow Conventional Commits (`feat:`, `fix:`, `docs:`, ...). Squash merges use
  the title as the commit, and release-please reads those commits to pick the next version.
