# TotalRPChat

A full rework of the chat and radio systems for Project Zomboid, built with roleplay servers in mind.

> **Compatibility:** Project Zomboid **B42** only (`versionMin 42.18.0`). Current runtime version: **v3.0.0**.

## Features

### Chat system

- Complete replacement of the vanilla chat UI (custom rendering, tab panel, text entry, context menu).
- Range-based voice channels — **whisper / low / say / yell** — with independent range, color, and zombie-noise range per channel.
- Action channels: `/me` (roleplay action) and `/do` (event narration, admin/mod-gated by default).
- Non-voice channels: faction, safehouse, general, admin, OOC, and private messages.
- Radio channels: speak over a two-way radio and relay to everyone tuned to the same frequency, plus a `scriptedRadio` channel for vanilla scripted radio content.
- Chat bubbles over players (with optional avatar/portrait) and typing dots while composing.
- Markdown-ish formatting: `*italic*` and `**bold**` with server-configurable colors.
- `/roll xdy` dice rolling and per-player `/color` name colors.
- Optional boredom reduction, auto-capitalize/punctuate, hide callout, and language system.
- In-game **Survival Guide** listing every command; username auto-complete in PMs and `/r` quick-reply.

### Customizable tabs

- Built-in tabs: General, Out Of Character, Private Message, Admin (the last three appear only when their channel is enabled).
- Player-created **custom tabs** with a custom title, a chosen default input channel, and excluded (hidden) channels.
- Tabs persist across sessions via ModData; the active tab is remembered.
- Tab editor window (gear menu → "Manage chat tabs"): create, rename, delete, pick input channel, add/remove/clear excluded channels.
- Drag-to-reorder, unread tab blinking, and tab cycling via the "Switch chat stream" key.

### Radio system

- Voice over radio: speaking on a voice channel while a two-way radio is on and unmuted relays to everyone tuned to the same frequency.
- Three radio bubble types — square/world, player-held, and vehicle radios — shown at the emitting radio.
- Listening- and speaking-range indicators, sound max-range, and radio icon toggles.
- Muting devices and state sync (frequency, volume, battery, headphone, two-way, transmit range) for in-hand, square, and belt radios.
- Belt radios simulated with a fake radio object; battery drain tracked every game minute.
- Radio noise attracts zombies per channel's zombie range.

### Avatar system

- Custom player avatar shown in chat bubbles (60×80 PNG/JPEG, transparency supported).
- Upload flow: drop a properly-named file into `%userprofile%\Zomboid\Lua\avatars\client\<serverIP>\<username>\request\`, then use the upload button.
- Admin/Moderator validation window with approve/reject controls and a pending queue.
- Server-side dimension validation (header parsing, no full image decode) before storing and before approving.

### Server / multiplayer

- Server-authoritative message routing: range, line-of-sight, and same-vehicle checks, per-channel delivery, alive-only enforcement.
- Per-channel permissions (faction membership, safehouse ownership, admin level, `/do` admin-only).
- Persistent chat log per server/date (`TRPC/logs/<serverName>/trpc-chat-log-<date>.txt`).
- Optional **Discord bridge** for general chat and a chosen radio frequency.
- Server pushes all chat/radio settings to clients and re-broadcasts them live when sandbox vars change.

## Commands

| Command | Aliases | Purpose |
|---|---|---|
| `/say` | `/s` | Normal volume |
| `/whisper` | `/w` | Whisper |
| `/low` | `/l` | Quiet talk |
| `/yell` | `/y` | Shout |
| `/me` | — | Roleplay action |
| `/do` | — | Event narration (admin/mod by default) |
| `/faction` | `/f` | Faction channel |
| `/safehouse` | `/sh` | Safehouse channel |
| `/all` | `/g` | General channel |
| `/ooc` | `/o` | Out of character |
| `/pm <name>` | `/p` | Private message |
| `/r` | — | Reply to last PM |
| `/admin` | `/a` | Admin channel (admin only) |
| `/color [value]` | — | Show/set player color |
| `/roll xdy` | — | Roll dice (optionally `+add`) |
| `/language <code>` | — | Switch to a learned language (with `Languages` enabled) |

## Configuration

Everything is configured through **sandbox options**:

- Page **TRPC**: character name display, boredom reduction, language system, bubble portrait/opacity/timer, capitalize, hide callout, markdown colors, Discord bridge, radio color/sound range.
- Page **TRPCChannels**: per-channel enabled toggle, color, and (where relevant) player and zombie-attract ranges.

Run `/color`, `/roll`, or `/language` with no arguments to print current values and lists. Open the in-game chat info button / Survival Guide for the full command reference.

## Installation

1. **Server**: enable the mod on the dedicated server. The server is required for full multiplayer features (message routing, permissions, avatar moderation, logging, Discord bridge).
2. **Clients**: subscribe and enable the mod so chat/radio UI and settings work correctly.
3. Configure the sandbox options above to taste.

Solo play works for the chat/radio UI, but server-side features require the server.

## Translations

UI, sandbox, and survival guide translations ship for **EN**, **ES**, **DE**, **JP**, **CN**, **PTBR**, **RU**, and **UA**. The optional language system ships 182 "Learn \<Language\>" books plus a "Forget Languages" book.

> **Community translation help wanted.** Some translations (notably **JP**, **CN**, and **PTBR**) were initially generated with AI assistance and may read less naturally than a native speaker would write them. If you spot a mistake, an awkward phrasing, or a better term, please open a pull request or issue — contributions that improve translation quality are very welcome.

## Architecture

The codebase is refactored from a single monolithic script into a layered architecture:

```
42/media/lua/
├── client/trpc/client/   # client-side UI, network, parser
├── server/trpc/server/   # server-side domain, radio, network
└── shared/trpc/          # shared core, utils, registries
    ├── core/             # Logger, EventBus
    └── shared/           # ChannelRegistry, Settings, AvatarStore, utils
```

Key patterns used throughout:

- **ChannelRegistry** — data-driven identity for chat channels.
- **PermissionRegistry** — per-channel permission closures, side-effect free.
- **AvatarStore** / **Settings** — shared data-layer modules following the same registry pattern.
- **EventBus** — decouples network dispatch from UI rendering.
- **Logger** — centralized, level-filtered logging (no raw `print()` in production).

## Versioning and releases

The runtime version is maintained in [`Version.lua`](42/media/lua/shared/trpc/shared/Version.lua), separately from the B42 `versionMin` in [`42/mod.info`](42/mod.info). See [`CHANGELOG.md`](CHANGELOG.md) for public release history and [`docs/release-template.md`](docs/release-template.md) for the manual release checklist.

## Credits

This project is derived from **Total Immersive Chat System (TICS)** by [Phibonacci](https://github.com/Phibonacci/Total-Immersive-Chat-System). The base commit retains its original authorship.

Sound assets from the original TICS (keyboard and phoneme sounds) are kept in a local backup and are not distributed in this repository.

## License

All rights reserved. No license is granted for redistribution of this code. See the original TICS project for its licensing terms.
