import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/crud_m14.dart';
import 'cpa_commun.dart';

/// `m12-plan-comptable` — « Plan comptable OHADA » : le référentiel des comptes SYSCOHADA de la clinique, par classe. Création et modification en
/// modale (`CrudM14` : le CRUD à formulaire du kit), archivage avec motif, annulable (RG-14). Les commandes d'écriture sont ABSENTES sans le droit.
class EcranPlanComptable extends StatelessWidget with EcranMaquette {
  const EcranPlanComptable({super.key});

  @override
  String get titre => 'Plan comptable OHADA';

  @override
  String get description =>
      'Référentiel des comptes du plan SYSCOHADA utilisés par la clinique, par classe.';

  @override
  String get regle =>
      'Les comptes marqués « document » proviennent du classeur comptable SYSCOHADA transmis lors du cadrage ; les autres complètent le plan pour permettre le bouclage des schémas d’écriture.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Imprimer le plan comptable',
          icone: LucideIcons.printer,
          onPressed: () => _imprimer(context, c)),
    ];
  }

  static void _imprimer(BuildContext context, ContexteEcran c) {
    final comptes = trierPar(c.magasin.collection('comptes').actives, (x) => x['num']);
    afficherApercu(
        context,
        pieceM9(c,
            titre: 'Plan comptable SYSCOHADA',
            sousTitre: 'Référentiel des comptes utilisés par la clinique',
            cartouche: [
              ('Comptes paramétrés', nombre(comptes.length)),
              ('Classes', nombre(cpaGrouper(comptes, 'classe').length)),
              ('Exercice', '${exerciceChoisi(c)}'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'N° de compte', valeur: (x) => x['num']),
                ColonneEtat(libelle: 'Intitulé', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Classe', valeur: (x) => x['classe'], droite: true),
                ColonneEtat(libelle: 'Journal', valeur: (x) => x['journal']),
              ], lignes: comptes)
            ],
            signatures: [signComptable, signDafCompta]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecouteCompta(c),
      builder: (context, _) {
        final e = ecrituresExercice(c);
        ({double debit, double credit, double solde, int nb}) solde(Object? num) =>
            cpaSoldeCompte(e, '$num');
        final classes = [for (var i = 1; i <= 8; i++) i];
        return CrudM14(
          collection: c.magasin.collection('comptes'),
          entite: 'compte',
          entiteP: 'comptes',
          prefixeId: 'CPT',
          triInitial: 'num',
          taillePage: 20,
          provenance: 'Classeur comptable SYSCOHADA — journal des comptes par mois.',
          titreDetail: (f) => '${f['libelle']}',
          sousTitreDetail: (f) => '',
          colonnes: [
            ColonneTableau(
                cle: 'num',
                libelle: 'N° de compte',
                sansCoupure: true,
                texte: (f) => '${f['num']}',
                rendu: (_, f) => Text('${f['num']}',
                    style: mono.copyWith(color: JetonsShell.navy800, fontWeight: FontWeight.w600))),
            const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
            ColonneTableau(
                cle: 'classe',
                libelle: 'Classe',
                texte: (f) => cpaClasseLibelle(f['classe']),
                rendu: (_, f) => BadgeSigh('Classe ${f['classe']}', ton: TonSigh.navy)),
            ColonneTableau(
                cle: 'journal',
                libelle: 'Journal usuel',
                texte: (f) => '${f['journal'] ?? ''}',
                rendu: (_, f) => BadgeSigh('${f['journal'] ?? ''}')),
            ColonneTableau(
                cle: 'source',
                libelle: 'Provenance',
                texte: (f) => f['source'] == 'DOC' ? 'Document clinique' : 'Complément',
                rendu: (_, f) => f['source'] == 'DOC'
                    ? const BadgeSigh('Document clinique', ton: TonSigh.succes)
                    : const BadgeSigh('Complément')),
            ColonneTableau(
                cle: 'mouvements',
                libelle: 'Écritures',
                droite: true,
                valeur: (f) => solde(f['num']).nb,
                texte: (f) => '${solde(f['num']).nb}'),
            ColonneTableau(
                cle: 'solde',
                libelle: 'Solde',
                droite: true,
                valeur: (f) => solde(f['num']).solde,
                texte: (f) => m(solde(f['num']).solde),
                rendu: (_, f) {
                  final s = solde(f['num']).solde;
                  return Text(m(s),
                      style: TextStyle(
                          color: s < 0 ? JetonsShell.danger600 : JetonsShell.slate700,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()]));
                }),
          ],
          filtres: [
            FiltreTableau(
                nom: 'classe',
                libelle: 'Classe',
                options: [for (final k in classes) OptionChamp('$k', cpaClasseLibelle(k))],
                correspond: (f, v) => '${f['classe']}' == v),
            FiltreTableau(
                nom: 'journal',
                libelle: 'Journal',
                options: [for (final j in cpaJournaux) OptionChamp(j.$1, j.$2)]),
            const FiltreTableau(nom: 'source', libelle: 'Provenance', options: [
              OptionChamp('DOC', 'Document clinique'),
              OptionChamp('CDCT', 'Complément'),
            ]),
          ],
          kpis: (rows) => [
            KpiSigh(libelle: 'Comptes paramétrés', valeur: nombre(rows.length), icone: LucideIcons.listTree),
            KpiSigh(
                libelle: 'Issus des documents',
                valeur: nombre(rows.where((f) => f['source'] == 'DOC').length),
                icone: LucideIcons.fileCheck2,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Classes utilisées',
                valeur: nombre(cpaGrouper(rows, 'classe').length),
                icone: LucideIcons.layers,
                ton: TonSigh.info),
            KpiSigh(
                libelle: 'Comptes mouvementés',
                valeur: nombre(rows.where((f) => solde(f['num']).nb > 0).length),
                icone: LucideIcons.activity,
                ton: TonSigh.neutre),
          ],
          ongletsApres: (ctx) => [
            OngletDef(
                id: 'classes',
                libelle: 'Par classe',
                construire: (ctx) {
                  final g = cpaGrouper(c.magasin.collection('comptes').actives, 'classe');
                  final cl = g.keys.map((k) => int.tryParse(k) ?? 0).toList()..sort();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final k in cl) ...[
                      CarteSigh(
                          titre: cpaClasseLibelle(k),
                          sansRemplissage: true,
                          child: MiniTableauSigh(colonnes: [
                            ColonneMini('Compte', (x) => '${x['num']}', rendu: (x) => Text('${x['num']}', style: mono)),
                            ColonneMini('Intitulé', (x) => '${x['libelle']}'),
                            ColonneMini('Journal', (x) => '${x['journal']}', rendu: (x) => BadgeSigh('${x['journal']}')),
                            ColonneMini('Solde', (x) => m(solde(x['num']).solde), droite: true),
                          ], lignes: trierPar(g['$k']!, (x) => x['num']))),
                      const SizedBox(height: 16),
                    ]
                  ]);
                })
          ],
          champs: (ctx, record) => [
            const ChampDef(
                nom: 'num',
                libelle: 'Numéro de compte',
                requis: true,
                aide: 'Format SYSCOHADA à 6 chiffres.'),
            const ChampDef(nom: 'libelle', libelle: 'Intitulé', requis: true, col: ColChamp.plein),
            ChampDef(
                nom: 'classe',
                libelle: 'Classe',
                type: TypeChamp.select,
                requis: true,
                options: [for (final k in classes) OptionChamp('$k', cpaClasseLibelle(k))]),
            ChampDef(
                nom: 'journal',
                libelle: 'Journal usuel',
                type: TypeChamp.select,
                requis: true,
                options: [for (final j in cpaJournaux) OptionChamp(j.$1, '${j.$1} — ${j.$2}')]),
          ],
          avant: (ctx, saisie, record) => cpaVerifierNumeroCompte(saisie['num'], c.magasin.collection('comptes').actives,
              edition: record != null, idEnEdition: record?['id'], archives: c.magasin.collection('comptes').archivees),
          transformer: (ctx, saisie, record) => cpaCompteDeSaisie(saisie, record: record),
          detail: (ctx, f) => DescListeSigh([
            ('N° de compte', '${f['num']}'),
            ('Intitulé', '${f['libelle']}'),
            ('Classe', cpaClasseLibelle(f['classe']).replaceFirst(RegExp(r' — .*'), '')),
            ('Journal usuel', '${f['journal'] ?? ''}'),
            ('Provenance', f['source'] == 'DOC' ? 'Document clinique' : 'Complément'),
            ('Écritures', '${solde(f['num']).nb}'),
            ('Solde', m(solde(f['num']).solde)),
          ]),
        );
      },
    );
  }
}
