"""ENJIN app icon: an electric motor, as simple as it can be and still be a motor.

Renders the three iPadOS app icon variants into the asset catalog:
  light  - black motor on white (opaque, as the App Store requires)
  dark   - white motor on transparent
  tinted - white motor on transparent (iPadOS applies the tint)

Run from the repo root: python3 tools/icon/motor_icon.py   (needs Pillow)
"""
import math
from PIL import Image, ImageDraw

SS = 4          # draw at 4x and downsample for clean edges
N = 1024 * SS
K = 0.42        # ellipse squash: seen from ~25 degrees above

def upright(fg, bg):
    """A standing cylinder, one seam, a shaft. Nothing else."""
    im = Image.new("RGBA", (N, N), bg); d = ImageDraw.Draw(im)
    cx = N / 2; R = N * 0.25; top = N * 0.42; bot = N * 0.70
    def ebox(y, r): return (cx - r, y - K * r, cx + r, y + K * r)
    d.ellipse(ebox(bot, R), fill=fg)
    d.rectangle((cx - R, top, cx + R, bot), fill=fg)
    seam_y = top + (bot - top) * 0.42
    d.arc(ebox(seam_y, R), 0, 180, fill=bg, width=int(N * 0.018))
    d.ellipse(ebox(top, R), fill=fg)
    d.ellipse(ebox(top, R * 0.80), outline=bg, width=int(N * 0.018))
    rs, hs, g = N * 0.042, N * 0.14, N * 0.016
    d.ellipse(ebox(top, rs + g), fill=bg)
    d.rectangle((cx - rs - g, top - hs, cx + rs + g, top), fill=bg)
    d.ellipse(ebox(top - hs, rs + g), fill=bg)
    d.rectangle((cx - rs, top - hs, cx + rs, top), fill=fg)
    d.ellipse(ebox(top - hs, rs), fill=fg)
    d.ellipse(ebox(top, rs), fill=fg)
    return im


OUT = "Enjin/Resources/Assets.xcassets/AppIcon.appiconset"
black, white, clear = (0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 0)
upright(black, white).resize((1024, 1024), Image.LANCZOS).convert("RGB").save(f"{OUT}/AppIcon-light.png")
dark = upright(white, clear).resize((1024, 1024), Image.LANCZOS)
dark.save(f"{OUT}/AppIcon-dark.png")
dark.save(f"{OUT}/AppIcon-tinted.png")
print("wrote", OUT)
