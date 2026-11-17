"""Dessine les cadres rouges (et les pastilles numérotées) sur les captures du poste Flutter (poste-*.png) d'après leurs fichiers .rects.json,
puis supprime ces fichiers. Pixels logiques x 1.5 (facteur de la capture). python3 annoter-poste.py"""
import json, os, glob
from PIL import Image, ImageDraw, ImageFont
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures')
K = 1.5
for j in sorted(glob.glob(os.path.join(d, 'poste-*.rects.json'))):
    png = j.replace('.rects.json', '.png')
    rects = json.load(open(j, encoding='utf-8'))
    if os.path.exists(png) and rects:
        im = Image.open(png).convert('RGB'); dr = ImageDraw.Draw(im)
        try: f = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf', 20)
        except Exception: f = ImageFont.load_default()
        for i, r in enumerate(rects, 1):
            x, y, w, h = r['x'] * K, r['y'] * K, r['w'] * K, r['h'] * K
            if y < 0 or y + h > im.height - 20: continue
            dr.rounded_rectangle([x - 5, y - 5, x + w + 5, y + h + 5], radius=8, outline=(225, 29, 29), width=4)
            if len(rects) > 1:
                cx, cy = max(x - 14, 12), max(y - 14, 12)
                dr.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=(225, 29, 29)); dr.text((cx - 6, cy - 12), str(i), fill='white', font=f)
        im.save(png, optimize=True)
    os.remove(j)
