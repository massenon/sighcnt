import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';

/// Briques communes aux écrans de l'hospitalisation (M3) : listes de choix tirées du magasin, lecture des dates et heures, solde d'un patient.
/// Les règles chiffrées vivent dans `packages/domaine/lib/src/hospitalisation/hos_regles.dart`.

/// `optionsPatients()` : le répertoire trié par code, « code — nom prénom ».
List<OptionChamp> optionsPatientsHos(Magasin m) => [
      for (final p in trierPar(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

/// `optionsInfirmiersNom()` (E361) : infirmiers, sages-femmes et aides-soignantes, valeur = NOM (jamais l'identifiant du soignant).
List<OptionChamp> optionsInfirmiersNom(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (const ['infirmier', 'sage_femme', 'aide_soignant'].contains(e['fonction']))
          OptionChamp('${e['nomComplet']}', '${e['nomComplet']} — ${e['poste']}')
    ];

/// `optionsMedecinsObs()` : les médecins, valeur = nom.
List<OptionChamp> optionsMedecinsHos(Magasin m) => [
      for (final e in m.collection('personnel').actives)
        if (e['fonction'] == 'medecin') OptionChamp('${e['nomComplet']}', '${e['nomComplet']}')
    ];

/// `soldePatient(patientId)` : la somme des reliquats des factures du patient (RG-06 : la sortie suppose un solde apuré).
num soldePatient(Magasin m, Object? patientId) {
  num s = 0;
  for (final f in m.collection('factures').actives) {
    if (f['patientId'] == patientId) {
      final r = f['reliquat'];
      s += r is num ? r : (num.tryParse('${r ?? ''}') ?? 0);
    }
  }
  return s;
}

/// `C.toDate` puis heure LOCALE : la maquette affiche l'heure du poste (Bénin, UTC+1), pas l'heure UTC stockée.
DateTime? dateLocale(Object? v) => hosVersDate(v)?.toLocal();

/// `C.dateFR(d) + ' ' + C.heure(d)` : « 15/08/2026 09h00 ».
String dateHeureCourte(Object? v) {
  final d = dateLocale(v);
  return d == null ? '' : '${dateFR(d)} ${heure(d)}';
}

String heureDe(Object? v) {
  final d = dateLocale(v);
  return d == null ? '' : heure(d);
}

/// `C.dateFR` d'une date ISO ou d'un horodatage (vide si illisible).
String jourFR(Object? v) {
  final d = hosVersDate(v);
  return d == null ? '' : dateFR(d);
}

/// Un champ « date » + un champ « HH:mm » → l'horodatage ISO (UTC) que la maquette enregistre pour un `datetime-local` (heure locale du poste).
/// Le kit n'a pas de sélecteur d'heure : l'heure se saisit en `HH:mm` (limite dite, E367).
DateTime? versHorodatage(Object? date, Object? hhmm) {
  final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${date ?? ''}');
  final h = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${hhmm ?? ''}'.trim());
  if (d == null || h == null) return null;
  final hh = int.parse(h[1]!), mm = int.parse(h[2]!);
  if (hh > 23 || mm > 59) return null;
  return DateTime(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!), hh, mm);
}

/// Validation d'un champ « HH:mm ».
String? validerHeure(Object? v, Map<String, Object?> _) =>
    RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch('${v ?? ''}'.trim())
        ? null
        : 'Heure attendue au format HH:mm.';

String pad2(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime d) => '${pad2(d.hour)}:${pad2(d.minute)}';

/// Deux cartes côte à côte dès 1024 px (`K.charts`), l'une sous l'autre en dessous.
Widget deuxColonnes(Widget a, Widget b) => LayoutBuilder(builder: (_, k) {
      final l = k.maxWidth >= 1024 ? (k.maxWidth - 16) / 2 : k.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: l, child: a),
        SizedBox(width: l, child: b),
      ]);
    });

/// Texte à chasse fixe (références, codes dossier).
Widget texteMono(String t, {Color? couleur, FontWeight? poids}) => Text(t,
    style: TextStyle(
        fontFamily: 'LiberationMono',
        fontSize: 12,
        fontWeight: poids,
        color: couleur ?? JetonsShell.slate700));
