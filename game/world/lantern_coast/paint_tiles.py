"""Generate two seamless, authored terrain pattern maps using wrapped brush marks.

Ground RGBA stores meadow, packed earth, silt, and woodland litter in separate
channels. Rock is a single grayscale pattern. The shader supplies the pigment.
"""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 256


def wash(rng):
    values = np.full((SIZE, SIZE), 153.0)
    for resolution, amplitude in ((5, 51), (13, 25), (29, 10)):
        grid = rng.integers(0, 255, (resolution, resolution), dtype=np.uint8)
        wrapped = Image.fromarray(np.tile(grid, (3, 3))).resize((SIZE * 3,) * 2, Image.Resampling.BICUBIC)
        values += (np.asarray(wrapped)[SIZE:-SIZE, SIZE:-SIZE] / 255 - 0.5) * amplitude
    return Image.fromarray(np.uint8(np.clip(values, 0, 255)))


def stamp(draw, x, y, points, fill):
    """Draw the same mark at the opposite edge when its brush crosses a seam."""
    offsets_x = [0, SIZE] if x < 35 else [0, -SIZE] if x > SIZE - 35 else [0]
    offsets_y = [0, SIZE] if y < 35 else [0, -SIZE] if y > SIZE - 35 else [0]
    for dx in offsets_x:
        for dy in offsets_y:
            draw.polygon([(x + px + dx, y + py + dy) for px, py in points], fill=fill)


def soften(image, radius):
    canvas = Image.fromarray(np.tile(np.asarray(image), (3, 3)))
    canvas = canvas.filter(ImageFilter.GaussianBlur(radius))
    return canvas.crop((SIZE, SIZE, SIZE * 2, SIZE * 2))


def brush_layer(rng, kind):
    image = wash(rng)
    draw = ImageDraw.Draw(image)
    count = {"meadow": 460, "dirt": 330, "sand": 400, "litter": 520}[kind]
    for _ in range(count):
        x, y = rng.uniform(0, SIZE, 2)
        angle = rng.uniform(0, math.tau)
        size = rng.uniform(1.7, 6.5)
        if kind == "meadow":
            angle = rng.normal(-0.77, 0.48)
            shape = [(-1, -.3), (.1, -.67), (1, -.48), (.52, -.1), (1.15, .24), (.23, .60), (-.86, .35)]
        elif kind == "dirt":
            shape = [(-.8, -.38), (.35, -.58), (.88, -.13), (.61, .48), (-.43, .62), (-1, .22)]
        elif kind == "sand":
            size *= 1.22
            angle = rng.normal(0.23, 0.25)
            shape = [(-1, 0), (-.35, -.21), (.48, -.13), (1, .01), (.33, .12), (-.49, .12)]
        else:
            shape = [(-1, 0), (-.35, -.40), (.52, -.29), (1, -.1), (.33, .27), (-.43, .45)]
        c, s = math.cos(angle), math.sin(angle)
        points = [((a * c - b * s) * size, (a * s + b * c) * size) for a, b in shape]
        center = image.getpixel((int(x), int(y)))
        pigment = int(np.clip(center + rng.uniform(-37, 43), 24, 233))
        stamp(draw, x, y, points, pigment)
        if kind in ("dirt", "litter") and size > 4.1:
            rim = [(.2, -.3), (.72, -.19), (.25, -.03), (-.22, -.05)]
            stamp(draw, x, y, [((a*c-b*s)*size, (a*s+b*c)*size) for a,b in rim], min(251, pigment + 34))
    return soften(image, 0.58)


def sandstone(rng):
    image = wash(rng)
    field = np.asarray(image, dtype=float).copy()
    x, y = np.meshgrid(np.arange(SIZE), np.arange(SIZE))
    seam = y + 5 * np.sin(x * math.tau / SIZE) + 2 * np.sin(x * math.tau * 3 / SIZE)
    field += np.sin(seam * math.tau * 5 / SIZE) * 22
    field -= (np.cos(seam * math.tau * 9 / SIZE) > 0.91) * 18
    image = Image.fromarray(np.uint8(np.clip(field, 0, 255)))
    draw = ImageDraw.Draw(image)
    for _ in range(255):
        x, y = rng.uniform(0, SIZE, 2)
        width, depth = rng.uniform(4, 25), rng.uniform(0.8, 3.7)
        points = [(-width, 0), (-width*.35, -depth), (width*.61, -.5*depth), (width, depth*.14), (0, depth)]
        center = image.getpixel((int(x), int(y)))
        stamp(draw, x, y, points, int(np.clip(center + rng.uniform(-25, 27), 16, 238)))
    return soften(image, 0.67)


def write_tiles(directory):
    rng = np.random.default_rng(80312)
    Image.merge("RGBA", tuple(brush_layer(rng, kind) for kind in ("meadow", "dirt", "sand", "litter"))).save(
        directory / "ground_detail.png", optimize=True)
    sandstone(rng).save(directory / "rock_detail.png", optimize=True)
    cobbles(np.random.default_rng(19412)).save(directory / "cobble_detail.png", optimize=True)
    rng = np.random.default_rng(45527)
    Image.merge("RGBA", (
        accents(rng, "grass"), accents(rng, "gravel"),
        accents(rng, "shale"), accents(rng, "ripple"),
    )).save(directory / "terrain_accents.png", optimize=True)
    rng = np.random.default_rng(92517)
    Image.merge("RGBA", tuple(surface_pigment(rng, kind) for kind in ("grass", "dunes", "ice", "ash"))).save(
        directory / "biome_brushwork.png", optimize=True)
    bank_rng = np.random.default_rng(42159)
    Image.merge("RGBA", (brush_layer(bank_rng, "litter"), accents(bank_rng, "shale"),
                         broad_wash(), accents(bank_rng, "grass"))).save(directory / "bank_detail.png", optimize=True)


def broad_wash():
    u, v = np.meshgrid(np.arange(SIZE)*math.tau/SIZE, np.arange(SIZE)*math.tau/SIZE)
    flow = .42*np.sin(2*u + v + 0.8*np.sin(v)) + .31*np.sin(u - 2*v) + .22*np.cos(3*u + 3*v)
    return Image.fromarray(np.uint8(np.clip(134 + 108 * flow, 0, 255)))


def surface_pigment(rng, kind):
    """Seamless grayscale detail. Each channel describes a different surface."""
    u, v = np.meshgrid(np.arange(SIZE)*math.tau/SIZE, np.arange(SIZE)*math.tau/SIZE)
    if kind == "dunes":
        crest = 8*v + 2*u + .78*np.sin(2*u-v) + .36*np.sin(4*u+v)
        signal = .47*np.sin(crest) + .21*np.sin(2*crest+.6) + .10*np.sin(3*crest)
        return Image.fromarray(np.uint8(np.clip(143 + signal*112 + (np.asarray(wash(rng), dtype=float)-153)*.73, 0, 255)))
    if kind == "grass":
        return accents(rng, "grass")

    image = wash(rng)
    draw = ImageDraw.Draw(image)
    if kind == "ice":
        for _ in range(60):
            x, y = rng.uniform(0, SIZE, 2)
            length = rng.uniform(4, 22)
            stamp(draw, x, y, [(-length,.0),(-length*.18,-1.4),(length*.72,-2.0),(length,0),(.25*length,1.1)],
                  int(rng.uniform(91, 185)))
            stamp(draw, x, y, [(-length,-1.2),(-length*.25,-2.1),(length*.72,-2.8),(length*.61,-1.5)],
                  int(rng.uniform(183, 229)))
    else:
        # Thin warm seams under dark, scattered chunks of porous clinker.
        for _ in range(310):
            x, y = rng.uniform(0, SIZE, 2)
            w, h = rng.uniform(1.25, 7.5), rng.uniform(.9, 3.5)
            polygon = [(-w,0),(-w*.55,-h),(.45*w,-h*.82),(w,0),(.66*w,h*.75),(-.25*w,h)]
            stamp(draw, x, y, polygon, int(rng.uniform(67, 194)))
            if w >= 6.8:
                stamp(draw, x, y, [(-w,-.3),(-w*.52,-h),(.32*w,-h*.81),(-w*.38,-h*.49)],
                      int(rng.uniform(234, 255)))
    return soften(image, .52)


def accents(rng, kind):
    """Wrapped brushwork packed for terrain and water materials."""
    image = wash(rng)
    draw = ImageDraw.Draw(image)
    if kind == "ripple":
        x, y = np.meshgrid(np.arange(SIZE) * math.tau / SIZE, np.arange(SIZE) * math.tau / SIZE)
        phase = 2*x + 6*y + 0.85*np.sin(2*x-y) + 0.55*np.sin(3*x+2*y)
        signal = np.sin(phase) * 0.58 + np.sin(3*x-5*y+np.sin(x+2*y)) * 0.42
        return Image.fromarray(np.uint8(np.clip(signal * 112 + 127, 0, 255)))
    if kind == "grass":
        for _ in range(235):
            x, y = rng.uniform(0, SIZE, 2)
            for j in range(rng.integers(3, 8)):
                px, py = x + rng.uniform(-5, 5), y + rng.uniform(-4, 4)
                length = rng.uniform(2.0, 7.5)
                lean = rng.uniform(-0.72, 0.43)*length
                shade = int(rng.uniform(93, 218))
                stamp(draw, px % SIZE, py % SIZE,
                      [(-0.7, 1), (lean-0.65, -length*.64), (lean, -length),
                       (lean+0.7, -length*.67), (0.9, 1.2)], shade)
    elif kind == "gravel":
        draw.rectangle((0, 0, SIZE, SIZE), fill=39)
        for _ in range(410):
            x, y = rng.uniform(0, SIZE, 2)
            length = rng.uniform(1.2, 5.0)
            width = length*rng.uniform(0.49, 0.85)
            shade = int(rng.uniform(122, 217))
            stamp(draw, x, y, [(-length, 0), (-.44*length, -width), (.63*length, -.7*width),
                               (length, -.1*width), (.44*length, width), (-.62*length, .8*width)], shade)
            stamp(draw, x, y, [(-.5*length, -.25*width), (0, -.85*width),
                               (.6*length, -.45*width), (.20*length, -.12*width)], min(251, shade+43))
    else:
        for _ in range(350):
            x, y = rng.uniform(0, SIZE, 2)
            length, width = rng.uniform(3, 15), rng.uniform(1, 4)
            shade = int(rng.uniform(83, 196))
            stamp(draw, x, y, [(-length, width), (-.49*length, -.4*width), (.1*length, -width),
                               (length, -.5*width), (.5*length, .45*width), (-.1*length, width)], shade)
    return soften(image, 0.48)


def cobbles(rng):
    """Paint chipped, uneven cobble faces and seams into a wrapped tile."""
    x, y = np.meshgrid(np.arange(SIZE), np.arange(SIZE))
    best = np.full((SIZE, SIZE), np.inf)
    next_best = best.copy()
    shade = np.zeros_like(best)
    for row in range(8):
        for col in range(8):
            cx = (col + 0.45*(row % 2) + rng.uniform(-0.23, 0.23))*32
            cy = (row + rng.uniform(-0.22, 0.22))*32
            dx = (x-cx+128) % SIZE - 128
            dy = (y-cy+128) % SIZE - 128
            distance = np.hypot(dx, dy)
            nearer = distance < best
            next_best = np.where(nearer, best, np.minimum(next_best, distance))
            best = np.minimum(best, distance)
            shade = np.where(nearer, rng.uniform(0.43, 0.83), shade)
    brush = np.asarray(brush_layer(rng, "dirt"), dtype=float) / 255
    face = np.clip((next_best-best + 3*np.sin(x*np.pi/16)*np.sin(y*np.pi/16)-1.1)/5.8, 0, 1)
    bevel = np.clip((next_best-best-5)/8, 0, 1)
    pigment = 0.14 + face * (shade + (brush-0.60)*0.52 - bevel*0.14)
    return Image.fromarray(np.uint8(np.clip(pigment, 0, 1)*255))


if __name__ == "__main__":
    write_tiles(Path(__file__).resolve().parent)
