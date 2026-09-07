#!/usr/bin/env python3
"""Regenerate website WebP variants from the original artwork and screenshots.

Requires Pillow with WebP support; only needed when source images change.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    output = ROOT / "site/assets"
    output.mkdir(parents=True, exist_ok=True)
    sources = [(ROOT / "docs/branding/lightning-premium.png", (400, 800, 1200), False)]
    sources += [(ROOT / f"docs/images/webui-{name}.png", (480, 800, 1000), True)
                for name in ("overview", "profiles", "maintenance")]
    for source, widths, lossless in sources:
        with Image.open(source) as original:
            for width in widths:
                height = round(original.height * width / original.width)
                image = original.resize((width, height), Image.Resampling.LANCZOS)
                path = output / f"{source.stem}-{width}.webp"
                image.save(path, "WEBP", quality=90 if lossless else 85,
                           lossless=lossless and width == 1000, method=6)
                print(f"{path.relative_to(ROOT)}: {path.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
