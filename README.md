# Efficiency Scanner v0.4.0-beta

A PSO Blue Burst addon that tracks quest efficiency per run — EXP/hr, elapsed time, drop counts, and per-floor breakdowns — with persistent session history and configurable drop tracking thresholds.

> 📖 **Full documentation, configuration reference, and graph mode descriptions:**
> **[addons/Efficiency Scanner/README.md](addons/Efficiency%20Scanner/README.md)**

---

## Requirements

1. **PSOBB Addon Plugin** — provides the Lua runtime and `pso.*` API this addon depends on.
   - **PSOBB.IO**: bundled with the client, no separate install needed.
   - **Other servers**: [psobbaddonplugin](https://github.com/Solybum/psobbaddonplugin) + Visual C++ Redistributable 2015.
2. **solylib** — shared utility library used for item data lookups. Install from [PSOBBMod-Addons](https://github.com/Solybum/PSOBBMod-Addons) so that `solylib/` sits in the same `addons/` directory as `Efficiency Scanner/`.

## Quick Start

1. Install the addon plugin and solylib (see Requirements above).
2. Copy **`addons/Efficiency Scanner/`** from this repo into your PSOBB `addons/` directory.
3. Launch the game — the addon appears in the addon menu (default key: `` ` ``).
4. Enter a quest. Tracking starts automatically on your first floor transition out of Pioneer 2.
