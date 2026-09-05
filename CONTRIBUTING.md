# Contributing

- Build with `xcodegen generate` and open the project; see the README.
- Run the tests before opening a pull request. The loudness tests fail if any
  soundscape drifts more than 1 LU from -22 LUFS. If you change a voice,
  adjust its `Trim` in `Sources/Audio/Voices.swift` until they pass.
- Keep the audio path free of allocations and locks. The render thread reads
  control values through atomics only.
- Commit messages follow Conventional Commits: `type(scope): description`.
