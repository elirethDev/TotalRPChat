# Release Template

Use this document for a manual TotalRPChat release. The current process is intentionally manual; automation can be added later once the version and packaging contracts are stable.

## Quick path

1. Confirm the release scope and choose a SemVer version such as `3.0.0`.
2. Update the canonical runtime value in `42/media/lua/shared/trpc/shared/Version.lua` with the `v` prefix.
3. Add the dated release entry to `CHANGELOG.md` and prepare matching release notes.
4. Run `pwsh -File tools/release-check.ps1 -ExpectedVersion <version>`.
5. Run the Lua bytecode checks, `git diff --check`, and the gameplay/runtime checks below.
6. Review the package contents and compatibility metadata.
7. Create the Git tag and GitHub release, then publish the same reviewed package to Steam Workshop.

## Version and tag rules

- Use one canonical runtime version: `42/media/lua/shared/trpc/shared/Version.lua` returns `v<MAJOR.MINOR.PATCH>`.
- Use valid SemVer: `MAJOR.MINOR.PATCH`, with optional prerelease and build metadata.
- Use the matching tag `v<MAJOR.MINOR.PATCH>`.
- Keep Project Zomboid compatibility separate from the release version. `mod.info` and `42/mod.info` provide `versionMin` for B41 and B42 respectively.
- Do not create a second hardcoded release-version source in documentation or package metadata.

## Changelog and release notes

- [ ] Add an empty `Unreleased` section at the top of `CHANGELOG.md`.
- [ ] Add `## [<version>] - <YYYY-MM-DD>` using the release date.
- [ ] Group user-facing changes under `Added`, `Changed`, `Fixed`, `Security`, or `Performance` as appropriate.
- [ ] Describe behavior and user impact, not internal implementation details alone.
- [ ] Copy the relevant changelog content into the GitHub release notes.
- [ ] Keep runtime `Logger` output separate from public changelog and release notes. Logs support diagnosis and operations; public notes describe validated user-visible changes and must not be assembled from log output.
- [ ] Do not claim Steam Workshop publication until the Workshop upload has completed successfully.

## B41/B42 compatibility

- [ ] Confirm root `mod.info` is present and retains the B41 `versionMin` value.
- [ ] Confirm `42/mod.info` is present and retains the B42 `versionMin` value.
- [ ] Test the package in the supported B41 environment.
- [ ] Test the package in the supported B42 environment.
- [ ] Verify that the package layout keeps B41 files at the root and B42 files under `42/`.

## Static and runtime validation

- [ ] Run `pwsh -File tools/release-check.ps1 -ExpectedVersion <version>`.
- [ ] Run `luajit -bl` against every repository Lua file and confirm all checks pass.
- [ ] Run `git diff --check`.
- [ ] Test chat, player radio, square/vehicle radio behavior, avatar moderation authorization, hand-item radios, empty stream switching, belt-radio updates, and radio range indicators.
- [ ] Review the diff and confirm no gameplay behavior changed outside the intended release scope.

## Package hygiene

- [ ] Build or stage the package from the repository contents without `.git`, local saves, logs, editor files, or temporary artifacts.
- [ ] Confirm both compatibility descriptors and the canonical runtime version are present in the package.
- [ ] Confirm no secrets, local configuration, debug artifacts, or unrelated files are included.
- [ ] Inspect the final archive or Workshop upload contents before publishing.

## GitHub release

- [ ] Review the final diff and release checklist on the intended commit.
- [ ] Create the matching annotated tag `v<version>` after validation.
- [ ] Create a GitHub release for that tag using the reviewed changelog text.
- [ ] Attach the reviewed package when a downloadable archive is needed.

## Steam Workshop publication

- [ ] Upload the reviewed package manually through the established Workshop workflow.
- [ ] Set the Workshop title, description, supported game/build information, and release notes from the reviewed artifacts.
- [ ] Verify the uploaded files and version in the Workshop item page.
- [ ] Only after successful publication, update any external publication status or announcement.
