import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pai_commun.dart';

/// `m11-cotisations` — « Cotisations CNSS / ITS / VPS » : les états exploitables pour les déclarations périodiques. Part patronale 16,4 % et part ouvrière
/// 3,6 % (CNSS), VPS 4 %, ITS au barème progressif, ORTB Radio et Télé qui SE CUMULENT et ne figurent que sur le mois de leur prélèvement. Le coût
/// employeur et les retenues de l'agent ne s'additionnent jamais : les KPI les montrent séparément.
class EcranCotisations extends StatefulWidget with EcranMaquette {
  const EcranCotisations({super.key});

  @override
  String get titre => 'Cotisations CNSS / ITS / VPS';

  @override
  String get description => 'États des cotisations sociales et fiscales, exploitables pour les déclarations périodiques.';

  @override
  String get regle =>
      'Part patronale ${paiNum(paiCnssPatronale)} % et part ouvrière ${paiNum(paiCnssOuvriere)} % de la CNSS ; VPS ${paiNum(paiVpsTaux)} % ; ITS au barème progressif ; redevances ORTB forfaitaires et annuelles — Radio 1 000 F pour tous en mars, Télé 3 000 F au-delà de 60 000 F en juin, les deux se cumulant.';

  @override
  State<EcranCotisations> createState() => _EtatCotisations();
}

class _EtatCotisations extends State<EcranCotisations> {
  ControleurFormulaire? _mois;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mois != null) return;
    _mois = selecteurMois(ContexteEcran.of(context), 'Période', optionsMoisCap(paiAnnee));
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

  static String _mf(num v) => money(v, avecDevise: false);

  void _etat(BuildContext ctx, ContexteEcran c, String type) {
    final calc = trierPar(calculerTousPaie(c, _m), (x) => x.nomComplet);
    final colonnes = <ColonneEtat>[];
    late final String titre;
    late final num total;
    ColonneEtat mat() => ColonneEtat(libelle: 'Mat.', valeur: (r) => calculDe(r).matricule);
    ColonneEtat agent() => ColonneEtat(libelle: 'Agent', valeur: (r) => calculDe(r).nomComplet);
    ColonneEtat montant(String lib, num Function(PaiCalcul) f) => ColonneEtat(libelle: lib, droite: true, valeur: (r) => _mf(f(calculDe(r))));
    ColonneEtat optionnel(String lib, num Function(PaiCalcul) f) => ColonneEtat(libelle: lib, droite: true, valeur: (r) => f(calculDe(r)) != 0 ? _mf(f(calculDe(r))) : '—');
    switch (type) {
      case 'CNSS':
        titre = 'État des cotisations CNSS';
        colonnes.addAll([
          mat(),
          agent(),
          ColonneEtat(libelle: 'N° CNSS', valeur: (r) => calculDe(r).employe['cnss']),
          montant('Salaire brut', (x) => x.brut),
          montant('Part ouvrière (${paiNum(paiCnssOuvriere)} %)', (x) => x.cnssOuvriere),
          montant('Part patronale (${paiNum(paiCnssPatronale)} %)', (x) => x.cnssPatronale),
          montant('Total', (x) => x.cnssOuvriere + x.cnssPatronale),
        ]);
        total = paiSomme(calc, (x) => x.cnssOuvriere) + paiSomme(calc, (x) => x.cnssPatronale);
      case 'ITS':
        titre = 'État de l’impôt sur les traitements et salaires';
        colonnes.addAll([
          mat(),
          agent(),
          montant('Salaire brut', (x) => x.brut),
          montant('Base imposable', (x) => x.brutApresSanction - x.cnssOuvriere),
          montant('ITS retenu', (x) => x.its),
        ]);
        total = paiSomme(calc, (x) => x.its);
      case 'ORTB':
        titre = 'État des redevances ORTB';
        colonnes.addAll([
          mat(),
          agent(),
          montant('Salaire brut', (x) => x.brut),
          optionnel('ORTB Radio', (x) => x.ortbRadio),
          optionnel('ORTB Télé', (x) => x.ortbTele),
          montant('Total retenu', (x) => x.ortb),
        ]);
        total = paiSomme(calc, (x) => x.ortb);
      default:
        titre = 'État du versement patronal de solidarité';
        colonnes.addAll([
          mat(),
          agent(),
          montant('Salaire brut', (x) => x.brut),
          montant('VPS (${paiNum(paiVpsTaux)} %)', (x) => x.vps),
        ]);
        total = paiSomme(calc, (x) => x.vps);
    }
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: titre,
            sousTitre: periodeBrute(_m),
            cartouche: [
              ('Période', periodeBrute(_m)),
              ('Effectif', nombre(calc.length)),
              ('Masse salariale', money(paiSomme(calc, (x) => x.brut))),
              ('Montant à verser', money(total)),
              ('IFU employeur', IdentiteClinique.ifu),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [TableauEtat(colonnes: colonnes, lignes: [for (final x in calc) ligneCalcul(x)])],
            signatures: const [signComptable, signDaf]));
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
            BoutonSigh(libelle: 'État CNSS', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _etat(context, c, 'CNSS')),
            BoutonSigh(libelle: 'État ITS', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _etat(context, c, 'ITS')),
            BoutonSigh(libelle: 'État VPS', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, onPressed: () => _etat(context, c, 'VPS')),
            BoutonSigh(libelle: 'État ORTB', icone: LucideIcons.radio, variante: VarianteBouton.secondaire, onPressed: () => _etat(context, c, 'ORTB')),
          ]),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'CNSS part ouvrière', valeur: money(paiSomme(calc, (x) => x.cnssOuvriere)), icone: LucideIcons.user, ton: TonSigh.attention, indice: '${paiNum(paiCnssOuvriere)} % du brut'),
            KpiSigh(
                libelle: 'CNSS part patronale',
                valeur: money(paiSomme(calc, (x) => x.cnssPatronale)),
                icone: LucideIcons.building2,
                ton: TonSigh.attention,
                indice: '${paiNum(paiCnssPatronale)} % du brut'),
            KpiSigh(
                libelle: 'CNSS totale à verser',
                valeur: money(paiSomme(calc, (x) => x.cnssOuvriere) + paiSomme(calc, (x) => x.cnssPatronale)),
                icone: LucideIcons.landmark,
                ton: TonSigh.danger),
            KpiSigh(libelle: 'ITS retenu', valeur: money(paiSomme(calc, (x) => x.its)), icone: LucideIcons.receipt, ton: TonSigh.info),
            KpiSigh(libelle: 'VPS', valeur: money(paiSomme(calc, (x) => x.vps)), icone: LucideIcons.percent, indice: '${paiNum(paiVpsTaux)} % du brut'),
            KpiSigh(libelle: 'ORTB Radio', valeur: money(paiSomme(calc, (x) => x.ortbRadio)), icone: LucideIcons.radioTower, ton: TonSigh.neutre, indice: 'Tous les salariés · prélevée en mars'),
            KpiSigh(libelle: 'ORTB Télé', valeur: money(paiSomme(calc, (x) => x.ortbTele)), icone: LucideIcons.tv, ton: TonSigh.neutre, indice: 'Au-delà de 60 000 F · prélevée en juin'),
            KpiSigh(libelle: 'Masse salariale brute', valeur: money(paiSomme(calc, (x) => x.brut)), icone: LucideIcons.banknote, ton: TonSigh.succes),
            KpiSigh(libelle: 'Coût employeur', valeur: money(paiSomme(calc, (x) => x.coutEmployeur)), icone: LucideIcons.calculator, ton: TonSigh.neutre),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            key: ValueKey('cotisations:$_m'),
            titre: 'Détail des cotisations — ${paiMois[_m]} $paiAnnee',
            lignes: lignes,
            nomExport: 'cotisations',
            taillePage: 20,
            colonnes: [
              ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true, texte: (l) => '${l['matricule']}'),
              ColonneTableau(cle: 'agent', libelle: 'Agent', texte: (l) => '${l['agent']}'),
              ColonneTableau(
                  cle: 'cnssNum',
                  libelle: 'N° CNSS',
                  sansCoupure: true,
                  valeur: (l) => calculDe(l).employe['cnss'],
                  texte: (l) => '${calculDe(l).employe['cnss'] ?? ''}',
                  rendu: (_, l) => cellTexte('${calculDe(l).employe['cnss'] ?? ''}', couleur: JetonsShell.slate500, taille: 12)),
              for (final (k, lib) in [('brut', 'Brut'), ('cnssOuvriere', 'CNSS ouvrière'), ('cnssPatronale', 'CNSS patronale'), ('vps', 'VPS'), ('its', 'ITS')])
                ColonneTableau(cle: k, libelle: lib, droite: true, texte: (l) => m(l[k]), rendu: (_, l) => cellMontant(n(l[k]))),
              for (final (k, lib) in [('ortbRadio', 'ORTB Radio'), ('ortbTele', 'ORTB Télé')])
                ColonneTableau(
                    cle: k,
                    libelle: lib,
                    droite: true,
                    texte: (l) => m(l[k]),
                    rendu: (_, l) => n(l[k]) != 0 ? cellMontant(n(l[k])) : cellTexte('—', couleur: JetonsShell.slate300, taille: 12)),
              ColonneTableau(cle: 'ortb', libelle: 'ORTB total', droite: true, texte: (l) => m(l['ortb']), rendu: (_, l) => cellMontant(n(l['ortb']), fort: true)),
            ],
          ),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Barème ITS appliqué',
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Tranche de revenu', (t) => '${t['libelle']}'),
                ColonneMini('Taux', (t) => '${t['taux']} %', droite: true),
              ], lignes: [
                for (final t in paiBaremeIts)
                  {'libelle': t.a == null ? 'Au-delà de ${money(t.de - 1)}' : '${money(t.de)} à ${money(t.a)}', 'taux': paiNum(t.taux)}
              ])),
        ]);
      },
    );
  }
}
