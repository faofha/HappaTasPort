# Draws an element dump from tests/test_render.lua (EL {...} lines) with PIL, using Roboto Mono Bold.
# usage: python3 render_dump.py dump.txt out.png [height] [font.ttf] [background.png]
import sys, json, math
from PIL import Image, ImageDraw, ImageFont

dump, out = sys.argv[1], sys.argv[2]
H = int(sys.argv[3]) if len(sys.argv) > 3 else 120
FONT = sys.argv[4] if len(sys.argv) > 4 else None
BGIMG = sys.argv[5] if len(sys.argv) > 5 else None
W = 1920
img = Image.new('RGBA', (W, H), (124, 189, 218, 255))  # sky like the screenshot
if BGIMG:
    b = Image.open(BGIMG).convert('RGBA')
    img.paste(b.crop((0, 0, W, H)), (0, 0))
fonts = {}
def font(size, weight):
    key = (round(size * 100), weight)
    if key in fonts: return fonts[key]
    f = ImageFont.truetype(FONT, size) if FONT else ImageFont.load_default()
    try: f.set_variation_by_axes([weight])
    except Exception: pass
    fonts[key] = f
    return f

def blend(dst, rect, color, alpha, clip):
    x0, y0, x1, y1 = rect
    if clip:
        x0, y0, x1, y1 = max(x0, clip[0]), max(y0, clip[1]), min(x1, clip[2]), min(y1, clip[3])
    # Roblox snaps GUI edges to whole pixels
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    if x1 <= x0 or y1 <= y0: return
    over = Image.new('RGBA', (x1 - x0, y1 - y0), tuple(color) + (int(round(alpha * 255)),))
    dst.alpha_composite(over, (x0, y0))

def grad_box(dst, rect, top, bot, alpha, clip):
    x0, y0, x1, y1 = [int(round(v)) for v in rect]
    if clip:
        cx0, cy0, cx1, cy1 = [int(round(v)) for v in clip]
    else:
        cx0, cy0, cx1, cy1 = 0, 0, W, H
    h = y1 - y0
    for yy in range(max(y0, cy0), min(y1, cy1)):
        t = (yy - y0 + 0.5) / h if h > 0 else 0
        c = tuple(int(round(top[i] + (bot[i] - top[i]) * t)) for i in range(3))
        blend(dst, (max(x0, cx0), yy, min(x1, cx1), yy + 1), c, alpha, None)

# text model: "line" = a TextSize-tall line holds Roboto Mono's whole ascender..descender (2146 + 555
# per 2048 em), like Roblox's text engine; otherwise the em is TextSize and the ascender..descender box
# is centred on an em-high line
LINE_MODEL = any(l.startswith('TEXTMODEL line') for l in open(dump, encoding='utf-8'))
for line in open(dump, encoding='utf-8'):
    if not line.startswith('EL '): continue
    e = json.loads(line[3:])
    x, y, w, h = e['x'], e['y'], e['w'], e['h']
    clip = e.get('clip')
    a = 1 - e['bt']
    if a > 0.001 and w > 0 and h > 0:
        if e['rot'] not in (0, 0.0):
            # rotated thin line (the close box X)
            cx, cy = x + w / 2, y + h / 2
            ang = math.radians(e['rot'])
            dx, dy = math.cos(ang) * w / 2, math.sin(ang) * w / 2
            d = ImageDraw.Draw(img)
            d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=tuple(e['bg']) + (int(a * 255),), width=max(1, int(round(h))))
        elif 'grad' in e:
            top, bot = e['grad']
            tint = e['bg']
            top = [top[i] * tint[i] / 255 for i in range(3)]
            bot = [bot[i] * tint[i] / 255 for i in range(3)]
            grad_box(img, (x, y, x + w, y + h), top, bot, a, clip)
        else:
            blend(img, (x, y, x + w, y + h), e['bg'], a, clip)
    if 'text' in e:
        size = e['ts']
        em = size * 2048 / 2701 if LINE_MODEL else size
        f = font(em, e.get('fw', 700))
        layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if LINE_MODEL:
            asc = size * 2146 / 2701                      # baseline 2146 / 2048 em under the line top
        else:
            asc = (size + em * (2146 - 555) / 2048) / 2  # ascender..descender centred on the em line
        bx = x
        for i, ch in enumerate(e['text']):
            d.text((bx + i * em * 0.6001, y + asc), ch, font=f, fill=tuple(e['tc']) + (255,), anchor='ls')
        if clip:
            m = Image.new('L', img.size, 0)
            ImageDraw.Draw(m).rectangle([clip[0], clip[1], clip[2] - 1, clip[3] - 1], fill=255)
            layer.putalpha(Image.composite(layer.getchannel('A'), Image.new('L', img.size, 0), m))
        img.alpha_composite(layer)
img.convert('RGB').save(out)
print(out)
