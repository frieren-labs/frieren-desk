#!/usr/bin/env python3
"""
Render the README showcase from the real pose sprites.

Composes assets/poses-preview.png: every Frieren pose next to the chat line
she shows in that state, on a Hyprland-style dark desktop. The sprites are the
exact PNGs the shell loads, so the image matches what you get after install.

Usage:
    python3 tools/make_poses_preview.py
    python3 tools/make_poses_preview.py --out assets/poses-preview.png --scale 2

Requires Pillow (already needed by tools/slice_spritesheet.py).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
POSES = ROOT / "quickshell" / "frieren" / "assets" / "poses"
ICON = ROOT / "quickshell" / "frieren" / "assets" / "frieren-icon.png"
DEFAULT_OUT = ROOT / "assets" / "poses-preview.png"

# ---------------- palette (matches ChatPanel.qml / PetSprite.qml) ----------------
BG_TOP = (19, 17, 24)
BG_BOTTOM = (26, 24, 29)
BAR_BG = (23, 21, 28)
BAR_LINE = (42, 39, 50)
PANEL = (30, 28, 34)
PANEL_LINE = (48, 45, 54)
TEXT = (236, 231, 241)
TEXT_DIM = (154, 147, 166)
LABEL = (139, 132, 150)
ACCENT = (208, 188, 255)
DANGER = (242, 184, 181)
WARM = (245, 208, 138)
COOL = (150, 189, 236)

# ---------------- layout, in logical pixels ----------------
W, H = 1200, 630
MARGIN = 28
BAR_H = 30
GRID_Y = 108
GAP = 18
COLS, ROWS = 3, 2
CELL_W = (W - 2 * MARGIN - 2 * GAP) // COLS
CELL_H = (H - GRID_Y - MARGIN - (ROWS - 1) * GAP) // ROWS

SPRITE_H = 172
SPRITE_W = round(SPRITE_H * 228 / 256)
CELL_PAD = 14
RADIUS = 16

# name, label, chat line, glow color
SCENES = [
    ("idle", "idle", "ask me something", (150, 130, 200)),
    ("think", "think", "thinking\u2026", (170, 150, 240)),
    ("cast", "cast", "casting a spell\u2026", (190, 160, 255)),
    ("happy", "happy", "done", WARM),
    ("sad", "sad", "oops\u2026", DANGER),
    ("sleep", "sleep", "zzz\u2026", COOL),
]

BUBBLE_TEXT = {
    "idle": TEXT,
    "think": ACCENT,
    "cast": ACCENT,
    "happy": WARM,
    "sad": DANGER,
    "sleep": COOL,
}


def find_font(names: list[str]) -> Path:
    roots = [
        Path("/usr/share/fonts"),
        Path.home() / ".local/share/fonts",
        Path.home() / ".fonts",
    ]
    for name in names:
        for root in roots:
            if not root.exists():
                continue
            for path in root.rglob(name):
                return path
    raise SystemExit(f"missing font: {names[0]}")


FONT_SANS = find_font(["DejaVuSans.ttf", "NotoSans-Regular.ttf"])
FONT_BOLD = find_font(["DejaVuSans-Bold.ttf", "NotoSans-Bold.ttf"])
FONT_MONO = find_font(["DejaVuSansMono.ttf", "NotoSansMono-Regular.ttf"])


def font(path: Path, size: float, ss: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), round(size * ss))


def tracked_width(draw: ImageDraw.ImageDraw, text: str, f, tracking: float) -> float:
    return sum(draw.textlength(ch, font=f) + tracking for ch in text) - tracking


def draw_tracked(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    f,
    fill: tuple[int, int, int],
    tracking: float,
    right: bool = False,
) -> None:
    x, y = xy
    if right:
        x -= tracked_width(draw, text, f, tracking)
    for ch in text:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking


def load_pose(name: str, ss: int) -> Image.Image:
    return Image.open(POSES / f"{name}.png").convert("RGBA").resize(
        (SPRITE_W * ss, SPRITE_H * ss), Image.LANCZOS
    )


def soft_shadow(sprite: Image.Image, blur: float, opacity: int) -> Image.Image:
    alpha = sprite.getchannel("A").filter(ImageFilter.GaussianBlur(blur))
    alpha = alpha.point(lambda a: a * opacity // 255)
    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(alpha)
    return shadow


def radial_glow(size: tuple[int, int], color: tuple[int, int, int], alpha: int) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    w, h = size
    draw.ellipse((w * 0.18, h * 0.18, w * 0.82, h * 0.82), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(w * 0.16))


def gradient(size: tuple[int, int], top, bottom) -> Image.Image:
    w, h = size
    strip = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        strip.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize((w, h), Image.BILINEAR).convert("RGBA")


def build(ss: int) -> Image.Image:
    canvas = gradient((W * ss, H * ss), BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(canvas)

    f_title = font(FONT_BOLD, 25, ss)
    f_sub = font(FONT_SANS, 12.5, ss)
    f_label = font(FONT_MONO, 10, ss)
    f_chat = font(FONT_SANS, 13, ss)
    f_clock = font(FONT_MONO, 10, ss)

    # ---------------- top bar ----------------
    draw.rectangle((0, 0, W * ss, BAR_H * ss), fill=BAR_BG + (255,))
    draw.rectangle((0, BAR_H * ss, W * ss, BAR_H * ss + ss), fill=BAR_LINE + (255,))

    x = MARGIN
    for i in range(5):
        color = ACCENT if i == 0 else (58, 54, 66)
        draw.rounded_rectangle(
            (x * ss, 12 * ss, (x + 16) * ss, 18 * ss), radius=3 * ss, fill=color + (255,)
        )
        x += 22

    draw_tracked(draw, ((W - MARGIN - 26) * ss, 10 * ss), "09:41", f_clock, TEXT_DIM, 0.6 * ss, right=True)
    if ICON.exists():
        icon = Image.open(ICON).convert("RGBA").resize((16 * ss, 16 * ss), Image.LANCZOS)
        canvas.alpha_composite(icon, ((W - MARGIN - 16) * ss, 7 * ss))

    # ---------------- header ----------------
    draw.text((MARGIN * ss, 48 * ss), "Frieren Desk", font=f_title, fill=TEXT)
    draw.text(
        (MARGIN * ss, 82 * ss),
        "Every pose, with her chat right beside it",
        font=f_sub,
        fill=TEXT_DIM,
    )

    # ---------------- pose grid ----------------
    for index, (name, label, line, glow) in enumerate(SCENES):
        row, col = divmod(index, COLS)
        cx = MARGIN + col * (CELL_W + GAP)
        cy = GRID_Y + row * (CELL_H + GAP)

        draw.rounded_rectangle(
            (cx * ss, cy * ss, (cx + CELL_W) * ss, (cy + CELL_H) * ss),
            radius=RADIUS * ss,
            fill=PANEL + (255,),
            outline=PANEL_LINE + (255,),
            width=ss,
        )

        sprite = load_pose(name, ss)
        sx, sy = cx + CELL_PAD, cy + 10

        halo = radial_glow((sprite.width, sprite.height), glow, 34)
        canvas.alpha_composite(halo, (sx * ss, sy * ss))

        shadow = soft_shadow(sprite, blur=6 * ss, opacity=110)
        canvas.alpha_composite(shadow, ((sx) * ss, (sy + 6) * ss))
        canvas.alpha_composite(sprite, (sx * ss, sy * ss))

        # bubble beside the sprite
        text_color = BUBBLE_TEXT[name]
        text_w = draw.textlength(line, font=f_chat)
        bw = min(CELL_W - CELL_PAD * 2 - SPRITE_W - 10, max(96 * ss, text_w + 22 * ss))
        bh = 34 * ss
        bx = (sx + SPRITE_W + 10) * ss
        by = (sy + 70) * ss

        draw.rounded_rectangle(
            (bx, by, bx + bw, by + bh),
            radius=12 * ss,
            fill=(43, 41, 49, 255),
            outline=(73, 69, 78, 255),
            width=ss,
        )
        tip_y = by + bh // 2
        draw.polygon(
            [
                (bx, tip_y - 4 * ss),
                (bx - 6 * ss, tip_y),
                (bx, tip_y + 4 * ss),
            ],
            fill=(43, 41, 49, 255),
        )
        draw.line(
            [(bx - 6 * ss, tip_y), (bx, tip_y - 4 * ss)],
            fill=(73, 69, 78, 255),
            width=ss,
        )
        draw.line(
            [(bx - 6 * ss, tip_y), (bx, tip_y + 4 * ss)],
            fill=(73, 69, 78, 255),
            width=ss,
        )
        draw.text(
            (bx + 11 * ss, by + bh // 2),
            line,
            font=f_chat,
            fill=text_color,
            anchor="lm",
        )

        # caption
        draw_tracked(
            draw,
            ((cx + CELL_PAD) * ss, (cy + CELL_H - 23) * ss),
            label.upper(),
            f_label,
            LABEL,
            1.3 * ss,
        )
        dot_y = (cy + CELL_H - 17) * ss
        draw.ellipse(
            (
                (cx + CELL_W - CELL_PAD - 5) * ss,
                dot_y - 5 * ss,
                (cx + CELL_W - CELL_PAD) * ss,
                dot_y + 0 * ss,
            ),
            fill=glow + (255,),
        )

    return canvas.resize((W * ss // 2, H * ss // 2), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--scale", type=int, default=2, help="output pixel density")
    args = parser.parse_args()

    if args.scale < 1:
        raise SystemExit("--scale must be >= 1")

    image = build(ss=args.scale * 2)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.out, "PNG", optimize=True)
    print(f"wrote {args.out} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
