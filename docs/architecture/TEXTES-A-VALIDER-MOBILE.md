# Textes du mobile et de sa transcription : à valider par la Direction

Plage d'écarts E1600 à E1640 (01/11/2026). Chaque code de refus et chaque phrase que le téléphone d'un soignant, la mère ou le poste disent au sujet
d'une prescription est rapproché de la formulation de la maquette quand elle existe (EXTRAITE : simulateur `prototype_html/mobile/`, moteur
`assets/js/parcours.js`, console `assets/js/modules/mere.js`). Ce qui n'a pas de source est marqué « à valider » ici ET à l'écran (« Texte proposé, à
valider. »). La Direction peut valider cette table d'un coup : la valider revient à retirer la mention à l'écran (`aValider: false` dans
`packages/domaine/lib/src/mobile/mob_textes.dart`, qui est la source unique de cette table, vérifiée par `mob_transcription_test.dart`).

Aucune règle clinique n'est inventée ici : les textes proposés décrivent un refus de gestion (périmètre du lot, catalogue, stock, appairage) ou un
état d'avancement. La seule règle sans source est la durée de la note exigée avant de prescrire (E1557, « du jour »), proposée à valider.

| Code | Où | Texte | Source | Statut |
|---|---|---|---|---|
| `SAISIE_INVALIDE` | téléphone, champ d’un formulaire | … est obligatoire. / … doit être un nombre. / … : valeur improbable (a à b). | mobile/mobile.js (valider) | repris de la maquette |
| `SAISIE_INVALIDE/quantite` | téléphone, prescription | La quantité est obligatoire. / La quantité doit être un entier d’au moins 1. | aucune source | à valider |
| `SANS_NOTE` | téléphone, prescription | Aucune note de consultation du jour pour ce patient : la prescription se fait après l’enregistrement de la fiche (dossier, fiche, prescription). | mobile/ecrans.js (« la prescription se fait après l’enregistrement de la fiche ») (partielle) | à valider |
| `FONCTION_NON_HABILITEE` | téléphone, mère, poste | … n’est pas habilité à prescrire « … ». | assets/js/parcours.js (prescrireSoins : « X n’est pas habilité à prescrire. ») (partielle) | repris de la maquette |
| `ECRAN_FERME_AU_PROFIL` | téléphone, prescription | Écran fermé au profil « … ». Ce profil ne couvre pas cette fonction ; la clinique le refuserait aussi côté serveur. | mobile/mobile.js (écran fermé au profil) | repris de la maquette |
| `LOT_EXPIRE` | téléphone, toute écriture | Le lot de la tournée a expiré le … à …. Passé ce délai, les dossiers s’effacent du téléphone, sauf ce qui n’est pas encore parti. | mobile/ecrans.js (écran Lot de tournée) (partielle) | repris de la maquette |
| `PATIENT_HORS_LOT` | téléphone | Ce patient n’est pas dans le lot de ce téléphone. | aucune source | à valider |
| `ACTEUR_INCONNU` | téléphone, toute écriture | Aucune action anonyme : le nom de l’agent n’est pas renseigné sur ce téléphone (RG-12). | CLAUDE.md (RG-12, aucune action anonyme) (partielle) | repris de la maquette |
| `NATURE_NON_PORTEE` | téléphone et poste | Le mobile ne prescrit pas « … ». | aucune source | à valider |
| `EXAMEN_INCONNU` | téléphone et poste | Examen hors catalogue du mobile : … / Examen sans correspondance au catalogue du laboratoire : …. | aucune source | à valider |
| `PRODUIT_INCONNU` | téléphone et poste | Médicament absent du catalogue du lot / de la clinique : « … ». | aucune source | à valider |
| `STOCK_INSUFFISANT` | téléphone et poste | Stock insuffisant pour « … » : disponible : N ; demandé : M (RG-03). À faire : Corriger la quantité ou demander un transfert du gros. | assets/js/modules/mere.js (refus STOCK_INSUFFISANT : « Stock disponible : 4 ; demandé : 6 (RG-03). ») (partielle) | repris de la maquette |
| `QUANTITE_INVALIDE` | poste, transcription | Quantité invalide pour « … » : un entier d’au moins 1 est attendu. | aucune source | à valider |
| `ORDONNANCE_VIDE` | poste, transcription | L’ordonnance ne porte aucune ligne. / La demande ne porte aucun examen. | assets/js/modules/m2-consultations.js (« Une ordonnance doit porter au moins un médicament, une analyse ou un acte. ») (partielle) | à valider |
| `PATIENT_INTROUVABLE` | poste, transcription | Le dossier « … » n’existe pas à la clinique : la prescription ne peut pas être facturée. | assets/js/parcours.js (« Patient introuvable : … ») (partielle) | à valider |
| `droit_refuse` | mère, collection hors profil | Le profil « … » ne couvre pas la collection …. | assets/js/modules/mere.js (refus PROFIL_NON_COUVERT : « Le profil « réception de secours » ne couvre pas la caisse. ») (partielle) | repris de la maquette |
| `patient_hors_lot` | mère | Ce patient n’est pas dans le lot de ce téléphone. | aucune source | à valider |
| `fonction_falsifiee` | mère | Le téléphone déclare « … » mais la clinique l’a appairé comme « … » : la fonction est fixée à l’appairage et ne se change pas depuis le téléphone. | aucune source | à valider |
| `fonction_non_fixee` | mère | Cet appareil a été appairé avant que la clinique fixe la fonction du soignant : la mère ne peut pas vérifier son habilitation. | aucune source | à valider |
| `profil_requis` | console de la mère, code d’appairage | Choisir le profil du téléphone : soignant ou réception de secours. | aucune source | à valider |
| `fonction_inconnue` | console de la mère, code d’appairage | Fonction « … » inconnue : choisir parmi …. | aucune source | à valider |
| `fonction_non_applicable` | console de la mère, code d’appairage | La réception de secours n’a pas de fonction de soignant. | aucune source | à valider |
| `appareil_deja_appaire` | relais, appairage | Cet appareil est déjà appairé : pour changer sa fonction, le révoquer puis l’appairer avec un nouveau code. | aucune source | à valider |
| `texte/envoi-prescription` | téléphone, écran de prescription | La prescription part à la clinique par le relais. L’ordonnance et la facture de la caisse sont générées quand le poste de la clinique la transcrit : le dossier vous le confirme, ou vous dit pourquoi elle est refusée. | mobile/ecrans.js (« Prescrire génère l’ordonnance et la facture de la caisse… ») (partielle) | à valider |
| `texte/transcrite` | téléphone, dossier | Transcrite par la clinique : ordonnance …, facture …. + la phrase du simulateur : Prescrire génère l’ordonnance et la facture de la caisse. Le patient règle à la caisse de la clinique ; la délivrance n’a lieu qu’après paiement (RG-03). | mobile/ecrans.js (écran Prescription) (partielle) | à valider |
| `texte/attente-transcription` | téléphone, dossier | En attente de transcription par la clinique. | aucune source | à valider |
| `texte/refusee` | téléphone, dossier | Refusée par la clinique : … À faire : … (code). | aucune source | à valider |
| `texte/attente-clinique` | téléphone, appairage | Téléphone appairé. En attente de la clinique : elle vous attribue votre profil et votre fonction dès qu’elle est joignable. | aucune source | à valider |
| `texte/pieces-refusees` | poste, écran des ordonnances | N prescription(s) reçue(s) d’un téléphone n’ont pas pu être transcrites : … À faire : … […]. | aucune source | à valider |

## Règles proposées (sans source), à valider avec les textes

| Réf. | Règle | Statut |
|---|---|---|
| E1557 | Une note de consultation de CE patient, écrite le jour même (jour local), est exigée avant de prescrire (refus `SANS_NOTE`). Le simulateur dit « la prescription se fait après l'enregistrement de la fiche », sans durée. | à valider |
| E1600 | La fonction du soignant est fixée par le code d'appairage de la console de la mère et relue par la mère à chaque dépôt ; un appareil ne change de fonction qu'avec un nouvel appairage (nouvel appareil). | décision de la Direction du 01/11/2026 |
| E1601 | Le catalogue des produits (prix d'achat, stock du jour) part avec le lot d'un soignant habilité à prescrire des médicaments, jamais à une infirmière ni à une réception. | à valider |
| E1602 | La quantité d'une ligne ne dépasse pas le stock de la pharmacie (détail) connu du lot au téléphone, ni le stock du jour au poste (RG-03) ; la maquette (`PR.prescrire`) ne refuse pas à la prescription, elle refuse à la délivrance. | à valider |
| E1603 | Correspondance entre les six examens du simulateur et le catalogue du laboratoire (NFS, glycémie, GE-DP, CRP, TBG sérique, créatinine) ; le TDR du paludisme n'a pas de ligne propre au catalogue. | à valider par le biologiste |
