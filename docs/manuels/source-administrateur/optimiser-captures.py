"""Réduit les captures brutes (OUT de captures.js) à 1800 px de large et 256 couleurs, puis les range dans captures/.
Usage : python3 optimiser-captures.py <dossier des brutes> [nom ...]"""
import os, sys
from PIL import Image
src = sys.argv[1]
noms = sys.argv[2:]
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures')
avant = apres = 0
for f in sorted(os.listdir(src)):
    if not f.endswith('.png') or (noms and f[:-4] not in noms):
        continue
    im = Image.open(os.path.join(src, f))
    avant += os.path.getsize(os.path.join(src, f))
    im = im.convert('RGB')
    if im.width > 1800:
        im = im.resize((1800, round(im.height * 1800 / im.width)), Image.LANCZOS)
    im = im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    p = os.path.join(d, f)
    im.save(p, optimize=True)
    apres += os.path.getsize(p)
print(f'{avant/1e6:.1f} Mo -> {apres/1e6:.1f} Mo')
