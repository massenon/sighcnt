// LA SORTIE DES TABLEAUX (lot EXP, 16/11/2026) : port du moteur de sortie de la maquette (`prototype_html/assets/js/ui.js`, « SORTIE DES TABLEAUX »).
//
// PRD `docs/prd/PRD-TABLEAUX-export-xlsx-et-impression-de-la-selection.md` ; réponses de la Direction du 15/11/2026 (`DECISIONS-A-VALIDER.md`, section AH, points
// 38 à 42) : le CSV reste à côté du .xlsx ; sortir est un geste réservé de la fiche RBAC par rôle (`exporter_donnees`, défaut : tout rôle qui lit l'écran) ; une
// limite de lignes par export est un réglage de clinique (refus nommé au-delà, JAMAIS de fichier tronqué) ; la sélection se garde d'une page à l'autre jusqu'à ce
// que l'agent la vide ; l'impression d'une sélection est un seul tableau.
//
// LES DROITS DE L'ÉCRAN S'APPLIQUENT PAR CONSTRUCTION : la sortie ne reçoit que les lignes que l'écran a construites pour ce profil et les colonnes visibles ; une
// cellule montrée autrement que sa valeur brute sort sous le TEXTE montré, jamais sous la valeur brute, sauf quand le texte montré EST la même valeur (un montant
// ou une date formatés), qui sort alors typée. Les vecteurs `test/vecteurs/tableaux_sortie.json` sont TIRÉS de l'écran réel de la maquette dans Chrome
// (`prototype_html/build/vecteurs-tableaux.js`).
library;

import '../format/format_fr.dart' as f;

/// Le geste réservé de la fiche RBAC (`N.GESTES`, `rbac.json`).
const String tabGesteSortie = 'exporter_donnees';

/// Le réglage de clinique : lignes au plus par export (maquette : `exportLimiteLignes` dans `_reglages`). Famille `securite` : jamais vers un téléphone.
const String tabCleLimiteLignes = 'securite.limiteLignesExport';

/// La valeur d'ATTENTE semée : mesurée le 16/11/2026 sur le jeu de démonstration (plus grande table : le planning, 1 394 lignes) ; premier millier qui la laisse
/// sortir en entier. Proposition à valider (section AK) : la Direction n'a fixé aucune valeur (point 40).
const int tabLimiteDefaut = 2000;
const int tabLimiteMin = 1, tabLimiteMax = 100000;

/// Les formats d'une sortie et le libellé de leur entrée au journal.
const Map<String, String> tabLibellesFormat = {
  'xlsx': 'Export d’un tableau (.xlsx)',
  'csv': 'Export d’un tableau (.csv)',
  'impression': 'Impression d’un tableau',
};

/// Les périmètres : lignes cochées, lignes filtrées (toutes pages), tout le tableau (« en masse »).
const String tabPerimetreSelection = 'selection', tabPerimetreFiltre = 'filtre', tabPerimetreTout = 'tout';

/// Les identifiants journalisés au plus par entrée (le journal garde 400 entrées) ; `referencesTotal` dit combien il y en avait.
const int tabReferencesMax = 50;

/// La limite en vigueur depuis la valeur lue en base : un entier de [tabLimiteMin] à [tabLimiteMax], sinon le défaut semé.
int tabLimiteLue(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null || !n.isFinite || n != n.truncate() || n < tabLimiteMin || n > tabLimiteMax) return tabLimiteDefaut;
  return n.toInt();
}

/// Un refus nommé : code, motif, geste de correction.
class RefusSortieTableau {
  const RefusSortieTableau(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif';
}

/// `C.num(v)` de la maquette pour un entier : espace fine insécable (U+202F) entre les milliers.
String _num(int n) => n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u202f');

String _numSigne(int n) => (n < 0 ? '-' : '') + _num(n);

/// Le contrôle AVANT tout travail, dans l'ordre de la maquette : format, droit, lignes, colonnes, limite. `null` : la sortie peut s'écrire.
RefusSortieTableau? tabControleSortie({
  required String format,
  required bool droit,
  required String libelleRole,
  required int lignes,
  required int colonnes,
  required int limite,
}) {
  if (!tabLibellesFormat.containsKey(format)) {
    return RefusSortieTableau('FORMAT_INCONNU', 'le format « $format » n’existe pas', 'Choisir Excel (.xlsx), CSV ou Impression.');
  }
  if (!droit) {
    return RefusSortieTableau('EXPORT_NON_AUTORISE', 'le profil « $libelleRole » ne détient pas le droit d’exporter ou d’imprimer les lignes d’un tableau',
        'Demander ce droit à l’administrateur : il se règle par rôle dans « Rôles & permissions », gestes réservés.');
  }
  if (lignes <= 0) return const RefusSortieTableau('EXPORT_VIDE', 'aucune ligne à sortir', 'Cocher des lignes, ou élargir la recherche et les filtres.');
  if (colonnes <= 0) return const RefusSortieTableau('EXPORT_SANS_COLONNE', 'aucune colonne affichée', 'Afficher au moins une colonne (bouton « Colonnes »).');
  if (lignes > limite) {
    return RefusSortieTableau(
        'EXPORT_AU_DELA_DE_LA_LIMITE',
        '${_numSigne(lignes)} lignes demandées, la limite réglée par la clinique est de ${_numSigne(limite)} lignes par export : aucun fichier tronqué n’est écrit',
        'Affiner la recherche ou les filtres, ou cocher moins de lignes ; la limite se relève dans la fenêtre d’export par un profil qui écrit dans la sécurité.');
  }
  return null;
}

/// Le contrôle d'un réglage de la limite (profil qui écrit dans la sécurité, entier borné, motif exigé). `null` : le réglage peut s'écrire.
RefusSortieTableau? tabControleReglageLimite({required bool peutRegler, required Object? lignes, required String? motif}) {
  if (!peutRegler) {
    return const RefusSortieTableau('REGLAGE_RESERVE', 'la limite de lignes par export se règle par un profil qui écrit dans la sécurité (module M14)', 'Demander le réglage à l’administrateur.');
  }
  final n = lignes is num ? lignes : num.tryParse('${lignes ?? ''}');
  if (n == null || !n.isFinite || n != n.truncate() || n < tabLimiteMin || n > tabLimiteMax) {
    return RefusSortieTableau('LIMITE_INVALIDE', 'la limite est un nombre entier de lignes, de $tabLimiteMin à ${_num(tabLimiteMax)}', 'Saisir un nombre entier de lignes.');
  }
  if ((motif ?? '').trim().isEmpty) return const RefusSortieTableau('MOTIF_REQUIS', 'un réglage de limite se motive', 'Saisir le motif du réglage.');
  return null;
}

// --- La valeur d'une cellule ---------------------------------------------------------------------------------------------------------------

/// Une cellule de sortie, sous la forme de la maquette : un `num`, `{'date': 'AAAA-MM-JJ'}`, `{'dateHeure': '…'}` ou un texte (`''` : vide).
typedef CelluleSortie = Object;

final RegExp _reDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _reDateHeure = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');

/// `String(n)` de JavaScript (un double entier s'écrit sans « .0 »).
String _jsTexte(num n) => n == n.truncateToDouble() && n.abs() < 1e21 ? n.toInt().toString() : n.toString();
String _chiffres(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Le texte montré ne porte rien d'autre que le nombre (séparateurs, signe, pour cent, devise) ?
bool tabNombreSeul(String montre) =>
    montre.split(f.devise).join().split('F CFA').join().replaceAll(RegExp('[0-9\\s  .,+%\\-]'), '').isEmpty;

/// Une valeur brute typée : nombre, date, date et heure, sinon texte. Un booléen sort « Oui » ou « Non ».
CelluleSortie tabTyper(Object? v) {
  if (v == null) return '';
  if (v is num) return v.isFinite ? v : '';
  if (v is bool) return v ? 'Oui' : 'Non';
  if (v is DateTime) return {'dateHeure': v.toIso8601String()};
  if (v is Map && (v['date'] != null || v['dateHeure'] != null)) return v.cast<String, Object?>();
  final s = '$v';
  if (_reDate.hasMatch(s)) return {'date': s};
  if (_reDateHeure.hasMatch(s)) return {'dateHeure': s};
  return s;
}

DateTime? _date(String brut) => DateTime.tryParse(_reDate.hasMatch(brut) ? '${brut}T12:00:00' : brut)?.toLocal();

/// Le texte MONTRÉ est-il la même valeur que la brute ?
bool tabMemeValeur(Object? brut, String? montre) {
  if (brut == null || montre == null) return false;
  final m = montre.trim();
  if (brut is num && brut.isFinite) {
    if (!tabNombreSeul(m)) return false;
    final cm = _chiffres(m);
    return cm.isNotEmpty && (cm == _chiffres(_jsTexte(brut.abs())) || cm == _chiffres(_jsTexte(brut.abs().round())));
  }
  if (brut is String && (_reDate.hasMatch(brut) || _reDateHeure.hasMatch(brut))) {
    final d = _date(brut);
    if (d == null) return false;
    return m == f.dateFR(d) || m == f.dateHeure(d) || m == brut;
  }
  if (brut is String) return m == brut;
  return false;
}

/// La cellule d'une colonne : [typee] (la colonne déclare sa valeur typée, `col.xlsx`) ; sinon la [brute] (`col.value` ou `r[col.key]`) si le texte [montre]
/// (`col.text`, sinon le rendu) est cette même valeur ; sinon le texte montré. Le tiret d'une cellule vide sort vide. [aucunTexte] : la colonne n'a ni texte ni rendu.
CelluleSortie tabCelluleSortie({Object? brute, String? montre, bool aucunTexte = false, Object? typee, bool aTypee = false}) {
  if (aTypee) return tabTyper(typee);
  if (aucunTexte || montre == null) return tabTyper(brute);
  if (tabMemeValeur(brute, montre)) {
    final t = tabTyper(brute);
    if (t is Map && t['dateHeure'] != null) {
      final d = DateTime.tryParse('${t['dateHeure']}')?.toLocal();
      if (d != null && montre.trim() == f.dateFR(d)) return {'date': f.iso(d)};
    }
    return t;
  }
  final m = montre.replaceAll(RegExp(r'\s+'), ' ').trim();
  return m == '—' ? '' : m;
}

/// Une colonne de sortie : son libellé et la cellule d'une ligne.
class ColonneSortie<L> {
  const ColonneSortie(this.libelle, this.cellule, {this.droite = false, this.somme = false});
  final String libelle;
  final CelluleSortie Function(L ligne) cellule;
  final bool droite;

  /// `somme: true` : l'impression porte un total CALCULÉ sur les lignes imprimées.
  final bool somme;
}

/// La matrice : une ligne d'en-tête (libellés), puis une ligne par fiche.
List<List<CelluleSortie>> tabMatriceSortie<L>(List<ColonneSortie<L>> colonnes, List<L> lignes) => [
      [for (final c in colonnes) c.libelle],
      for (final l in lignes) [for (final c in colonnes) c.cellule(l)],
    ];

String _pad(int n) => n.toString().padLeft(2, '0');

/// Le texte d'une cellule (CSV, impression) : date jj/mm/aaaa, date et heure jj/mm/aaaa hh:mm, nombre à virgule décimale.
String tabTexteCellule(Object? v) {
  if (v is Map && v['date'] != null) {
    final d = DateTime.tryParse('${v['date']}T12:00:00');
    return d == null ? '${v['date']}' : f.dateFR(d);
  }
  if (v is Map && v['dateHeure'] != null) {
    final d = DateTime.tryParse('${v['dateHeure']}')?.toLocal();
    return d == null ? '${v['dateHeure']}' : '${f.dateFR(d)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }
  if (v is num) return _jsTexte(v).replaceFirst('.', ',');
  return v == null ? '' : '$v';
}

/// Le CSV d'Excel FR : BOM, séparateur « ; », champs entre guillemets, CRLF.
String tabCsv(List<List<Object?>> matrice) =>
    '﻿${matrice.map((l) => l.map((v) => '"${tabTexteCellule(v).replaceAll('"', '""')}"').join(';')).join('\r\n')}';

/// Les largeurs de colonnes du classeur : la plus longue cellule (500 premières lignes) plus deux, de 8 à 60.
List<double> tabLargeurs(List<List<Object?>> matrice) {
  final n = matrice.isEmpty ? 0 : matrice.first.length;
  return [
    for (var c = 0; c < n; c++)
      () {
        var m = 8;
        for (var i = 0; i < matrice.length && i < 500; i++) {
          final t = tabTexteCellule(c < matrice[i].length ? matrice[i][c] : '').length + 2;
          if (t > m) m = t;
        }
        return (m > 60 ? 60 : m).toDouble();
      }(),
  ];
}

/// Le nom de la feuille : le titre sans les caractères interdits d'Excel, daté, 31 caractères au plus.
String tabNomFeuille(String? titre, DateTime jour) {
  var s = (titre == null || titre.trim().isEmpty ? 'Tableau' : titre).replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final date = ' ${f.iso(jour)}';
  final max = 31 - date.length;
  s = (s.length > max ? s.substring(0, max) : s).trim();
  return '${s.isEmpty ? 'Tableau' : s}$date';
}

/// Le nom du fichier : le nom de l'export (caractères sûrs), la date, l'extension.
String tabNomFichier(String? nom, String ext, DateTime jour) =>
    '${(nom == null || nom.isEmpty ? 'export' : nom).replaceAll(RegExp(r'[^\w.\-]+'), '-')}-${f.iso(jour)}.$ext';

/// Les totaux d'une impression : CALCULÉS sur les lignes imprimées pour les colonnes `somme` ; une valeur non numérique rend « non calculable », jamais zéro.
/// `null` si aucune colonne ne demande de total.
List<Object?>? tabTotaux<L>(List<ColonneSortie<L>> colonnes, List<List<Object?>> matrice) {
  if (!colonnes.any((c) => c.somme)) return null;
  return [
    for (var i = 0; i < colonnes.length; i++)
      if (!colonnes[i].somme)
        null
      else
        () {
          num t = 0;
          for (var k = 1; k < matrice.length; k++) {
            final v = matrice[k][i];
            if (v == null || v == '') continue;
            if (v is! num) return 'non calculable';
            t += v;
          }
          return t;
        }(),
  ];
}

/// L'entrée du journal (RG-12) d'une sortie : qui, quel écran, quel format, quel périmètre, combien de lignes, les identifiants (au plus [tabReferencesMax]) ;
/// JAMAIS le contenu d'une cellule.
Map<String, Object?> tabEntreeJournal({
  required String format,
  required String perimetre,
  required List<Object?> references,
  required String utilisateur,
  String? role,
  String? ecran,
  String? nom,
  String module = 'TAB',
  String? action,
}) {
  final refs = [for (final r in references) '${r ?? ''}'];
  return {
    'action': action ?? tabLibellesFormat[format] ?? format,
    'module': module,
    'entite': 'Tableau',
    'reference': ecran ?? nom ?? 'tableau',
    'format': format,
    'perimetre': perimetre,
    'lignes': refs.length,
    'references': refs.length > tabReferencesMax ? refs.sublist(0, tabReferencesMax) : refs,
    'referencesTotal': refs.length,
    'utilisateur': utilisateur,
    if (role != null) 'role': role,
    if (ecran != null) 'ecran': ecran,
    if (nom != null) 'cible': nom,
    'succes': true,
  };
}

/// La série Excel (système 1900) d'une date `AAAA-MM-JJ` ou d'une date et heure : port de `SIGH.xlsx.versSerie`. Une date seule se lit telle quelle ; une date
/// et heure à l'heure LOCALE (un instant en UTC, « …Z », est ramené à l'heure du poste). `null` : pas une date, ou antérieure au 01/03/1900.
num? tabVersSerie(String? iso) {
  final t = iso ?? '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?').firstMatch(t);
  if (m == null) return null;
  var a = int.parse(m[1]!), mo = int.parse(m[2]!), j = int.parse(m[3]!), h = 0, mi = 0, se = 0;
  final avecHeure = m[4] != null;
  if (avecHeure) {
    if (RegExp(r'Z|[+-]\d{2}:?\d{2}$').hasMatch(t)) {
      final d = DateTime.tryParse(t)?.toLocal();
      if (d == null) return null;
      a = d.year; mo = d.month; j = d.day; h = d.hour; mi = d.minute; se = d.second;
    } else {
      h = int.parse(m[4]!); mi = int.parse(m[5]!); se = m[6] == null ? 0 : int.parse(m[6]!);
    }
  }
  final jours = (DateTime.utc(a, mo, j).difference(DateTime.utc(1899, 12, 30)).inHours / 24).round();
  if (jours <= 60) return null;
  if (!avecHeure) return jours;
  return ((jours + (h * 3600 + mi * 60 + se) / 86400) * 1e8).round() / 1e8;
}

/// La cellule d'un tableau dont on ne connaît que le TEXTE montré (encarts, tableaux construits à la main) : port de `celluleDom` de la maquette. Une date
/// jj/mm/aaaa seule sort en date ; dans une colonne alignée à droite, un texte qui n'est qu'un nombre (séparateurs, signe, pour cent, devise) sort en nombre ;
/// sinon le texte. Le tiret d'une cellule vide sort vide.
CelluleSortie tabCelluleTexte(String texte, {bool droite = false}) {
  final t = texte.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t == '—' || t.isEmpty) return '';
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(t);
  if (m != null) return {'date': '${m[3]}-${m[2]}-${m[1]}'};
  if (droite && RegExp(r'\d').hasMatch(t) && tabNombreSeul(t) && !RegExp(r'[.,].*[.,]').hasMatch(t.replaceAll(RegExp(r'\s'), ''))) {
    final n = num.tryParse(t.split(f.devise).join().split('F CFA').join().replaceAll(RegExp('[\\s\u00a0\u202f%+]'), '').replaceFirst(',', '.'));
    if (n != null && n.isFinite) return n;
  }
  return t;
}

