# Rhythm Side-Scroller — Dev Doc

## Overview

A 2D side-scrolling beat-em-up inspired by Bad Dudes. The player walks right, fights waves of enemies, and eventually reaches a boss. The core twist: all combat is rhythm-gated — punches and blocks only work in specific beat windows.

**Engine:** Godot 4.6.1  
**Target Platforms:** Desktop (Windows/Mac/Linux) + Mobile (Android/iOS, landscape)  
**Art Style:** TBD — placeholder colored rectangles, architecture supports hand-drawn 2D, pixel art, or voxel 3D  
**Status:** Phase 2 complete. Phase 3 in progress — player sprite set generated.

**Paths:**
- Project (Windows): `C:\Users\Xliminal\Code\PersonalProjects\Rythmic_Side_Scroller`
- Project (WSL): `/mnt/c/Users/Xliminal/Code/PersonalProjects\Rythmic_Side_Scroller`
- Godot executable: `C:\Users\Xliminal\Godot\Godot_v4.6.1-stable_win64_console.exe`

---

## Current State

### What works
- Player walks left/right, punches (Space), blocks (Z hold)
- Beat map loaded from `assets/beat_maps/fast_shadow.json` — 327 per-beat timestamps extracted offline via librosa
- `rhythm_engine.gd` uses `AudioServer` latency compensation for tight sync
- `is_on_beat()` and `is_on_offbeat()` (beat midpoint) both available
- HUD: orange square flashes on beat, yellow square flashes on off-beat
- Enemies inflate slowly while in range (visual telegraph), deflate on punch
- Enemies punch player on beat every 2 beats — green fist square extends
- Full combo system (see below)
- Enemy HP = 1 (tunable) — any completed combo kills

---

## Combat System

### Beat Windows
- **On-beat**: within 80ms of a beat timestamp (orange flash)
- **Off-beat**: within 80ms of the midpoint between two beats (yellow flash)

### Player Actions
| Action | Key | Beat requirement |
|---|---|---|
| Punch | Space | On-beat to hit; off-beat to combo-finish |
| Block | Z (hold) | Only active during on-beat window |
| Duck | S (hold) | Any time — dodges enemy punches |
| Uppercut | S + Space | Must be on-beat; only fires from duck state |
| Move | A / D / ← / → | Any time (including while ducking) |

### Combo System

Enemies only die from a completed Quad Combo. Double and Triple combos open the path to quad but deal no damage on their own.

**Double Combo** (2 hits) — no damage
1. Punch on-beat → enemy flashes red (combo armed)
2. Punch off-beat → enemy flashes purple (combo resets, no kill)

**Triple Combo** (3 hits) — no damage, opens quad window
1. Block enemy's on-beat punch → player flashes yellow (combo armed)
2. Punch off-beat → enemy flashes orange
3. Punch on-beat → enemy flashes purple (quad window opens)

**Quad Combo** (4 hits) — kills enemy
1. Block enemy's on-beat punch → player flashes yellow
2. Punch off-beat → enemy flashes orange
3. Punch on-beat → enemy flashes purple (quad window opens)
4. **Uppercut on-beat** (S + Space) → enemy launches into air in slow-mo, fades out

Regular on-beat punch at stage 4 whiffs — only the uppercut closes it out.

**Uppercut kill animation:** enemy shoots upward ~400px (EASE_OUT quad arc), random horizontal drift, holds full opacity 0.4s then fades over 1.8s, sprite stretches tall as it rises.

Miss any step or let combo timer (0.6s) expire → combo resets, must restart.

### Enemy Behavior
- States: `APPROACH | ATTACK | PUNCH | HIT | DEAD`
- Approaches player, stops at melee range
- Inflates (scale 1.0→1.2) while in ATTACK state — deflates instantly on punch (the tell)
- Punches every 2nd beat; fist appears simultaneously with hit check
- Unblocked hit → player flashes red; blocked hit → player flashes yellow + enemy combo armed

---

## Beat Sync

Offline beat extraction via **librosa** (`beat_extract.py` in project root).

```bash
# From project root (WSL):
.venv/bin/python beat_extract.py "assets/audio/music/MySong.ogg"
# Output: assets/beat_maps/myson.json
```

Rhythm engine falls back to BPM clock if JSON is absent. Tap-calibration (T key ×8) available for new songs.

---

## Phases

### Phase 1 — Core Brawler ✅
- Player movement, punch, block
- Enemy spawn, approach, take damage, die
- Placeholder art (colored rectangles)

### Phase 2 — Rhythm Layer ✅ (mostly)
- Beat map from offline librosa analysis
- Latency-compensated audio clock
- On-beat / off-beat windows
- Double, triple, quad combo system
- Enemy telegraphed punches

### Phase 3 — Content & Polish
- ✅ Player sprite set generated (see `assets/sprites/player/`)
- ✅ Enemy grunt sprite set — Last Dragon / Sho'nuff crew aesthetic (`assets/sprites/enemies/grunt/`)
  - AnimatedSprite2D wired, faces player each frame via `_face_player()`
  - Idle/walk/punch animations, modulate hit flashes
- ✅ Sprite background removal pipeline (`strip_bg.py`, auto-runs in `sprite_gen.py`)
  - Flood fill threshold 230, feather 200 (catches near-white and fake checkerboard ~235 pixels)
  - Enemy grunt re-stripped at feather 180 to clear inner-arm fringe
- ✅ Parallax background — 4-layer street-level night scene wired into `main.tscn` (sky, mid alley, near wall, perspective floor)
- ✅ Player camera follow
- Player HP and death
- Boss fight
- Sound effects, screenshake
- Scoring system
- Level length / win condition
- Mobile build

### Phase 4 — Co-op (stretch)
- Second player as a second `CharacterBody2D` using the same `player.gd` script
- Input abstraction: player 1 reads keyboard, player 2 reads gamepad (or split keyboard)
- Shared `RhythmEngine` — both players on the same beat clock
- Enemy aggro split between players
- Combo system works independently per player

---

## Scene Structure

```
Main (Node2D)
├── World (Node2D)
│   └── Ground (StaticBody2D)
├── Player (CharacterBody2D)
│   ├── Sprite (ColorRect, blue, 90×180)
│   ├── CollisionShape2D
│   └── Hitbox (Area2D)
├── EnemySpawner (Node2D)
├── RhythmEngine (Node)
└── HUD (CanvasLayer)
    ├── BeatIndicator (ColorRect, orange)
    └── OffbeatIndicator (ColorRect, yellow)
```

---

## Art Strategy

`AnimatedSprite2D` nodes for all characters — swapping art = replacing `SpriteFrames` resource only.

- **Placeholder:** `ColorRect` nodes. Player = blue (90×180), enemies = green (90×180)
- **Current:** AI-generated comic-style sprites via Gemini Imagen 4 / gemini-2.5-flash-image (transparent PNG, white bg auto-stripped)
- **Hand-drawn 2D:** PNG sprite sheets → `SpriteFrames`
- **Voxel 3D:** `SubViewport` renders 3D to texture → `Sprite2D`
- **Resolution:** `canvas_items` stretch, base `1280×720`

### Player Sprite Set (`assets/sprites/player/`)

Character: middle-aged heavyset Black man, cornrow braids, dark grey zip-up hoodie, cargo pants. Ghost Dog / Forest Whitaker aesthetic.
Generated with `sprite_gen.py` using Gemini API (`--ref` mode for consistency).

| File | Animation | Notes |
|---|---|---|
| `idle_1.png` – `idle_6.png` | Idle breathing loop | Sequence: 1→2→3→4→5→6→loop |
| `walk_1.png`, `walk_2.png` | Walk cycle | 2-frame placeholder; needs more frames for smooth loop |
| `punch_1.png`, `punch_2.png` | Cross punch | Two variants, both usable |
| `uppercut.png` | Uppercut | Fist high, explosive |
| `crouch.png` | Crouch/dodge | Low guard, hands up |
| `block.png` | Block | Forearms crossed, wide stance |

**Walk cycle note:** AI-generated frames don't produce correct opposing arm/leg timing. Treat as placeholder until hand-tweaked or redrawn in Phase 3 polish pass.

---

## Audio

- `assets/audio/beat_click.wav` — metronome click
- `assets/audio/music/Fast Shadow.ogg` — current song, ~107.7 BPM
- `assets/beat_maps/fast_shadow.json` — 327 beat timestamps (ms)

---

## File Structure

```
Rythmic_Side_Scroller/
├── beat_extract.py           # offline beat map generator (librosa)
├── sprite_gen.py             # Gemini image generator (Imagen 4 / flash-image, auto strips bg)
├── strip_bg.py               # standalone white-bg remover for existing PNGs
├── devdoc.md
├── project.godot
├── .venv/                    # Python venv (librosa + google-genai), WSL only
├── scenes/
│   ├── main.tscn
│   ├── player.tscn
│   ├── enemy.tscn
│   └── hud.tscn
├── scripts/
│   ├── player.gd
│   ├── enemy.gd
│   ├── enemy_spawner.gd
│   ├── rhythm_engine.gd
│   ├── spectrum_debug.gd
│   └── hud.gd
└── assets/
    ├── audio/
    │   ├── beat_click.wav
    │   └── music/
    ├── beat_maps/
    └── sprites/
        ├── player/           # final selected sprites (13 files, transparent)
        ├── enemies/grunt/    # 7 frames: idle x3, walk x2, punch x2
        ├── background/       # parallax layers: bg_sky_v2_2, bg_mid_v2_2, bg_near_v2_1, bg_floor_v2_2
        └── generated/        # raw AI generation output
```

---

## Open Questions / TBD

- [ ] Player HP and death state
- [ ] Enemy variety and attack patterns
- [ ] Boss design
- [ ] Final art style (hand-drawn 2D vs pixel art vs voxel 3D)
- [ ] Scoring / combo multiplier display
- [ ] Level length / win condition
- [ ] Song structure data for breakdown combos
- [ ] Mobile build + publishing
