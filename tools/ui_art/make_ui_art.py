"""Рукодельные текстуры интерфейса v1.3: бумага вахтенного журнала, просмолённый лист для HUD,
карандашные рамки кнопок, чернильные мазки, штамп. Всё процедурное (без чужих ассетов).
python3 tools/ui_art/make_ui_art.py  ->  assets/ui/paper/*.png"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "paper")
FONTS = os.path.join(ROOT, "assets", "fonts")
os.makedirs(OUT, exist_ok=True)
R = random.Random(1979)


def noise(w, h, scale, seed):
    rnd = random.Random(seed)
    small = Image.new("L", (max(2, w // scale), max(2, h // scale)))
    small.putdata([rnd.randint(0, 255) for _ in range(small.size[0] * small.size[1])])
    return small.resize((w, h), Image.BICUBIC)


def rough_mask(w, h, margin, wobble, seed, corner_cut=True):
    """Неровный край листа: многоугольник с дрожащими сторонами + мелкие надрывы."""
    rnd = random.Random(seed)
    pts = []
    step = 6
    def j():
        return rnd.uniform(-wobble, wobble)
    for x in range(margin, w - margin, step):
        pts.append((x, margin + j()))
    for y in range(margin, h - margin, step):
        pts.append((w - margin + j(), y))
    for x in range(w - margin, margin, -step):
        pts.append((x, h - margin + j()))
    for y in range(h - margin, margin, -step):
        pts.append((margin + j(), y))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    # надрывы и загнутый угол
    d = ImageDraw.Draw(m)
    for _ in range(4):
        side = rnd.choice("tblr")
        t = rnd.uniform(.15, .85)
        if side in "tb":
            x = int(w * t); y = margin if side == "t" else h - margin
            d.polygon([(x - 5, y), (x + 5, y), (x + rnd.randint(-2, 2), y + (9 if side == "t" else -9))], fill=0)
        else:
            y = int(h * t); x = margin if side == "l" else w - margin
            d.polygon([(x, y - 5), (x, y + 5), (x + (9 if side == "l" else -9), y + rnd.randint(-2, 2))], fill=0)
    if corner_cut:
        c = rnd.randint(10, 18)
        d.polygon([(w - margin - c, margin - 2), (w - margin + 2, margin - 2), (w - margin + 2, margin + c)], fill=0)
    m = m.filter(ImageFilter.GaussianBlur(.8))
    # выкрошенный край: «дырочки» только в полосе у кромки, середина листа сплошная
    edge = noise(w, h, 3, seed + 1).point(lambda v: 255 if v > 40 else 150)
    band = Image.new("L", (w, h), 255)
    ImageDraw.Draw(band).rectangle([margin + 7, margin + 7, w - margin - 7, h - margin - 7], fill=0)
    band = band.filter(ImageFilter.GaussianBlur(3))
    holes = ImageChops.lighter(edge, ImageChops.invert(band))
    return ImageChops.multiply(m, holes)


def stains(img, seed, count, color, rmin, rmax, alpha):
    rnd = random.Random(seed)
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        cx, cy = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.uniform(rmin, rmax)
        # кольцо от кружки / пятно
        if rnd.random() < .4:
            d.ellipse([cx - r, cy - r * .9, cx + r, cy + r * .9], outline=color + (alpha,), width=max(1, int(r * .08)))
        else:
            d.ellipse([cx - r, cy - r * .7, cx + r, cy + r * .7], fill=color + (alpha // 2,))
    layer = layer.filter(ImageFilter.GaussianBlur(3))
    return Image.alpha_composite(img, layer)


def fibers(img, seed, count, color, alpha):
    rnd = random.Random(seed)
    w, h = img.size
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(count):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        a = rnd.uniform(0, math.pi)
        l = rnd.uniform(3, 14)
        d.line([(x, y), (x + math.cos(a) * l, y + math.sin(a) * l)], fill=color + (rnd.randint(alpha // 3, alpha),), width=1)
    return img


def sheet(name, w, h, base, dark_edge, seed, stain_color, margin=6, wobble=2.4, lines=False, alpha=255):
    n1 = noise(w, h, 40, seed).filter(ImageFilter.GaussianBlur(6))
    n2 = noise(w, h, 3, seed + 7).filter(ImageFilter.GaussianBlur(1.2))
    img = Image.new("RGBA", (w, h), base + (255,))
    px = img.load(); a1 = n1.load(); a2 = n2.load()
    for y in range(h):
        for x in range(w):
            k = (a1[x, y] - 128) / 128 * .09 + (a2[x, y] - 128) / 128 * .018
            r, g, b, _ = px[x, y]
            px[x, y] = (int(max(0, min(255, r * (1 + k)))), int(max(0, min(255, g * (1 + k)))), int(max(0, min(255, b * (1 + k * 1.2)))), 255)
    img = stains(img, seed + 3, 7, stain_color, 14, 60, 60)
    img = fibers(img, seed + 4, 22, dark_edge, 12)
    if lines:
        d = ImageDraw.Draw(img, "RGBA")
        d.line([(40, 10), (40, h - 10)], fill=(150, 60, 50, 22), width=1)
    # потемневшие края (подпалины, грязь от пальцев)
    edge = Image.new("L", (w, h), 0)
    ImageDraw.Draw(edge).rectangle([margin + 10, margin + 10, w - margin - 10, h - margin - 10], fill=255)
    edge = edge.filter(ImageFilter.GaussianBlur(14))
    burn = Image.new("RGBA", (w, h), dark_edge + (150,))
    img = Image.composite(img, Image.alpha_composite(img, burn), edge)
    mask = rough_mask(w, h, margin, wobble, seed + 9)
    if alpha < 255:
        mask = mask.point(lambda v: v * alpha // 255)
    img.putalpha(mask)
    img.save(os.path.join(OUT, name))


def pencil_box(name, w, h, color, seed, width=2, double=False, fill=None):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if fill:
        d.polygon([(6 + rnd.uniform(-2, 2), 6 + rnd.uniform(-2, 2)), (w - 6 + rnd.uniform(-2, 2), 5), (w - 5, h - 6 + rnd.uniform(-2, 2)), (5, h - 5)], fill=fill)
    def stroke(a, b):
        steps = 18
        pts = []
        for i in range(steps + 1):
            t = i / steps
            pts.append((a[0] + (b[0] - a[0]) * t + rnd.uniform(-.8, .8), a[1] + (b[1] - a[1]) * t + rnd.uniform(-.8, .8)))
        d.line(pts, fill=color, width=width)
    passes = 2 if double else 1
    for p in range(passes):
        o = 4 + p * 4
        # углы перехлёстываются, как у рамки от руки
        stroke((o - 3, o + rnd.uniform(-1, 1)), (w - o + 4, o + rnd.uniform(-2, 2)))
        stroke((w - o + rnd.uniform(-1, 1), o - 3), (w - o + rnd.uniform(-2, 2), h - o + 3))
        stroke((w - o + 3, h - o + rnd.uniform(-1, 1)), (o - 4, h - o + rnd.uniform(-2, 2)))
        stroke((o + rnd.uniform(-1, 1), h - o + 3), (o + rnd.uniform(-2, 2), o - 4))
    grain = noise(w, h, 2, seed + 2).point(lambda v: 255 if v > 70 else 120)
    a = ImageChops.multiply(img.getchannel("A"), grain)
    img.putalpha(a)
    img.save(os.path.join(OUT, name))


def ink_smear(name, w, h, color, seed, alpha=150):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(26):
        y = h * .5 + rnd.uniform(-h * .26, h * .26)
        x0 = rnd.uniform(4, 22); x1 = w - rnd.uniform(4, 22)
        d.line([(x0, y), (x1, y + rnd.uniform(-4, 4))], fill=color + (rnd.randint(alpha // 3, alpha),), width=rnd.randint(4, 9))
    img = img.filter(ImageFilter.GaussianBlur(2.2))
    grain = noise(w, h, 2, seed + 5).point(lambda v: 255 if v > 50 else 150)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), grain))
    img.save(os.path.join(OUT, name))


def bar(name, w, h, color, seed, alpha=230):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(6):
        y = h / 2 + rnd.uniform(-h * .22, h * .22)
        d.line([(rnd.uniform(0, 3), y), (w - rnd.uniform(0, 3), y + rnd.uniform(-1, 1))], fill=color + (rnd.randint(alpha // 2, alpha),), width=max(2, h // 3))
    grain = noise(w, h, 2, seed + 1).point(lambda v: 255 if v > 60 else 140)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), grain))
    img.save(os.path.join(OUT, name))


def stamp(name, text, color, seed, size=(300, 120)):
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(os.path.join(FONTS, "OldStandard-Bold.ttf"), 40)
    d.rounded_rectangle([8, 10, w - 8, h - 10], radius=6, outline=color + (255,), width=5)
    d.rounded_rectangle([17, 19, w - 17, h - 19], radius=4, outline=color + (255,), width=2)
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, h / 2 - 25), text, font=font, fill=color + (255,))
    grain = noise(w, h, 2, seed).point(lambda v: 255 if v > 95 else (90 if v > 50 else 0))
    blot = noise(w, h, 30, seed + 1).point(lambda v: 255 if v > 70 else 60)
    a = ImageChops.multiply(ImageChops.multiply(img.getchannel("A"), grain), blot)
    img.putalpha(a.filter(ImageFilter.GaussianBlur(.5)))
    img = img.rotate(-7, resample=Image.BICUBIC, expand=True)
    img.save(os.path.join(OUT, name))


def smudge(name, w, h, seed):
    """Отпечаток пальца/сажи — для украшения углов."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    for i in range(14):
        r = 6 + i * 3.2
        d.ellipse([cx - r * 1.2 + rnd.uniform(-2, 2), cy - r + rnd.uniform(-2, 2), cx + r * 1.2, cy + r], outline=(30, 24, 18, 60 - i * 3), width=2)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    img.save(os.path.join(OUT, name))


if __name__ == "__main__":
    # светлая бумага журнала — меню, настройки, рекорды, записи
    sheet("paper_sheet.png", 900, 680, (205, 193, 160), (92, 70, 44), 11, (140, 110, 70), lines=True)
    sheet("paper_card.png", 384, 160, (214, 203, 172), (96, 74, 48), 21, (150, 118, 76))
    # просмолённый тёмный лист — панели HUD поверх ночной сцены
    sheet("tar_sheet.png", 384, 256, (34, 30, 25), (8, 7, 5), 31, (70, 58, 40), alpha=232)
    sheet("tar_strip.png", 512, 96, (30, 27, 22), (6, 5, 4), 41, (64, 52, 36), wobble=1.8, alpha=226)
    # кнопки: карандашная рамка, чернильная заливка при наведении, штамп для главной
    pencil_box("btn_pencil.png", 320, 64, (60, 48, 34, 200), 51)
    pencil_box("btn_pencil_light.png", 320, 64, (205, 190, 150, 170), 52)
    pencil_box("btn_primary.png", 320, 64, (138, 46, 32, 235), 53, width=3, double=True, fill=(170, 150, 110, 70))
    ink_smear("btn_hover.png", 320, 64, (36, 28, 20), 54, alpha=170)
    ink_smear("btn_hover_light.png", 320, 64, (200, 186, 150), 55, alpha=90)
    bar("bar_fill.png", 192, 12, (240, 240, 240), 61)
    bar("bar_track.png", 192, 12, (120, 110, 90), 62, alpha=90)
    stamp("stamp_recorded.png", "ЗАПИСАНО", (140, 40, 28), 71)
    stamp("stamp_danger.png", "ОПАСНО", (150, 36, 24), 72, size=(250, 110))
    smudge("smudge.png", 96, 96, 81)
    print("ok", sorted(os.listdir(OUT)))
