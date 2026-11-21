#!/usr/bin/env python3
"""
Crop a magenta-background sprite sheet into individual poses.

Built for the 3x2 Frieren sheet. It:

1. Keys out the magenta background with a soft alpha and despill (un-premultiply
   against the background color), so no pink halos are left on the hair or robe.
2. Crops each cell from the grid.
3. Scales every pose with the same factor and anchors it by the face (eye
   midpoint, or skin center when the eyes are closed), so the face does not jump
   between poses.
4. Grounds each pose on the original sprite's feet line. The "happy" pose keeps
   the cell line so the little jump is preserved.
5. Saves each pose as a 228x256 PNG and writes poses.json with the eye
   rectangles, skin color and gem position, so QML can blink and make the staff
   glow in the right place.
6. Renders a preview on a dark background for a quick visual check.

Usage:
    python3 tools/slice_spritesheet.py "assets/frieren-sheet.png"

Optional:
    --cols 3 --rows 2 --names idle,think,cast,happy,sad,sleep
    --scale 0.5 --canvas 228x256 --ground-y 253 --ground-line 501
    --jump happy
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

# Names follow the grid reading order: left to right, top to bottom.
DEFAULT_NAMES = ["idle", "think", "cast", "happy", "sad", "sleep"]
DEFAULT_KEY = (250, 3, 250)
DEFAULT_CANVAS = (228, 256)


def parse_canvas(raw: str) -> tuple[int, int]:
    w, h = raw.lower().split("x")
    return int(w), int(h)


def key_magenta(
    im: Image.Image,
    bg: tuple[int, int, int],
    low: int = 20,
    high: int = 200,
    cut: float = 0.06,
) -> Image.Image:
    """Return RGBA with the magenta removed and despilled edges.

    `m = min(r, b) - g` measures how magenta a pixel is. Pure background is
    ~247, skin and gold are negative, the red gem is ~6. low/high build a soft
    alpha; then the real edge color is recovered by solving
    `pixel = a * fg + (1 - a) * bg`.
    """
    rgb = im.convert("RGB")
    w, h = rgb.size
    out = Image.new("RGBA", (w, h))
    src = rgb.load()
    dst = out.load()
    br, bgc, bb = bg

    def clamp(v: float) -> int:
        return max(0, min(255, int(round(v))))

    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            m = min(r, b) - g
            if m >= high:
                a = 0.0
            elif m <= low:
                a = 1.0
            else:
                a = (high - m) / (high - low)

            if a <= cut:
                dst[x, y] = (0, 0, 0, 0)
                continue
            if a >= 0.995:
                dst[x, y] = (r, g, b, 255)
                continue

            inv = 1.0 - a
            dst[x, y] = (
                clamp((r - inv * br) / a),
                clamp((g - inv * bgc) / a),
                clamp((b - inv * bb) / a),
                round(a * 255),
            )
    return out


def clusters(points: set[tuple[int, int]], gap: int = 2) -> list[list[tuple[int, int]]]:
    """Group neighboring points (chebyshev <= gap) without numpy."""
    pending = set(points)
    found: list[list[tuple[int, int]]] = []
    offsets = [
        (dx, dy)
        for dx in range(-gap, gap + 1)
        for dy in range(-gap, gap + 1)
        if dx or dy
    ]
    while pending:
        seed = pending.pop()
        comp = [seed]
        stack = [seed]
        while stack:
            cx, cy = stack.pop()
            for dx, dy in offsets:
                q = (cx + dx, cy + dy)
                if q in pending:
                    pending.remove(q)
                    comp.append(q)
                    stack.append(q)
        found.append(comp)
    return found


def bbox_of(points: list[tuple[int, int]]) -> tuple[int, int, int, int] | None:
    if not points:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def color_hex(rgb: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % rgb


def analyse(cell: Image.Image) -> dict:
    """Find eyes, skin and gem in an already transparent cell."""
    px = cell.load()
    w, h = cell.size
    skin: set[tuple[int, int]] = set()
    green: set[tuple[int, int]] = set()
    red: set[tuple[int, int]] = set()

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            if r > 200 and g > 170 and b > 120 and (r - g) > 8 and (g - b) > 4:
                skin.add((x, y))
            elif g > 85 and g > r + 20 and g > b + 10:
                green.add((x, y))
            elif r > 140 and r > g + 60 and r > b + 40:
                red.add((x, y))

    skin_comps = sorted(clusters(skin), key=len, reverse=True)
    face = skin_comps[0] if skin_comps else []
    face_center = None
    skin_color = None
    if face:
        face_center = (
            sum(p[0] for p in face) / len(face),
            sum(p[1] for p in face) / len(face),
        )
        # The mode is more stable than the average for a flat color.
        skin_color = Counter(px[x, y][:3] for x, y in face).most_common(1)[0][0]

    eye_comps = [c for c in clusters(green) if len(c) >= 20]
    eye_comps.sort(key=len, reverse=True)
    eye_comps = eye_comps[:2]
    eye_comps.sort(key=lambda c: sum(p[0] for p in c) / len(c))
    eyes = [bbox_of(c) for c in eye_comps]
    eyes = [e for e in eyes if e is not None]

    red_comps = sorted(clusters(red), key=len, reverse=True)
    gem = bbox_of(red_comps[0]) if red_comps else None

    return {
        "face_center": face_center,
        "skin": skin_color,
        "eyes": eyes,
        "gem": gem,
    }


def build_pose(
    cell: Image.Image,
    info: dict,
    *,
    scale: float,
    canvas: tuple[int, int],
    ground_y: int,
    ground_line: int,
    align: str,
    bbox: tuple[int, int, int, int],
) -> tuple[Image.Image, dict]:
    cw, ch = cell.size
    cw2, ch2 = canvas

    eyes = info["eyes"]
    if eyes:
        anchor_x = sum((e[0] + e[2]) / 2 for e in eyes) / len(eyes)
    elif info["face_center"]:
        anchor_x = info["face_center"][0]
    else:
        anchor_x = cw / 2

    if align == "cell":
        bottom = ground_line
    else:
        bottom = bbox[3]

    place_x = cw2 / 2 - anchor_x * scale
    place_y = ground_y - bottom * scale

    scaled = cell.resize((round(cw * scale), round(ch * scale)), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(scaled, (round(place_x), round(place_y)))

    def sx(v: float) -> float:
        return place_x + v * scale

    def sy(v: float) -> float:
        return place_y + v * scale

    skin = color_hex(info["skin"]) if info["skin"] else "#f8e8d7"
    meta: dict = {"file": "", "eyes": [], "skin": skin}

    # Slightly larger than the iris so the blink covers the whole eye, not
    # only the green part.
    for ex0, ey0, ex1, ey1 in eyes:
        meta["eyes"].append(
            [
                round(sx(ex0 - 3)),
                round(sy(ey0 - 2)),
                round((ex1 - ex0 + 6) * scale),
                round((ey1 - ey0 + 4) * scale),
            ]
        )

    if info["gem"]:
        gx0, gy0, gx1, gy1 = info["gem"]
        meta["glow"] = [round(sx((gx0 + gx1) / 2)), round(sy((gy0 + gy1) / 2))]

    return out, meta


def make_preview(poses: dict[str, Image.Image], names: list[str], canvas: tuple[int, int]) -> Image.Image:
    cw, ch = canvas
    pad = 12
    label_h = 20
    cols = 3
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGB", (cols * (cw + pad) + pad, rows * (ch + pad + label_h) + pad), (24, 22, 28))
    draw = ImageDraw.Draw(out)
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        x = pad + c * (cw + pad)
        y = pad + r * (ch + pad + label_h)
        bg = Image.new("RGBA", canvas, (43, 41, 47, 255))
        bg.alpha_composite(poses[name])
        out.paste(bg.convert("RGB"), (x, y))
        draw.text((x + 4, y + ch + 3), name, fill=(214, 205, 220))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Crop a magenta-background sprite sheet.")
    parser.add_argument("sheet", type=Path, help="sprite sheet PNG")
    parser.add_argument("--out", type=Path, default=None, help="output directory (default: assets/poses)")
    parser.add_argument("--cols", type=int, default=3)
    parser.add_argument("--rows", type=int, default=2)
    parser.add_argument("--names", default=",".join(DEFAULT_NAMES))
    parser.add_argument("--scale", type=float, default=0.5)
    parser.add_argument("--canvas", default="228x256")
    parser.add_argument("--ground-y", type=int, default=253)
    parser.add_argument("--ground-line", type=int, default=501)
    parser.add_argument(
        "--jump",
        default="happy",
        help="poses that keep the cell baseline so the jump is preserved (comma-separated)",
    )
    parser.add_argument("--key-color", default="250,3,250", help="background color, r,g,b")
    parser.add_argument("--preview", type=Path, default=None)
    args = parser.parse_args()

    names = [n.strip() for n in args.names.split(",") if n.strip()]
    if len(names) != args.cols * args.rows:
        parser.error(f"--names has {len(names)} names but the grid is {args.cols}x{args.rows}")

    canvas = parse_canvas(args.canvas)
    key = tuple(int(v) for v in args.key_color.split(","))
    jump = {n.strip() for n in args.jump.split(",") if n.strip()}

    sheet = Image.open(args.sheet).convert("RGB")
    cw, ch = sheet.size[0] // args.cols, sheet.size[1] // args.rows

    out_dir = args.out or (Path(__file__).resolve().parent.parent / "quickshell/frieren/assets/poses")
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict = {"canvas": list(canvas), "poses": {}}
    rendered: dict[str, Image.Image] = {}

    for i, name in enumerate(names):
        r, c = divmod(i, args.cols)
        raw_cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
        cell = key_magenta(raw_cell, key)
        bbox = bbox_of([(x, y) for y in range(cell.size[1]) for x in range(cell.size[0]) if cell.getpixel((x, y))[3] > 16])
        if bbox is None:
            raise SystemExit(f"cell {name} is empty")
        info = analyse(cell)
        pose, meta = build_pose(
            cell,
            info,
            scale=args.scale,
            canvas=canvas,
            ground_y=args.ground_y,
            ground_line=args.ground_line,
            align="cell" if name in jump else "ground",
            bbox=bbox,
        )
        meta["file"] = f"{name}.png"
        pose.save(out_dir / meta["file"])
        rendered[name] = pose
        manifest["poses"][name] = meta
        print(f"{name:6} -> {meta['file']}  eyes={len(meta['eyes'])}  gem={meta.get('glow')}")

    (out_dir / "poses.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"manifest: {out_dir / 'poses.json'}")

    preview_path = args.preview or (out_dir / "preview.png")
    make_preview(rendered, names, canvas).save(preview_path)
    print(f"preview:  {preview_path}")


if __name__ == "__main__":
    main()
