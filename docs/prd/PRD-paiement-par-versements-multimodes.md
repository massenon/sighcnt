# PRD : paiement par versements successifs et modes multiples (caisse)

Statut : brouillon, réponses de la Direction du 20/11/2026 intégrées. Auteur : Claude Code. Aucune ligne de code n'est écrite : ce document cadre le lot (nom proposé : PAIE-V).

## 1. Besoin

Un patient qui règle sa facture peut la payer en plusieurs versements, avec des modes différents : par exemple une partie en mobile money, le solde en espèces. Aujourd'hui l'encaissement d'une pièce porte UN montant et UN mode.

## 2. État mesuré (maquette, avant le lot)

- `PR.encaisser(factureId, opts)` (parcours.js) règle des LIGNES entières (`opts.lignes`) ou alloue un `opts.montant` aux lignes encore dues dans l'ordre de la pièce ; un demi-examen ne se prélève pas.
- La pièce porte `statutPaiement` : impayée, partielle, soldée ; l'écran affiche « Reste dû » et propose « Encaisser le reste » (m8-facturation).
- Les moyens de paiement sont une liste semée (`data.js`, MTN Mobile Money compte 521000, etc.). Rien ne trace plusieurs versements de modes différents sur un même encaissement, ni la référence d'une transaction mobile money.
- Proposition à valider : cette lecture est faite sur le code, pas sur une exécution de l'écran ; elle sera confirmée par la mesure du lot (règle de la maquette d'abord).

## 3. Décisions de la Direction (20/11/2026)

1. **Autant de versements que nécessaire**, pas deux. Les **types de versement** et les **modalités de versement** sont des paramètres de clinique (CRUD, défaut semé, versionnés par date), jamais des constantes du code.
2. **Pas de paiement différé d'un jour à l'autre** : le reste se règle LE MÊME JOUR. Conséquence : la caisse ne laisse pas une pièce ouverte au-delà du jour ; ce qui n'est pas réglé le jour même relève des règles existantes (créance, sortie RG-06), jamais d'un nouveau mécanisme de crédit patient.
3. **On garde la règle des prestations bloquées** : une prestation (examen, délivrance) n'est débloquée que si SA ligne est entièrement payée. Un versement partiel ne débloque que les lignes qu'il solde entièrement.
4. **Mobile money : la liste des opérateurs est un paramètre (CRUD)** (MTN, Moov, Celtiis en défaut proposé à valider) et **la référence de la transaction se saisit à la main** (aucune interface avec un opérateur : le texte médical et les données de santé ne quittent jamais la clinique, et aucun service externe n'est appelé).
5. **Le versement concerne la part du patient**, pour les patients assurés ET pour les patients non assurés. La part d'un assureur n'est pas un versement de caisse (elle suit le circuit des tiers payeurs et des règlements d'assureurs).
6. **Facture normalisée (MECeF) : ne mentionner QUE le montant total**, avec la formule « Arrêtée la présente facture à la somme de ... » et le montant **en lettres**. Les modes et les versements ne figurent pas sur la facture normalisée. Lecture à confirmer : on n'imprime pas le détail des modes sur la pièce normalisée.
7. **Sortie d'hospitalisation (RG-06) : règle inchangée** (solde apuré, signatures, constat du gardien, décision de la Direction pour une exception).

## 4. Points d'attention (rien d'inventé)

- **MECeF** : j'ignore si le boîtier ou la procédure de la DGI exige un champ de type de paiement dans la requête de vente. La décision 6 règle ce qui s'IMPRIME ; ce qui est ENVOYÉ au boîtier doit être confirmé avec le fournisseur (document de questions : `scratchpad/MECEF-questions-fournisseur-DGI.md`). Tant que ce n'est pas confirmé, le port `Mecef` ne simule rien et refuse nommément.
- **Le même jour** : « jour » se lit à la date de la pièce de caisse (l'horloge du poste), jamais à un fuseau choisi en dur ; une facture ouverte à minuit pendant un versement est un cas limite à nommer dans la spécification.
- **Justificatif** : chaque versement a sa propre pièce (RG-12, aucune action anonyme) ; une pièce émise ne se réécrit jamais (annulation par contre-passation, jamais de modification).

## 5. Objectifs

- Enregistrer N versements d'un même patient sur une même facture, chacun avec son type, sa modalité, son montant, sa référence (mobile money) et son horodatage, dont la somme ne dépasse jamais le dû de la part du patient.
- Débloquer les prestations exactement comme aujourd'hui (ligne entièrement payée).
- Calcul du reste dû et du statut (impayée, partielle, soldée) à partir des versements, jamais saisi.
- La comptabilité reçoit une écriture équilibrée par versement (RG-10), sur le compte de la modalité (par exemple mobile money 521000, espèces caisse), lu au paramétrage.
- Les versements voyagent à la synchronisation comme les autres pièces de caisse (famille A, identité par le contenu), jamais vers un téléphone.

## 6. Hors périmètre

- Paiement différé sur plusieurs jours, crédit patient, échéancier (décision 2).
- Interface automatique avec un opérateur mobile money (CDCT §4.3 : aucun interfaçage externe).
- Versement d'un assureur (circuit existant des tiers payeurs).

## 7. Récits

- Caissier : je saisis un premier versement de 15 000 en mobile money avec la référence, puis un second de 8 500 en espèces ; la facture est soldée et le reçu récapitule le total.
- Caissier : le patient paie une partie seulement ; les lignes entièrement couvertes se débloquent, les autres restent bloquées, la facture reste « partielle » jusqu'à la fin de la journée.
- Administrateur : j'ajoute un opérateur ou une modalité dans les paramètres sans toucher au code ; une modalité déjà utilisée par une pièce s'archive, elle ne se supprime pas (RG-14).
- Comptable : chaque versement a son écriture et le rapprochement mobile money se fait par la référence.
- Direction : je lis par jour le total par modalité (espèces, mobile money par opérateur).

## 8. Exigences P0

1. **Collection de versements** `versementsCaisse` (une ligne par versement : facture, ligne(s) réglée(s), type, modalité, opérateur, référence, montant, agent, date et heure) ; la pièce de caisse reste unique par facture, ses versements s'y rattachent ; aucune suppression physique.
2. **Paramètres** `types de versement`, `modalités` et `opérateurs mobile money` en base, CRUD, défaut semé « à valider », geste réservé `regler_modalites_versement` (droit de la fiche RBAC, jamais un nom de rôle).
3. **Moteur** : refus nommés (code, motif, geste) : `VERSEMENT_SUPERIEUR_AU_DU`, `VERSEMENT_REFERENCE_ABSENTE` (mobile money sans référence), `VERSEMENT_MODALITE_ARCHIVEE`, `VERSEMENT_PART_ASSUREUR` (versement sur la part d'un tiers refusé), `VERSEMENT_PIECE_SOLDEE`.
4. **Écran de caisse** : saisie de plusieurs versements dans une seule fenêtre (ajouter un versement, retirer avant validation), reste dû calculé en direct, commande absente sans le droit d'encaisser.
5. **Reçu et facture normalisée** : le reçu détaille les versements ; la facture normalisée ne porte que le total et « Arrêtée la présente facture à la somme de ... » avec le montant en lettres français (montant en lettres : règle unique au domaine, avec vecteurs).
6. **Comptabilité** : une écriture équilibrée par versement.
7. **Poste Flutter** : même moteur au domaine, vecteurs tirés de l'écran réel de la maquette.
8. **Synchronisation** : famille A, identité par le contenu, refus au rejeu d'un versement qui ferait dépasser le dû (`refusRejeuVersement`), jamais vers un téléphone.

## 9. Critères d'acceptation (extraits, Given/When/Then)

- Étant donné une facture de 23 500 à la charge du patient, quand le caissier saisit 15 000 en mobile money (référence M123) puis 8 500 en espèces, alors la facture est soldée, les lignes sont débloquées, deux écritures équilibrées existent et la facture normalisée porte « 23 500 » et « vingt-trois mille cinq cents francs CFA » sans aucun mode.
- Étant donné un versement mobile money sans référence, alors refus `VERSEMENT_REFERENCE_ABSENTE`, rien d'écrit.
- Étant donné un versement qui dépasse le reste dû, alors refus `VERSEMENT_SUPERIEUR_AU_DU`.
- Étant donné un versement partiel qui solde entièrement une ligne mais pas la suivante, alors la première prestation est débloquée, la seconde reste bloquée.
- Étant donné une modalité archivée, alors elle n'est plus proposée à la saisie mais reste lisible sur les pièces passées (versionnée par date).

## 10. Mutations prévues

Versement supérieur au dû accepté ; mobile money sans référence accepté ; prestation débloquée par un versement partiel ; mode imprimé sur la facture normalisée ; modalité écrite en dur ; versement réécrit après émission ; versement envoyé à un téléphone.

## 11. Questions ouvertes

- **MECeF (fournisseur)** : le type de paiement est-il exigé dans la requête envoyée au boîtier ? Voir §4.
- **Direction** : liste des opérateurs et modalités par défaut (MTN, Moov, Celtiis, espèces, autres), comptes comptables de chaque modalité.
- **Direction** : que devient une pièce non soldée à la fin de la journée (rien de nouveau n'est créé : relève de la créance et de RG-06) ; un rappel d'alerte en fin de journée est-il souhaité ?
- **Non vérifié** : écran de caisse non exécuté pour cette lecture, formule « Arrêtée la présente facture » et montant en lettres à valider sur un modèle de facture de la clinique.
