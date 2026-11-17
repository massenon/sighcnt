"""Pose les cadres rouges numérotés sur les captures Flutter (rects.json écrit par apps/poste/test_captures/captures_admin_test.dart), masque le code de secours,
réduit à 1800 px de large et 256 couleurs, et range le résultat dans captures/.
Usage : python3 annoter-flutter.py <dossier de sortie du test>"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
src = sys.argv[1]
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures')
rects = json.load(open(os.path.join(src, 'rects.json'), encoding='utf-8'))
police = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 30)
masquer = {'f-ins-code-secours': 1}
E = 2  # rapport pixels / pixels logiques de la capture
for f in sorted(os.listdir(src)):
    if not f.endswith('.png'):
        continue
    nom = f[:-4]
    im = Image.open(os.path.join(src, f)).convert('RGB')
    d = ImageDraw.Draw(im)
    for r in rects.get(nom, []):
        x, y, l, h = r['x'] * E, r['y'] * E, r['l'] * E, r['h'] * E
        if masquer.get(nom) == r['n']:
            d.rounded_rectangle([x, y, x + l, y + h], radius=14, fill=(15, 23, 42))
            d.text((x + 24, y + h / 2 - 18), 'Code de secours masqué sur cette capture', fill=(255, 255, 255), font=police)
        p = 7
        d.rounded_rectangle([x - p, y - p, x + l + p, y + h + p], radius=18, outline=(227, 6, 19), width=6)
        cx, cy = x - p - 6, y - p - 6
        d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(227, 6, 19))
        t = str(r['n'])
        w = d.textlength(t, font=police)
        d.text((cx - w / 2, cy - 19), t, fill=(255, 255, 255), font=police)
    if im.width > 1800:
        im = im.resize((1800, round(im.height * 1800 / im.width)), Image.LANCZOS)
    im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(os.path.join(dst, nom + '.png'), optimize=True)
    print('ok', nom)
