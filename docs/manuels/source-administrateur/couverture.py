"""Pose la couverture nue (sans pied de page) par-dessus la page 1 du manuel, en gardant le sommaire cliquable.
Usage : python3 couverture.py <manuel.pdf> <couverture.pdf> <sortie.pdf>  (nécessite pypdf)."""
import sys
from pypdf import PdfReader, PdfWriter

manuel, couverture, sortie = sys.argv[1:4]
w = PdfWriter(clone_from=manuel)
w.pages[0].merge_page(PdfReader(couverture).pages[0])
w.write(sortie)
