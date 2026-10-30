import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Ce que partagent les écrans du bloc, de l'anesthésie et des sorties (M3) : les lectures du répertoire et des soignants, les dates, la
/// restitution d'un refus nommé. Les règles chiffrées sont dans `packages/domaine` (`bloc_regles.dart`).

/// `optionsPatients3()` : le répertoire trié par code, « code — nom prénom ».
List<OptionChamp> optionsPatientsBloc(Magasin m) => [
      for (final p in trierPar([...m.collection('patients').actives], (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

/// `patientParCode3(code)`.
Fiche? patientParCodeBloc(Magasin m, Object? code) =>
    m.collection('patients').actives.where((p) => p['code'] == code).firstOrNull;

/// `optionsSoignants(filtre)` : la valeur est l'IDENTIFIANT du soignant, le libellé « nom — poste ».
List<OptionChamp> optionsSoignantsBloc(Magasin m, [bool Function(Fiche)? filtre]) => [
      for (final x in m.collection('soignants').actives)
        if (filtre == null || filtre(x)) OptionChamp('${x['id']}', '${x['nomComplet']} — ${x['poste']}')
    ];

/// `nomSoignant(id)` : le nom, ou « — » si le soignant est introuvable.
String nomSoignantBloc(Magasin m, Object? id) {
  final x = m.collection('soignants').actives.where((y) => y['id'] == id).firstOrNull;
  return x == null ? '—' : '${x['nomComplet']}';
}

/// `C.dateFR` d'une date saisie (AAAA-MM-JJ) ou d'un instant ISO ; vide → « — ».
String dateBloc(Object? v) {
  final t = '${v ?? ''}';
  if (t.isEmpty) return '—';
  final d = DateTime.tryParse(t);
  if (d == null) return t;
  // Une date seule se lit sans fuseau ; un instant se lit à l'heure locale (comme la maquette).
  final seule = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t);
  return dateFR(seule ? d : d.toLocal());
}

String dateHeureBloc(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '—' : dateHeure(d.toLocal());
}

/// `iso(d)` du jour de l'horloge du poste (date locale).
String aujourdhuiIso(ContexteEcran c) => iso(c.aujourdhui);

/// L'heure saisie au clavier (`HH:MM`) : le kit du poste n'a pas de champ « heure » (écart E422, comme E367).
ChampDef champHeure(String nom, String libelle, {bool requis = false}) => ChampDef(
    nom: nom,
    libelle: libelle,
    requis: requis,
    indicatif: 'HH:MM',
    valider: (v, _) => '$v'.isEmpty || RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('$v')
        ? null
        : 'Heure attendue au format HH:MM.');

/// Un refus NOMMÉ du domaine, dit par son propre toast (rien n'est écrit).
String? refusEnTexte(BlocRefus? r) => r == null ? null : (r.detail == null ? r.message : '${r.message}\n${r.detail}');

void toastRefus(BuildContext ctx, BlocRefus r) => ToastsSigh.afficher(ctx, r.message,
    type: TypeToast.erreur, detail: r.detail, duree: const Duration(seconds: 8));

/// `K.section(titre, contenu)` d'un tiroir de détail.
Widget sectionBloc(String titre, Widget corps) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: const TextStyle(
              color: JetonsShell.slate500,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6)),
      const SizedBox(height: 8),
      corps,
    ]));

Widget texteBloc(String t, {bool lignes = false}) => Text(t.isEmpty ? '—' : t,
    style: const TextStyle(color: JetonsShell.slate600, fontSize: 14, height: 20 / 14));

/// Les indicateurs d'un écran, en tête.
Widget kpisBloc(List<KpiSigh> kpis) => Padding(padding: const EdgeInsets.only(bottom: 16), child: KpiGrilleSigh(kpis: kpis));
