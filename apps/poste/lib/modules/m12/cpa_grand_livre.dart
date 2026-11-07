import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cpa_commun.dart';

/// `m12-grand-livre` — « Grand livre » : le détail chronologique des mouvements par compte, avec solde progressif. Écran en LECTURE SEULE : le grand
/// livre est reconstitué depuis les écritures de l'exercice ; toute correction passe par l'écriture d'origine, qui doit rester équilibrée (RG-10).
///
/// Écart E724 (corrigé dans la maquette d'abord) : le plan du jeu porte deux fiches au même numéro (631810) ; la liste ne propose qu'UNE entrée par numéro.
class EcranGrandLivre extends StatefulWidget with EcranMaquette {
  const EcranGrandLivre({super.key});

  @override
  String get titre => 'Grand livre';

  @override
  String get description =>
      'Détail chronologique des mouvements par compte, avec solde progressif.';

  @override
  String get regle =>
      'Écran en lecture seule. Le grand livre est reconstitué depuis les écritures : il ne se modifie pas ici. Toute correction passe par l’écriture d’origine (Écritures comptables), qui doit rester équilibrée (RG-10).';

  @override
  State<EcranGrandLivre> createState() => _EtatGrandLivre();
}

class _EtatGrandLivre extends State<EcranGrandLivre> {
  ControleurFormulaire? _compte;

  List<Fiche> _mouvementes(ContexteEcran c) =>
      cpaComptesMouvementes(c.magasin.collection('comptes').actives, ecrituresExercice(c));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_compte != null) return;
    final c = ContexteEcran.of(context);
    final l = _mouvementes(c);
    _compte = champUnique(
        ChampDef(
            nom: 'compte',
            libelle: 'Compte',
            type: TypeChamp.select,
            col: ColChamp.plein,
            options: [for (final x in l) OptionChamp('${x['num']}', '${x['num']} — ${x['libelle']}')]),
        l.isEmpty ? '' : '${l.first['num']}');
    _compte!.addListener(_surChangement);
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _compte?.removeListener(_surChangement);
    _compte?.dispose();
    super.dispose();
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, String compte, List<Fiche> rows) {
    final s = cpaSoldeCompte(ecrituresExercice(c), compte);
    final lib = cpaCompteLibelle(compte, comptes: c.magasin.collection('comptes').toutes);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Grand livre',
            sousTitre: 'Compte $compte — $lib',
            cartouche: [
              ('Compte', compte),
              ('Intitulé', lib),
              ('Mouvements', nombre(rows.length)),
              ('Total débit', money(s.debit)),
              ('Total crédit', money(s.credit)),
              ('Solde', money(s.solde)),
            ],
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Date', valeur: (e) => dateDe(e['date'])),
                ColonneEtat(libelle: 'N° pièce', valeur: (e) => e['numero']),
                ColonneEtat(libelle: 'Journal', valeur: (e) => e['journal']),
                ColonneEtat(libelle: 'Libellé', valeur: (e) => e['libelle']),
                ColonneEtat(libelle: 'Débit', droite: true, valeur: (e) => n(e['debit']) != 0 ? m(e['debit']) : '', somme: (e) => n(e['debit'])),
                ColonneEtat(libelle: 'Crédit', droite: true, valeur: (e) => n(e['credit']) != 0 ? m(e['credit']) : '', somme: (e) => n(e['credit'])),
                ColonneEtat(libelle: 'Solde', droite: true, valeur: (e) => m(e['soldeProgressif'])),
              ], lignes: rows)
            ],
            signatures: [signComptable]));
  }

  void _imprimerComplet(BuildContext ctx, ContexteEcran c) {
    final e = ecrituresExercice(c);
    final mouv = _mouvementes(c);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Grand livre général',
            sousTitre: 'Exercice ${exerciceChoisi(c)} — tous comptes mouvementés',
            cartouche: [
              ('Comptes mouvementés', nombre(mouv.length)),
              ('Écritures', nombre(e.length)),
              ('Total débit', money(e.fold<num>(0, (a, x) => a + n(x['debit'])))),
              ('Total crédit', money(e.fold<num>(0, (a, x) => a + n(x['credit'])))),
            ],
            blocs: [
              for (final cp in mouv) ...[
                BlocTexte(
                    '${cp['num']} — ${cp['libelle']}  (solde : ${m(cpaSoldeCompte(e, '${cp['num']}').solde)})',
                    gras: true),
                BlocTableau(TableauEtat(colonnes: [
                  ColonneEtat(libelle: 'Date', valeur: (x) => dateDe(x['date'])),
                  ColonneEtat(libelle: 'N° pièce', valeur: (x) => x['numero']),
                  ColonneEtat(libelle: 'Libellé', valeur: (x) => x['libelle']),
                  ColonneEtat(libelle: 'Débit', droite: true, valeur: (x) => n(x['debit']) != 0 ? m(x['debit']) : ''),
                  ColonneEtat(libelle: 'Crédit', droite: true, valeur: (x) => n(x['credit']) != 0 ? m(x['credit']) : ''),
                ], lignes: trierPar([for (final x in e) if (x['compte'] == cp['num']) x], (x) => x['date']).take(15).toList())),
              ]
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
        final compte = '${_compte!['compte'] ?? ''}';
        final rows = cpaGrandLivre(e, compte);
        final s = cpaSoldeCompte(e, compte);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            commande(_compte!, largeur: 512),
            BoutonSigh(libelle: 'Imprimer le grand livre', icone: LucideIcons.printer, onPressed: () => _imprimer(context, c, compte, rows)),
            BoutonSigh(
                libelle: 'Grand livre complet',
                icone: LucideIcons.bookOpen,
                variante: VarianteBouton.secondaire,
                onPressed: () => _imprimerComplet(context, c)),
          ])),
          const SizedBox(height: 16),
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Mouvements', valeur: nombre(rows.length), icone: LucideIcons.fileText),
            KpiSigh(libelle: 'Total débit', valeur: money(s.debit), icone: LucideIcons.arrowDownLeft, ton: TonSigh.attention),
            KpiSigh(libelle: 'Total crédit', valeur: money(s.credit), icone: LucideIcons.arrowUpRight, ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Solde',
                valeur: money(s.solde),
                indice: s.solde >= 0 ? 'Débiteur' : 'Créditeur',
                icone: LucideIcons.scale,
                ton: s.solde >= 0 ? TonSigh.navy : TonSigh.danger),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            key: ValueKey('gl-$compte'),
            titre: '$compte — ${cpaCompteLibelle(compte, comptes: c.magasin.collection('comptes').toutes)}',
            lignes: rows,
            nomExport: 'grand-livre-$compte',
            taillePage: 20,
            messageVide: 'Aucun mouvement sur ce compte.',
            colonnes: [
              colNumeroEcriture(),
              colDateEcriture(),
              colJournalEcriture(),
              const ColonneTableau(cle: 'libelle', libelle: 'Libellé'),
              const ColonneTableau(cle: 'piece', libelle: 'Pièce'),
              colDebitEcriture(),
              colCreditEcriture(),
              ColonneTableau(
                  cle: 'soldeProgressif',
                  libelle: 'Solde',
                  droite: true,
                  triable: false,
                  texte: (e) => m(e['soldeProgressif']),
                  rendu: (_, e) => Text(m(e['soldeProgressif']),
                      style: TextStyle(
                          color: n(e['soldeProgressif']) < 0 ? JetonsShell.danger600 : JetonsShell.navy900,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()]))),
            ],
          ),
        ]);
      },
    );
  }
}
