#!/usr/bin/env python3
"""Draws Scratch's app icon: a notepad with a ticked checkbox (plan 6 task 9, spec section 8.2,
docs/decisions/0010-one-point-oh-calls.md).

    make-app-icon.py [<appiconset directory>]

The directory defaults to App/Resources/Assets.xcassets/AppIcon.appiconset. The sizes come from its Contents.json (the
ten images of a Mac icon, 16 to 1024 pixels), and the script writes the PNGs that file names, over any that are there.
The PNGs are checked in: run this script again after changing the design, and check in what it wrote.

The script needs Pillow, a development tool only (it is not part of the app and nothing at build time runs it):
apt-get install python3-pil, or pip install pillow. Everything is drawn on a 1024 px canvas, in the units below, and
each size is drawn at 4 times its pixels and scaled down with LANCZOS, so that no edge is a staircase at 16 px.

The design (all numbers are on the 1024 px canvas):
  - the base is the macOS squircle of the Big Sur grid, 824 x 824 at (100, 100), a superellipse with exponent 5, filled
    with a vertical gradient from #FFE07A (top) to #FFB938 (bottom), with a shadow of 28 px blur (a Gaussian of sigma 14,
    which is what a blur of 28 means in CSS and in design tools), 12 px down, 30% black
  - a ticked checkbox: a 120 px square of radius 28 at (230, 300), filled #0A84FF, with a white tick of 22 px stroke
  - a line from x 400 to 790, centred at y 360 (the checkbox's height), 56 px high, #1C1C1E at 85%
  - a dot of 64 px, #0A84FF, centred at (290, 540), with a line from 400 to 720 at y 540
  - a line from 260 to 620 at y 720, at 45%

Exit: 0 all written, 64 usage error, 70 cannot run (no Pillow, or no Contents.json in the directory).
"""

import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("make-app-icon.py needs Pillow: apt-get install python3-pil, or pip install pillow", file=sys.stderr)
    sys.exit(70)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

# The canvas, and how many times its pixels each size is drawn at before it is scaled down.
CANVAS = 1024
SUPERSAMPLE = 4

# The base: the Big Sur grid's squircle.
SQUIRCLE_ORIGIN = 100
SQUIRCLE_SIZE = 824
SQUIRCLE_EXPONENT = 5
GRADIENT_TOP = (0xFF, 0xE0, 0x7A)
GRADIENT_BOTTOM = (0xFF, 0xB9, 0x38)
SHADOW_SIGMA = 14
SHADOW_OFFSET = 12
SHADOW_OPACITY = 0.30

# What is on it.
BLUE = (0x0A, 0x84, 0xFF)
WHITE = (255, 255, 255)
INK = (0x1C, 0x1C, 0x1E)
LINE_HEIGHT = 56
CHECKBOX_ORIGIN = (230, 300)
CHECKBOX_SIZE = 120
CHECKBOX_RADIUS = 28
# The tick, in the checkbox's own units (its corner is (0, 0)): the foot of the stroke, its bend and its tip.
TICK_POINTS = ((31, 63), (53, 85), (91, 36))
TICK_STROKE = 22
DOT_CENTRE = (290, 540)
DOT_SIZE = 64
# (x from, x to, centre y, opacity of the ink) of the three lines.
LINES = ((400, 790, 360, 0.85), (400, 720, 540, 0.85), (260, 620, 720, 0.45))


def squircle_points(origin: float, size: float, exponent: float, count: int = 1440):
    """The outline of a superellipse |x|^n + |y|^n = 1 filling the square at `origin` of side `size`."""
    half = size / 2
    centre = origin + half
    points = []
    for step in range(count):
        angle = 2 * math.pi * step / count
        cosine, sine = math.cos(angle), math.sin(angle)
        x = centre + half * math.copysign(abs(cosine) ** (2 / exponent), cosine)
        y = centre + half * math.copysign(abs(sine) ** (2 / exponent), sine)
        points.append((x, y))
    return points


def vertical_gradient(width: int, height: int, top, bottom) -> Image.Image:
    """An RGB image that goes from `top` on its first row to `bottom` on its last."""
    ramp = Image.linear_gradient("L").resize((width, height), Image.Resampling.BILINEAR)
    return Image.composite(Image.new("RGB", (width, height), bottom), Image.new("RGB", (width, height), top), ramp)


def draw_icon(pixels: int) -> Image.Image:
    """The icon at `pixels` x `pixels`, drawn at SUPERSAMPLE times that and scaled down."""
    canvas = pixels * SUPERSAMPLE
    unit = canvas / CANVAS

    def scaled(value: float) -> int:
        return round(value * unit)

    def rectangle(x0: float, y0: float, x1: float, y1: float):
        return (scaled(x0), scaled(y0), scaled(x1), scaled(y1))

    def layer() -> Image.Image:
        return Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    # The shape of the base, and the shadow that it throws: 12 px down, blurred, 30% black.
    outline = squircle_points(SQUIRCLE_ORIGIN * unit, SQUIRCLE_SIZE * unit, SQUIRCLE_EXPONENT)
    shape = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(shape).polygon(outline, fill=255)
    shadow_shape = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(shadow_shape).polygon([(x, y + SHADOW_OFFSET * unit) for x, y in outline], fill=255)
    shadow_alpha = shadow_shape.filter(ImageFilter.GaussianBlur(SHADOW_SIGMA * unit)).point(
        lambda value: round(value * SHADOW_OPACITY)
    )
    icon = layer()
    icon.putalpha(shadow_alpha)

    # The base: the gradient, from the top of the squircle to its bottom, cut to the shape.
    top = scaled(SQUIRCLE_ORIGIN)
    side = scaled(SQUIRCLE_SIZE)
    fill = Image.new("RGB", (canvas, canvas), GRADIENT_BOTTOM)
    fill.paste(vertical_gradient(canvas, side, GRADIENT_TOP, GRADIENT_BOTTOM), (0, top))
    fill.paste(Image.new("RGB", (canvas, top), GRADIENT_TOP), (0, 0))
    base = layer()
    base.paste(fill, mask=shape)
    icon = Image.alpha_composite(icon, base)

    # The lines, each in a layer of its own, so that its opacity blends with the paper.
    for x0, x1, centre, opacity in LINES:
        ink = layer()
        ImageDraw.Draw(ink).rounded_rectangle(
            rectangle(x0, centre - LINE_HEIGHT / 2, x1, centre + LINE_HEIGHT / 2),
            radius=scaled(LINE_HEIGHT / 2),
            fill=INK + (round(255 * opacity),),
        )
        icon = Image.alpha_composite(icon, ink)

    # The ticked checkbox and the bullet's dot are opaque, and so are drawn straight onto the icon.
    pen = ImageDraw.Draw(icon)
    left, below = CHECKBOX_ORIGIN
    pen.rounded_rectangle(
        rectangle(left, below, left + CHECKBOX_SIZE, below + CHECKBOX_SIZE),
        radius=scaled(CHECKBOX_RADIUS),
        fill=BLUE + (255,),
    )
    tick = [(scaled(left + x), scaled(below + y)) for x, y in TICK_POINTS]
    pen.line(tick, fill=WHITE + (255,), width=scaled(TICK_STROKE), joint="curve")
    cap = scaled(TICK_STROKE) / 2
    for x, y in (tick[0], tick[-1]):
        pen.ellipse((x - cap, y - cap, x + cap, y + cap), fill=WHITE + (255,))
    centre_x, centre_y = DOT_CENTRE
    pen.ellipse(
        rectangle(centre_x - DOT_SIZE / 2, centre_y - DOT_SIZE / 2, centre_x + DOT_SIZE / 2, centre_y + DOT_SIZE / 2),
        fill=BLUE + (255,),
    )

    return icon.resize((pixels, pixels), Image.Resampling.LANCZOS)


def sizes_in(contents: Path):
    """(file name, pixels) of each image of an asset catalog's Contents.json: 16x16 at 2x is 32 pixels."""
    images = json.loads(contents.read_text())["images"]
    return [(image["filename"], int(image["size"].split("x")[0]) * int(image["scale"].rstrip("x"))) for image in images]


def main(arguments) -> int:
    if len(arguments) > 1 or any(argument.startswith("-") for argument in arguments):
        print("usage: make-app-icon.py [<appiconset directory>]", file=sys.stderr)
        return 64
    directory = Path(arguments[0]) if arguments else DEFAULT_SET
    contents = directory / "Contents.json"
    if not contents.is_file():
        print(f"make-app-icon.py: {contents} does not exist: it names the files and sizes to write", file=sys.stderr)
        return 70
    drawn = {}
    for name, pixels in sizes_in(contents):
        if pixels not in drawn:
            drawn[pixels] = draw_icon(pixels)
        drawn[pixels].save(directory / name, format="PNG", optimize=True)
        print(f"make-app-icon.py: wrote {directory / name} ({pixels} x {pixels})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
