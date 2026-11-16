"""Réduit les captures PNG à une palette de 256 couleurs (lisible, quatre fois plus léger). python3 optimiser.py"""
import os, sys
from PIL import Image
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures')
avant = apres = 0
for f in sorted(os.listdir(d)):
    if not f.endswith('.png'):
        continue
    p = os.path.join(d, f)
    avant += os.path.getsize(p)
    im = Image.open(p)
    if im.width > 2000:
        im = im.convert('RGB').resize((2000, round(im.height * 2000 / im.width)), Image.LANCZOS)
    if im.mode != 'P':
        im = im.convert('RGB').quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        im.save(p, optimize=True)
    apres += os.path.getsize(p)
print(f'{avant/1e6:.1f} Mo -> {apres/1e6:.1f} Mo')
