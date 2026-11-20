import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cpa_commun.dart';

/// `m12-journaux` — « Journaux comptables » : écran CALCULÉ. Un journal est la vue des écritures d'une nature donnée ; il ne se saisit pas — les
/// écritures se corrigent depuis la saisie comptable, seul endroit où l'équilibre débit / crédit est contrôlé (RG-10).
class EcranJournaux extends StatelessWidget with EcranMaquette {
  const EcranJournaux({super.key});

  @override
  String get titre => 'Journaux comptables';

  @override
  String get description =>
      'Journaux d’achats, ventes, caisse, banque, salaires, immobilisations et opérations diverses.';

  @override
  String get regle =>
      'Écran calculé : un journal est la vue des écritures d’une nature donnée. Il ne se saisit pas — les écritures se corrigent depuis la saisie comptable, seul endroit où l’équilibre débit / crédit est contrôlé (RG-10).';

  static Fiche _ligne(CpaLigneJournal j) => {
        'id': j.code,
        'code': j.code,
        'libelle': j.libelle,
        'contrepartie': j.contrepartie,
        'nb': j.nb,
        'debit': j.debit,
        'credit': j.credit,
        'equilibre': j.equilibre,
      };

  static List<Fiche> _mouvements(List<Fiche> e, Object? code, {bool desc = false}) =>
      trierPar([for (final x in e) if (x['journal'] == code) x], (x) => x['date'], descendant: desc);

  void _consulter(BuildContext context, ContexteEcran c, List<Fiche> e, Fiche j) {
    final sel = _mouvements(e, j['code'], desc: true);
    afficherTiroir<void>(context,
        titre: '${j['libelle']}',
        sousTitre: 'Journal ${j['code']} — ${sel.length} écriture(s)',
        largeurMax: 896,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(colonnes: 2, kpis: [
            KpiSigh(libelle: 'Total débit', valeur: money(j['debit']), icone: LucideIcons.arrowDownLeft, ton: TonSigh.attention),
            KpiSigh(libelle: 'Total crédit', valeur: money(j['credit']), icone: LucideIcons.arrowUpRight, ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          MiniTableauSigh(colonnes: [
            ColonneMini('N° pièce', (x) => '${x['numero']}', rendu: (x) => Text('${x['numero']}', style: mono)),
            ColonneMini('Date', (x) => dateDe(x['date'])),
            ColonneMini('Compte', (x) => '${x['compte']}', rendu: (x) => Text('${x['compte']}', style: mono)),
            ColonneMini('Libellé', (x) => '${x['libelle'] ?? ''}'),
            ColonneMini('Débit', (x) => n(x['debit']) != 0 ? m(x['debit']) : '—', droite: true),
            ColonneMini('Crédit', (x) => n(x['credit']) != 0 ? m(x['credit']) : '—', droite: true),
          ], lignes: sel.take(40).toList()),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer le journal',
                  icone: LucideIcons.printer,
                  onPressed: () => _imprimer(context, c, e, j)),
            ]);
  }

  void _imprimer(BuildContext context, ContexteEcran c, List<Fiche> e, Fiche j) {
    final sel = _mouvements(e, j['code']);
    final debit = n(j['debit']), credit = n(j['credit']);
    final eq = debit == credit;
    afficherApercu(
        context,
        pieceM9(c,
            titre: 'Journal comptable — ${j['libelle']}',
            sousTitre: 'Code journal ${j['code']} — exercice ${exerciceChoisi(c)}',
            cartouche: [
              ('Journal', '${j['code']} — ${j['libelle']}'),
              ('Écritures', nombre(sel.length)),
              ('Total débit', money(debit)),
              ('Total crédit', money(credit)),
              ('Équilibre', eq ? 'Équilibré' : 'Écart de ${money((debit - credit).abs())}'),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: [
              // Les totaux se REFONT depuis les écritures imprimées : un journal dont le pied est vide ne prouve plus son équilibre (RG-10).
              TableauEtat(libelleTotal: 'TOTAUX', colonnes: [
                ColonneEtat(libelle: 'N° pièce', valeur: (x) => x['numero']),
                ColonneEtat(libelle: 'Date', valeur: (x) => dateDe(x['date'])),
                ColonneEtat(libelle: 'Compte', valeur: (x) => x['compte']),
                ColonneEtat(libelle: 'Intitulé du compte', valeur: (x) => x['compteLibelle'] ?? cpaCompteLibelle(x['compte'])),
                ColonneEtat(libelle: 'Libellé de l’opération', valeur: (x) => x['libelle']),
                ColonneEtat(libelle: 'Débit', droite: true, valeur: (x) => n(x['debit']) != 0 ? m(x['debit']) : '', somme: (x) => n(x['debit'])),
                ColonneEtat(libelle: 'Crédit', droite: true, valeur: (x) => n(x['credit']) != 0 ? m(x['credit']) : '', somme: (x) => n(x['credit'])),
              ], lignes: sel)
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
        final lignes = [for (final j in cpaLignesJournaux(e)) _ligne(j)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Journaux ouverts', valeur: nombre(lignes.length), icone: LucideIcons.book),
            KpiSigh(libelle: 'Écritures totales', valeur: nombre(e.length), icone: LucideIcons.fileText, ton: TonSigh.info),
            KpiSigh(
                libelle: 'Total débit',
                valeur: money(e.fold<num>(0, (a, x) => a + n(x['debit']))),
                icone: LucideIcons.arrowDownLeft,
                ton: TonSigh.attention),
            KpiSigh(
                libelle: 'Total crédit',
                valeur: money(e.fold<num>(0, (a, x) => a + n(x['credit']))),
                icone: LucideIcons.arrowUpRight,
                ton: TonSigh.succes),
          ]),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Journaux comptables',
            lignes: lignes,
            nomExport: 'journaux',
            taillePage: 10,
            alClicLigne: (j) => _consulter(context, c, e, j),
            actionsLigne: (ctx, j) => [
              BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter le journal', onPressed: () => _consulter(context, c, e, j)),
              BoutonIcone(icone: LucideIcons.printer, libelle: 'Imprimer', onPressed: () => _imprimer(context, c, e, j)),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'code',
                  libelle: 'Code',
                  sansCoupure: true,
                  rendu: (_, j) => Text('${j['code']}', style: mono.copyWith(color: JetonsShell.navy800, fontWeight: FontWeight.w600))),
              const ColonneTableau(cle: 'libelle', libelle: 'Intitulé'),
              ColonneTableau(
                  cle: 'contrepartie',
                  libelle: 'Compte de contrepartie',
                  texte: (j) => '${j['contrepartie'] ?? 'Variable'}',
                  rendu: (_, j) => j['contrepartie'] != null
                      ? Text('${j['contrepartie']}', style: mono)
                      : const Text('Variable', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
              const ColonneTableau(cle: 'nb', libelle: 'Écritures', droite: true),
              ColonneTableau(cle: 'debit', libelle: 'Total débit', droite: true, texte: (j) => m(j['debit'])),
              ColonneTableau(cle: 'credit', libelle: 'Total crédit', droite: true, texte: (j) => m(j['credit'])),
              ColonneTableau(
                  cle: 'equilibre',
                  libelle: 'Équilibre',
                  texte: (j) => j['equilibre'] == true ? 'Équilibré' : 'Déséquilibré',
                  rendu: (_, j) => j['equilibre'] == true
                      ? const BadgeSigh('Équilibré', ton: TonSigh.succes)
                      : BadgeSigh('Écart ${m((n(j['debit']) - n(j['credit'])).abs())}', ton: TonSigh.danger)),
            ],
          ),
        ]);
      },
    );
  }
}
