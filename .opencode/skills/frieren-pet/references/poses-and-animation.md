# Poses and animation

All of this lives in `components/PetSprite.qml`, `assets/poses/poses.json` and
`tools/slice_spritesheet.py`.

## Pose selection

`mood` is a read-only binding. First match wins:

| Order | Condition | Pose |
| --- | --- | --- |
| 1 | `reaction === "error"` | `sad` |
| 2 | `reaction === "ok"` or `reaction === "wake"` | `happy` |
| 3 | `asleep` | `sleep` |
| 4 | `toolActive` | `cast` |
| 5 | `busy` | `think` |
| 6 | `wandering` | `walk`, which is not in `poses.json` and falls back to `idle` |
| 7 | default | `idle` |

`reaction` clears after 1100 ms. If you add a pose, add it to the mood mapping,
to `poses.json`, and to the README table.

## Inputs from the shell

| Property | Meaning |
| --- | --- |
| `busy` | opencode is reasoning |
| `toolActive` | a tool is running |
| `chatOpen` | chat panel visible; adds a small lean |
| `lookDir` | +1 chat on the right, -1 on the left |
| `wanderEnabled` | allow autonomous movement |
| `sleepEnabled` | allow sleeping when idle |
| `blinkEnabled` | allow blinking |
| `uiScale` | pet scale, 0.7 to 1.4 |
| `accent`, `danger`, `textDim`, `surface`, `outline` | theme colors |

## Timers

### Idle and sleep

`ticker` runs every second:

- It resets `idleSeconds` to 0 when `busy`, `toolActive`, `wandering`,
  `chatOpen`, `hovered` or `asleep` is true.
- Otherwise it increments `idleSeconds`.
- At 180 seconds, with `sleepEnabled`, it sets `asleep = true`.

Sleeping resets the counter every tick, so the pet stays asleep until an event
wakes her. Wake paths:

- Mouse enters the pet (`onEntered`).
- Mouse press or drag (`onPressed`).
- Click without dragging also emits `activate`, which toggles the chat.
- `sleepEnabled` turns false (`onSleepEnabledChanged`).
- The shell calls `pet.wake()` after restore, send, fresh or toggle.

If `sleepEnabled` becomes false while asleep, the pet wakes immediately. There
is no automatic wake after a fixed time.

### Wander

`wanderTimer` fires every 25 to 60 seconds. It skips when wandering is disabled,
the chat is open, opencode is busy or casting, the pet is asleep, hovered,
dragged or already moving.

`wander()` picks a target up to 130 px horizontally and 70 px vertically away,
keeps 6 px from the edges, and avoids the top bar and bottom dock by clamping to
60 px. The animation lasts between 800 and 3200 ms based on distance. On finish
it emits `moved`, which saves state and may minimize if the pet ended near a bar.

### Blink

`blinkTimer` starts at 4200 ms, then picks 2600 to 6400 ms. It only animates when
the pet is awake, blinking is enabled, the pose has eye rectangles and no
reaction is active. The blink covers each eye with a rounded rectangle filled
with the pose skin color.

### Reaction

`reactionTimer` clears `reaction` after 1100 ms.

## Sleep presentation

When `asleep` is true:

- Body opacity drops to 0.82 and the ground shadow to 60 percent.
- Bobbing, sway and breathing slow to 3800 or 6000 ms.
- Hair sway stops.
- Blink stops.
- A three-letter `z` layer animates with `sleepPhase` over 3200 ms.
- The status hint is empty.

## poses.json schema

```json
{
  "canvas": [228, 256],
  "poses": {
    "idle": {
      "file": "idle.png",
      "eyes": [[95, 74, 10, 9], [123, 74, 10, 10]],
      "skin": "#fae7d7",
      "glow": [59, 116]
    }
  }
}
```

| Field | Meaning |
| --- | --- |
| `canvas` | Logical sprite size used by the QML geometry helpers |
| `file` | PNG name inside `assets/poses/` |
| `eyes` | Rectangles `[x, y, w, h]` in canvas coordinates for blinking |
| `skin` | Fill color for the blink rectangles |
| `glow` | Staff gem center `[x, y]` for the cast glow and particles |

Missing fields fall back to the `idle` pose metadata, then to hardcoded defaults.

## Sprite pipeline

`tools/slice_spritesheet.py` expects a magenta-background sheet, default 3x2:

```bash
python3 tools/slice_spritesheet.py assets/frieren-sheet.png
```

Development only: the installed app does not need Python. This script rebuilds
the checked-in pose assets.

It keys out magenta with a soft alpha and despill, crops each cell, scales all
poses by the same factor, anchors by the face, grounds the feet, writes six
228x256 PNGs, generates `poses.json`, and renders `preview.png`.

Defaults: names `idle,think,cast,happy,sad,sleep`, scale 0.5, canvas 228x256,
ground y 253, ground line 501, jump pose `happy`. Override with flags when the
sheet layout changes.

`tools/make_poses_preview.py` builds the README showcase from the generated
poses, so run it after changing art.

## Animation layers

The component stacks, from bottom to top:

1. Ground shadow, scaled and faded by hop height.
2. Bobbing item with breathing scale, hair shear and lean rotation.
3. Sprite crossfade: two `Image` items, 170 ms fade.
4. Blink rectangles.
5. Cast glow, particles and pulsing gem while `mood === "cast"`.
6. Success sparkles during `burst`.
7. Sleeping `z` letters.
8. Thinking dots while `mood === "think"`.
9. Error bubble with `!` while `reaction === "error"`.
10. Status hint above or below the pet.

## Pitfalls

- Do not add a timer that runs while the panel is hidden or minimized without
  gating it on visibility. Quickshell keeps QML animations alive.
- Do not assume `wandering` shows a walk pose. It currently shows `idle`.
- Do not flip the sprite with `lookDir` without checking the blink rectangles,
  which are defined in unflipped canvas coordinates.
- Keep the canvas at 228x256 unless you update `spriteW`, `spriteH`,
  `poses.json` and every image.
- The hint text must stay empty while asleep.
