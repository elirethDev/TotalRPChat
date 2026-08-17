# TotalRPChat

A full rework of the chat system and radio system for Project Zomboid, made with RP servers in mind.

## What it does

- Layered, modular chat system (client / server / shared) with a data-driven channel registry
- Radio system with square, player and vehicle radios
- Custom chat channels, per-channel permissions, and server-side moderation
- Persistent chat logging
- Extensible command dispatch and bubble system

## Architecture

The codebase was refactored from a single monolithic script into a layered architecture:

```
42/media/lua/
├── client/trpc/client/   # client-side UI, network, voice, parser
├── server/trpc/server/   # server-side domain, radio, network
└── shared/trpc/          # shared core, utils, registries
    ├── core/             # Logger, EventBus
    └── shared/           # ChannelRegistry, Settings, AvatarStore, utils
```

Key patterns used throughout:

- **ChannelRegistry** — data-driven identity for chat channels
- **PermissionRegistry** — per-channel permission closures, side-effect free
- **AvatarStore** / **Settings** — shared data-layer modules following the same registry pattern
- **EventBus** — decouples network dispatch from UI rendering
- **Logger** — centralized, level-filtered logging (no raw `print()` in production)

## Requirements

- Project Zomboid **B42** (multi-build: root `mod.info` for B41, `42/mod.info` for B42)
- Server with the mod enabled for full multiplayer features

## Versioning and releases

The runtime version is maintained in [`Version.lua`](42/media/lua/shared/trpc/shared/Version.lua). See [`CHANGELOG.md`](CHANGELOG.md) for public release history and [`docs/release-template.md`](docs/release-template.md) for the manual release checklist.

## Credits

This project is derived from **Total Immersive Chat System (TICS)** by [Phibonacci](https://github.com/Phibonacci/Total-Immersive-Chat-System). The base commit retains its original authorship.

- Sound assets from the original TICS (keyboard and phoneme sounds) are kept in a local backup and are not distributed in this repository.

## License

All rights reserved. No license is granted for redistribution of this code. See the original TICS project for its licensing terms.
