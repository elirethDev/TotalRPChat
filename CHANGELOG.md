# Changelog

All notable changes to TotalRPChat are documented here. This changelog follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, and release versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.0.0] - 2026-08-17

Validated changes since the previous published commit.

### Added

- Added player-radio support for chat and radio interactions.

### Changed

- Improved radio range indicator updates without changing their existing behavior.

### Fixed

- Fixed chat messages containing a single character.
- Fixed hand-item radio detection and belt-radio update handling.
- Fixed switching to a chat stream with no enabled streams.

### Security

- Added server-side authorization for avatar moderation approval and rejection actions.

### Performance

- Optimized radio indicator reconciliation incrementally to reduce unnecessary UI and subscription churn.
