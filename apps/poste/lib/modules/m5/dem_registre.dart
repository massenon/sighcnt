import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/stock_crud.dart';
import 'dem_commun.dart';

const _prescripteurExterne = 'EXTERNE';

/// `m5-demandes` — « Demandes d'analyses » : la file des prélèvements à réaliser, puis le registre des demandes (créer, corriger, archiver en
/// annulable). Les demandes d'une ordonnance naissent d'office du parcours ; la saisie manuelle reste ouverte pour les patients adressés de l'extérieur
/// (leur dossier s'ouvre ici). Le code d'analyse NNNNN-AAAA vient de la fabrique unique du domaine (`demCodeAnalyse`).
class EcranDemandesAnalyses extends StatelessWidget with EcranMaquette {
  const EcranDemandesAnalyses({super.key});

  @override
  String get titre => 'Demandes d’analyses';

  @override
  String get description =>
      'File des prescriptions de laboratoire, rattachées au dossier patient et à la facturation.';

  @override
  String get regle =>
      'Les demandes issues d’une ordonnance sont créées d’office par le médecin prescripteur : le laboratoire n’a rien à ressaisir. La saisie manuelle reste ouverte pour les patients adressés de l’extérieur, à qui le laboratoire remet directement leurs résultats. Un prélèvement ne s’engage qu’après encaissement.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Saisie des résultats',
          icone: LucideIcons.clipboardCheck,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m5-resultats')),
      BoutonSigh(
          libelle: 'Ordonnances',
          icone: LucideIcons.fileText,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m2-ordonnances')),
    ];
  }

  /// « Prendre en charge » sur la file : les demandes de l'ordonnance encore `en_attente` passent `en_cours`, la tâche est close (écart E146 :
  /// ce geste ne passe pas par le prélèvement, et ne touche pas ce que la caisse a déjà débloqué).
  void _prendreEnCharge(BuildContext ctx, Fiche tache) {
    final c = ContexteEcran.of(ctx);
    final dem = c.magasin.collection('demandesAnalyses');
    final r = demPriseEnCharge(dem.toutes, tache['ordonnanceId']);
    for (final id in r.aMettreAJour) {
      dem.mettreAJour(id, {'etatAnalyse': 'en_cours'});
    }
    c.magasin.collection('taches').mettreAJour(tache['id'], {
      'statut': 'fait',
      'faitLe': c.aujourdhui.toUtc().toIso8601String(),
      'faitPar': c.utilisateur,
    });
    ToastsSigh.afficher(ctx, '${r.annonce} analyse(s) prise(s) en charge.',
        type: TypeToast.succes,
        detail: 'Saisir les résultats depuis l’écran « Saisie des résultats ».');
  }

  static List<ChampDef> champs(Magasin m) => [
        ChampDef(
            nom: 'patientCode',
            libelle: 'Patient (dossier du répertoire)',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: optionsPatients(m),
            aide:
                'Laisser vide pour un patient ADRESSÉ DE L’EXTÉRIEUR — renseigner alors son identité ci-dessous.'),
        const ChampDef.section(
            'Ou patient adressé de l’extérieur (dossier créé ici)'),
        const ChampDef(nom: 'nom', libelle: 'Nom', col: ColChamp.tiers),
        const ChampDef(nom: 'prenom', libelle: 'Prénom(s)', col: ColChamp.tiers),
        const ChampDef(
            nom: 'sexe',
            libelle: 'Sexe',
            type: TypeChamp.select,
            col: ColChamp.tiers,
            options: [OptionChamp('F', 'Féminin'), OptionChamp('M', 'Masculin')]),
        const ChampDef(
            nom: 'naissanceConnue',
            libelle: 'Date de naissance',
            type: TypeChamp.select,
            requis: true,
            options: [
              OptionChamp('date', 'Connue — la saisir'),
              OptionChamp('age', 'Inconnue — indiquer l’âge déclaré'),
            ]),
        ChampDef(
            nom: 'dateNaissance',
            libelle: 'Date de naissance',
            type: TypeChamp.date,
            condition: (controle: 'naissanceConnue', quand: ['date']),
            valider: (v, _) {
              final d = DateTime.tryParse('$v');
              return d != null && d.isAfter(DateTime.now())
                  ? 'La date ne peut pas être dans le futur.'
                  : null;
            }),
        const ChampDef(
            nom: 'age',
            libelle: 'Âge déclaré (ans)',
            type: TypeChamp.nombre,
            condition: (controle: 'naissanceConnue', quand: ['age'])),
        const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
        const ChampDef(nom: 'residence', libelle: 'Quartier / résidence'),
        const ChampDef.section('L’analyse demandée'),
        ChampDef(
            nom: 'analyseCode',
            libelle: 'Analyse demandée',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final a in m.referentiel('analyses'))
                OptionChamp('${a['code']}', '${a['code']} — ${a['designation']}')
            ]),
        // Le kit du poste n'a pas de champ « date et heure » : la date et l'heure se saisissent à part et s'enregistrent ensemble (`dateHeure`).
        const ChampDef(
            nom: 'dateHeure',
            libelle: 'Date de la demande',
            type: TypeChamp.date,
            requis: true),
        ChampDef(
            nom: 'heureDemande',
            libelle: 'Heure de la demande',
            requis: true,
            indicatif: 'HH:MM',
            valider: (v, _) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('$v')
                ? null
                : 'Heure attendue au format HH:MM.'),
        ChampDef(
            nom: 'prescripteur',
            libelle: 'Médecin prescripteur',
            type: TypeChamp.select,
            requis: true,
            options: [
              ...medecins(m),
              const OptionChamp(
                  _prescripteurExterne, '— Prescripteur extérieur à la clinique —'),
            ]),
        const ChampDef(
            nom: 'prescripteurExterne',
            libelle: 'Prescripteur extérieur — nom, qualification et structure',
            col: ColChamp.plein,
            condition: (controle: 'prescripteur', quand: [_prescripteurExterne]),
            aide:
                'Ex. : Dr SALIFOU Aminou, médecin généraliste, Centre de santé de Perma. C’est ce qui permet de lui renvoyer le compte rendu.'),
        ChampDef(
            nom: 'laborantin',
            libelle: 'Laborantin',
            type: TypeChamp.select,
            options: laborantins(m)),
        const ChampDef(
            nom: 'urgent', libelle: 'Analyse urgente', type: TypeChamp.case_),
        const ChampDef(
            nom: 'etatAnalyse',
            libelle: 'État',
            type: TypeChamp.select,
            requis: true,
            options: [
              OptionChamp('en_attente', 'En attente de prélèvement'),
              OptionChamp('en_cours', 'En cours d’analyse'),
              OptionChamp('valide', 'Résultat validé'),
            ]),
      ];

  /// Valeurs d'une fiche existante dans le formulaire : `dateHeure` se sépare en date et heure locales.
  static Map<String, Object?> valeursEdition(Fiche f) {
    final d = dateDe(f['dateHeure']);
    String deux(int n) => n.toString().padLeft(2, '0');
    return {
      for (final e in f.entries) e.key: e.value is num ? '${e.value}' : e.value,
      if (d != null) 'dateHeure': iso(d),
      if (d != null) 'heureDemande': '${deux(d.hour)}:${deux(d.minute)}',
    };
  }

  Fiche _transformer(BuildContext ctx, Map<String, Object?> saisie, Fiche? existante) {
    final c = ContexteEcran.of(ctx);
    final m = c.magasin;
    final v = {...saisie};
    final h = v.remove('heureDemande');
    v['dateHeure'] = '${v['dateHeure']}T$h';
    final patients = m.collection('patients');
    final p = patients.actives
        .where((x) => x['code'] == v['patientCode'])
        .firstOrNull;
    final analyse = m
        .referentiel('analyses')
        .where((a) => a['code'] == v['analyseCode'])
        .firstOrNull;
    return demPreparerDemande(
        saisie: v,
        patient: p,
        analyse: analyse,
        demandes: m.collection('demandesAnalyses').toutes,
        creerPatient: (dossier) => patients.inserer({
              'statut': 'actif',
              ...dossier,
              '_creePar': c.utilisateur,
              '_creeLe': c.aujourdhui.toIso8601String(),
            }, prefixe: 'PAT').fiche,
        effectifRepertoire: patients.toutes.length,
        maintenant: c.aujourdhui,
        existante: existante);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final categories = <String>{
      for (final a in m.referentiel('analyses')) '${a['categorie']}'
    }.toList()
      ..sort((a, b) => comparerNaturel(a, b));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Une marge sous la file : sans elle le tableau touche les indicateurs qui le suivent.
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: FileAttenteSigh(
            type: 'prelevement',
            titre: 'Prélèvements à réaliser',
            vide: 'Aucun prélèvement en attente.',
            icone: LucideIcons.flaskConical,
            action: 'Prendre en charge',
            surAction: _prendreEnCharge),
      ),
      CrudStock(
        collection: m.collection('demandesAnalyses'),
        entite: 'demande d’analyse',
        entiteP: 'demandes d’analyses',
        colonnes: colonnesDemande(),
        taillePage: 12,
        triInitial: 'dateHeure',
        sensInitial: 'desc',
        prefixeId: 'DEM',
        filtres: [
          const FiltreTableau(nom: 'etatAnalyse', libelle: 'État', options: [
            OptionChamp('en_attente', 'En attente'),
            OptionChamp('en_cours', 'En cours'),
            OptionChamp('valide', 'Validé'),
          ]),
          FiltreTableau(
              nom: 'categorie',
              libelle: 'Catégorie',
              options: [for (final k in categories) OptionChamp(k)]),
          FiltreTableau(
              nom: 'urgent',
              libelle: 'Priorité',
              options: const [OptionChamp('true', 'Urgentes')],
              correspond: (r, _) => vrai(r['urgent'])),
        ],
        kpis: (ctx, rows) => [
          KpiSigh(
              libelle: 'Demandes enregistrées',
              valeur: nombre(rows.length),
              icone: LucideIcons.flaskConical),
          KpiSigh(
              libelle: 'En attente de prélèvement',
              valeur: nombre(rows.where((r) => r['etatAnalyse'] == 'en_attente').length),
              icone: LucideIcons.hourglass,
              ton: TonSigh.attention),
          KpiSigh(
              libelle: 'Urgentes',
              valeur: nombre(rows
                  .where((r) => vrai(r['urgent']) && r['etatAnalyse'] != 'valide')
                  .length),
              icone: LucideIcons.siren,
              ton: TonSigh.danger),
          KpiSigh(
              libelle: 'Recette laboratoire',
              valeur: money(rows.fold<num>(
                  0, (a, r) => a + (r['prix'] is num ? r['prix'] as num : 0))),
              icone: LucideIcons.coins,
              ton: TonSigh.succes),
        ],
        champs: champs,
        valeursInitiales: () {
          final now = c.aujourdhui;
          String deux(int n) => n.toString().padLeft(2, '0');
          return {
            'dateHeure': iso(now),
            'heureDemande': '${deux(now.hour)}:${deux(now.minute)}',
            'etatAnalyse': 'en_attente',
            'urgent': false,
          };
        },
        valeursEdition: valeursEdition,
        transformer: (ctx, s) => _transformer(ctx, s, null),
        transformerExistante: _transformer,
        refuser: demRefusSaisie,
        detail: (ctx, r) => detailDemande(r),
        titreDetail: (r) => '${r['patient'] ?? r['reference']}',
        sousTitreDetail: (r) => '${r['reference'] ?? ''}',
        referenceToast: (r) => '${r['reference'] ?? ''}',
        etat: (ctx, r) => imprimerDemande(ctx, r),
      ),
    ]);
  }
}
