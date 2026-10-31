import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';
import 'pai_pieces.dart';

/// `m11-calcul` — « Calcul de la paie » : la chaîne planning validé → primes NS 132 → évaluation NS 131 → cotisations → bulletin. Aucun montant n'est
/// saisi : tout découle des référentiels versionnés. « Générer les bulletins » écrit UN bulletin par agent en statut « à valider » — la diffusion attend
/// la validation de la Direction.
///
/// Écart porté (E685) : la maquette offre « Générer les bulletins » à tout profil qui OUVRE l'écran (bouton nu) ; la commande d'écriture est ici derrière
/// la porte `droit.editer` — ABSENTE, jamais grisée (RG-13).
class EcranCalculPaie extends StatefulWidget with EcranMaquette {
  const EcranCalculPaie({super.key});

  @override
  String get titre => 'Calcul de la paie';

  @override
  String get description => 'Consolidation automatique : salaire de base, primes du planning, sanctions, cotisations et retenues.';

  @override
  String get regle =>
      'La chaîne appliquée est : planning validé → primes NS 132 → évaluation NS 131 → cotisations → bulletin. Aucun montant n’est saisi manuellement : tout découle des référentiels versionnés.';

  @override
  State<EcranCalculPaie> createState() => _EtatCalcul();
}

class _EtatCalcul extends State<EcranCalculPaie> {
  ControleurFormulaire? _mois;
  int _relances = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mois != null) return;
    _mois = selecteurMois(ContexteEcran.of(context), 'Période de paie', optionsMoisCap(paiAnnee));
    _mois!.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mois?.removeListener(_maj);
    _mois?.dispose();
    super.dispose();
  }

  int get _m => moisChoisi(_mois!);

  Future<void> _generer(BuildContext ctx, ContexteEcran c, List<PaiCalcul> calc) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Générer ${calc.length} bulletin(s) de paie ?',
        message: 'Les bulletins seront enregistrés pour la période ${periodeBrute(_m)} et soumis à la validation de la Direction avant diffusion.',
        libelleOk: 'Générer');
    if (!ok || !ctx.mounted) return;
    final col = c.magasin.collection('bulletins');
    final annulations = <VoidCallback>[];
    for (final x in calc) {
      // La série suit le registre (archivés compris), pas un compteur de page — et chaque bulletin voit ceux qu'on vient d'écrire.
      final ref = paiReferenceSuivante('BP-', 5, col.toutes);
      // A2 : celui qui génère est nommé sur la pièce ; la validation exige une AUTRE personne.
      final fiche = paiBulletinDe(x, ref, genereePar: c.utilisateur, dateGeneration: iso(c.aujourdhui));
      annulations.add(col.inserer({'statut': 'actif', ...fiche, '_creePar': c.utilisateur, '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'BUL').annuler);
    }
    ToastsSigh.afficher(ctx, '${annulations.length} bulletin(s) généré(s).', type: TypeToast.succes, detail: 'En attente de validation par la Direction.', annuler: () {
      for (final u in annulations) {
        u();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoutePaie(c),
      builder: (context, _) {
        final calc = calculerTousPaie(c, _m);
        final lignes = [for (final x in calc) ligneCalcul(x)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          barrePeriode(_mois!, [
            BoutonSigh(libelle: 'Lancer le calcul', icone: LucideIcons.play, onPressed: () => setState(() => _relances++)),
            if (c.droit.editer)
              BoutonSigh(libelle: 'Générer les bulletins', icone: LucideIcons.filePlus, variante: VarianteBouton.succes, onPressed: () => _generer(context, c, calc)),
            BoutonSigh(libelle: 'Éditer le journal de paie', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => imprimerJournalCalcul(context, _m, calc)),
          ]),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Agents concernés', valeur: nombre(calc.length), icone: LucideIcons.usersRound),
            KpiSigh(libelle: 'Masse salariale brute', valeur: money(paiSomme(calc, (x) => x.brut)), icone: LucideIcons.banknote, ton: TonSigh.info),
            KpiSigh(libelle: 'Total des retenues', valeur: money(paiSomme(calc, (x) => x.totalRetenues)), icone: LucideIcons.trendingDown, ton: TonSigh.attention),
            KpiSigh(libelle: 'Net à payer', valeur: money(paiSomme(calc, (x) => x.net)), icone: LucideIcons.wallet, ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            key: ValueKey('calcul:$_m:$_relances'),
            titre: 'Détail du calcul — ${paiMois[_m]} $paiAnnee',
            lignes: lignes,
            nomExport: 'calcul-paie',
            taillePage: 20,
            triInitial: 'net',
            sensInitial: 'desc',
            colonnes: colonnesCalcul,
            alClicLigne: (l) => _detail(context, calculDe(l)),
            actionsLigne: (ctx, l) => [
              BoutonIcone(icone: LucideIcons.fileText, libelle: 'Bulletin de paie', onPressed: () => imprimerBulletin(context, vueDeCalcul(calculDe(l)))),
            ],
          ),
        ]);
      },
    );
  }

  static final colonnesCalcul = <ColonneTableau>[
    ColonneTableau(
        cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true, valeur: (l) => l['matricule'], rendu: (_, l) => monoTexte(l['matricule'])),
    ColonneTableau(
        cle: 'agent',
        libelle: 'Agent',
        valeur: (l) => l['agent'],
        texte: (l) => '${l['agent']}',
        rendu: (_, l) => cellAgent('${l['agent']}', paiFonctionLibelle(calculDe(l).employe['fonction']))),
    ColonneTableau(cle: 'salaireBase', libelle: 'Base', droite: true, texte: (l) => m(l['salaireBase']), rendu: (_, l) => cellMontant(n(l['salaireBase']))),
    ColonneTableau(cle: 'gardes', libelle: 'G', droite: true, rendu: (_, l) => cellTexte(n(l['gardes']) != 0 ? '${l['gardes']}' : '—')),
    ColonneTableau(cle: 'permanences', libelle: 'P', droite: true, rendu: (_, l) => cellTexte(n(l['permanences']) != 0 ? '${l['permanences']}' : '—')),
    ColonneTableau(cle: 'totalPrimes', libelle: 'Primes', droite: true, texte: (l) => m(l['totalPrimes']), rendu: (_, l) => cellMontant(n(l['totalPrimes']))),
    ColonneTableau(cle: 'brut', libelle: 'Brut', droite: true, texte: (l) => m(l['brut']), rendu: (_, l) => cellMontant(n(l['brut']), fort: true)),
    ColonneTableau(
        cle: 'sanction',
        libelle: 'Sanction',
        droite: true,
        texte: (l) => m(l['sanction']),
        rendu: (_, l) => n(l['sanction']) != 0
            ? cellTexte('− ${m(l['sanction'])}', couleur: JetonsShell.danger600, poids: FontWeight.w600)
            : cellSecondaire('—')),
    ColonneTableau(cle: 'cnssOuvriere', libelle: 'CNSS', droite: true, texte: (l) => m(l['cnssOuvriere']), rendu: (_, l) => cellMontant(n(l['cnssOuvriere']))),
    ColonneTableau(cle: 'its', libelle: 'ITS', droite: true, texte: (l) => m(l['its']), rendu: (_, l) => cellMontant(n(l['its']))),
    ColonneTableau(
        cle: 'avances',
        libelle: 'Avance sur salaire',
        droite: true,
        texte: (l) => m(l['avances']),
        rendu: (_, l) {
          if (n(l['avances']) == 0) return cellTexte('—', couleur: JetonsShell.slate300, taille: 12);
          final c = calculDe(l);
          final reste = paiResteAvances(c.avancesDetail);
          return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            cellTexte('− ${m(c.avances)}', couleur: JetonsShell.warning700, poids: FontWeight.w600),
            cellSecondaire(c.avancesDetail.length > 1 ? '${nombre(c.avancesDetail.length)} avances · reste ${m(reste)}' : 'reste ${m(reste)}'),
          ]);
        }),
    ColonneTableau(
        cle: 'participations',
        libelle: 'Événements',
        droite: true,
        texte: (l) => m(l['participations']),
        rendu: (_, l) {
          if (n(l['participations']) == 0) return cellTexte('—', couleur: JetonsShell.slate300, taille: 12);
          final c = calculDe(l);
          return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            cellTexte('− ${m(c.participations)}', couleur: JetonsShell.warning700, poids: FontWeight.w600),
            cellSecondaire('${nombre(c.participationsDetail.length)} participation(s)'),
          ]);
        }),
    ColonneTableau(
        cle: 'net', libelle: 'Net à payer', droite: true, texte: (l) => m(l['net']), rendu: (_, l) => cellTexte(m(l['net']), couleur: JetonsShell.navy900, poids: FontWeight.w700)),
  ];

  /// Le tiroir d'un agent : gains, retenues, charges patronales. Les rubriques conditionnelles n'existent que si elles valent quelque chose.
  void _detail(BuildContext ctx, PaiCalcul x) {
    Widget mini(List<ColonneMini> cols, List<Map<String, Object?>> l) => MiniTableauSigh(colonnes: cols, lignes: l);
    ColonneMini col(String lib, String k, {bool droite = false}) => ColonneMini(lib, (r) => '${r[k] ?? ''}', droite: droite);
    afficherTiroir<void>(ctx,
        titre: x.nomComplet,
        sousTitre: 'Paie de ${x.periode}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(colonnes: 2, kpis: [
            KpiSigh(libelle: 'Salaire brut', valeur: money(x.brut), icone: LucideIcons.banknote),
            KpiSigh(libelle: 'Net à payer', valeur: money(x.net), icone: LucideIcons.wallet, ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Gains',
              child: mini([col('Rubrique', 'k'), col('Base', 'b', droite: true), col('Montant', 'm', droite: true)], [
                {'k': 'Salaire de base', 'b': '', 'm': money(x.salaireBase, avecDevise: false)},
                {'k': 'Prime d’ancienneté', 'b': '${x.anciennete} ans', 'm': money(x.primeAnciennete, avecDevise: false)},
                for (final p in x.lignesPrimes)
                  {'k': 'Prime — ${p.libelle}', 'b': '${p.nombre} × ${money(p.unitaire, avecDevise: false)}', 'm': money(p.total, avecDevise: false)},
                if (x.heuresSupMontant != 0) {'k': 'Heures supplémentaires', 'b': '${nombre(x.heuresSupNb)} h', 'm': money(x.heuresSupMontant, avecDevise: false)},
                {'k': 'TOTAL BRUT', 'b': '', 'm': money(x.brut, avecDevise: false)},
              ])),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Retenues',
              child: mini([col('Rubrique', 'k'), col('Taux / base', 'b', droite: true), col('Montant', 'm', droite: true)], [
                if (x.sanction != 0) {'k': 'Sanction NS 131', 'b': '${paiNum(x.pctSanction)} %', 'm': money(x.sanction, avecDevise: false)},
                {'k': 'CNSS part ouvrière', 'b': '${paiNum(paiCnssOuvriere)} %', 'm': money(x.cnssOuvriere, avecDevise: false)},
                {'k': 'ITS', 'b': 'Barème progressif', 'm': money(x.its, avecDevise: false)},
                for (final l in paiLignesOrtb(x.detailOrtb)) {'k': l.libelle, 'b': l.base, 'm': l.montant},
                if (x.avances != 0) {'k': 'Remboursement d’avance', 'b': '', 'm': money(x.avances, avecDevise: false)},
                if (x.prets != 0)
                  {
                    'k': 'Échéance de prêt',
                    'b': x.pretsDetail.map((p) => '${p['reference']} ${p['rang']}/${p['nbEcheances']}').join(' · '),
                    'm': money(x.prets, avecDevise: false)
                  },
                if (x.participations != 0)
                  {
                    'k': 'Participation aux événements',
                    'b': x.participationsDetail.map((p) => '${p['evenementLibelle'] ?? ''}').join(' · '),
                    'm': money(x.participations, avecDevise: false)
                  },
                {'k': 'TOTAL DES RETENUES', 'b': '', 'm': money(x.totalRetenues + x.sanction, avecDevise: false)},
              ])),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Charges patronales',
              child: mini([col('Rubrique', 'k'), col('Taux', 'b', droite: true), col('Montant', 'm', droite: true)], [
                {'k': 'CNSS part patronale', 'b': '${paiNum(paiCnssPatronale)} %', 'm': money(x.cnssPatronale, avecDevise: false)},
                {'k': 'VPS', 'b': '${paiNum(paiVpsTaux)} %', 'm': money(x.vps, avecDevise: false)},
                {'k': 'COÛT TOTAL EMPLOYEUR', 'b': '', 'm': money(x.coutEmployeur, avecDevise: false)},
              ])),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Éditer le bulletin', icone: LucideIcons.printer, onPressed: () => imprimerBulletin(ctx, vueDeCalcul(x))),
            ]);
  }
}
