#!/usr/bin/env python3
"""Generates every WakaBoard icon asset from one vector description.

The mark is a five-bar chart whose tops are joined by a sparkline that traces a
``W`` — the initial and the product in a single figure. There is no binary source
image in the repository: the art is redrawn from the constants below, so a colour
or proportion change is a diff rather than a re-export from a design tool.

Rendering is done at ``SUPERSAMPLE``x and downscaled with Lanczos, which is what
gives the curves clean edges without any anti-aliasing support in Pillow's
drawing primitives.

Outputs, all overwritten in place:

* ``Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset`` — the iOS 1024pt
  single-size entry plus the ten macOS entries.
* ``docs/assets/wakaboard-wordmark.png`` — the lockup the README leads with.

Usage: ``python3 scripts/make-icon.py`` (requires Pillow).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
APPICON = ROOT / "Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset"
DOCS = ROOT / "docs/assets"

SUPERSAMPLE = 4

# Diagonal gradient stops, top-left to bottom-right. Deliberately unlike
# WakaTime's own blue: WakaBoard is an independent client and should not be
# mistaken for a first-party app.
GRADIENT = [
    (0.00, (67, 56, 202)),    # indigo 700
    (0.45, (99, 102, 241)),   # indigo 500
    (0.75, (139, 92, 246)),   # violet 500
    (1.00, (192, 132, 252)),  # purple 400
]

# Bar centres and bar-top heights in unit coordinates, y measured from the top.
# The five tops are the vertices of the W: outer peaks, inner valleys, and a
# middle peak held lower than the outer two so the letter reads correctly.
BAR_X = (0.205, 0.3525, 0.500, 0.6475, 0.795)
BAR_TOP = (0.250, 0.585, 0.392, 0.585, 0.250)
BASELINE = 0.775
BAR_WIDTH = 0.086
BAR_ALPHA = 98          # bars are texture; the sparkline is the mark
STROKE_WIDTH = 0.054
OPTICAL_LIFT = -0.012   # the art's bounding box sits low without this


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _gradient_colour(t: float) -> tuple[int, int, int]:
    """Samples the multi-stop gradient at ``t`` in [0, 1]."""
    t = min(max(t, 0.0), 1.0)
    for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if t <= t1:
            local = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(_lerp(c0[i], c1[i], local)) for i in range(3))
    return GRADIENT[-1][1]


def _background(size: int) -> Image.Image:
    """Draws the 135-degree gradient plus a soft top-left highlight.

    The gradient is computed at low resolution and upscaled: it is linear, so
    bicubic interpolation reproduces it exactly while skipping a million-pixel
    Python loop.
    """
    small = 128
    grad = Image.new("RGB", (small, small))
    pixels = grad.load()
    for y in range(small):
        for x in range(small):
            pixels[x, y] = _gradient_colour((x + y) / (2 * (small - 1)))
    base = grad.resize((size, size), Image.Resampling.BICUBIC)

    # A radial highlight off the top-left corner keeps the large icon from
    # looking like a flat swatch; it is invisible below about 64pt, which is
    # exactly where flatness stops being a problem.
    glow_small = 96
    glow = Image.new("L", (glow_small, glow_small), 0)
    gp = glow.load()
    cx, cy, radius = 0.24 * glow_small, 0.18 * glow_small, 0.72 * glow_small
    for y in range(glow_small):
        for x in range(glow_small):
            d = math.hypot(x - cx, y - cy) / radius
            gp[x, y] = round(78 * max(0.0, 1.0 - d) ** 2)
    mask = glow.resize((size, size), Image.Resampling.BICUBIC)
    base.paste(Image.new("RGB", (size, size), (255, 255, 255)), (0, 0), mask)
    return base


def _mark(size: int, bar_alpha: int = BAR_ALPHA) -> Image.Image:
    """Renders the bars and the W sparkline as a white RGBA layer."""
    art = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    draw = ImageDraw.Draw(art)

    def px(v: float) -> float:
        return v * size

    lift = px(OPTICAL_LIFT)
    half = px(BAR_WIDTH) / 2
    for x, top in zip(BAR_X, BAR_TOP):
        draw.rounded_rectangle(
            [px(x) - half, px(top) + lift, px(x) + half, px(BASELINE) + lift],
            radius=half,
            fill=(255, 255, 255, bar_alpha),
        )

    # Round joins and caps, drawn as segments plus a disc at every vertex.
    # Pillow's `line(joint="curve")` only rounds interior joins, not the ends.
    stroke = px(STROKE_WIDTH)
    points = [(px(x), px(top) + lift) for x, top in zip(BAR_X, BAR_TOP)]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        draw.line([x0, y0, x1, y1], fill=(255, 255, 255, 255), width=round(stroke))
    for x, y in points:
        r = stroke / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255))
    return art


def _shadow(art: Image.Image, size: int) -> Image.Image:
    """A blurred, offset copy of the mark, so it sits on the gradient rather
    than floating above it."""
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 92), (0, 0), art.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.022))
    offset = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset.paste(shadow, (0, round(size * 0.014)))
    return offset


def _squircle_mask(size: int, exponent: float = 5.0) -> Image.Image:
    """A superellipse mask approximating the macOS app-icon silhouette.

    macOS icons carry their own shape and margin; iOS masks the artwork itself,
    which is why the iOS entry is full-bleed and this is used only for the Mac
    idiom and the documentation asset.
    """
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    cx = cy = (size - 1) / 2
    r = (size - 1) / 2
    steps = 720
    points = []
    for i in range(steps):
        theta = 2 * math.pi * i / steps
        ct, st = math.cos(theta), math.sin(theta)
        x = math.copysign(abs(ct) ** (2 / exponent), ct)
        y = math.copysign(abs(st) ** (2 / exponent), st)
        points.append((cx + r * x, cy + r * y))
    draw.polygon(points, fill=255)
    return mask


def render(size: int, *, shaped: bool) -> Image.Image:
    """Renders one icon. ``shaped`` applies the macOS squircle and its margin."""
    work = size * SUPERSAMPLE
    # Below about 64pt the bars stop being texture and start being noise around
    # the sparkline, so they are faded rather than dropped: the chart reading
    # survives at 128pt and up, the letter stays legible in a 16pt menu row.
    art = _mark(work, BAR_ALPHA if size >= 64 else round(BAR_ALPHA * 0.55))
    canvas = _background(work).convert("RGBA")
    canvas.alpha_composite(_shadow(art, work))
    canvas.alpha_composite(art)

    if shaped:
        # 824/1024 is Apple's published live area for a macOS icon; the rest is
        # the margin the system expects to be transparent.
        inner = round(work * 824 / 1024)
        shaped_icon = canvas.resize((inner, inner), Image.Resampling.LANCZOS)
        shaped_icon.putalpha(_squircle_mask(inner))
        out = Image.new("RGBA", (work, work), (255, 255, 255, 0))
        out.alpha_composite(shaped_icon, ((work - inner) // 2, (work - inner) // 2))
        canvas = out

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def _wordmark(height: int = 320) -> Image.Image:
    """The README lockup: the shaped icon beside the product name."""
    icon = render(height, shaped=True)
    font_size = round(height * 0.42)
    font = None
    for candidate in (
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if Path(candidate).exists():
            font = ImageFont.truetype(candidate, font_size)
            break
    if font is None:  # pragma: no cover - every macOS host has one of the above
        font = ImageFont.load_default()

    gap = round(height * 0.06)
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    box = probe.textbbox((0, 0), "WakaBoard", font=font)
    text_w, text_h = box[2] - box[0], box[3] - box[1]

    canvas = Image.new("RGBA", (height + gap + text_w + gap, height), (0, 0, 0, 0))
    canvas.alpha_composite(icon, (0, 0))
    ImageDraw.Draw(canvas).text(
        (height + gap - box[0], (height - text_h) // 2 - box[1]),
        "WakaBoard",
        font=font,
        fill=(99, 102, 241, 255),
    )
    return canvas


# (filename, pixel size, shaped, Contents.json entry)
IOS_ENTRY = {"filename": "icon-ios-1024.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"}
MAC_POINTS = (16, 32, 128, 256, 512)


def _appicon_contents() -> dict:
    images = [dict(IOS_ENTRY)]
    for point in MAC_POINTS:
        for scale in (1, 2):
            images.append({
                "filename": f"icon-mac-{point}x{point}@{scale}x.png",
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{point}x{point}",
            })
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def main() -> None:
    APPICON.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)

    # iOS supplies one full-bleed, fully opaque 1024pt image; the system masks
    # and scales it. An alpha channel here is an App Store validation failure.
    render(1024, shaped=False).convert("RGB").save(APPICON / IOS_ENTRY["filename"])

    for point in MAC_POINTS:
        for scale in (1, 2):
            render(point * scale, shaped=True).save(
                APPICON / f"icon-mac-{point}x{point}@{scale}x.png"
            )

    (APPICON / "Contents.json").write_text(
        json.dumps(_appicon_contents(), indent=2) + "\n"
    )
    (APPICON.parent / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    _wordmark().save(DOCS / "wakaboard-wordmark.png")
    print("ICON_GENERATED_OK")


if __name__ == "__main__":
    main()
