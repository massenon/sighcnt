/// LES TEXTES DU MOBILE ET DE SA TRANSCRIPTION, AVEC LEUR SOURCE (E1558).
///
/// Chaque code de refus et chaque phrase que le téléphone ou le poste dit au sujet d'une prescription est rapproché de la formulation de la maquette
/// quand elle existe (EXTRAITE, pas devinée : simulateur `prototype_html/mobile/`, moteur `parcours.js`, console `modules/mere.js`). Ce qui n'a AUCUNE source
/// est marqué `aValider` : l'écran le dit (« Texte proposé, à valider. ») et la Direction le valide d'un coup sur
/// `docs/architecture/TEXTES-A-VALIDER-MOBILE.md`, dont le test `mob_transcription_test.dart` vérifie qu'il liste exactement ces codes.
library;

/// Un texte : [code] (ou clé), [ou] (où il s'affiche), [texte] (tel qu'il est écrit, `…` pour les parties calculées), [source] (le fichier de la maquette
/// qui le porte, ou `null` : aucune source), [partielle] (une partie seulement vient de la source), [aValider] (la Direction doit le valider).
typedef MobTexte = ({String code, String ou, String texte, String? source, bool partielle, bool aValider});

const List<MobTexte> mobTextes = [
  (code: 'SAISIE_INVALIDE', ou: 'téléphone, champ d’un formulaire', texte: '… est obligatoire. / … doit être un nombre. / … : valeur improbable (a à b).', source: 'mobile/mobile.js (valider)', partielle: false, aValider: false),
  (code: 'SAISIE_INVALIDE/quantite', ou: 'téléphone, prescription', texte: 'La quantité est obligatoire. / La quantité doit être un entier d’au moins 1.', source: null, partielle: false, aValider: true),
  (code: 'SANS_NOTE', ou: 'téléphone, prescription', texte: 'Aucune note de consultation du jour pour ce patient : la prescription se fait après l’enregistrement de la fiche (dossier, fiche, prescription).', source: 'mobile/ecrans.js (« la prescription se fait après l’enregistrement de la fiche »)', partielle: true, aValider: true),
  (code: 'FONCTION_NON_HABILITEE', ou: 'téléphone, mère, poste', texte: '… n’est pas habilité à prescrire « … ».', source: 'assets/js/parcours.js (prescrireSoins : « X n’est pas habilité à prescrire. »)', partielle: true, aValider: false),
  (code: 'ECRAN_FERME_AU_PROFIL', ou: 'téléphone, prescription', texte: 'Écran fermé au profil « … ». Ce profil ne couvre pas cette fonction ; la clinique le refuserait aussi côté serveur.', source: 'mobile/mobile.js (écran fermé au profil)', partielle: false, aValider: false),
  (code: 'LOT_EXPIRE', ou: 'téléphone, toute écriture', texte: 'Le lot de la tournée a expiré le … à …. Passé ce délai, les dossiers s’effacent du téléphone, sauf ce qui n’est pas encore parti.', source: 'mobile/ecrans.js (écran Lot de tournée)', partielle: true, aValider: false),
  (code: 'PATIENT_HORS_LOT', ou: 'téléphone', texte: 'Ce patient n’est pas dans le lot de ce téléphone.', source: null, partielle: false, aValider: true),
  (code: 'ACTEUR_INCONNU', ou: 'téléphone, toute écriture', texte: 'Aucune action anonyme : le nom de l’agent n’est pas renseigné sur ce téléphone (RG-12).', source: 'CLAUDE.md (RG-12, aucune action anonyme)', partielle: true, aValider: false),
  (code: 'NATURE_NON_PORTEE', ou: 'téléphone et poste', texte: 'Le mobile ne prescrit pas « … ».', source: null, partielle: false, aValider: true),
  (code: 'EXAMEN_INCONNU', ou: 'téléphone et poste', texte: 'Examen hors catalogue du mobile : … / Examen sans correspondance au catalogue du laboratoire : ….', source: null, partielle: false, aValider: true),
  (code: 'PRODUIT_INCONNU', ou: 'téléphone et poste', texte: 'Médicament absent du catalogue du lot / de la clinique : « … ».', source: null, partielle: false, aValider: true),
  (code: 'STOCK_INSUFFISANT', ou: 'téléphone et poste', texte: 'Stock insuffisant pour « … » : disponible : N ; demandé : M (RG-03). À faire : Corriger la quantité ou demander un transfert du gros.', source: 'assets/js/modules/mere.js (refus STOCK_INSUFFISANT : « Stock disponible : 4 ; demandé : 6 (RG-03). »)', partielle: true, aValider: false),
  (code: 'QUANTITE_INVALIDE', ou: 'poste, transcription', texte: 'Quantité invalide pour « … » : un entier d’au moins 1 est attendu.', source: null, partielle: false, aValider: true),
  (code: 'ORDONNANCE_VIDE', ou: 'poste, transcription', texte: 'L’ordonnance ne porte aucune ligne. / La demande ne porte aucun examen.', source: 'assets/js/modules/m2-consultations.js (« Une ordonnance doit porter au moins un médicament, une analyse ou un acte. »)', partielle: true, aValider: true),
  (code: 'PATIENT_INTROUVABLE', ou: 'poste, transcription', texte: 'Le dossier « … » n’existe pas à la clinique : la prescription ne peut pas être facturée.', source: 'assets/js/parcours.js (« Patient introuvable : … »)', partielle: true, aValider: true),
  (code: 'droit_refuse', ou: 'mère, collection hors profil', texte: 'Le profil « … » ne couvre pas la collection ….', source: 'assets/js/modules/mere.js (refus PROFIL_NON_COUVERT : « Le profil « réception de secours » ne couvre pas la caisse. »)', partielle: true, aValider: false),
  (code: 'patient_hors_lot', ou: 'mère', texte: 'Ce patient n’est pas dans le lot de ce téléphone.', source: null, partielle: false, aValider: true),
  (code: 'fonction_falsifiee', ou: 'mère', texte: 'Le téléphone déclare « … » mais la clinique l’a appairé comme « … » : la fonction est fixée à l’appairage et ne se change pas depuis le téléphone.', source: null, partielle: false, aValider: true),
  (code: 'fonction_non_fixee', ou: 'mère', texte: 'Cet appareil a été appairé avant que la clinique fixe la fonction du soignant : la mère ne peut pas vérifier son habilitation.', source: null, partielle: false, aValider: true),
  (code: 'profil_requis', ou: 'console de la mère, code d’appairage', texte: 'Choisir le profil du téléphone : soignant ou réception de secours.', source: null, partielle: false, aValider: true),
  (code: 'fonction_inconnue', ou: 'console de la mère, code d’appairage', texte: 'Fonction « … » inconnue : choisir parmi ….', source: null, partielle: false, aValider: true),
  (code: 'fonction_non_applicable', ou: 'console de la mère, code d’appairage', texte: 'La réception de secours n’a pas de fonction de soignant.', source: null, partielle: false, aValider: true),
  (code: 'appareil_deja_appaire', ou: 'relais, appairage', texte: 'Cet appareil est déjà appairé : pour changer sa fonction, le révoquer puis l’appairer avec un nouveau code.', source: null, partielle: false, aValider: true),
  (code: 'texte/envoi-prescription', ou: 'téléphone, écran de prescription', texte: 'La prescription part à la clinique par le relais. L’ordonnance et la facture de la caisse sont générées quand le poste de la clinique la transcrit : le dossier vous le confirme, ou vous dit pourquoi elle est refusée.', source: 'mobile/ecrans.js (« Prescrire génère l’ordonnance et la facture de la caisse… »)', partielle: true, aValider: true),
  (code: 'texte/transcrite', ou: 'téléphone, dossier', texte: 'Transcrite par la clinique : ordonnance …, facture …. + la phrase du simulateur : Prescrire génère l’ordonnance et la facture de la caisse. Le patient règle à la caisse de la clinique ; la délivrance n’a lieu qu’après paiement (RG-03).', source: 'mobile/ecrans.js (écran Prescription)', partielle: true, aValider: true),
  (code: 'texte/attente-transcription', ou: 'téléphone, dossier', texte: 'En attente de transcription par la clinique.', source: null, partielle: false, aValider: true),
  (code: 'texte/refusee', ou: 'téléphone, dossier', texte: 'Refusée par la clinique : … À faire : … (code).', source: null, partielle: false, aValider: true),
  (code: 'texte/attente-clinique', ou: 'téléphone, appairage', texte: 'Téléphone appairé. En attente de la clinique : elle vous attribue votre profil et votre fonction dès qu’elle est joignable.', source: null, partielle: false, aValider: true),
  (code: 'texte/pieces-refusees', ou: 'poste, écran des ordonnances', texte: 'N prescription(s) reçue(s) d’un téléphone n’ont pas pu être transcrites : … À faire : … […].', source: null, partielle: false, aValider: true),
];

/// Les codes dont le texte n'a pas de source complète et attend la validation de la Direction (affichés « Texte proposé, à valider. »).
final Set<String> mobCodesAValider = {for (final t in mobTextes) if (t.aValider) t.code};

/// Le refus de ce [code] porte-t-il un texte à valider ? (Les codes de la mère, en minuscules, et ceux du téléphone, en majuscules, sont dans la même liste.)
bool mobRefusAValider(String code) => mobCodesAValider.contains(code);

/// La mention affichée sous un texte proposé.
const mobMentionAValider = 'Texte proposé, à valider.';
