"""Draws the app icon: a doodle creature stitched together from four bands,
one per story part (introduction, development 1/2, development 2/2,
epilogue), in the palette of images/background_portrait.jpeg.

Run from the repo root:  python3 assets/icon/draw_icon.py
Outputs icon.png (full icon) and icon_foreground.png (Android adaptive
foreground) next to this script.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw

SAGE = (213, 226, 200)
SAGE_DOODLE = (190, 207, 178)
CREAM = (244, 238, 218)
PATCH = (185, 211, 174)
INK = (46, 46, 40)
WHITE = (255, 255, 255)

K = 4            # supersampling factor
N = 1024         # output size
S = N * K        # drawing size
LINE = 14 * K    # main outline width
THIN = 8 * K     # detail line width

OUT = os.path.dirname(os.path.abspath(__file__))


def p(x, y):
    return (x * K, y * K)


def box(x0, y0, x1, y1):
    return [x0 * K, y0 * K, x1 * K, y1 * K]


# Body outline and the slanted seams between the four bands.
BODY = (322, 210, 702, 770)
BODY_R = 190
SEAMS = [(414, -0.08), (520, 0.07), (642, -0.06)]  # (y at centre, slope)


def seam_y(seam, x):
    y0, slope = seam
    return y0 + slope * (x - 512)


def band_mask(i):
    """Mask of band i (0..3), clipped to the body."""
    body = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body).rounded_rectangle(box(*BODY), BODY_R * K, fill=255)
    band = Image.new("L", (S, S), 0)
    top = SEAMS[i - 1] if i > 0 else None
    bottom = SEAMS[i] if i < len(SEAMS) else None
    xs = (0, N)
    pts = [p(x, seam_y(top, x) if top else 0) for x in xs]
    pts += [p(x, seam_y(bottom, x) if bottom else N) for x in reversed(xs)]
    ImageDraw.Draw(band).polygon(pts, fill=255)
    return ImageChops.multiply(body, band)


def draw_doodles(d):
    """Faint spirals, stars and clouds, like the background pattern."""
    def spiral(cx, cy, r):
        pts = []
        for t in range(0, 720, 6):
            a = math.radians(t)
            rr = r * t / 720
            pts.append(p(cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.line(pts, fill=SAGE_DOODLE, width=THIN, joint="curve")

    def star(cx, cy, r):
        pts = []
        for k in range(10):
            a = math.radians(-90 + k * 36)
            rr = r if k % 2 == 0 else r * 0.45
            pts.append(p(cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(pts, outline=SAGE_DOODLE, width=THIN)

    spiral(150, 170, 70)
    spiral(880, 860, 64)
    star(860, 190, 46)
    star(150, 640, 38)
    star(830, 520, 26)
    for cx, cy in ((180, 880), (860, 330)):
        puffs = ((-40, 8, 26), (0, -4, 36), (40, 8, 26))
        for dx, dy, r in puffs:
            d.ellipse(box(cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r),
                      fill=SAGE_DOODLE)
        d.rectangle(box(cx - 40, cy + 8, cx + 40, cy + 34), fill=SAGE_DOODLE)
        inner = r_in = THIN / K
        for dx, dy, r in puffs:
            r_in = r - inner
            d.ellipse(box(cx + dx - r_in, cy + dy - r_in, cx + dx + r_in,
                          cy + dy + r_in), fill=SAGE)
        d.rectangle(box(cx - 40, cy + 8, cx + 40, cy + 34 - inner),
                    fill=SAGE)


def draw_creature(img):
    d = ImageDraw.Draw(img)

    # Horns / antenna behind the head.
    d.polygon([p(400, 262), p(372, 150), p(456, 232)], fill=CREAM,
              outline=INK, width=LINE)
    d.line([p(600, 236), p(640, 150)], fill=INK, width=LINE)
    d.ellipse(box(618, 116, 668, 166), fill=PATCH, outline=INK, width=LINE)

    # Teapot handle (left) and spout (right) on band 2.
    d.arc(box(250, 410, 360, 520), 90, 270, fill=INK, width=LINE)
    d.polygon([p(690, 430), p(790, 390), p(812, 402), p(700, 492)],
              fill=CREAM, outline=INK, width=LINE)

    # Tentacle curling out of band 3: a tapering spiral.
    cx, cy = 262, 640
    pts = [p(340, 596), p(300, 594)]
    for t in range(0, 460, 6):
        a = math.radians(-90 - t)
        r = 46 * (1 - t / 600)
        pts.append(p(cx + r * math.cos(a) + 0, cy + 0 + r * math.sin(a)))
    d.line(pts, fill=INK, width=LINE, joint="curve")
    for t in (60, 150, 240):
        a = math.radians(-90 - t)
        r = 46 * (1 - t / 600) + 14
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        d.ellipse(box(x - 7, y - 7, x + 7, y + 7), outline=INK,
                  width=THIN // 2 + K)

    # Legs and boots under the body.
    for x in (452, 572):
        d.line([p(x, 760), p(x, 856)], fill=INK, width=LINE)
        d.rounded_rectangle(box(x - 34, 846, x + 44, 904), 18 * K,
                            fill=CREAM, outline=INK, width=LINE)

    # The four bands, alternating cream and patch green.
    for i in range(4):
        fill = CREAM if i % 2 == 0 else PATCH
        layer = Image.new("RGBA", (S, S), fill + (255,))
        img.paste(layer, (0, 0), band_mask(i))
    details = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(details)

    # Band 1: one big eye and a grin with a tooth.
    d.ellipse(box(452, 252, 572, 372), fill=WHITE, outline=INK, width=LINE)
    d.ellipse(box(500, 292, 548, 340), fill=INK)
    d.ellipse(box(520, 300, 534, 314), fill=WHITE)
    d.arc(box(470, 340, 554, 394), 25, 155, fill=INK, width=THIN)

    # Band 2: a stitched square patch.
    d.rectangle(box(410, 430, 470, 486), outline=INK, width=THIN)
    for x in range(418, 470, 16):
        d.line([p(x, 424), p(x + 6, 436)], fill=INK, width=THIN // 2)

    # Band 3: croc scales.
    for row, y in enumerate((548, 590)):
        off = 0 if row == 0 else 26
        for x in range(372 + off, 660, 52):
            d.arc(box(x, y - 18, x + 40, y + 18), 0, 180, fill=INK,
                  width=THIN)

    # Band 4: a little belly button spiral.
    sp = []
    for t in range(0, 540, 10):
        a = math.radians(t)
        r = 22 * t / 540
        sp.append(p(512 + r * math.cos(a), 700 + r * math.sin(a)))
    d.line(sp, fill=INK, width=THIN, joint="curve")

    # Seams with cross stitches.
    for seam in SEAMS:
        xs = [x for x in range(330, 700, 4)]
        d.line([p(x, seam_y(seam, x)) for x in xs], fill=INK, width=THIN)
        for x in range(352, 690, 34):
            y = seam_y(seam, x)
            d.line([p(x - 6, y - 16), p(x + 6, y + 16)], fill=INK,
                   width=THIN // 2 + K)

    body = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body).rounded_rectangle(box(*BODY), BODY_R * K, fill=255)
    details.putalpha(ImageChops.multiply(details.getchannel("A"), body))
    img.alpha_composite(details)
    d = ImageDraw.Draw(img)

    # Body outline on top.
    d.rounded_rectangle(box(*BODY), BODY_R * K, outline=INK, width=LINE)


def creature_layer():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_creature(layer)
    return layer


def main():
    creature = creature_layer()

    # Full icon (iOS, web, legacy Android): opaque sage background.
    full = Image.new("RGBA", (S, S), SAGE + (255,))
    draw_doodles(ImageDraw.Draw(full))
    full.alpha_composite(creature)
    full.convert("RGB").resize((N, N), Image.LANCZOS).save(
        os.path.join(OUT, "icon.png"))

    # Android adaptive foreground. flutter_launcher_icons insets it by 16%
    # per side, so this image covers roughly the visible launcher area;
    # 0.8 keeps the antenna and spout inside a circular mask.
    bbox = creature.getbbox()
    crop = creature.crop(bbox)
    scale = (0.8 * S) / max(crop.size)
    crop = crop.resize((int(crop.width * scale), int(crop.height * scale)),
                       Image.LANCZOS)
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fg.alpha_composite(crop, ((S - crop.width) // 2, (S - crop.height) // 2))
    fg.resize((N, N), Image.LANCZOS).save(
        os.path.join(OUT, "icon_foreground.png"))


if __name__ == "__main__":
    main()
