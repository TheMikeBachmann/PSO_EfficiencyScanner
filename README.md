# Efficiency Scanner

A PSO Blue Burst addon that tracks quest efficiency per run — EXP/hr, elapsed time, drop counts, and per-floor breakdowns — with persistent session history and configurable drop tracking thresholds.

## Prerequisites

### 1. PSOBB Addon Plugin

The addon plugin must be installed in your PSOBB client. It provides the Lua runtime, ImGui bindings, and the `pso.*` memory API that this addon depends on.

- **PSOBB.IO**: The addon plugin is bundled with the client — no separate installation needed.
- **Other servers**: Download and install from [Solybum/psobbaddonplugin](https://github.com/Solybum/psobbaddonplugin) or the original [HybridEidolon/psobbaddonplugin](https://github.com/HybridEidolon/psobbaddonplugin).
  - Also requires **Visual C++ Redistributable for Visual Studio 2015** ([download from Microsoft](https://www.microsoft.com/en-us/download/details.aspx?id=48145))

### 2. solylib

solylib is a shared utility library required by this addon. It provides item data lookups used for drop tracking.

Download from [Solybum/PSOBBMod-Addons](https://github.com/Solybum/PSOBBMod-Addons) and copy the `solylib` folder into your `addons/` directory.

## Installation

1. Download this repository (click **Code → Download ZIP** or clone it)
2. Create a folder named exactly `Efficiency Scanner` inside your PSOBB `addons/` directory
3. Copy `init.lua` and `configuration.lua` into that folder:

```
PSOBB/
└── addons/
    ├── solylib/          ← required dependency
    └── Efficiency Scanner/
        ├── init.lua
        └── configuration.lua
```

4. Launch the game. The addon will appear in the addon menu (default key: `` ` ``)

## Usage

The addon automatically detects when you enter and leave a quest by watching for floor transitions out of Pioneer 2. No manual start is required, though a **Start** button is available in the IDLE state to begin tracking manually.

**Quest name** must be entered manually — type it into the field at the bottom of the window during an active run. The last-used name is pre-filled on the next run.

### States

| State | Description |
|---|---|
| Idle | Waiting for a quest to begin |
| Active | Tracking in progress |
| Pending | Paused while in town via telepipe (resumes if you return) |
| Complete | Run finished — stats displayed with graphs |

Taking a telepipe back to town pauses tracking; time spent in town is excluded from all calculations. Using `$exit` ends the run immediately.

## Drop Tracking

Three categories of drops are tracked per run:

| Category | Default threshold | What counts |
|---|---|---|
| Tech disks | Level 20+ | Any technique disk at or above the configured level |
| Hit weapons | 30%+ hit | Any weapon with a Hit attribute at or above the configured percentage |
| Rare items | On | Any item flagged as rare in the item database |

Thresholds are configurable in **Configuration → Drop Tracking**. Drop counts appear in the main window and are saved with each run in history.

## Graphs

Six graph modes, cycled with the `<` / `>` buttons:

| Mode | Description |
|---|---|
| EXP/hr Rate | Live EXP per hour rate over time |
| Cumulative EXP | Total EXP gained over time |
| EXP per Floor | EXP gained in each floor area visited |
| Drops over Time | Cumulative tech disk, hit weapon, and rare drop counts over time |
| Drops per Floor | Drop counts broken down by floor area visited |
| Drop Breakdown | Three-bar summary of total rare, hit, and tech drops for the run |

## Session History

Completed runs are saved to `addons/Efficiency Scanner/history.lua` and persist across game sessions. Up to 50 runs are stored. Each entry records quest name, time, EXP, EXP/hr, difficulty, player count, drop counts, end reason, and timestamp.

## Configuration

Open via the addon menu. Options include window position, transparency, title bar visibility, and drop tracking thresholds.
