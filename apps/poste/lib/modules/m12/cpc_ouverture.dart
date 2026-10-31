import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpc_commun.dart';

/// `m12-ouverture` — « Bilan d'ouverture & à-nouveaux » : le report des soldes de bilan au 1ᵉʳ janvier, écrit au journal AN.
///
/// Seules les CLASSES 1 À 5 se reportent : un compte de charge ou de produit ne passe jamais à l'exercice suivant, il est soldé par le résultat, qui
/// s'inscrit au compte 13 du passif — le reporter reviendrait à compter deux fois la même dépense. Le report est REFUSÉ s'il ne s'équilibre pas (RG-10)
/// et REFUSÉ une seconde fois (double à-nouveau) ; la pièce naît en BROUILLON, la validation reste un geste humain. Règles dans `cpc_exercice.dart`.
class EcranOuverture extends StatefulWidget with EcranMaquette {
  const EcranOuverture({super.key});

  @override
  String get titre => 'Bilan d’ouverture & à-nouveaux';

  @override
  String get description => 'Report des soldes de bilan au 1ᵉʳ janvier — les à-nouveaux, écrits au journal AN.';

  @override
  String get regle =>
      'Seules les classes 1 à 5 se reportent : un compte de charge ou de produit ne passe jamais à l’exercice suivant, il est soldé par le résultat, qui s’inscrit au compte 13 du passif. Le reporter reviendrait à compter deux fois la même dépense. Le report est refusé s’il ne s’équilibre pas (RG-10) : un à-nouveau boiteux propagerait le déséquilibre à toutes les années suivantes. La pièce naît en brouillon — la validation reste un geste humain.';

  @override
  State<EcranOuverture> createState() => _EtatOuverture();
}

class _EtatOuverture extends State<EcranOuverture> {
  ControleurFormulaire? _annee;

  List<Fiche> _ecritures(ContexteEcran c) => c.magasin.collection('ecritures').actives;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_annee != null) return;
    final c = ContexteEcran.of(context);
    final annees = <int>{for (final e in _ecritures(c)) if (cpaAnnee(e['date']) != null) cpaAnnee(e['date'])!}.toList()..sort();
    _annee = champUnique(
        ChampDef(
            nom: 'annee',
            libelle: 'Exercice clos',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [for (final a in annees) OptionChamp('$a', 'Exercice $a')]),
        annees.isEmpty ? '${c.aujourdhui.year}' : '${annees.last}');
    _annee!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  int get _a => int.tryParse('${_annee!['annee']}') ?? 0;

  int _dejaEcrits(ContexteEcran c) =>
      _ecritures(c).where((x) => x['journal'] == 'AN' && cpaAnnee(x['date']) == _a + 1).length;

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final s = cpcSoldesDeCloture(_ecritures(c), _a);
    final lignes = cpcLignesOuverture(s, _a, compteResultat: '130000');
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Bilan d’ouverture — à-nouveaux',
            sousTitre: 'Au 1ᵉʳ janvier ${_a + 1}, report de l’exercice $_a',
            cartouche: [
              ('Exercice clos', '$_a'),
              ('Ouverture au', '1ᵉʳ janvier ${_a + 1}'),
              ('Journal', 'AN — Journal des à-nouveaux'),
              ('Comptes reportés', nombre(s.comptes.length)),
              ('Résultat reporté', money(s.resultat)),
              ('Référentiel', 'Plan comptable SYSCOHADA révisé'),
            ],
            blocs: [
              BlocTableau(TableauEtat(libelleTotal: 'TOTAUX DU REPORT', colonnes: [
                ColonneEtat(libelle: 'Compte', valeur: (l) => l['compte']),
                ColonneEtat(libelle: 'Intitulé', valeur: (l) => l['libelle']),
                ColonneEtat(
                    libelle: 'Débit',
                    droite: true,
                    valeur: (l) => n(l['solde']) > 0 ? m(l['solde']) : '',
                    somme: (l) => n(l['solde']) > 0 ? n(l['solde']) : 0),
                ColonneEtat(
                    libelle: 'Crédit',
                    droite: true,
                    valeur: (l) => n(l['solde']) < 0 ? m(-n(l['solde'])) : '',
                    somme: (l) => n(l['solde']) < 0 ? -n(l['solde']) : 0),
              ], lignes: lignes)),
              const BlocTexte(
                  'Seules les classes 1 à 5 sont reportées : un compte de charge ou de produit ne passe jamais à l’exercice suivant, il est soldé par le résultat. Les deux totaux doivent être égaux (RG-10).'),
            ],
            signatures: [signComptable, const Signature('La Directrice de l’Administration et des Finances', nom: 'TAKI Alimatou')]));
  }

  Future<void> _ecrire(BuildContext ctx, ContexteEcran c) async {
    final s = cpcSoldesDeCloture(_ecritures(c), _a);
    final r = cpcReporterANouveaux(s, _a, dejaEcrits: _dejaEcrits(c));
    if (!r.ok) {
      ToastsSigh.afficher(ctx, r.message!, type: TypeToast.erreur, detail: r.detail);
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Écrire les à-nouveaux du 1ᵉʳ janvier ${_a + 1} ?',
        message:
            '${nombre(s.comptes.length)} compte(s) de bilan seront reportés, plus le résultat de l’exercice $_a (${money(s.resultat)}) au compte 13. La pièce naît en brouillon : la validation reste un geste humain.',
        libelleOk: 'Écrire le report');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('ecritures');
    final ecrits = <({Fiche fiche, VoidCallback annuler})>[];
    final refus = refuseSiClos(ctx, () {
      for (final l in r.lignes) {
        ecrits.add(col.inserer(l, prefixe: 'ECR'));
      }
    });
    if (refus) return;
    ToastsSigh.afficher(ctx, 'À-nouveaux écrits — ${nombre(ecrits.length)} ligne(s) au journal AN.',
        type: TypeToast.succes,
        detail: 'Pièce ${r.numero}, en brouillon.',
        annuler: () {
          for (final e in ecrits) {
            e.annuler();
          }
        },
        messageAnnulation: 'Report annulé.');
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection('ecritures'), c.magasin.collection('comptes')]),
      builder: (context, _) {
        final s = cpcSoldesDeCloture(_ecritures(c), _a);
        final deja = _dejaEcrits(c);
        final lignes = cpcLignesOuverture(s, _a);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              titre: 'Exercice à reporter',
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                commande(_annee!, largeur: 220),
                if (c.droit.editer)
                  BoutonSigh(libelle: 'Écrire les à-nouveaux', icone: LucideIcons.filePlus, onPressed: () => _ecrire(context, c)),
                BoutonSigh(
                    libelle: 'Imprimer le bilan d’ouverture',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _imprimer(context, c)),
              ])),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Comptes à reporter', valeur: nombre(s.comptes.length), icone: LucideIcons.list, indice: 'Classes 1 à 5 seulement'),
            KpiSigh(libelle: 'Total des soldes débiteurs', valeur: money(s.totalDebiteurs), icone: LucideIcons.arrowDownRight, ton: TonSigh.info),
            KpiSigh(libelle: 'Total des soldes créditeurs', valeur: money(s.totalCrediteurs), icone: LucideIcons.arrowUpRight, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Résultat de l’exercice $_a',
                valeur: money(s.resultat),
                icone: s.resultat >= 0 ? LucideIcons.smile : LucideIcons.frown,
                ton: s.resultat >= 0 ? TonSigh.succes : TonSigh.danger,
                indice: 'Compte 13 — il équilibre le report'),
          ]),
          const SizedBox(height: 16),
          s.equilibre
              ? NoteSigh(
                  'Le report s’équilibre : soldes débiteurs ${money(s.totalDebiteurs)} = soldes créditeurs ${money(s.totalCrediteurs)} + résultat ${money(s.resultat)}. L’à-nouveau peut être écrit.',
                  ton: TonSigh.succes,
                  icone: LucideIcons.scale)
              : NoteSigh(
                  'Le report NE S’ÉQUILIBRE PAS — écart de ${money(s.ecart)}. L’à-nouveau est refusé : un report boiteux propagerait le déséquilibre à toutes les années suivantes (RG-10). Vérifier les écritures de l’exercice $_a avant de reporter.',
                  ton: TonSigh.danger,
                  icone: LucideIcons.triangleAlert),
          if (deja > 0) ...[
            const SizedBox(height: 16),
            NoteSigh(
                'Les à-nouveaux du 1ᵉʳ janvier ${_a + 1} sont DÉJÀ écrits : ${nombre(deja)} ligne(s) au journal AN. Les réécrire créerait un double report — la pièce existante fait foi.',
                ton: TonSigh.attention,
                icone: LucideIcons.fileCheck),
          ],
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Bilan d’ouverture au 1ᵉʳ janvier ${_a + 1} — à-nouveaux des classes 1 à 5',
              sansRemplissage: true,
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Compte', (l) => '${l['compte']}'),
                ColonneMini('Intitulé', (l) => '${l['libelle']}'),
                ColonneMini('Débit', (l) => n(l['solde']) > 0 ? m(l['solde']) : '', droite: true),
                ColonneMini('Crédit', (l) => n(l['solde']) < 0 ? m(-n(l['solde'])) : '', droite: true),
              ], lignes: lignes)),
          const SizedBox(height: 16),
          const NoteSigh(
              'Seules les classes 1 à 5 se reportent. Un compte de charge (classe 6) ou de produit (classe 7) ne passe jamais à l’exercice suivant : il est soldé par le résultat, qui s’inscrit au compte 13 du passif. Le reporter reviendrait à compter deux fois la même dépense.',
              icone: LucideIcons.bookOpenCheck),
        ]);
      },
    );
  }
}
