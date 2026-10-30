import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m5/dem_commun.dart' show dateDe, dateHeureDe, vrai;

/// Éléments communs aux écrans de la maternité (M4) — la copie des fonctions d'aide de `m4-maternite.js` : patientes, sages-femmes, rattachement d'une
/// fiche à son dossier patient, cellules de tableau, impression d'un état.

const String matPoliceMono = 'LiberationMono';

List<Fiche> matPatients(Magasin m) => m.collection('patients').actives;

/// `femmes()` : les patientes de sexe féminin, triées par code (`C.sortBy(…, 'code')`, tri français numérique).
List<Fiche> matFemmes(Magasin m) =>
    trierPar([for (final p in matPatients(m)) if (p['sexe'] == 'F') p], (p) => p['code']);

List<OptionChamp> matOptionsFemmes(Magasin m) => [
      for (final p in matFemmes(m)) OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

List<OptionChamp> matOptionsPatients(Magasin m) => [
      for (final p in trierPar(matPatients(m), (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

/// `sagesFemmes()` : sages-femmes et médecins du personnel, dans l'ordre de la collection.
List<OptionChamp> matSagesFemmes(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'sage_femme' || e['fonction'] == 'medecin')
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']} — ${e['poste']}')
    ];

/// `rattacher(v, source)` : le code patient devient identifiant et nom.
Fiche matRattacher(Fiche v, Iterable<Fiche> source, {String code = 'patientCode', String id = 'patientId', String nom = 'patient'}) {
  for (final p in source) {
    if (p['code'] == v[code]) {
      v[id] = p['id'];
      v[nom] = '${p['nom']} ${p['prenom']}';
      break;
    }
  }
  return v;
}

Fiche? matPatientDe(Magasin m, Object? code) {
  for (final p in matPatients(m)) {
    if (p['code'] == code) return p;
  }
  return null;
}

// ---- Cellules ------------------------------------------------------------------------------------------------------------------------------

TonSigh matTon(String t) => switch (t) {
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      'success' => TonSigh.succes,
      'info' => TonSigh.info,
      'navy' => TonSigh.navy,
      _ => TonSigh.neutre,
    };

Widget matRef(Object? ref) => Text('${ref ?? ''}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 12, color: JetonsShell.slate900));

/// Nom en gras léger et code en police fixe dessous (`el('p.truncate.text-sm.font-medium')` + `el('p.font-mono.text-xs.text-slate-400')`).
Widget matCelPatient(String nom, String sous, {bool mono = true}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nom,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
          Text(sous,
              style: TextStyle(
                  fontFamily: mono ? matPoliceMono : null, color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
        ]);

Widget matMuet(String t) => Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

Widget matBadges(List<(String, TonSigh)> l) =>
    Wrap(spacing: 4, runSpacing: 4, children: [for (final b in l) BadgeSigh(b.$1, ton: b.$2)]);

/// `C.dateFR(r.dateHeure)` en heure LOCALE du poste.
String matDateFR(Object? v) {
  final d = dateDe(v);
  return d == null ? '' : dateFR(d);
}

String matDateHeure(Object? v) => dateHeureDe(v);

int matMs(Object? v) => dateDe(v)?.millisecondsSinceEpoch ?? 0;

/// `C.pct(x)` : un pourcentage à une décimale, 0 si le dénominateur est vide.
String matPct(int n, int total) => pourcent(total > 0 ? n / total * 100 : 0);

String matNombre(num n) => nombre(n);

bool matVrai(Object? v) => vrai(v);

// ---- Date et heure : le champ `datetime-local` de la maquette devient une date et une heure ----------------------------------------------

/// `datetime-local` n'existe pas dans le kit du poste : la date et l'heure se saisissent dans deux champs voisins et s'enregistrent ensemble
/// (« AAAA-MM-JJThh:mm », heure locale, comme le champ HTML — écart E405).
List<ChampDef> matChampsDateHeure(String nom, String libelle, {bool requis = true}) => [
      ChampDef(nom: '${nom}Date', libelle: libelle, type: TypeChamp.date, requis: requis),
      ChampDef(
          nom: '${nom}Heure',
          libelle: 'Heure',
          indicatif: 'hh:mm',
          requis: requis,
          valider: (v, _) => RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch('$v'.trim()) ? null : 'Heure attendue : hh:mm.'),
    ];

/// Valeurs du formulaire d'une fiche existante : la date-heure stockée est scindée en date et heure locales.
Map<String, Object?> matValeursEdition(Fiche f, List<String> champsDateHeure) {
  final v = <String, Object?>{for (final e in f.entries) e.key: e.value is num ? '${e.value}' : e.value};
  for (final n in champsDateHeure) {
    final d = dateDe(f[n]);
    v['${n}Date'] = d == null ? '' : iso(d);
    v['${n}Heure'] = d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return v;
}

/// Recompose « AAAA-MM-JJThh:mm » depuis les deux champs (et retire les deux champs de la fiche).
void matRecomposerDateHeure(Map<String, Object?> v, String nom) {
  final d = '${v.remove('${nom}Date') ?? ''}';
  final h = '${v.remove('${nom}Heure') ?? ''}'.trim().padLeft(5, '0');
  v[nom] = d.isEmpty ? null : '${d}T$h';
}

/// Retire les valeurs `null` (les champs nuls ne sont pas écrits au magasin, comme le jeu de la maquette).
Fiche matSansNuls(Fiche f) => {
      for (final e in f.entries)
        if (e.value != null) e.key: e.value
    };

// ---- Impression ------------------------------------------------------------------------------------------------------------------------------

/// `P.etat({titre, sousTitre, filigrane, cartouche, contenu, signatures})` : l'état A4 à en-tête officiel.
void matImprimer(BuildContext ctx,
    {required String titre,
    String? sousTitre,
    String? filigrane,
    List<(String, String)> cartouche = const [],
    List<BlocPiece> blocs = const [],
    List<Signature> signatures = const []}) {
  final c = ContexteEcran.of(ctx);
  afficherApercu(
      ctx,
      PieceA4(
          titre: titre,
          sousTitre: sousTitre,
          filigrane: filigrane,
          cartouche: cartouche,
          blocs: blocs,
          signatures: signatures,
          reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui));
}

/// Tableau « Rubrique / Information » des états de la maternité (`P.tableau([{label:'Rubrique',key:'k'},{label:'Information',key:'v'}], …)`).
BlocPiece matBlocRubriques(List<(String, String)> lignes, {String libelleValeur = 'Information'}) => BlocTableau(TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['k']),
      ColonneEtat(libelle: libelleValeur, valeur: (l) => l['v']),
    ], lignes: [
      for (final l in lignes) {'k': l.$1, 'v': l.$2}
    ]));

String matOuiNon(Object? v) => matVrai(v) ? 'Oui' : 'Non';

String matOuTiret(Object? v) => v == null || v == '' ? '—' : '$v';

/// Une note de la maquette (`K.note`) : balises retirées.
Widget matNote(String texte, {TonSigh ton = TonSigh.info, IconData? icone}) =>
    NoteSigh(sansBalises(texte), ton: ton, icone: icone ?? Icons.info_outline);

/// Titre du tiroir de `K.crud` : `nomComplet || designation || libelle || patient || code || reference || numero || 'Détail'`.
String matTitreDetail(Fiche r) {
  for (final k in const ['nomComplet', 'designation', 'libelle', 'patient', 'code', 'reference', 'numero']) {
    final v = r[k];
    if (v != null && v != '' && v != false && v != 0) return '$v';
  }
  return 'Détail';
}

String matSousTitreDetail(Fiche r) {
  for (final k in const ['code', 'reference', 'numero']) {
    final v = r[k];
    if (v != null && v != '' && v != false && v != 0) return '$v';
  }
  return '';
}
