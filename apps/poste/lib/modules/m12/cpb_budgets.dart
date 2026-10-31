import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/crud_m14.dart';
import 'cpb_commun.dart';

/// `m12-budgets` — « Budgets » : la budgétisation par centre de coûts et le suivi du RÉALISÉ par rapport au prévisionnel. Le réalisé n'est jamais saisi :
/// il se lit aux écritures de l'exercice (débits de classe 6 du centre, `cpbRealise`). Un budget s'ARCHIVE, il ne se supprime pas (RG-14).
///
/// Écart E772 (corrigé dans la maquette d'abord) : la référence d'un nouveau budget venait d'un compteur de page (`C.nextRef`) et redonnait « BG-2026-001 »,
/// déjà attribuée — elle se lit désormais sur les budgets EXISTANTS. Écart E773 (corrigé) : une modification renumérotait le budget (la référence était
/// recalculée à chaque enregistrement) — elle est conservée.
/// Écart E774 : le réalisé d'un budget ignore son EXERCICE — c'est le centre de coûts et l'exercice choisi à l'écran qui décident ; un budget 2027 se lit
/// donc face aux écritures 2026. Porté fidèlement et dit ; à trancher.
/// Écart E777 : le préfixe « BG-2026- » de la référence est une année écrite en dur (comme E661) ; l'exercice saisi n'y entre pas.
class EcranBudgets extends StatelessWidget with EcranMaquette {
  const EcranBudgets({super.key});

  @override
  String get titre => 'Budgets';

  @override
  String get description => 'Budgétisation par centre de coûts et suivi du réalisé par rapport au prévisionnel.';

  static const naturesBudget = ['Charges de fonctionnement', 'Investissements', 'Charges de personnel', 'Achats de marchandises'];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('budgets');
    return ListenableBuilder(
      listenable: ecouteCompta(c, const ['budgets']),
      builder: (context, _) {
        final e = ecrituresExercice(c);
        double realise(Fiche b) => cpbRealise(e, b['centreCout']);
        double prevu(Fiche b) => n(b['prevu']).toDouble();
        return CrudM14(
          collection: col,
          entite: 'budget',
          entiteP: 'budgets',
          prefixeId: 'BUD',
          triInitial: 'prevu',
          sensInitial: 'desc',
          taillePage: 15,
          valeursCreation: const {'exercice': '2026', 'centreCout': 'laboratoire'},
          colonnes: [
            ColonneTableau(
                cle: 'reference',
                libelle: 'N°',
                sansCoupure: true,
                texte: (b) => '${b['reference']}',
                rendu: (_, b) => Text('${b['reference']}', style: mono)),
            const ColonneTableau(cle: 'exercice', libelle: 'Exercice', droite: true),
            const ColonneTableau(cle: 'centre', libelle: 'Centre de coûts'),
            const ColonneTableau(cle: 'nature', libelle: 'Nature'),
            ColonneTableau(
                cle: 'prevu',
                libelle: 'Budget prévu',
                droite: true,
                valeur: prevu,
                texte: (b) => m(b['prevu']),
                rendu: (_, b) => Text(m(b['prevu']),
                    style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
            ColonneTableau(
                cle: 'realise',
                libelle: 'Réalisé',
                droite: true,
                valeur: realise,
                texte: (b) => m(realise(b))),
            ColonneTableau(
                cle: 'ecart',
                libelle: 'Disponible',
                droite: true,
                valeur: (b) => prevu(b) - realise(b),
                texte: (b) => m(prevu(b) - realise(b)),
                rendu: (_, b) {
                  final d = prevu(b) - realise(b);
                  return Text(m(d),
                      style: TextStyle(
                          color: d < 0 ? JetonsShell.danger600 : JetonsShell.success700,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()]));
                }),
            ColonneTableau(
                cle: 'consommation',
                libelle: 'Consommation',
                droite: true,
                valeur: (b) => cpbConsommation(prevu(b), realise(b)),
                texte: (b) => '${cpbConsommation(prevu(b), realise(b))} %',
                rendu: (_, b) {
                  final pct = cpbConsommation(prevu(b), realise(b));
                  return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                        width: 80,
                        height: 6,
                        decoration: BoxDecoration(color: JetonsShell.slate100, borderRadius: BorderRadius.circular(3)),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                            widthFactor: (pct.clamp(2, 100)) / 100,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: pct > 100 ? JetonsShell.danger500 : (pct > 80 ? JetonsShell.warning500 : JetonsShell.success500),
                                    borderRadius: BorderRadius.circular(3))))),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 40,
                        child: Text('$pct %',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: JetonsShell.slate700, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]))),
                  ]);
                }),
          ],
          kpis: (rows) {
            final p = rows.fold<double>(0, (a, b) => a + prevu(b));
            final r = rows.fold<double>(0, (a, b) => a + realise(b));
            return [
              KpiSigh(libelle: 'Budget total prévu', valeur: money(p), icone: LucideIcons.target, ton: TonSigh.navy),
              KpiSigh(libelle: 'Budget consommé', valeur: money(r), icone: LucideIcons.trendingDown, ton: TonSigh.attention),
              KpiSigh(libelle: 'Disponible', valeur: money(p - r), icone: LucideIcons.wallet, ton: p - r >= 0 ? TonSigh.succes : TonSigh.danger),
              KpiSigh(libelle: 'Taux de consommation', valeur: pourcent(p != 0 ? r / p * 100 : 0), icone: LucideIcons.percent, ton: TonSigh.info),
            ];
          },
          ongletsApres: (ctx) => [
            OngletDef(
                id: 'suivi',
                libelle: 'Budget vs réalisé',
                construire: (ctx) {
                  final rows = col.actives;
                  return CarteSigh(
                      titre: 'Comparaison budget prévisionnel et réalisé',
                      child: GraphiqueBarres(horizontal: true, hauteur: 380, etiquettes: [
                        for (final b in rows) '${b['centre']}'
                      ], series: [
                        SerieGraphique('Prévu', [for (final b in rows) prevu(b)], couleur: tonNavy),
                        SerieGraphique('Réalisé', [for (final b in rows) realise(b)], couleur: tonOrange),
                      ]));
                }),
          ],
          champs: (ctx, record) => [
            const ChampDef(nom: 'exercice', libelle: 'Exercice', type: TypeChamp.nombre, requis: true),
            ChampDef(
                nom: 'centreCout',
                libelle: 'Centre de coûts',
                type: TypeChamp.select,
                requis: true,
                options: [for (final x in c.magasin.collection('centresCouts').actives) OptionChamp('${x['code']}', '${x['libelle']}')]),
            ChampDef(
                nom: 'nature',
                libelle: 'Nature budgétaire',
                type: TypeChamp.select,
                requis: true,
                options: [for (final x in naturesBudget) OptionChamp(x)]),
            ChampDef(
                nom: 'prevu',
                libelle: 'Montant prévisionnel (FCFA)',
                type: TypeChamp.nombre,
                requis: true,
                valider: (v, _) => (num.tryParse('$v'.replaceAll(',', '.')) ?? 0) < 0 ? 'La valeur doit être supérieure ou égale à 0.' : null),
          ],
          // La référence se lit sur les budgets EXISTANTS (E772) et ne change pas à la modification (E773).
          transformer: (ctx, s, record) => {
            'exercice': num.tryParse('${s['exercice']}') ?? 0,
            'centreCout': s['centreCout'],
            'nature': s['nature'],
            'prevu': num.tryParse('${s['prevu']}'.replaceAll(',', '.')) ?? 0,
            'centre': libelleCentre(c, s['centreCout']),
            if (record == null) 'reference': cpbReferenceSuivante('BG-2026-', 3, col.toutes),
          },
          detail: (ctx, b) {
            final ligne = realise(b);
            final d = prevu(b) - ligne;
            return DescListeSigh([
              ('N°', '${b['reference']}'),
              ('Exercice', '${b['exercice']}'),
              ('Centre de coûts', '${b['centre']}'),
              ('Nature', '${b['nature']}'),
              ('Budget prévu', m(b['prevu'])),
              ('Réalisé', m(ligne)),
              ('Disponible', m(d)),
              ('Consommation', '${cpbConsommation(prevu(b), ligne)} %'),
              ('Centre de coûts', libelleCentre(c, b['centreCout'])),
            ]);
          },
        );
      },
    );
  }
}
