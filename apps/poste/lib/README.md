# Organisation de `lib/` (à remplir par tranches verticales)

```
core/      thème (jetons), formats français (U+202F / U+00A0), HLC, UUID v7
data/      base locale (drift + SQLCipher), file d'envoi, curseurs
sync/      client P1 (fileul -> mère) ; en mode mère : serveur + pont P2 (enveloppes chiffrées)
ui/        kit de composants (tableau, modale, formulaire à six colonnes, combo, tiroir), ruban, droits
modules/   un dossier par module, dans l'ordre des tranches : m8 caisse + MECeF -> m6/m7 -> m5/m2 -> ...
mere/      console (appareils, jetons, conflits, supervision, sauvegardes) et service
```
