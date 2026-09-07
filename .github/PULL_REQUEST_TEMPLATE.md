## Summary

<!-- What changes and why. Link the issue if there is one. -->

## Checklist

- [ ] Commit messages follow Conventional Commits: `type(scope): description`
- [ ] Tests pass locally, including the loudness tests
- [ ] If a voice changed, its `Trim` in `Sources/Audio/Voices.swift` was adjusted so every soundscape stays within 1 LU of -22 LUFS
- [ ] The audio render path has no new allocations or locks
- [ ] README updated if user-facing behavior changed
