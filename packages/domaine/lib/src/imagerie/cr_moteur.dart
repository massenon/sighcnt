/// La mécanique du compte rendu d'imagerie — `champDeCR`, `valeurLisibleCR`, `lignesCR`, `corpsCR`, `rendreCR`, `detailCR`, `imprimerCR` et les
/// cinq tableaux (`ecranTableauImagerie`) de `prototype_html/assets/js/modules/m2-consultations.js`.
///
/// Rejouée sur les vecteurs `test/vecteurs/imagerie-cr.json`, tirés des écrans RÉELS pilotés dans Chrome (`build/vecteurs-imagerie-cr.js`). Les
/// VARIABLES vivent au magasin (`variablesImagerie`) ; ce fichier n'en connaît aucune : il les lit, comme la maquette (`imVariablesDe`).
library;

import 'cr_modalites.dart';

typedef FicheCR = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les variables d'un examen, leurs rubriques, leurs exemplaires
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `imVariablesDe(codeExamen)` : les variables ACTIVES de l'examen, dans l'ordre déclaré (`ordre`, à égalité l'ordre du magasin).
List<FicheCR> variablesDeExamen(
    Iterable<FicheCR> variables, String codeExamen) {
  final l = [
    for (final v in variables)
      if (v['statut'] != 'archive' &&
          v['examen'] == codeExamen &&
          v['actif'] != false)
        v
  ];
  // Tri STABLE (Dart `sort` ne l'est pas) : à égalité, l'ordre du magasin.
  final indexe = [for (var i = 0; i < l.length; i++) (i, l[i])];
  indexe.sort((a, b) {
    final c = _nombre(a.$2['ordre']).compareTo(_nombre(b.$2['ordre']));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexe) e.$2];
}

num _nombre(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// `imRubriquesDe` : les rubriques, dans l'ordre de première apparition.
List<String> rubriquesDeVariables(Iterable<FicheCR> vars) {
  final vus = <String>{};
  final out = <String>[];
  for (final v in vars) {
    final r = '${v['rubrique']}';
    if (vus.add(r)) out.add(r);
  }
  return out;
}

/// `imModaliteDe(codeExamen)` : la modalité se lit au CATALOGUE (`examensImagerie`). Un examen introuvable reste à l'échographie.
String modaliteDeCodeExamen(Iterable<FicheCR> examens, Object? codeExamen) {
  for (final x in examens) {
    if (x['statut'] != 'archive' && x['code'] == codeExamen)
      return modaliteDeExamen(x);
  }
  return 'echographie';
}

/// `crsDeModalite(code)` : les comptes rendus actifs dont l'EXAMEN est de cette modalité.
List<FicheCR> crsDeModalite(String modalite, Iterable<FicheCR> comptesRendus,
        Iterable<FicheCR> examens) =>
    [
      for (final r in comptesRendus)
        if (r['statut'] != 'archive' &&
            modaliteDeCodeExamen(examens, r['examenCode']) == modalite)
          r
    ];

/// `imLibresDe(codeExamen)` : les rubriques rédigées de la modalité de l'examen.
List<RubriqueLibre> rubriquesLibresDe(
        Iterable<FicheCR> examens, Object? codeExamen) =>
    modaliteOuInconnue(modaliteDeCodeExamen(examens, codeExamen))
        .rubriquesLibres;

/// `saisieTexteDe(codeExamen)` : les mesures se saisissent en TEXTE (« environ 12 mm », « sup à 5 cm »).
bool saisieTexteDe(Iterable<FicheCR> examens, Object? codeExamen) =>
    modaliteOuInconnue(modaliteDeCodeExamen(examens, codeExamen)).saisieTexte;

/// `exemplairesDe(v, valeurs)` : combien d'exemplaires d'une variable répétée — lu sur la variable qui porte le nombre (« 02 » → 2). `parseInt` :
/// un préfixe numérique suffit (« 2 sacs » → 2) ; hors de 2 à 3, un seul.
int exemplairesDe(FicheCR v, FicheCR? valeurs) {
  final repete = v['repete'];
  if (repete == null || repete == '') return 1;
  final brut = '${(valeurs ?? const {})[repete] ?? ''}';
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch(brut);
  final n = m == null ? null : int.tryParse(m.group(0)!.trim());
  return (n != null && n >= 2 && n <= 3) ? n : 1;
}

/// `exemplaire(v, k)` : la variable pour son k-ième exemplaire — code suffixé `__k`, précisions suffixées.
FicheCR exemplaire(FicheCR v, int k) {
  if (k <= 1) return v;
  final suf = '__$k';
  return {
    ...v,
    'code': '${v['code']}$suf',
    'numero': k,
    'conditionnels': [
      for (final c in (v['conditionnels'] as List? ?? const []))
        {...(c as Map).cast<String, Object?>(), 'code': '${c['code']}$suf'}
    ],
  };
}

/// `valeurCorrespond(c, valeur)` : la valeur est-elle l'une de celles qui appellent le champ de précision ? Insensible à la casse.
bool valeurCorrespond(Iterable<Object?> quand, Object? valeur) {
  final v = '${valeur ?? ''}'.toLowerCase();
  return quand.any((q) => '$q'.toLowerCase() == v);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les champs de saisie d'une variable
// ---------------------------------------------------------------------------------------------------------------------------------------------

enum GenreChampCR { texte, nombre, selection, multiple, zone }

/// Un champ de saisie du compte rendu (`champDeCR`), indépendant de l'interface.
class ChampCR {
  const ChampCR(this.nom, this.libelle, this.genre,
      {this.options = const [], this.controle, this.quand = const []});
  final String nom;
  final String libelle;
  final GenreChampCR genre;
  final List<String> options;

  /// Un champ de PRÉCISION : n'apparaît que si le champ [controle] prend l'une des valeurs [quand].
  final String? controle;
  final List<String> quand;
  bool get conditionnel => controle != null;
}

/// `champDeCR(v, texte)` : les champs d'une variable. Les champs de précision suivent IMMÉDIATEMENT la liste qui les appelle.
List<ChampCR> champsDeCR(FicheCR v, {required bool texte}) {
  final code = '${v['code']}';
  final lib = '${v['libelle']}';
  final type = v['type'];
  final unite = v['unite'];
  final options = [for (final o in (v['options'] as List? ?? const [])) '$o'];
  final g = texte ? GenreChampCR.texte : GenreChampCR.nombre;
  late List<ChampCR> out;
  if (type == 'gestationnel') {
    out = [
      ChampCR('${code}_sa', '$lib — semaines d’aménorrhée', g),
      ChampCR('${code}_j', '$lib — jours', g),
    ];
  } else if (type == 'dimensions') {
    out = [
      ChampCR('${code}_a', '$lib — longueur (mm)', g),
      ChampCR('${code}_b', '$lib — largeur (mm)', g),
      ChampCR('${code}_c', '$lib — épaisseur (mm)', g),
    ];
  } else if (type == 'liste' || type == 'binaire') {
    out = [ChampCR(code, lib, GenreChampCR.selection, options: options)];
  } else if (type == 'mesure') {
    out = [
      ChampCR(
          code, lib + ((unite != null && unite != '') ? ' ($unite)' : ''), g)
    ];
  } else if (type == 'multiple') {
    out = [ChampCR(code, lib, GenreChampCR.multiple, options: options)];
  } else if (type == 'zone') {
    out = [ChampCR(code, lib, GenreChampCR.zone)];
  } else {
    out = [ChampCR(code, lib, GenreChampCR.texte)];
  }
  for (final c in (v['conditionnels'] as List? ?? const [])) {
    final cm = (c as Map).cast<String, Object?>();
    out.add(ChampCR('${cm['code']}', '${cm['libelle']}', GenreChampCR.texte,
        controle: code,
        quand: [for (final q in (cm['quand'] as List? ?? const [])) '$q']));
  }
  return out;
}

/// `corpsCR` : le plan de la saisie d'un examen — une carte par rubrique, dans l'ordre. Le champ qui commande les blocs répétés est celui de la
/// PREMIÈRE variable répétée de la rubrique (`repetees[0].repete`).
class PlanSaisieCR {
  PlanSaisieCR(this.rubriques, this.libres);
  final List<PlanRubriqueCR> rubriques;
  final List<RubriqueLibre> libres;
}

class PlanRubriqueCR {
  PlanRubriqueCR(this.rubrique, this.champs, this.exemplaires, this.controle);
  final String rubrique;
  final List<ChampCR> champs;
  final Map<int, List<ChampCR>> exemplaires;
  final String? controle;
}

PlanSaisieCR planSaisieCR(List<FicheCR> vars,
    {required bool texte, required List<RubriqueLibre> libres}) {
  final rubriques = <PlanRubriqueCR>[];
  for (final rub in rubriquesDeVariables(vars)) {
    final duBloc = [
      for (final v in vars)
        if ('${v['rubrique']}' == rub) v
    ];
    if (duBloc.isEmpty) continue;
    final champs = <ChampCR>[
      for (final v in duBloc) ...champsDeCR(v, texte: texte)
    ];
    final repetees = [
      for (final v in duBloc)
        if (v['repete'] != null && v['repete'] != '') v
    ];
    final ex = <int, List<ChampCR>>{};
    if (repetees.isNotEmpty) {
      for (final k in [2, 3]) {
        ex[k] = [
          for (final v in repetees)
            ...champsDeCR(exemplaire(v, k), texte: texte)
        ];
      }
    }
    rubriques.add(PlanRubriqueCR(rub, champs, ex,
        repetees.isEmpty ? null : '${repetees.first['repete']}'));
  }
  return PlanSaisieCR(rubriques, libres);
}

/// Le bloc n°[rang] est-il affiché ? (`actualiser()` : le nombre déclaré par le champ qui commande, de [rang] à 3.)
bool exemplaireVisible(Object? valeurNombre, int rang) {
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch('${valeurNombre ?? ''}');
  final n = m == null ? null : int.tryParse(m.group(0)!.trim());
  return n != null && n >= rang && n <= 3;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Lecture d'un compte rendu : tiroir et pièce imprimée
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _deux(Object? x) {
  final s = '$x';
  return RegExp(r'^\d$').hasMatch(s) ? '0$s' : s;
}

bool _vide(Object? x) => x == null || x == '';

/// `valeurLisibleCR(v, valeurs)` : la valeur telle qu'elle se LIT — « 12 SA + 03 jours », « 12 x 8 x 5 mm », « T2, FLAIR », « 275 mg/l » — suivie de
/// la précision qu'elle a appelée.
String valeurLisibleCR(FicheCR v, FicheCR valeurs) {
  final code = '${v['code']}';
  String lu;
  if (v['type'] == 'gestationnel') {
    final sa = valeurs['${code}_sa'], j = valeurs['${code}_j'];
    lu = _vide(sa) ? '—' : '${_deux(sa)} SA + ${_deux(_vide(j) ? 0 : j)} jours';
  } else if (v['type'] == 'dimensions') {
    final dims = [
      valeurs['${code}_a'],
      valeurs['${code}_b'],
      valeurs['${code}_c']
    ].where((x) => !_vide(x)).map((x) => '$x').toList();
    lu = dims.isNotEmpty ? '${dims.join(' x ')} mm' : '—';
  } else {
    final val = valeurs[code];
    if (val is List) {
      lu = val.isNotEmpty ? val.map((x) => '$x').join(', ') : '—';
    } else if (_vide(val)) {
      lu = '—';
    } else {
      final u = v['unite'];
      lu =
          '$val${(u != null && u != '' && !RegExp(r'[a-zA-Zµ%]\s*$').hasMatch('$val')) ? ' $u' : ''}';
    }
  }
  for (final c in (v['conditionnels'] as List? ?? const [])) {
    final cm = (c as Map).cast<String, Object?>();
    if (valeurCorrespond(cm['quand'] as List? ?? const [], valeurs[code]) &&
        !_vide(valeurs[cm['code']])) {
      lu += ' — ${cm['libelle']} : ${valeurs[cm['code']]}';
    }
  }
  return lu;
}

class LigneCR {
  const LigneCR(this.variable, this.lu, this.hors);
  final FicheCR variable;
  final String lu;

  /// La valeur sort de la normale déclarée : elle s'imprime en gras.
  final bool hors;
}

class GroupeCR {
  const GroupeCR(this.titre, this.lignes);
  final String titre;
  final List<LigneCR> lignes;
}

/// `lignesCR(r)` : les lignes lisibles d'un compte rendu, rubrique par rubrique, en tenant compte des exemplaires — un deuxième sac ne se lit que
/// si le compte rendu en déclare deux. Une mécanique pour le tiroir et l'impression.
List<GroupeCR> groupesCR(FicheCR r, List<FicheCR> vars) {
  final valeurs = ((r['valeurs'] as Map?) ?? const {}).cast<String, Object?>();
  final out = <GroupeCR>[];
  for (final rub in rubriquesDeVariables(vars)) {
    final duBloc = [
      for (final v in vars)
        if ('${v['rubrique']}' == rub) v
    ];
    var max = 1;
    for (final v in duBloc) {
      final e = exemplairesDe(v, valeurs);
      if (e > max) max = e;
    }
    for (var k = 1; k <= max; k++) {
      out.add(GroupeCR(max > 1 ? '$rub n°$k' : rub, [
        for (final v in duBloc)
          if (k == 1 ||
              ((v['repete'] != null && v['repete'] != '') &&
                  exemplairesDe(v, valeurs) >= k))
            () {
              final inst = exemplaire(v, k);
              return LigneCR(inst, valeurLisibleCR(inst, valeurs),
                  ecartDeLaNormale(inst, valeurs[inst['code']]));
            }()
      ]));
    }
  }
  return out;
}

/// `annexesAnterieures(r)` : les comptes rendus d'AVANT le retrait de « Annexes » la portent encore — on l'affiche, marquée comme saisie
/// antérieure : faire disparaître un texte écrit et rendu au prescripteur serait réécrire la pièce.
String? annexesAnterieures(FicheCR r, List<RubriqueLibre> libres) {
  final a = r['annexes'];
  if (a == null || a == '' || libres.any((l) => l.code == 'annexes'))
    return null;
  return '$a';
}

/// Une ligne de la pièce imprimée : un intitulé de rubrique (gras) ou « libellé : valeur » (gras si la valeur sort de la norme).
class LigneImpressionCR {
  const LigneImpressionCR(this.texte, {this.gras = false, this.titre = false});
  final String texte;
  final bool gras;
  final bool titre;
}

/// Le corps de `imprimerCR(r)`. La conclusion s'imprime TOUJOURS, fût-elle vide (son absence doit se voir) ; les autres rubriques rédigées ne
/// paraissent que remplies.
List<LigneImpressionCR> contenuImpressionCR(
    FicheCR r, List<FicheCR> vars, List<RubriqueLibre> libres) {
  final out = <LigneImpressionCR>[];
  for (final g in groupesCR(r, vars)) {
    out.add(LigneImpressionCR(g.titre, gras: true, titre: true));
    for (final l in g.lignes) {
      out.add(LigneImpressionCR('${l.variable['libelle']} : ${l.lu}',
          gras: l.hors));
    }
  }
  final anc = annexesAnterieures(r, libres);
  if (anc != null) {
    out.add(const LigneImpressionCR('Annexes', gras: true, titre: true));
    out.add(LigneImpressionCR(anc));
  }
  for (final lib in libres) {
    final t = r[lib.code];
    if (lib.code != 'conclusion' && _vide(t)) continue;
    out.add(LigneImpressionCR(lib.label, gras: true, titre: true));
    out.add(LigneImpressionCR(_vide(t) ? '—' : '$t',
        gras: lib.code == 'conclusion'));
  }
  return out;
}

/// Le cartouche de la pièce (`imprimerCR`). La DDR est une donnée d'échographie ; ailleurs, la modalité la remplace, et la provenance ne
/// s'imprime qu'à l'échographie.
List<(String, String)> cartoucheCR(FicheCR r, String modalite) {
  final echo = modalite == 'echographie';
  return [
    ('Nom et prénoms', '${r['patient']}'),
    ('Âge', r['age'] != null ? '${r['age']} ans' : '—'),
    ('Indication', '${r['indication'] ?? ''}'),
    echo
        ? ('DDR', _vide(r['ddr']) ? '—' : '${r['ddr']}')
        : ('Modalité', modaliteOuInconnue(modalite).label),
    ('Prescripteur', '${r['prescripteur'] ?? ''}'),
    if (echo)
      ('Provenance', _vide(r['provenance']) ? '—' : '${r['provenance']}'),
    (
      'Condition de l’examen',
      _vide(r['condition']) ? '—' : '${r['condition']}'
    ),
  ];
}

/// Les paires du tiroir « Consulter » (`detailCR`, `K.grid`).
List<(String, String)> pairesDetailCR(FicheCR r) => [
      ('Référence', '${r['reference']}'),
      ('Examen', '${r['examen']}'),
      ('Patient', '${r['patient']} — ${r['patientCode']}'),
      ('Âge', r['age'] != null ? '${r['age']} ans' : '—'),
      ('Indication', '${r['indication'] ?? ''}'),
      ('DDR', _vide(r['ddr']) ? '—' : '${r['ddr']}'),
      ('Provenance', _vide(r['provenance']) ? '—' : '${r['provenance']}'),
      (
        'Condition de l’examen',
        _vide(r['condition']) ? '—' : '${r['condition']}'
      ),
      ('Prescripteur', '${r['prescripteur'] ?? ''}'),
      ('Réalisé par', '${r['realisateur'] ?? ''}'),
      (
        'État',
        r['statut'] == 'rendu' ? 'Rendu au prescripteur' : 'En rédaction'
      ),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les indicateurs des cinq tableaux
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `compterValeur(rows, codes, valeurs)` : combien de comptes rendus dont l'une des variables nommées vaut l'une des valeurs.
int compterValeur(
    Iterable<FicheCR> rows, List<String> codes, List<String> valeurs) {
  var n = 0;
  for (final r in rows) {
    final v = ((r['valeurs'] as Map?) ?? const {}).cast<String, Object?>();
    if (codes.any((c) => valeurs.contains(v[c]))) n++;
  }
  return n;
}

/// Un indicateur : libellé, valeur entière, indice éventuel, ton (`navy|success|warning|info|neutral|danger`) et icône Lucide.
class IndicateurImagerie {
  const IndicateurImagerie(this.libelle, this.valeur, this.ton, this.icone,
      {this.indice});
  final String libelle;
  final int valeur;
  final String ton;
  final String icone;
  final String? indice;
}

/// Les quatre indicateurs d'un tableau de modalité : trois communs, puis celui de la modalité (`o.kpi`) — ou, à défaut, « Payés — à exécuter ».
List<IndicateurImagerie> indicateursImagerie(
    String modalite, List<FicheCR> rows, List<FicheCR> aExecuter) {
  final rendus = rows.where((r) => r['statut'] == 'rendu').length;
  final brouillons = rows.length - rendus;
  final communs = [
    IndicateurImagerie('Comptes rendus', rows.length, 'navy',
        modaliteImagerie(modalite)?.icone ?? 'scan-line'),
    IndicateurImagerie('Rendus au prescripteur', rendus, 'success', 'send'),
    IndicateurImagerie('En cours de rédaction', brouillons,
        brouillons > 0 ? 'warning' : 'neutral', 'pencil'),
  ];
  final IndicateurImagerie dernier;
  switch (modalite) {
    case 'echographie':
      dernier = IndicateurImagerie(
          'Examens obstétricaux',
          rows
              .where((r) => RegExp('OBS').hasMatch('${r['examenCode'] ?? ''}'))
              .length,
          'info',
          'baby');
    case 'radiographie':
      dernier = IndicateurImagerie(
          'Fractures relevées',
          compterValeur(rows, ['BAS_FRACT', 'MEM_FRACT'], ['présente']),
          'danger',
          'bone',
          indice: 'Bassin et membres');
    case 'mammographie':
      dernier = IndicateurImagerie(
          'ACR 4 ou plus',
          compterValeur(rows, [
            'MAM_ACR_D',
            'MAM_ACR_G'
          ], [
            'ACR 4 — suspect',
            'ACR 5 — hautement suspect',
            'ACR 6 — malignité prouvée'
          ]),
          'danger',
          'alert-triangle',
          indice: 'Examens appelant une conduite à tenir');
    case 'scanner':
      final reac = compterValeur(
          rows, ['TDM_REAC'], ['réaction mineure', 'réaction sévère']);
      dernier = IndicateurImagerie(
          'Avec injection',
          compterValeur(rows, ['TDM_INJ'], ['avec injection']),
          'info',
          'syringe',
          indice: '$reac réaction(s) consignée(s)');
    case 'irm':
      dernier = IndicateurImagerie(
          'Avec gadolinium',
          compterValeur(rows, ['IRM_GADO'], ['avec gadolinium']),
          'info',
          'droplets');
    default:
      dernier = IndicateurImagerie('Payés — à exécuter', aExecuter.length,
          aExecuter.isNotEmpty ? 'info' : 'neutral', 'wallet',
          indice: 'Demandes réglées à la caisse');
  }
  return [...communs, dernier];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les gestes d'écriture
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `rendreCR` : la conclusion est obligatoire avant de rendre le compte rendu. Rend le message de refus, ou `null` si le geste est permis.
String? refusRendreCR(FicheCR r) => _vide(r['conclusion'])
    ? 'La conclusion est obligatoire avant de rendre le compte rendu.'
    : null;

/// Le message de la confirmation « Rendre au prescripteur ».
String messageRendreCR(FicheCR r) =>
    'Le compte rendu ${r['reference']} sera transmis à ${r['prescripteur']}. Une correction ultérieure devra être signalée comme telle.';

/// `PR.notifier` du rendu : l'avis adressé au POSTE de consultation (pas à une personne — le prescripteur peut être en congé).
FicheCR notificationRenduCR(FicheCR r, String maintenantIso) => {
      'type': 'imagerie_rendue',
      'poste': 'consultation',
      'destinataire': null,
      'libelle': 'Compte rendu d’imagerie rendu — ${r['patient']}',
      'detail':
          '${r['examen']} — ${r['reference']} — prescripteur ${r['prescripteur']}',
      'priorite': 'normale',
      'demandeId': null,
      'factureId': null,
      'ordonnanceId': null,
      'patientId': r['patientId'],
      'reference': r['reference'],
      'lue': false,
      'creeLe': maintenantIso,
    };

/// `enregistrer(cible)` — le patch du compte rendu (valeurs relevées + rubriques rédigées) et celui de la demande liée : « exécutée » dès la saisie
/// pourvu qu'elle soit « payée » ou déjà « exécutée ». [releve] : les valeurs des champs VISIBLES (un champ masqué ne s'enregistre pas).
({FicheCR patch, FicheCR? patchDemande}) patchEnregistrerCR(
    Map<String, Object?> releve, List<RubriqueLibre> libres,
    {FicheCR? demande, required String maintenantIso}) {
  final v = {...releve};
  final patch = <String, Object?>{};
  for (final r in libres) {
    patch[r.code] = (v[r.code] == null || v[r.code] == '') ? '' : v[r.code];
    v.remove(r.code);
  }
  patch['valeurs'] = v;
  FicheCR? pd;
  if (demande != null &&
      (demande['statut'] == 'payee' || demande['statut'] == 'executee')) {
    pd = {'statut': 'executee', 'executeLe': maintenantIso};
  }
  return (patch: patch, patchDemande: pd);
}

/// `ficheDepuisEntete(v)` : la fiche qui NAÎT à l'enregistrement (jamais à la validation de la modale : un compte rendu ne doit pas exister au
/// registre tant que personne ne l'a écrit). [reference] se lit sur les comptes rendus EXISTANTS (écart E120 : jamais un compteur de page).
FicheCR ficheDepuisEntete(
  Map<String, Object?> v, {
  required String reference,
  required String dateIso,
  required String examenLibelle,
  required FicheCR? patient,
  required int? age,
  required String prescripteur,
  required String? prescripteurId,
  required String realisateur,
}) =>
    {
      'reference': reference,
      'date': dateIso,
      'examenCode': v['examenCode'],
      'examen': examenLibelle,
      'patientId': patient?['id'],
      'patient': patient != null
          ? '${patient['nom']} ${patient['prenom']}'
          : '${v['patientCode']}',
      'patientCode': v['patientCode'],
      'age': age,
      'indication': v['indication'],
      'ddr': _vide(v['ddr']) ? '—' : v['ddr'],
      'condition': v['condition'],
      'provenance': v['provenance'] ?? '',
      'prescripteurId': prescripteurId,
      'prescripteur': prescripteur,
      'realisateurId': v['realisateurId'],
      'realisateur': realisateur,
      'valeurs': <String, Object?>{},
      'annexes': '',
      'conclusion': '',
      'statut': 'brouillon',
    };

/// Le prescripteur désigne-t-il quelqu'un d'EXTÉRIEUR à la clinique ? (`K.PRESCRIPTEUR_EXTERNE`)
const prescripteurExterne = 'EXTERNE';

/// `K.nomPrescripteur` : le nom à porter sur la pièce. [interne] sait nommer un soignant de la maison.
String nomPrescripteurCR(
    Map<String, Object?> v, String Function(Object?) interne) {
  if ('${v['prescripteurId'] ?? ''}' == prescripteurExterne) {
    final libre = '${v['prescripteurIdExterne'] ?? ''}'.trim();
    return libre.isNotEmpty ? '$libre (extérieur)' : 'Prescripteur extérieur';
  }
  return interne(v['prescripteurId']);
}

/// `K.idPrescripteur` : l'identifiant à ENREGISTRER — nul pour un prescripteur du dehors.
String? idPrescripteurCR(Map<String, Object?> v) =>
    '${v['prescripteurId'] ?? ''}' == prescripteurExterne
        ? null
        : v['prescripteurId'] as String?;

/// `C.ageDe(patient)` : l'âge se lit sur la date de naissance ; à défaut sur l'âge DÉCLARÉ (que `ageReferenceLe` fait vieillir).
int? ageDePatient(FicheCR? rec, DateTime aujourdhui) {
  if (rec == null) return null;
  int? ans(Object? depuis) {
    final d = DateTime.tryParse('$depuis');
    if (d == null) return null;
    final jours = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    return (jours / 365.25).floor();
  }

  final nais = rec['dateNaissance'];
  if (nais != null && nais != '') {
    final a = ans(nais);
    return a == null ? null : (a < 0 ? 0 : a);
  }
  final declare = rec['age'];
  if (declare == null || declare == '') return null;
  final n = int.tryParse('$declare'.trim());
  if (n == null || n < 0) return null;
  final ref = rec['ageReferenceLe'];
  if (ref == null || ref == '') return n;
  final ecoule = ans(ref) ?? 0;
  return n + (ecoule < 0 ? 0 : ecoule);
}
