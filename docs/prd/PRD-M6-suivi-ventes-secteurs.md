# PRD — M6 : Suivi des ventes par patient et par secteur, et « Imagerie médicale » à la place d'« Échographie »

Statut : **brouillon** du 20/10/2026, à arrêter par la Direction et le Gestionnaire de stock
Sources : demande de la Direction du 20/10/2026 · exigences du Gestionnaire de stock (vague 34, quatorze points) · vocabulaire des six secteurs arrêté le 06/09/2026 (vague 55) · imagerie à cinq modalités (vague 61) · prototype `m6-point-ventes`

## 1. Problème

Le **Point global des ventes** imprime les totaux par groupe de prestation et les trois parts (assureur, personnel, remise), mais quand on **sélectionne un ou plusieurs patients**, il ne dit pas **ce qui a été vendu à chacun** : quelles analyses au laboratoire, quels articles à la pharmacie, quelles consultations, quels examens d'imagerie, quels actes de maternité, quels soins d'hospitalisation. La Direction veut lire, patient par patient et secteur par secteur, le détail des prestations — c'est la question posée quand un assuré conteste, quand une compagnie demande un relevé, quand on compare deux patients. Par ailleurs, le secteur de recette s'appelle encore **« Échographie »** dans les groupes de prestation, les centres de coûts, la fabrique `secteurNormalise` et plusieurs écrans, alors que la clinique pratique aussi radiographie, mammographie, scanner et IRM (vague 61) : un examen IRM se compte aujourd'hui sous « Échographie », ce qui est faux sur le papier qu'on signe.

## 2. Objectifs et non-objectifs

**Objectifs**

- O1. Le Point global, pour un ou plusieurs patients sélectionnés, **détaille par secteur** ce qui a été vendu à chacun : Laboratoire (analyses), Pharmacie (articles), Consultation (consultations et actes de cabinet), Imagerie médicale (examens, toutes modalités), Maternité (actes du secteur), Hospitalisation et soins (séjours, soins, actes) — avec quantités, montants, parts et reste dû.
- O2. Le vocabulaire **« Imagerie médicale »** remplace « Échographie » comme secteur de recette et centre de coûts, **partout** (groupes, centres, fabrique, écrans, états, tableaux de bord), sans renommer les identifiants techniques (`echographie`, `imagerie`) ni perdre une donnée historique.
- O3. Les quatre axes existants (période, client, article, groupe) restent une **seule population de lignes** ; le détail par patient en est une **cinquième lecture**, pas une seconde source.

**Non-objectifs**

- Un état par secteur imprimé depuis chaque module (M5, M6, M2…) : le détail vit dans le point des ventes, qui lit les **lignes payables** — une seconde famille d'états divergerait au premier correctif.
- Afficher des données **médicales** (résultats, diagnostics) dans un état de ventes : le point dit ce qui a été **facturé**, jamais ce qui a été trouvé (RG-13).
- Recalculer le prix des lignes : les montants sont ceux de la pièce émise.
- Créer une modalité « Ingénierie médicale » : la demande emploie ce mot, mais le secteur de la nomenclature nationale et du catalogue des actes est **Imagerie médicale** (déjà le libellé des actes IM01-IM06 et de la rangée du ruban depuis la vague 55) ; l'ingénierie biomédicale est la maintenance du parc (`m13-maintenance`), un autre métier.

## 3. Utilisateurs et rôles

| Rôle | Voit | Fait | Ne voit pas |
|---|---|---|---|
| Gestionnaire de stock | les quatre axes et le détail par patient | imprime point global / détaillé / **par patient** | rien de médical : libellés de prestations seulement |
| Directrice Administrative, Direction | idem | idem | — |
| Caissier | le registre des pièces du jour (M8) | — | `m6-point-ventes` reste fermé (M6 hors stock détail) |
| Comptable, Assistant de Direction | lecture | imprime | — |

## 4. Parcours

1. Le gestionnaire choisit une période, puis **un ou plusieurs clients** dans la liste à recherche (existante).
2. L'écran affiche, en plus des quatre onglets, un onglet **« Par patient »** : une carte par patient, six blocs (un par secteur, les secteurs vides dits « aucune vente »), chaque bloc listant les lignes (date, pièce, désignation, quantité, brut, remise, part assureur, part personnel, payé, reste dû) avec son sous-total par `somme`.
3. **« Point global »** imprime, **si des patients sont sélectionnés**, le récapitulatif par groupe **puis** une page par patient avec ses six blocs ; sans sélection, le point global reste ce qu'il est.
4. **« Point détaillé »** inchangé (une ligne par pièce) ; un troisième bouton **« Point par patient »** imprime seulement les pages par patient.

## 5. Exigences fonctionnelles

| Réf. | Énoncé | Source | Règles | Critère d'acceptation |
|---|---|---|---|---|
| EF-M6-40 | Onglet **« Par patient »** dans `m6-point-ventes`, actif dès qu'un client est sélectionné ; un bloc par secteur de `D.GROUPES_PRESTATION`, dans l'ordre arrêté | demande 20/10 | — | Avec deux patients sélectionnés, deux cartes, six blocs chacune, sous-totaux par bloc = somme des lignes affichées |
| EF-M6-41 | Le rattachement d'une ligne à un secteur passe par la **fabrique existante** `groupePrestation(categorie, ligne)` (secteur de l'acte au catalogue, modalité pour l'imagerie) — jamais une seconde règle | vague 55 | — | Un accouchement tombe en Maternité, un pansement en Hospitalisation et soins, une IRM en Imagerie médicale |
| EF-M6-42 | Chaque ligne porte la **désignation** (analyse, article, acte, examen), la quantité, le brut, la remise, les parts assureur / personnel, le payé et le reste dû (lus de la ligne payable et de ses règlements) | vague 29 (lignes payables), vague 34 (trois parts) | RG-02 | Aucune remise sur une ligne de médicament ; reste dû = patient − encaissé, au franc |
| EF-M6-43 | **Point global** imprimé : récapitulatif par groupe, puis, si sélection, une page par patient avec ses blocs ; **Point par patient** : les pages par patient seules ; cartouche : période, patients retenus, nombre de pièces | demande 20/10 | — | L'état porte les filtres en force (`print.js`), totaux par `somme`, en-tête légal |
| EF-M6-44 | Renommage du secteur : `GROUPES_PRESTATION[echographie].label = 'Imagerie médicale'`, `CENTRES_COUT[imagerie].label = 'Imagerie médicale'`, `secteurNormalise()` rend `'Imagerie médicale'` ; `D.SECTEURS_RECETTE` suit ; **identifiants techniques inchangés** | demande 20/10 · doctrine « laborantin » | — | `grep "Échographie"` dans `data.js` ne reste que sur les examens échographiques et la modalité ; les écrans qui comparaient au libellé (« Échographie ») passent par l'identifiant |
| EF-M6-45 | Reprise des **données en place** : les écritures et lignes portant `secteur: 'Échographie'` ou `centreCout: 'imagerie'` se lisent via la fabrique normalisée — aucune réécriture du magasin ; `VERSION` incrémentée si un référentiel semé change de forme (`centresCouts`) | vague 55 (`centresCouts` au socle) | RG-14 | Le rapprochement groupe ↔ centre continue de rapprocher ; la ventilation analytique affiche « Imagerie médicale » sur les écritures anciennes |
| EF-M6-46 | **Écrans et états** qui disaient « Échographie » pour le secteur : `m12-rentabilite-groupes`, `m12-cout-activite`, `m2-stats-echographie` (titre déjà « imagerie médicale »), tableaux de bord DA/Direction, point des ventes, centres de coûts de `cfg-*` : libellé « Imagerie médicale » ; le mot « Échographie » reste pour l'**examen** et la **modalité** | vague 55, 61 | — | Audit par scénario : aucun libellé de SECTEUR « Échographie » sur ces écrans ; les examens ECHO gardent leur nom |
| EF-M6-47 | Les **statistiques** par secteur (PIL) lisent le même libellé ; `m2-stats-echographie` devient le tableau des cinq modalités avec un filtre « Modalité » (déjà en place au registre) | vague 61 | — | Une IRM figure aux statistiques d'imagerie, pas sous « Échographie » |

## 6. Données

- Aucune collection nouvelle. Lignes payables et règlements existants.
- Référentiels touchés : `GROUPES_PRESTATION`, `CENTRES_COUT` (semence) et la collection `centresCouts` (au socle depuis la vague 55 : son libellé change → **`VERSION` incrémentée**, et une reprise `fusionner…` au chargement renomme le libellé sans toucher au `code`).
- Mesure du magasin : aucune croissance (lecture seule).

## 7. Hors ligne et synchronisation

Le point des ventes **lit** : rien n'y est écrit. Sans hub, il lit les lignes présentes sur le poste ; une bannière dit « ventes des autres postes reçues jusqu'au … » (dernière séquence synchronisée), car un point imprimé sur un poste isolé ne porte que ce que ce poste a reçu. Le renommage de secteur est une modification de **référentiel** (fiche descriptive, dernier écrit gagne) semée au socle : chaque poste l'applique à la mise à jour de schéma.

## 8. Impression et états

Trois états depuis le même écran : **Point global** (groupes + pages patients si sélection), **Point détaillé** (par pièce), **Point par patient** (pages patients). Gabarit A4, en-tête légal, pied normalisé, les trois pourcentages en toutes lettres (existant), **sous-totaux par secteur et total par patient** par `somme`. Signatures : Gestionnaire de stock, Directrice Administrative.

## 9. Ce qui n'est pas documenté

- L'**ordre des six blocs** et le choix de dire « aucune vente » pour un secteur vide sont des propositions.
- Aucun document ne demande un état « par patient » signé par la compagnie d'assurance : s'il doit servir de **relevé opposable**, il relève de M9 (`m9-factures-assureur`), qui contrôle déjà que relevé et facture mensuelle se recoupent.

## 10. Questions ouvertes

1. Le « Point global » imprimé avec sélection doit-il **remplacer** le récapitulatif par groupe par les pages patients, ou les **ajouter** ? (recommandation : ajouter — le récapitulatif reste la première page)
2. Le détail par patient doit-il porter les **noms des analyses** (libellé de catalogue, non médical) ? (recommandation : oui — c'est la désignation facturée, pas le résultat)

## 11. Priorités

- **P0** : EF-M6-40 à 44 (onglet par patient, fabrique unique, impression, renommage du référentiel).
- **P1** : EF-M6-45 à 47 (reprise des écrans et statistiques, filtre modalité).
- **P2** : export CSV par patient ; relevé par compagnie depuis le même détail (à rapprocher de M9).

## 12. Indicateurs

- Au guichet, la question « qu'a-t-on facturé à ce patient ce mois-ci ? » trouve sa réponse imprimée en moins d'une minute (scénario mesuré).
- 0 ligne d'imagerie non échographique comptée sous « Échographie » après la vague (sonde sur le jeu : IRM, scanner, mammographie, radiographie).
