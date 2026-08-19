# Workshop Publication — TotalRPChat v3.0.0

Prepared texts for the first Steam Workshop publication. Everything below is ready to paste; adjust only if you change scope before publishing.

> Publish order (from `docs/release-template.md`): validate the package -> create the `v3.0.0` tag and GitHub release -> upload the staged folder to Workshop using these texts -> verify the item page.

## Title

```
TotalRPChat
```

## Short description (item summary)

```
A full rework of the chat and radio systems for Project Zomboid, built with roleplay servers in mind.
```

## Long description (Workshop item body)

Use the description block from [`workshop.txt`](../workshop.txt) — it is the same text and is kept in sync with the uploaded descriptor. Paste it verbatim.

## Release notes (v3.0.0)

```
TotalRPChat 3.0.0

- Player-radio support for chat and radio interactions.
- Improved radio range indicator updates.
- Fixed chat messages containing a single character.
- Fixed hand-item radio detection and belt-radio update handling.
- Fixed switching to a chat stream with no enabled streams.
- Added server-side validation for the configured 60x80 avatar dimensions.
- Added server-side authorization for avatar moderation approval and rejection actions.
- Optimized radio indicator reconciliation to reduce UI and subscription churn.

Compatibility: Project Zomboid B42 only (build 42.18.0 or newer).
```

## Upload checklist

- [ ] `tools/stage-workshop.ps1` ran and the staged folder passed its checks.
- [ ] Changelog `3.0.0` entry has a release date (no `Unreleased` heading).
- [ ] `tools/release-check.ps1 -ExpectedVersion 3.0.0 -RequireReleased` passes.
- [ ] Runtime avatar 60x80 validation re-tested (valid 60x80 approved; 60x60/60x81, malformed, unsupported rejected).
- [ ] Tag `v3.0.0` created and GitHub release published with the release notes above.
- [ ] Staged folder uploaded to Steam Workshop with the texts above.
- [ ] Workshop item page verified (files, version, description).