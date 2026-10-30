import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'surv_commun.dart';

/// `m3-transfusion` — « Surveillance transfusionnelle » : un PROTOCOLE à temps imposés (avant la pose, 15, 30, 60, 90 min, fin, 1 h et 2 h après) sur
/// huit éléments. Elle reste ouverte quand la banque de sang est fermée : la clinique ne collecte pas de sang mais elle en pose. Règles :
/// `hosTempsTransfusion`, `hosElementsTransfusion`, `hosValeursTransfusion`.
///
/// E366 : la commande « Modifier » de la maquette lève une exception (aucun champ n'est déclaré) — elle est ABSENTE ici, jamais une commande morte.
/// Un protocole incomplet est SIGNALÉ, jamais refusé : refuser ferait remplir n'importe quoi pour pouvoir valider.
class EcranTransfusion extends StatelessWidget with EcranMaquette {
  const EcranTransfusion({super.key});

  @override
  String get titre => 'Surveillance transfusionnelle';

  @override
  String get description =>
      'Surveillance d’une transfusion à temps imposés : avant la pose, 15 min, toutes les 30 min, fin, 1 h et 2 h après.';

  @override
  String get regle =>
      'Les temps de relevé sont imposés par le protocole : ce n’est pas une périodicité de confort, c’est la fenêtre pendant laquelle un accident transfusionnel se déclare. Cette fiche reste ouverte quand la banque de sang est fermée : la clinique ne collecte pas de sang mais elle en pose, et doit le surveiller.';

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient',
            type: TypeChamp.select,
            requis: true,
            options: optionsPatientsM3(m)),
        const ChampDef(nom: 'service', libelle: 'Service', requis: true),
        const ChampDef(nom: 'date', libelle: 'Date', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'pochePSL',
            libelle: 'Référence de la poche de PSL',
            requis: true,
            aide: 'Le numéro porté sur la poche — c’est lui qui rattache un incident à un produit.'),
        const ChampDef(nom: 'debut', libelle: 'Heure du début de la transfusion', requis: true),
        ChampDef(
            nom: 'responsableId',
            libelle: 'Responsable de la surveillance',
            type: TypeChamp.select,
            requis: true,
            options: optionsSoignants(m, (x) => x['execute'] == true)),
        for (final t in hosTempsTransfusion) ...[
          ChampDef.section(t.$2),
          for (final e in hosElementsTransfusion)
            ChampDef(
                nom: '${t.$1}_${e.$1}',
                libelle: e.$3.isNotEmpty ? '${e.$2} (${e.$3})' : e.$2,
                col: ColChamp.tiers),
        ],
        const ChampDef.section('Conclusion'),
        const ChampDef(
            nom: 'incident',
            libelle: 'Un incident transfusionnel est survenu',
            type: TypeChamp.case_,
            col: ColChamp.plein),
        const ChampDef(nom: 'natureIncident', libelle: 'Nature de l’incident'),
        const ChampDef(
            nom: 'conclusion',
            libelle: 'Conclusion',
            type: TypeChamp.textarea,
            requis: true,
            col: ColChamp.plein),
      ];

  /// La fiche qu'écrit « Enregistrer » : les relevés par temps, le nombre de temps relevés sur les huit attendus.
  static Fiche construire(Magasin m, CollectionMagasin col, Map<String, Object?> v) {
    final pt = patientParCode(m, v['patientCode']);
    final calcul = hosValeursTransfusion(v);
    return {
      'statut': 'actif',
      'reference': referenceSuivante('TRF-', 4, col.toutes),
      'patientId': pt?['id'],
      'patient': pt != null ? '${pt['nom']} ${pt['prenom']}' : v['patientCode'],
      'patientCode': v['patientCode'],
      'service': v['service'],
      'date': v['date'],
      'pochePSL': v['pochePSL'],
      'debut': v['debut'],
      'responsableId': v['responsableId'],
      'responsable': nomSoignant(m, v['responsableId']),
      'valeurs': calcul.valeurs,
      'releves': calcul.releves,
      'attendus': hosTempsTransfusion.length,
      'incident': v['incident'] == true,
      'natureIncident': v['natureIncident'],
      'conclusion': v['conclusion'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('surveillancesTransfusion');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final completes = rows.where((r) => r['releves'] == r['attendus']).length;
        final incidents = rows.where((r) => vrai(r['incident'])).length;
        final tri = trierPar(rows, (r) => r['date']).reversed.toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Surveillances', valeur: nombre(rows.length), icone: LucideIcons.droplets, ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Protocole complet',
                valeur: nombre(completes),
                icone: LucideIcons.checkCheck,
                ton: completes == rows.length ? TonSigh.succes : TonSigh.attention,
                indice: '${nombre(hosTempsTransfusion.length)} temps de relevé attendus'),
            KpiSigh(
                libelle: 'Incidents signalés',
                valeur: nombre(incidents),
                icone: LucideIcons.siren,
                ton: incidents > 0 ? TonSigh.danger : TonSigh.succes),
            KpiSigh(
                libelle: 'Éléments surveillés',
                valeur: nombre(hosElementsTransfusion.length),
                icone: LucideIcons.activity,
                ton: TonSigh.info),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'La huitième ligne du formulaire officiel est illisible au scan. Elle figure ici sous l’intitulé provisoire « Autre élément surveillé » et reste à confirmer par le service — deviner ce qu’un protocole de sécurité demande de surveiller serait la pire des improvisations.',
              ton: TonSigh.attention,
              icone: LucideIcons.triangleAlert),
          const SizedBox(height: 16),
          RegistreFormulaire(
            collection: col,
            lignes: tri,
            prefixe: 'TRF',
            nomExport: 'surveillancesTransfusion',
            messageVide: 'Aucune surveillance transfusionnelle enregistrée.',
            libelleNouveau: 'Nouvelle surveillance',
            titreCreation: 'Surveillance transfusionnelle',
            sousTitreCreation: 'Les temps de relevé sont imposés par le protocole.',
            libelleCreer: 'Enregistrer',
            tailleCreation: TailleModale.xl,
            modifiable: false,
            champs: (_) => champs(c.magasin),
            initiales: (_) => {
              'date': '${c.aujourdhui.year.toString().padLeft(4, '0')}-${c.aujourdhui.month.toString().padLeft(2, '0')}-${c.aujourdhui.day.toString().padLeft(2, '0')}'
            },
            construire: (v, _) => construire(c.magasin, col, v),
            toastApres: (ctx, f, annuler) {
              final complet = f['releves'] == f['attendus'];
              ToastsSigh.afficher(
                  ctx,
                  complet
                      ? 'Surveillance complète enregistrée.'
                      : 'Surveillance enregistrée — ${(f['attendus'] as int) - (f['releves'] as int)} temps non relevé(s).',
                  type: complet ? TypeToast.succes : TypeToast.attention,
                  detail: '${f['reference']}');
              // `U.alerter` : l'incident s'affiche en rouge, par-dessus (le son d'alerte n'est pas porté par le kit).
              if (f['incident'] == true) {
                ToastsSigh.afficher(ctx, 'Incident transfusionnel signalé — poche ${f['pochePSL']}',
                    type: TypeToast.erreur);
              }
            },
            titreFiche: (r) => '${r['reference']}',
            colonnes: [
              const ColonneTableau(cle: 'reference', libelle: 'Référence'),
              ColonneTableau(cle: 'date', libelle: 'Date', texte: (r) => dateTexte(r['date'])),
              const ColonneTableau(cle: 'patient', libelle: 'Patient'),
              const ColonneTableau(cle: 'service', libelle: 'Service'),
              ColonneTableau(
                  cle: 'pochePSL',
                  libelle: 'Poche de PSL',
                  rendu: (_, r) => Text('${r['pochePSL']}',
                      style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12))),
              const ColonneTableau(cle: 'debut', libelle: 'Début de la transfusion'),
              ColonneTableau(
                  cle: 'releves',
                  libelle: 'Relevés',
                  texte: (r) => '${r['releves']} / ${r['attendus']}',
                  rendu: (_, r) => BadgeSigh('${r['releves']} / ${r['attendus']}',
                      ton: r['releves'] == r['attendus'] ? TonSigh.succes : TonSigh.attention)),
              ColonneTableau(
                  cle: 'incident',
                  libelle: 'Incident',
                  texte: (r) => vrai(r['incident']) ? 'OUI' : 'Non',
                  rendu: (_, r) => vrai(r['incident'])
                      ? const BadgeSigh('OUI', ton: TonSigh.danger)
                      : const BadgeSigh('Non', ton: TonSigh.succes)),
            ],
            detail: (ctx, r) {
              final valeurs = (r['valeurs'] as Map?)?.cast<String, Object?>() ?? const {};
              String cel(String t, String e) {
                final x = (valeurs[t] as Map?)?[e];
                return x == null || x == '' ? '—' : '$x';
              }

              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DescListeSigh([
                  ('Référence', r['reference']),
                  ('Patient', r['patient']),
                  ('Service', r['service']),
                  ('Date', dateTexte(r['date'])),
                  ('Référence de la poche de PSL', r['pochePSL']),
                  ('Heure de début de la transfusion', r['debut']),
                  ('Responsable de la surveillance', r['responsable']),
                  (
                    'Incident',
                    vrai(r['incident'])
                        ? 'OUI — ${vrai(r['natureIncident']) ? r['natureIncident'] : 'non précisé'}'
                        : 'Non'
                  ),
                ]),
                sectionDetail(
                    'Relevés du protocole',
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 760),
                            child: MiniTableauSigh(colonnes: [
                              ColonneMini('Élément', (l) => '${l['element']}'),
                              for (final t in hosTempsTransfusion)
                                ColonneMini(t.$2, (l) => '${l[t.$1]}'),
                            ], lignes: [
                              for (final e in hosElementsTransfusion)
                                {
                                  'element': e.$2,
                                  for (final t in hosTempsTransfusion) t.$1: cel(t.$1, e.$1),
                                }
                            ])))),
                if (vrai(r['conclusion'])) sectionDetail('Conclusion', paragrapheDetail('${r['conclusion']}')),
              ]);
            },
          ),
        ]);
      },
    );
  }
}
