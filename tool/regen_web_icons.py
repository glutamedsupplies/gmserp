"""Regenerate web favicon/icons with a transparent background from the brand logo."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "branding" / "gmserp_logo_foreground.png"


def _is_brand_green(r: int, g: int, b: int, a: int) -> bool:
    return a > 40 and g > 120 and g > r and g > b + 40


def transparent_logo(src: Image.Image) -> Image.Image:
    """Keep the circular emblem; clear opaque black padding outside it."""
    im = src.convert("RGBA")
    w, h = im.size
    cx = (w - 1) / 2
    cy = (h - 1) / 2
    px = im.load()

    max_r = 0.0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if _is_brand_green(r, g, b, a):
                max_r = max(max_r, math.hypot(x - cx, y - cy))

    # Include anti-aliased outer ring just past the green edge.
    radius = max_r + max(w, h) * 0.01
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_px = out.load()
    for y in range(h):
        for x in range(w):
            if math.hypot(x - cx, y - cy) <= radius:
                out_px[x, y] = px[x, y]
    return out


def fit_icon(logo: Image.Image, size: int, pad_ratio: float = 0.06) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bbox = logo.getbbox()
    cropped = logo.crop(bbox) if bbox else logo
    max_side = max(1, int(size * (1 - 2 * pad_ratio)))
    fitted = cropped.copy()
    fitted.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def maskable_icon(
    logo: Image.Image,
    size: int,
    bg: tuple[int, int, int, int] = (0xA2, 0xD9, 0x29, 255),
    pad_ratio: float = 0.18,
) -> Image.Image:
    """Opaque brand fill for maskable PWA icons (safe zone)."""
    canvas = Image.new("RGBA", (size, size), bg)
    bbox = logo.getbbox()
    cropped = logo.crop(bbox) if bbox else logo
    max_side = max(1, int(size * (1 - 2 * pad_ratio)))
    fitted = cropped.copy()
    fitted.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def main() -> None:
    logo = transparent_logo(Image.open(SRC))
    outputs = {
        ROOT / "web" / "favicon.png": fit_icon(logo, 64, pad_ratio=0.04),
        ROOT / "web" / "icons" / "Icon-192.png": fit_icon(logo, 192),
        ROOT / "web" / "icons" / "Icon-512.png": fit_icon(logo, 512),
        ROOT / "web" / "icons" / "Icon-maskable-192.png": maskable_icon(logo, 192),
        ROOT / "web" / "icons" / "Icon-maskable-512.png": maskable_icon(logo, 512),
    }
    for path, img in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path, format="PNG", optimize=True)
        px = img.load()
        print(f"saved {path.relative_to(ROOT)} corner={px[0, 0]}")


if __name__ == "__main__":
    main()
