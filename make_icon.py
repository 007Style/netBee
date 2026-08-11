#!/usr/bin/env python3
"""
make_icon.py  —  Generate AppIcon.icns for netBee
──────────────────────────────────────────────────
Draws a hexagonal bee-comb icon that visually matches the beeMon sibling app:
  • Dark background  #1C1E24
  • Bee-yellow hex   #F5D42E (DS.beeYellow)
  • Green ↓ / Blue ↑ bandwidth chevrons inside the hex
  • "net" label in monospaced white below the chevron pair

Requires only the stdlib + Pillow (pip install pillow).
Writes Sources/netBee/Assets/AppIcon.icns (all required sizes).
"""

import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow not found.  Run:  pip install pillow")

# ── Colour palette (mirrors DesignSystem.swift) ─────────────────────────────
BG        = (28,  30,  36, 255)   # #1C1E24
HEX_FILL  = (245, 212,  46, 255)  # #F5D42E  beeYellow
HEX_LINE  = (255, 255, 255,  30)  # subtle border
RX_GREEN  = ( 69, 179, 102, 255)  # #45B366
TX_BLUE   = ( 77, 153, 230, 255)  # #4D99E6
WHITE     = (255, 255, 255, 255)

SIZES = [16, 32, 64, 128, 256, 512, 1024]
DEST  = Path("Sources/netBee/Assets")
OUT   = DEST / "AppIcon.icns"


# ── Geometry helpers ─────────────────────────────────────────────────────────

def hex_points(cx: float, cy: float, r: float, flat_top: bool = True):
    """Return the 6 vertices of a regular hexagon."""
    pts = []
    for i in range(6):
        angle = math.radians(60 * i + (0 if flat_top else 30))
        pts.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    return pts


# ── Per-size renderer ────────────────────────────────────────────────────────

def render(size: int) -> Image.Image:
    """Draw one square icon at *size × size* pixels (RGBA)."""
    s = size
    img = Image.new("RGBA", (s, s), BG)
    draw = ImageDraw.Draw(img)

    cx, cy = s / 2, s / 2
    # Hex radius — generous but with a small margin
    r_hex = s * 0.42

    # ── Hexagon fill ────────────────────────────────────────────────────────
    pts = hex_points(cx, cy, r_hex, flat_top=True)
    draw.polygon(pts, fill=HEX_FILL)
    # Inner shadow ring
    pts_inner = hex_points(cx, cy, r_hex * 0.94, flat_top=True)
    draw.polygon(pts_inner, fill=None, outline=(0, 0, 0, 60))

    # ── Chevron pair  ↓ (green)  ↑ (blue) ──────────────────────────────────
    # Chevrons are drawn as two polylines centred inside the hex.
    # Size them relative to the hex.
    arm   = r_hex * 0.30   # half-width of each chevron arm
    thick = max(1, int(s * 0.045))   # stroke width
    vert_gap = r_hex * 0.22          # vertical spacing between the two chevrons
    tip_depth = r_hex * 0.16         # how far the tip points down / up

    # ↓ RX chevron (green) — points downward, slightly above centre
    ry   = cy - vert_gap * 0.5
    draw.line(
        [(cx - arm, ry - tip_depth),
         (cx,       ry + tip_depth),
         (cx + arm, ry - tip_depth)],
        fill=RX_GREEN, width=thick, joint="curve"
    )

    # ↑ TX chevron (blue) — points upward, slightly below centre
    ty   = cy + vert_gap * 0.5
    draw.line(
        [(cx - arm, ty + tip_depth),
         (cx,       ty - tip_depth),
         (cx + arm, ty + tip_depth)],
        fill=TX_BLUE, width=thick, joint="curve"
    )

    # ── "net" label ─────────────────────────────────────────────────────────
    if size >= 32:
        label     = "net"
        font_size = max(6, int(s * 0.13))
        try:
            # Use a monospaced system font when available
            font = ImageFont.truetype("/System/Library/Fonts/Monaco.ttf", font_size)
        except Exception:
            try:
                font = ImageFont.truetype("/System/Library/Fonts/Courier New Bold.ttf", font_size)
            except Exception:
                font = ImageFont.load_default()

        bbox = draw.textbbox((0, 0), label, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tx = cx - tw / 2
        # Place below the chevrons, inside the lower part of the hex
        ty_label = cy + vert_gap * 0.5 + tip_depth + th * 0.2
        draw.text((tx, ty_label), label, font=font, fill=BG)

    return img


# ── icns assembler ───────────────────────────────────────────────────────────
# OSType codes for the sizes we care about:
ICNS_TYPES = {
    16:   (b"icp4", b"icp4"),   # 16 pt @1x
    32:   (b"icp5", b"ic11"),   # 32 pt @1x  / 16 pt @2x
    64:   (b"icp6", b"ic12"),   # 32 pt @2x
    128:  (b"ic07", b"ic07"),
    256:  (b"ic08", b"ic08"),
    512:  (b"ic09", b"ic09"),
    1024: (b"ic10", b"ic10"),
}


def build_icns(images: dict[int, Image.Image], dest: Path) -> None:
    """Assemble a minimal .icns file from a dict of {size: PIL.Image}."""
    import io

    chunks = []
    for size, img in sorted(images.items()):
        ostype = ICNS_TYPES[size][0]
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        data = buf.getvalue()
        # Each icns chunk: 4-byte OSType + 4-byte length (includes 8-byte header)
        length = 8 + len(data)
        chunks.append(struct.pack(">4sI", ostype, length) + data)

    body = b"".join(chunks)
    total = 8 + len(body)
    with open(dest, "wb") as f:
        f.write(b"icns" + struct.pack(">I", total) + body)


# ── iconutil fallback (macOS native, higher quality) ────────────────────────

def build_with_iconutil(images: dict[int, Image.Image], dest: Path) -> bool:
    """Use macOS iconutil to build the .icns (preferred). Returns True on success."""
    iconutil = shutil.which("iconutil")
    if not iconutil:
        return False

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()

        mappings = {
            16:   "icon_16x16.png",
            32:   ["icon_16x16@2x.png", "icon_32x32.png"],
            64:   "icon_32x32@2x.png",
            128:  "icon_128x128.png",
            256:  ["icon_128x128@2x.png", "icon_256x256.png"],
            512:  ["icon_256x256@2x.png", "icon_512x512.png"],
            1024: "icon_512x512@2x.png",
        }
        for size, names in mappings.items():
            if size not in images:
                continue
            if isinstance(names, str):
                names = [names]
            for name in names:
                images[size].save(iconset / name, format="PNG")

        result = subprocess.run(
            [iconutil, "-c", "icns", "-o", str(dest), str(iconset)],
            capture_output=True
        )
        return result.returncode == 0


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    DEST.mkdir(parents=True, exist_ok=True)

    print("🎨  Rendering icon sizes: ", end="", flush=True)
    images = {}
    for sz in SIZES:
        images[sz] = render(sz)
        print(sz, end=" ", flush=True)
    print()

    if build_with_iconutil(images, OUT):
        print(f"✅  AppIcon.icns written via iconutil → {OUT}")
    else:
        build_icns(images, OUT)
        print(f"✅  AppIcon.icns written (manual assembler) → {OUT}")


if __name__ == "__main__":
    main()
