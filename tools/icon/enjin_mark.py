"""ENJIN flat mark (wordmark + spinner; the app icon is tools/icon/motor_bell.py): a motor seen end-on. Housing ring, six coils between six spokes, rotor, bore.

Redrawn from the hand-made mark as exact geometry: true circles, parallel-sided
spokes, one corner radius everywhere. Writes
  MotorMark      - template image for the wordmark (@1x/@2x/@3x)
  docs/enjin-mark.svg and canvas-web/src/assets/enjin-mark.svg

Run from the repo root: python3 tools/icon/enjin_mark.py   (needs Pillow)
"""
import math
from PIL import Image, ImageDraw

# Proportions, as fractions of the mark's outer radius.
HOUSING = (0.880, 1.000)   # outer ring
COILS = (0.500, 0.815)     # the six stator segments
ROTOR = (0.270, 0.390)     # inner ring; inside it is the bore
SPOKE = 0.135              # spoke width, parallel sided
CORNER = 0.040             # one corner radius for every coil corner
SPOKE_ANGLES = [90 + 60 * k for k in range(6)]  # vertical spokes top and bottom


def coil_core(r_out, r_in, spoke_a, spoke_b, steps=96):
    """The coil shrunk by CORNER: grow it back by CORNER with round joins and its
    corners come out rounded with exactly that radius (a Minkowski sum)."""
    h = SPOKE / 2 + CORNER
    r_out -= CORNER
    r_in += CORNER
    def span(r):
        da = math.degrees(math.asin(h / r))
        return spoke_a + da, spoke_b - da
    a0, a1 = span(r_out)
    b0, b1 = span(r_in)
    pts = [(r_out, a0 + (a1 - a0) * i / steps) for i in range(steps + 1)]
    pts += [(r_in, b1 - (b1 - b0) * i / steps) for i in range(steps + 1)]
    return [(r * math.cos(math.radians(a)), -r * math.sin(math.radians(a))) for r, a in pts]


def coils():
    a = sorted(SPOKE_ANGLES)
    return [coil_core(COILS[1], COILS[0], a[i], a[(i + 1) % 6] + (360 if i == 5 else 0)) for i in range(6)]


def render(size, radius, fg, bg, ss=4):
    """The mark centred in a size x size image, outer radius `radius` px."""
    n, R = size * ss, radius * ss
    c = n / 2
    im = Image.new("RGBA", (n, n), bg)
    d = ImageDraw.Draw(im)
    def disc(r, fill):
        d.ellipse((c - r * R, c - r * R, c + r * R, c + r * R), fill=fill)
    disc(HOUSING[1], fg); disc(HOUSING[0], bg)
    for poly in coils():
        pts = [(c + x * R, c + y * R) for x, y in poly]
        d.polygon(pts, fill=fg)
        d.line(pts + [pts[0]], fill=fg, width=round(2 * CORNER * R), joint="curve")
        for p in pts[:: max(1, len(pts) // 64)] + [pts[len(pts) // 2 - 1], pts[len(pts) // 2], pts[-1]]:
            r = CORNER * R
            d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=fg)
    disc(ROTOR[1], fg); disc(ROTOR[0], bg)
    return im.resize((size, size), Image.LANCZOS)


def svg():
    f = lambda v: f"{v * 50:.3f}"
    paths = []
    for poly in coils():
        d = "M" + " L".join(f"{f(x)},{f(y)}" for x, y in poly) + " Z"
        paths.append(f'<path d="{d}"/>')
    ring = lambda r: f'<circle r="{(r[0] + r[1]) / 2 * 50:.3f}" fill="none" stroke-width="{(r[1] - r[0]) * 50:.3f}"/>'
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-50 -50 100 100" fill="currentColor" stroke="currentColor">\n'
        f'  {ring(HOUSING)}\n  {ring(ROTOR)}\n'
        f'  <g stroke-width="{2 * CORNER * 50:.3f}" stroke-linejoin="round">\n    '
        + "\n    ".join(paths) + "\n  </g>\n</svg>\n"
    )


if __name__ == "__main__":
    black, white, clear = (0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 0)
    mark = "Enjin/Resources/Assets.xcassets/MotorMark.imageset"
    for s in (1, 2, 3):
        render(40 * s, 20 * s - 0.5, black, clear).save(f"{mark}/MotorMark@{s}x.png")
    for path in ("docs/enjin-mark.svg", "canvas-web/src/assets/enjin-mark.svg"):
        with open(path, "w") as fh:
            fh.write(svg())
    print("wrote MotorMark, enjin-mark.svg")
