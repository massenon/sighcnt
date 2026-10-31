/// Règles de la console du poste mère (lot MERE c) : service, base, réseau, planificateur, notifications serveur, assistant de première mise
/// en service, mises à jour et compatibilité, import de migration. Dart pur, un seul exemplaire pour la mère et ses tests.
///
/// DOCTRINE : une valeur sans source n'est pas affichée comme une valeur. [MrcValeur] porte soit la valeur, soit le MOTIF pour lequel elle n'est pas
/// disponible ; « non disponible » n'est jamais un zéro et jamais une absence silencieuse.
library;

/// Les deux rôles qui administrent la mère (DAF, administrateur système) : le groupe « Poste mère » leur est réservé.
const mrcRolesAdmin = {'admin', 'da'};

/// Une valeur lue à une source, ou le motif pour lequel elle ne l'est pas.
class MrcValeur<T> {
  const MrcValeur._(this.valeur, this.motif);

  /// La valeur est fournie par la source.
  const MrcValeur.de(T v) : this._(v, null);

  /// La source ne la fournit pas : [motif] dit pourquoi et ce qui manque.
  const MrcValeur.indisponible(String motif) : this._(null, motif);

  final T? valeur;
  final String? motif;
  bool get disponible => motif == null;

  /// « non disponible » ou la valeur mise en forme.
  String texte([String Function(T)? forme]) =>
      disponible ? (forme != null ? forme(valeur as T) : '$valeur') : 'non disponible';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Assistant de première mise en service (M-20)
// ---------------------------------------------------------------------------------------------------------------------------------------------

enum MrcEtatEtape {
  /// Constaté fait (par une lecture de l'état réel, ou par une confirmation nommée consignée).
  fait,

  /// Constaté pas fait.
  aFaire,

  /// Un prérequis n'est pas fait : l'étape ne s'ouvre pas.
  bloquee,

  /// Aucune source ne permet de dire si elle est faite : « non vérifié » ne rassure jamais.
  nonVerifiee,
}

/// Une étape du parcours. [prealables] : identifiants d'étapes à faire avant. [phrase] : la confirmation NOMMÉE à saisir avant le geste
/// (étapes qui engagent le serveur) ; `null` quand l'étape n'engage rien d'irréversible.
class MrcEtape {
  const MrcEtape(this.numero, this.id, this.libelle, this.contenu, {this.prealables = const [], this.phrase});
  final int numero;
  final String id;
  final String libelle;
  final String contenu;
  final List<String> prealables;
  final String? phrase;
}

/// Les cinq étapes de M-20, dans l'ordre du document `MODULES-COMPLEMENTAIRES-MERE.md` : identité de la clinique, premier administrateur, jeu de départ
/// (essentiels ou démonstration), activation du mode mère, premier appairage. Un appareil ne s'appaire que si la mère est active.
const mrcEtapes = <MrcEtape>[
  MrcEtape(1, 'identite', 'Identité de la clinique', 'Dénomination, en-tête légal et devise imprimés sur chaque pièce.'),
  MrcEtape(2, 'administrateur', 'Premier administrateur', 'Un compte administrateur muni d’un mot de passe défini, changé à la première connexion.'),
  MrcEtape(3, 'jeu_depart', 'Jeu de départ', 'Garder le jeu de démonstration, ou ne conserver que les essentiels (référentiels, comptes, droits, tarifs).',
      phrase: 'VIDER L’ACTIVITÉ'),
  MrcEtape(4, 'activation', 'Activation du mode mère', 'Démarre le service de synchronisation de ce serveur et déclare la mère au relais.'),
  MrcEtape(5, 'appairage', 'Premier appairage', 'Générer le code d’appairage d’un premier poste ou mobile.', prealables: ['activation']),
];

MrcEtape? mrcEtape(String id) {
  for (final e in mrcEtapes) {
    if (e.id == id) return e;
  }
  return null;
}

/// États des étapes à partir des CONSTATS : `true` fait, `false` pas fait, absent ou `null` non vérifiable. Un constat « fait » prime ; sinon un prérequis
/// non fait BLOQUE l'étape. Le parcours est reprenable par construction : l'état se relit toujours sur le constat, il ne dépend d'aucune progression mémorisée.
Map<String, MrcEtatEtape> mrcEtatsEtapes(Map<String, bool?> constats) {
  final fait = {for (final e in mrcEtapes) e.id: constats[e.id] == true};
  return {
    for (final e in mrcEtapes)
      e.id: fait[e.id]!
          ? MrcEtatEtape.fait
          : (e.prealables.any((p) => fait[p] != true)
              ? MrcEtatEtape.bloquee
              : (constats[e.id] == false ? MrcEtatEtape.aFaire : MrcEtatEtape.nonVerifiee)),
  };
}

/// Peut-on ouvrir l'étape ? Seule une étape bloquée par un prérequis ne s'ouvre pas.
bool mrcEtapeOuvrable(String id, Map<String, MrcEtatEtape> etats) => etats[id] != MrcEtatEtape.bloquee;

/// Prérequis non faits d'une étape, nommés pour le refus.
List<MrcEtape> mrcPrealablesManquants(String id, Map<String, MrcEtatEtape> etats) {
  final e = mrcEtape(id);
  if (e == null) return const [];
  return [
    for (final p in e.prealables)
      if (etats[p] != MrcEtatEtape.fait) mrcEtape(p)!
  ];
}

/// « 2 sur 5 » : nombre d'étapes constatées faites.
({int faites, int total}) mrcProgression(Map<String, MrcEtatEtape> etats) =>
    (faites: etats.values.where((x) => x == MrcEtatEtape.fait).length, total: mrcEtapes.length);

/// La confirmation nommée est-elle exacte ? Comparaison insensible à la casse et aux espaces superflus, jamais à moitié.
bool mrcConfirmationExacte(MrcEtape e, String saisie) => e.phrase == null || mrcPhraseExacte(e.phrase!, saisie);

/// La phrase saisie est-elle exactement la phrase attendue ? (casse et espaces superflus ignorés, rien d'autre.)
bool mrcPhraseExacte(String attendue, String saisie) {
  String n(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  return n(saisie) == n(attendue);
}

String mrcLibelleEtat(MrcEtatEtape e) => switch (e) {
      MrcEtatEtape.fait => 'Fait',
      MrcEtatEtape.aFaire => 'À faire',
      MrcEtatEtape.bloquee => 'Bloquée',
      MrcEtatEtape.nonVerifiee => 'Non vérifié',
    };

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Mises à jour et compatibilité (M-21)
// ---------------------------------------------------------------------------------------------------------------------------------------------

enum MrcCompat { aJour, tropAncien, plusRecent, inconnu }

/// Compatibilité d'un appareil avec la mère, sur la version de SCHÉMA (spec §14 : `426 schema_incompatible`, « version de schéma trop ancienne,
/// demande la mise à jour, n'envoie rien »). Un schéma plus ancien que celui de la mère est refusé ; égal, à jour ; plus récent, signalé sans être refusé (la
/// spécification ne prévoit de refus que pour un poste trop ancien) ; absent, INCONNU (le moteur ne le rassure pas).
MrcCompat mrcCompatibilite({required int? schemaMere, required int? schemaAppareil}) {
  if (schemaMere == null || schemaAppareil == null) return MrcCompat.inconnu;
  if (schemaAppareil < schemaMere) return MrcCompat.tropAncien;
  if (schemaAppareil > schemaMere) return MrcCompat.plusRecent;
  return MrcCompat.aJour;
}

String mrcLibelleCompat(MrcCompat c) => switch (c) {
      MrcCompat.aJour => 'À jour',
      MrcCompat.tropAncien => 'Refusé : schéma trop ancien',
      MrcCompat.plusRecent => 'Plus récent que la mère',
      MrcCompat.inconnu => 'Inconnu',
    };

/// Le refus NOMMÉ d'un poste trop ancien : code du protocole, appareil, versions, geste.
String mrcMotifRefusSchema(String appareil, int schemaAppareil, int schemaMere) =>
    'schema_incompatible : « $appareil » est au schéma $schemaAppareil, la mère au schéma $schemaMere. Le poste doit être mis à jour ; rien n’est envoyé tant qu’il ne l’est pas.';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Planificateur et notifications serveur (M-18, M-19)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Taille maximale du registre des exécutions (vague 69 : « registre borné à 500 »).
const mrcRegistreMax = 500;

/// Garde les [max] exécutions les plus récentes (la liste est ordonnée de la plus récente à la plus ancienne). Rien d'autre n'est jeté.
List<T> mrcBornerRegistre<T>(List<T> executions, {int max = mrcRegistreMax}) =>
    executions.length <= max ? List.of(executions) : executions.sublist(0, max);

/// Priorité d'une alerte serveur d'après l'état du contrôle de supervision qui l'a produite (le moteur nomme `alerte`, `attention`, `inconnu`).
String mrcPrioriteAlerte(String etat) => switch (etat) {
      'alerte' => 'Critique',
      'attention' => 'À surveiller',
      _ => 'Inconnue',
    };

/// Une alerte est OUVERTE tant que son contrôle n'est pas `ok` ; elle se résout quand la cause cesse (le contrôle est recalculé à chaque lecture).
/// `inconnu` est listé mais ne compte pas comme ouverte : il n'affirme rien.
bool mrcAlerteOuverte(String etat) => etat == 'alerte' || etat == 'attention';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Réseau local (M-17)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Seuil au-delà duquel un poste n'est plus compté joignable : celui de la supervision du moteur (`Seuils.posteSilenceAttentionMin`, 30 minutes).
const mrcSilencePosteMin = 30;

/// Un poste est « joignable » s'il a pris contact dans la fenêtre. C'est une lecture du DERNIER CONTACT, pas un test réseau : l'écran le dit.
bool mrcPosteJoignable(DateTime? dernierContact, DateTime maintenant, {int silenceMin = mrcSilencePosteMin}) =>
    dernierContact != null && maintenant.difference(dernierContact).inMinutes <= silenceMin;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Import de migration (M-22)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le profil d'un lot importable : son identifiant, la collection cible, les colonnes attendues (dans l'ordre), les colonnes facultatives.
class MrcProfilImport {
  const MrcProfilImport(this.id, this.libelle, this.collection, this.source, this.colonnes, {this.facultatives = const []});
  final String id;
  final String libelle;
  final String collection;
  final String source;
  final List<String> colonnes;
  final List<String> facultatives;
}

/// Inventaire SAGE « Grand Stock » : une ligne par article, `[référence, désignation, quantité, P.R. unitaire, catégorie]` (le P.R. unitaire est le coût
/// moyen pondéré de SAGE ; zéro signale un article non valorisé dans le document source).
const mrcProfilSage = MrcProfilImport(
  'sage-inventaire',
  'Inventaire SAGE (Grand Stock)',
  'produits',
  'SAGE_100_GESTION_COMMERCIALE_15.01',
  ['reference', 'designation', 'quantite', 'pr_unitaire', 'categorie'],
  facultatives: ['unite'],
);

const mrcProfilsImport = <MrcProfilImport>[mrcProfilSage];

/// Les sept familles d'articles de l'inventaire SAGE (D.FAMILLES_ARTICLES).
const mrcCategoriesSage = {'medicament', 'conso_medical', 'reactif', 'conso_labo', 'petit_materiel', 'entretien', 'fourniture'};

/// Une ligne refusée : son numéro dans le FICHIER (l'en-tête est la ligne 1), la colonne, la valeur lue et le motif.
class MrcRefusLigne {
  const MrcRefusLigne(this.ligne, this.colonne, this.valeur, this.motif);
  final int ligne;
  final String colonne;
  final String valeur;
  final String motif;
  @override
  String toString() => 'Ligne $ligne, colonne « $colonne »${valeur.isEmpty ? '' : ' (valeur « $valeur »)'} : $motif';
}

/// Résultat de l'analyse d'un fichier : TOUT ou RIEN. S'il y a un refus, [lignes] est vide et rien ne doit être écrit.
class MrcAnalyse {
  const MrcAnalyse(this.profil, this.lignes, this.refus, {this.nbRefusees = 0});
  final MrcProfilImport profil;
  final List<Map<String, Object?>> lignes;

  /// Les refus NOMMÉS (au plus `maxRefus`) ; [nbRefusees] est le nombre TOTAL de lignes fautives, non plafonné.
  final List<MrcRefusLigne> refus;
  final int nbRefusees;
  bool get accepte => refus.isEmpty && lignes.isNotEmpty;
}

/// Découpe un texte CSV (séparateur point-virgule, guillemets doubles pour un champ contenant `;`, un guillemet ou un saut de ligne).
List<List<String>> mrcLireCsv(String texte) {
  final lignes = <List<String>>[];
  var champ = StringBuffer();
  var ligne = <String>[];
  var guillemets = false;
  var i = 0;
  final t = texte.startsWith('﻿') ? texte.substring(1) : texte;
  void finChamp() {
    ligne.add(champ.toString());
    champ = StringBuffer();
  }

  void finLigne() {
    finChamp();
    lignes.add(ligne);
    ligne = <String>[];
  }

  while (i < t.length) {
    final c = t[i];
    if (guillemets) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          guillemets = false;
        }
      } else {
        champ.write(c);
      }
    } else if (c == '"' && champ.isEmpty) {
      guillemets = true;
    } else if (c == ';') {
      finChamp();
    } else if (c == '\r') {
      // ignoré : \r\n et \n sont équivalents
    } else if (c == '\n') {
      finLigne();
    } else {
      champ.write(c);
    }
    i++;
  }
  if (champ.isNotEmpty || ligne.isNotEmpty) finLigne();
  return lignes;
}

num? _nombre(String s) => num.tryParse(s.trim().replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));

/// Analyse un fichier CSV contre un profil. Le premier refus est nommé avec sa ligne ; l'analyse continue pour rendre TOUS les refus (jusqu'à [maxRefus]),
/// afin que la correction se fasse en un passage. [codesExistants] : codes déjà présents dans la collection cible, jamais écrasés.
MrcAnalyse mrcAnalyserImport(String texte, MrcProfilImport profil, {Set<String> codesExistants = const {}, int maxRefus = 20}) {
  final table = mrcLireCsv(texte).where((l) => !(l.length == 1 && l.first.trim().isEmpty)).toList();
  if (table.isEmpty) return MrcAnalyse(profil, const [], [const MrcRefusLigne(1, '(fichier)', '', 'fichier vide : aucune ligne à importer')]);
  final entete = table.first.map((c) => c.trim().toLowerCase()).toList();
  final refus = <MrcRefusLigne>[];
  for (final c in profil.colonnes) {
    if (!entete.contains(c)) refus.add(MrcRefusLigne(1, c, '', 'colonne obligatoire absente de l’en-tête (attendu : ${profil.colonnes.join('; ')})'));
  }
  for (final c in entete) {
    if (!profil.colonnes.contains(c) && !profil.facultatives.contains(c)) {
      refus.add(MrcRefusLigne(1, c, '', 'colonne inconnue pour le profil « ${profil.libelle} »'));
    }
  }
  if (refus.isNotEmpty) return MrcAnalyse(profil, const [], refus.take(maxRefus).toList(), nbRefusees: table.length - 1);
  if (table.length == 1) {
    return MrcAnalyse(profil, const [], [const MrcRefusLigne(1, '(fichier)', '', 'aucune ligne de données sous l’en-tête')]);
  }
  final idx = {for (var i = 0; i < entete.length; i++) entete[i]: i};
  final vues = <String, int>{};
  final lignes = <Map<String, Object?>>[];
  final fautives = <int>{};
  for (var n = 1; n < table.length; n++) {
    final fichierLigne = n + 1;
    final brute = table[n];
    String v(String col) => idx.containsKey(col) && idx[col]! < brute.length ? brute[idx[col]!].trim() : '';
    void refuser(String col, String motif) => refus.add(MrcRefusLigne(fichierLigne, col, v(col), motif));
    final avant = refus.length;
    if (brute.length != entete.length) {
      refus.add(MrcRefusLigne(fichierLigne, '(ligne)', '', '${brute.length} champ(s) au lieu de ${entete.length}'));
      fautives.add(fichierLigne);
      continue;
    }
    final ref = v('reference');
    if (ref.isEmpty) {
      refuser('reference', 'référence vide');
    } else if (vues.containsKey(ref)) {
      refuser('reference', 'référence déjà vue à la ligne ${vues[ref]}');
    } else if (codesExistants.contains(ref)) {
      refuser('reference', 'référence déjà présente au catalogue : rien n’est écrasé');
    } else {
      vues[ref] = fichierLigne;
    }
    if (v('designation').isEmpty) refuser('designation', 'désignation vide');
    final q = _nombre(v('quantite'));
    if (q == null) {
      refuser('quantite', 'quantité non numérique');
    } else if (q < 0) {
      refuser('quantite', 'quantité négative : le stock ne peut jamais devenir négatif (RG-03)');
    } else if (q != q.roundToDouble()) {
      refuser('quantite', 'quantité non entière');
    }
    final pr = _nombre(v('pr_unitaire'));
    if (pr == null) {
      refuser('pr_unitaire', 'prix de revient non numérique (0 pour un article non valorisé)');
    } else if (pr < 0) {
      refuser('pr_unitaire', 'prix de revient négatif');
    }
    if (!mrcCategoriesSage.contains(v('categorie'))) {
      refuser('categorie', 'catégorie inconnue (attendu : ${(mrcCategoriesSage.toList()..sort()).join(', ')})');
    }
    if (refus.length != avant) fautives.add(fichierLigne);
    if (refus.length == avant) {
      lignes.add({
        'reference': ref,
        'designation': v('designation'),
        'quantite': q!.toInt(),
        'pr_unitaire': pr!,
        'categorie': v('categorie'),
        if (v('unite').isNotEmpty) 'unite': v('unite'),
        'ligneFichier': fichierLigne,
      });
    }
  }
  if (refus.isNotEmpty) return MrcAnalyse(profil, const [], refus.take(maxRefus).toList(), nbRefusees: fautives.length);
  return MrcAnalyse(profil, lignes, const []);
}

/// Référence d'un lot : `IMPORT-<PROFIL>-<AAAAMMJJ>`, suffixée `-2`, `-3`… si elle existe déjà.
String mrcReferenceLot(MrcProfilImport profil, DateTime date, Iterable<String> existantes) {
  String d(int n, int l) => n.toString().padLeft(l, '0');
  final base = 'IMPORT-${profil.id.split('-').first.toUpperCase()}-${d(date.year, 4)}${d(date.month, 2)}${d(date.day, 2)}';
  final pris = existantes.toSet();
  if (!pris.contains(base)) return base;
  for (var k = 2;; k++) {
    if (!pris.contains('$base-$k')) return '$base-$k';
  }
}

/// Les fiches `produits` d'un lot accepté. Chacune porte `source`, `lotImport` (import_batch), `dateImport` et `validePar` (validated_by) : un article
/// importé se retrouve toujours jusqu'à son document. Le prix de vente est le prix d'achat (RG-02, pas de marge) ; le seuil d'alerte n'est PAS fixé
/// (un seuil absent n'est pas un seuil de zéro) ; un article au P.R. nul est marqué non valorisé (`valoriseSage: false`), jamais valorisé d'office.
List<Map<String, Object?>> mrcFichesProduits(MrcAnalyse a, {required String lot, required String date, required String validePar}) {
  return [
    for (final l in a.lignes)
      {
        'code': l['reference'],
        'designation': l['designation'],
        if (l['unite'] != null) 'unite': l['unite'],
        'categorie': l['categorie'],
        'prixAchat': l['pr_unitaire'],
        'prixVente': l['pr_unitaire'],
        'cump': l['pr_unitaire'],
        'stockGros': l['quantite'],
        'stockDetail': 0,
        'stock': l['quantite'],
        'quantiteImportee': l['quantite'],
        'valoriseSage': (l['pr_unitaire'] as num) > 0,
        'source': a.profil.source,
        'lotImport': lot,
        'dateImport': date,
        'validePar': validePar,
        'statut': 'actif',
      }
  ];
}
