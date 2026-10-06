"""ENJIN app icon: the hand-drawn three-quarter motor (tools/icon/motor-bell-source.png), cleaned up.

Cleanup: the alpha becomes pure ink/no-ink, its contour is smoothed at 4x (blur, then
re-threshold) so hand-drawn wobble and JPEG-ish fringing go, and the drawing is
centred on its optical middle with even padding for the icon mask. Writes
  AppIcon light  - black motor on white (opaque, as the App Store requires)
  AppIcon dark   - white motor on transparent
  AppIcon tinted - white motor on transparent (iPadOS applies the tint)
  MotorHero      - the logo as a template image, used everywhere in the app (@2x/@3x)
  canvas-web/src/assets/enjin-logo.png - the logo in black, for the canvas (busy hint)

It is ENJIN's only mark.
Run from the repo root: python3 tools/icon/motor_bell.py   (needs Pillow)
"""
from PIL import Image, ImageFilter

SRC = "tools/icon/motor-bell-source.png"
SS = 4


def clean_mask():
    a = Image.open(SRC).convert("RGBA")
    # Ink = dark and opaque.
    lum = a.convert("L")
    alpha = a.getchannel("A")
    ink = Image.eval(lum, lambda v: 255 if v < 128 else 0)
    ink = Image.composite(ink, Image.new("L", a.size, 0), alpha.point(lambda v: 255 if v > 128 else 0))
    big = ink.resize((a.width * SS, a.height * SS), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(SS * 1.6)).point(lambda v: 255 if v >= 128 else 0)
    return big.crop(big.getbbox())


def place(mask, size, fill_ratio):
    """Mask centred in a size x size square, its longer side = fill_ratio * size."""
    n = size * SS
    scale = fill_ratio * n / max(mask.size)
    m = mask.resize((round(mask.width * scale), round(mask.height * scale)), Image.LANCZOS)
    out = Image.new("L", (n, n), 0)
    out.paste(m, ((n - m.width) // 2, (n - m.height) // 2))
    return out.resize((size, size), Image.LANCZOS)


def colored(mask, fg, bg):
    im = Image.new("RGBA", mask.size, bg)
    im.paste(Image.new("RGBA", mask.size, fg), (0, 0), mask)
    return im


if __name__ == "__main__":
    mask = clean_mask()
    black, white, clear = (0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 0)
    out = "Enjin/Resources/Assets.xcassets/AppIcon.appiconset"
    icon = place(mask, 1024, 0.76)
    colored(icon, black, white).convert("RGB").save(f"{out}/AppIcon-light.png")
    colored(icon, white, clear).save(f"{out}/AppIcon-dark.png")
    colored(icon, white, clear).save(f"{out}/AppIcon-tinted.png")
    hero = "Enjin/Resources/Assets.xcassets/MotorHero.imageset"
    for s in (2, 3):
        colored(place(mask, 320 * s, 1.0), black, clear).save(f"{hero}/MotorHero@{s}x.png")
    colored(place(mask, 256, 1.0), (11, 11, 12, 255), clear).save("canvas-web/src/assets/enjin-logo.png")
    print("wrote app icon, MotorHero, enjin-logo.png")
