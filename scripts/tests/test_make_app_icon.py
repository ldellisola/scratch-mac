#!/usr/bin/env python3
"""Tests for scripts/make-app-icon.py: the script that draws Scratch's app icon (plan 6 task 9, spec section 8.2,
docs/decisions/0010-one-point-oh-calls.md). Run with `make script-test`.

The script needs Pillow (a development tool only, not part of the app: `apt-get install python3-pil` or
`pip install pillow`). It writes the ten PNGs that App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json lists.
The tests run it into a temporary copy of that set, and look at the pixels it wrote, at the points of the design (1024 px
canvas): the squircle, the ticked checkbox, the three lines and the corner that must stay transparent. They also hold the
checked-in set to the script: what is committed is what the script makes, to within what another Pillow version changes.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageStat
except ImportError:
    sys.exit("test_make_app_icon.py needs Pillow: apt-get install python3-pil, or pip install pillow")

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "make-app-icon.py"
CHECKED_IN = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

# The design's colours (plan 6 task 9), in the order of the design's own list.
BLUE = (0x0A, 0x84, 0xFF)
WHITE = (255, 255, 255)


def entries(contents: Path):
    """(file name, pixels) of every image in a Contents.json: 16x16 at 2x is 32 pixels."""
    images = json.loads(contents.read_text())["images"]
    return [(i["filename"], int(i["size"].split("x")[0]) * int(i["scale"].rstrip("x"))) for i in images]


def patch_mean(image: Image.Image, design_x: float, design_y: float, design_radius: float = 6):
    """The mean RGBA of a small square around a point given on the 1024 px canvas, in any size of icon."""
    scale = image.width / 1024
    x0 = max(0, int((design_x - design_radius) * scale))
    y0 = max(0, int((design_y - design_radius) * scale))
    x1 = min(image.width, max(x0 + 1, int((design_x + design_radius) * scale)))
    y1 = min(image.height, max(y0 + 1, int((design_y + design_radius) * scale)))
    stat = ImageStat.Stat(image.crop((x0, y0, x1, y1)))
    return tuple(stat.mean)


def is_blue(rgba) -> bool:
    """Whether a colour is the checkbox's blue, #0A84FF, or near it: a small mark at 32 px is blended with the paper round it."""
    red, green, blue = rgba[:3]
    return blue > 150 and blue - red > 100


class MakeAppIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.generated = cls.tmp / "AppIcon.appiconset"
        cls.generated.mkdir()
        shutil.copy(CHECKED_IN / "Contents.json", cls.generated / "Contents.json")
        cls.result = subprocess.run(
            [sys.executable, str(SCRIPT), str(cls.generated)], capture_output=True, text=True, check=False
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def image(self, directory: Path, name: str) -> Image.Image:
        return Image.open(directory / name).convert("RGBA")

    # --- the script -------------------------------------------------------------------------------------------------

    def test_make_app_icon(self):
        self.assertEqual(self.result.returncode, 0, f"the script failed:\n{self.result.stdout}\n{self.result.stderr}")
        wanted = entries(CHECKED_IN / "Contents.json")
        self.assertEqual(len(wanted), 10, "Contents.json lists the ten sizes of a Mac icon")
        for name, pixels in wanted:
            path = self.generated / name
            self.assertTrue(path.exists(), f"{name} was not written")
            with Image.open(path) as image:
                self.assertEqual(image.format, "PNG", name)
                self.assertEqual(image.size, (pixels, pixels), f"{name} is not {pixels} x {pixels} pixels")
                self.assertIn(image.mode, ("RGBA", "LA"), f"{name} has no alpha channel")
        largest = self.image(self.generated, "icon_512x512@2x.png")
        self.assertEqual(largest.size, (1024, 1024))
        self.assertEqual(largest.getpixel((0, 0))[3], 0, "the corner (0, 0) of the 1024 px icon must be transparent")

    def test_the_script_names_what_it_wrote(self):
        for name, _ in entries(CHECKED_IN / "Contents.json"):
            self.assertIn(name, self.result.stdout, f"the script does not report writing {name}")

    def test_a_directory_without_contents_json_is_an_error(self):
        empty = self.tmp / "empty"
        empty.mkdir()
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(empty)], capture_output=True, text=True, check=False
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Contents.json", result.stderr)
        self.assertEqual([p.name for p in empty.iterdir()], [], "nothing is written without a Contents.json")

    # --- the design, at the points the plan names -------------------------------------------------------------------

    def check_design(self, image: Image.Image, label: str, tick: bool = True):
        def red(point):
            return patch_mean(image, *point)

        # The squircle: yellow, lighter at the top than at the bottom, and transparent in the corners.
        top = red((512, 160))
        bottom = red((512, 860))
        self.assertGreater(top[3], 250, f"{label}: the squircle is opaque near its top")
        self.assertGreater(bottom[3], 250, f"{label}: the squircle is opaque near its bottom")
        self.assertGreater(top[1], bottom[1] + 15, f"{label}: the fill goes from #FFE07A at the top to #FFB938 at the bottom")
        self.assertGreater(top[0], 240, f"{label}: yellow is red")
        self.assertLess(bottom[2], 100, f"{label}: the bottom of the fill, #FFB938, has little blue")
        self.assertLess(red((112, 112))[3], 40, f"{label}: the corner of the squircle is cut (a superellipse, not a square)")
        self.assertEqual(image.getpixel((0, 0))[3], 0, f"{label}: the canvas corner is transparent")

        # The ticked checkbox: blue, with white inside it where the tick is, to the left of the first line.
        # (270, 335) is inside the box (230 to 350, 300 to 420) and clear of the tick, and inside one pixel of it at 32 px.
        self.assertTrue(is_blue(red((270, 335))), f"{label}: the checkbox is #0A84FF, it is {red((270, 335))}")
        if tick:
            # The bend of the tick, (283, 385), is white. At 32 px the stroke is under a pixel wide and is only a light
            # pixel in the box, so the check is made from 128 px up.
            self.assertGreater(red((283, 385))[0], 200, f"{label}: the tick is white")

        # The first line is dark, and centred at the checkbox's height.
        line = red((600, 360))
        self.assertLess(line[0], 90, f"{label}: the first line is #1C1C1E at 85%")
        # The dot of the second line is the same blue, and its line is dark too.
        self.assertTrue(is_blue(red((290, 540))), f"{label}: the bullet dot is #0A84FF, it is {red((290, 540))}")
        self.assertLess(red((560, 540))[0], 90, f"{label}: the second line is dark")
        # The third line is the same dark at 45%: between the paper and the first line.
        third = red((440, 720))
        self.assertGreater(third[0], line[0] + 30, f"{label}: the third line is paler than the first")
        self.assertLess(third[0], red((440, 640))[0] - 30, f"{label}: the third line is darker than the paper")
        # The paper between the lines is untouched.
        self.assertGreater(red((560, 450))[0], 240, f"{label}: the paper between the lines is yellow")
        # Nothing but paper to the right of the shortest lines and the left of the checkbox.
        self.assertGreater(red((850, 540))[0], 240, f"{label}: the second line ends at x 720")

    def test_the_design_at_1024(self):
        self.check_design(self.image(self.generated, "icon_512x512@2x.png"), "1024 px")

    def test_the_design_reads_at_32_px(self):
        # The checkbox and the lines must read at 32 px (the plan's rule). icon_32x32.png is the 32 px icon.
        self.check_design(self.image(self.generated, "icon_32x32.png"), "32 px", tick=False)

    def test_the_design_reads_at_128_px(self):
        self.check_design(self.image(self.generated, "icon_128x128.png"), "128 px")

    def test_the_shadow_lies_below_the_squircle(self):
        image = self.image(self.generated, "icon_512x512@2x.png")
        above = image.getpixel((512, 96))[3]
        below = image.getpixel((512, 940))[3]
        self.assertLess(above, below, "the shadow is 12 px down, so it shows more below than above")
        self.assertGreater(below, 8, "a shadow of 30% black shows below the bottom edge")
        self.assertLess(below, 120, "but no more than 30% of it")

    # --- the checked-in set -----------------------------------------------------------------------------------------

    def test_checked_in_set_has_ten_pngs_of_the_right_sizes(self):
        for name, pixels in entries(CHECKED_IN / "Contents.json"):
            path = CHECKED_IN / name
            self.assertTrue(path.exists(), f"{name} is not checked in")
            with Image.open(path) as image:
                self.assertEqual(image.size, (pixels, pixels), name)
        largest = self.image(CHECKED_IN, "icon_512x512@2x.png")
        self.assertEqual(largest.getpixel((0, 0))[3], 0, "the corner of the checked-in 1024 px icon is transparent")

    def test_checked_in_set_is_what_the_script_makes(self):
        # Pillow versions differ in the last bit of an antialiased edge or a blur, so the comparison is loose: a changed
        # design or a script that was not run again is far outside it.
        white = Image.new("RGBA", (1, 1), (255, 255, 255, 255))
        for name, pixels in entries(CHECKED_IN / "Contents.json"):
            made = self.image(self.generated, name)
            kept = self.image(CHECKED_IN, name)
            made = Image.alpha_composite(white.resize(made.size), made).convert("RGB")
            kept = Image.alpha_composite(white.resize(kept.size), kept).convert("RGB")
            difference = ImageChops.difference(made, kept)
            mean = sum(ImageStat.Stat(difference).mean) / 3
            self.assertLess(
                mean, 1.0, f"{name} is not what scripts/make-app-icon.py makes: run it again (mean difference {mean:.2f})"
            )

    def test_the_script_is_deterministic(self):
        again = self.tmp / "again"
        again.mkdir()
        shutil.copy(CHECKED_IN / "Contents.json", again / "Contents.json")
        result = subprocess.run([sys.executable, str(SCRIPT), str(again)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, _ in entries(CHECKED_IN / "Contents.json"):
            self.assertEqual((again / name).read_bytes(), (self.generated / name).read_bytes(), name)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(MakeAppIconTests)
    outcome = unittest.TextTestRunner(verbosity=1).run(suite)
    if not outcome.wasSuccessful():
        sys.exit(1)
    print("all make-app-icon tests passed")
