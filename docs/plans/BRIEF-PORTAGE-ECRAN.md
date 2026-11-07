# Brief — porter un écran de la maquette en Flutter (méthode de la tranche 1, à suivre à la lettre)

Public : un agent (ou une session) qui porte des écrans de `prototype_html/` vers `apps/poste`. Lire aussi `CLAUDE.md` (doctrine, RG-01→14) et `docs/architecture/ECARTS-MAQUETTE.md`.

## But et critère
Un écran est **porté** quand : (1) sa **parité de contenu N1 = 100 %** est MESURÉE (`apps/poste/test/parite_ecrans_test.dart` compare les libellés de `docs/architecture/ecrans/<id>.json` à ce que Flutter affiche) ; (2) ses **règles chiffrées** sont dans `packages/domaine` et **rejouées sur des vecteurs tirés de la maquette** ; (3) il a des **tests de comportement qui peuvent échouer** ; (4) mise en page = celle de la maquette (aucune refonte). Aucun écran n'est « à peu près » porté.

## Principe : on extrait, on ne devine
- Lire le code de l'écran dans `prototype_html/assets/js/modules/<module>.js` (`SIGH.screen('<id>', …)`).
- **Les vecteurs se tirent de l'écran réel piloté dans Chrome**, pas de la lecture du code : modèles à copier — `prototype_html/build/vecteurs-emission.js` (pilote l'écran), `vecteurs-avoir.js` (appelle un moteur exposé), `vecteurs-remboursements.js` (pilote une modale), `vecteurs-mecef.js`. Squelette : `const { ouvrirMaquette, ecrire, ROOT } = require('./extraire')` ; `m.page.addScriptTag({path: …/modules/<module>.js})` ; `SIGH.screens['<id>'].render(root)` ; sortie dans `packages/domaine/test/vecteurs/<nom>.json`.
- Une règle sans vecteur n'est pas portée. Un écart trouvé dans la maquette : **le corriger dans la maquette d'abord** (puis régénérer les vecteurs) s'il est indiscutable, sinon **le porter fidèlement et le signaler** dans `docs/architecture/ECARTS-MAQUETTE.md` (nouvelle section, numéros E17+ ; ne pas réutiliser un numéro).
- Ne jamais inventer un tarif, une borne, un numéro. « Non calculable » n'est pas zéro ; un refus se nomme ; une commande interdite est ABSENTE (pas grisée) ; archiver, jamais supprimer (RG-14).

## Où mettre quoi
- Écran : `apps/poste/lib/modules/<module>/<fichier>.dart` ; enregistrement : UNE ligne dans `apps/poste/lib/modules/<module>/registre_<module>.dart` (`ecransM6`, `ecransM7`…). **Ne pas toucher** `registre.dart`, `magasin.dart`, `parite-statuts.json`, `gen-poste-jeu.js`, `rapport-parite-*.json` (le coordinateur les gère).
- Règles : `packages/domaine/lib/src/<domaine>/<nom>.dart` + UNE ligne d'export dans `packages/domaine/lib/sigh_domaine.dart` (Edit ciblé, jamais de réécriture du fichier) + `packages/domaine/test/<nom>_test.dart`.
- Données : `apps/poste/assets/donnees/jeu/<collection>.json` (engendrées par la maquette). Une collection manque ? Le dire dans le rapport au coordinateur (ne pas éditer le générateur).
- Modèles à lire AVANT d'écrire : `lib/modules/m8/factures.dart` (CrudSigh), `m8/dashboard.dart` (tableau de bord), `m8/facturation.dart` (page de saisie), `m8/avoirs.dart` (tableau + modale + tiroir), `m8/remboursements.dart`, `lib/modules/mecef/ecrans.dart` (onglets, registres), `lib/kit/*` (composants mesurés contre la maquette : `TableauSigh`, `CrudSigh`, `FormulaireSigh`, `afficherModale`, `afficherTiroir`, `KpiSigh`, `CarteSigh`, `NoteSigh`, `GraphiqueBarres/Ligne/Anneau`, `OngletsSigh`, `FileAttenteSigh`…), `lib/shell/contexte_ecran.dart` (droits de L'ÉCRAN : `c.droit.editer/annuler`), `lib/donnees/magasin.dart` (`inserer` insère EN TÊTE comme la maquette, `mettreAJour` rend l'annulation, `archiver`/`restaurer`, journal RG-12 automatique).
- Impression : `lib/impression/piece.dart` (`PieceA4`, `BlocTableau`, `BlocTexte`, `Signature`) + `apercu.dart` (`afficherApercu`, `afficherApercuTicket`). Le total d'un tableau est CALCULÉ (`somme` sur la colonne), jamais fourni.

## Pièges déjà payés
- Une modale vit AU-DESSUS de la coque : `ContexteEcran.of(contexteDeLaModale)` échoue — passer le contexte de l'écran à la modale pour toasts/impressions.
- `CollectionMagasin.inserer` insère en tête : un test qui cherche « la dernière fiche » cherche `.first`.
- Le jeu ne contient pas de garantie d'assurance : un assuré y est facturé intégralement au patient (« convention non saisie ») ; les tests posent leurs propres fiches.
- `ToastsSigh` laisse un minuteur : finir chaque test par `await t.pump(const Duration(seconds: 10))`.
- Listes longues (`FormulaireSigh` select > 8 entrées) : le panneau ne construit que les lignes visibles — taper dans la recherche avant de toucher l'option (voir `test/m8_avoirs_test.dart`, `choisir`).
- Comparer des libellés : espaces insécables (U+202F, U+00A0) de `money()` ; ne pas comparer d'espaces ordinaires.
- Maquette : le « tri » est `localeCompare` français numérique → `trierPar` du domaine (déjà aligné sur les vecteurs).

## Commandes (SDK : `export PATH=$PATH:/tmp/flutter-dl/flutter/bin:/tmp/dartsdk/dart-sdk/bin` ; s'il manque, voir `.claude/skills/sigh-flutter`)
- Domaine : `cd packages/domaine && dart analyze && dart test`
- Poste : `cd apps/poste && flutter analyze lib test && flutter test test/<ton_fichier>_test.dart` ; parité : `flutter test test/parite_ecrans_test.dart` puis lire ton écran dans `docs/architecture/rapport-parite-flutter.json` (`taux` doit valoir 1.0, `manquants` vide) — ne pas committer ce rapport.
- Maquette (vecteurs) : `service postgresql start` ; `export CHROME_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome` ; **toute commande qui lance la maquette dans Chrome passe par `flock /tmp/sigh-banc.lock …`** (la base de test est unique et remise à neuf à chaque lancement) ; `cd prototype_html && flock /tmp/sigh-banc.lock node build/vecteurs-<nom>.js`.
- Dans un worktree : `ln -s /home/user/sighcnt/prototype_html/node_modules prototype_html/node_modules` (jamais versionné).
- Ne pas lancer `npm run test` de la maquette (30 min, base partagée). Ne pas modifier de fichier de la maquette hors du strict nécessaire à une correction d'écart indiscutable.

## Rapport attendu (court, factuel)
Écrans portés (id, N1 mesuré), fichiers créés/modifiés, vecteurs et nombre de cas, tests ajoutés (nombre, tous verts ?), écarts E17+ consignés, ce qui N'EST PAS porté sur chaque écran et pourquoi, collections manquantes. Dire ce qui n'a pas pu être vérifié. Ne pas affirmer « fait » sans avoir lu la sortie des commandes.
