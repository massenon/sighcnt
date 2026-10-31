import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-comptable` — « Tableau de bord — Comptabilité » : les écritures nées de la caisse arrivent en BROUILLON — la validation comptable reste un
/// geste humain. C'est donc la pile de brouillons qui attend le comptable. RG-10 : l'équilibre se lit, un écart se dit.
class EcranDashComptable extends StatelessWidget with EcranMaquette {
  const EcranDashComptable({super.key});

  @override
  String get titre => 'Tableau de bord — Comptabilité';

  @override
  String get description =>
      'Écritures SYSCOHADA, équilibre des journaux, créances, dettes et rapprochements bancaires.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['ecritures']),
      builder: (context, _) {
        final d = tbaComptable(ecritures: tbaActives(c, 'ecritures'));
        return TbaDash(
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m12-grand-livre', 'book-open', 'Grand livre', 'Par compte SYSCOHADA'),
              ('m12-balance', 'scale', 'Balance', 'Générale et âgée'),
              ('m12-banques', 'landmark', 'Rapprochements', 'Relevés bancaires'),
              ('m12-etats-financiers', 'file-spreadsheet', 'États financiers', 'Bilan et compte de résultat'),
            ]),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Dernières écritures',
                tbaMiniTableau([
                  ColonneMini('N°', (e) => '${e['numero'] ?? ''}', rendu: (e) => tbaMono(e['numero'])),
                  ColonneMini('Date', (e) => tbaDate(e['date'])),
                  ColonneMini('Journal', (e) => '${e['journal'] ?? ''}', rendu: (e) => BadgeSigh('${e['journal'] ?? ''}', ton: TonSigh.navy)),
                  ColonneMini('Compte', (e) => '${e['compte'] ?? ''}', rendu: (e) => tbaMono(e['compte'])),
                  ColonneMini('Libellé', (e) => '${e['libelle'] ?? ''}'),
                  ColonneMini('Débit', (e) => nombreOuZero(e['debit']) != 0 ? tbaMontant(e['debit']) : '—', droite: true),
                  ColonneMini('Crédit', (e) => nombreOuZero(e['credit']) != 0 ? tbaMontant(e['credit']) : '—', droite: true),
                ], d.dernieres),
                actions: [tbaLien(c, 'm12-ecritures', 'Toutes les écritures', 'arrow-right')],
                sansRemplissage: true),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Écritures par journal',
                  child: GraphiqueBarres(etiquettes: d.parJournal.etiquettes, series: [SerieGraphique('Écritures', d.parJournal.series.first.donnees)])),
              CarteSigh(
                  titre: 'Charges par centre de coûts',
                  child: GraphiqueAnneau(etiquettes: d.chargesParCentre.etiquettes, valeurs: d.chargesParCentre.series.first.donnees)),
            ),
          ],
        );
      },
    );
  }
}

const _parcours = [
  ParcoursTba('Valider les écritures du jour', 'file-check-2', 'Écritures', 'La caisse a posé des brouillons.', [
    EtapeTba('Relire les écritures en brouillon',
        ecran: 'm12-ecritures', detail: 'Chaque encaissement en pose une : 571 Caisse, 411 Clients, 706 Prestations.'),
    EtapeTba('Vérifier l’équilibre', ecran: 'm12-ecritures', detail: 'RG-10 — débit = crédit.'),
    EtapeTba('Valider', ecran: 'm12-ecritures', detail: 'C’est un geste humain : sans lui, la recette se ressaisirait à la main.'),
  ]),
  ParcoursTba('Déclarer et payer', 'siren', 'Échéances', 'Impôts, CNSS, CCIB.', [
    EtapeTba('Voir les échéances dues', ecran: 'm12-echeances', detail: 'Une échéance tombant un week-end est reportée, jamais avancée.'),
    EtapeTba('Déclarer puis payer', ecran: 'm12-echeances'),
    EtapeTba('Enregistrer la quittance', ecran: 'm12-echeances'),
  ]),
  ParcoursTba('Clôturer le mois', 'book-open', 'États', 'Arrêté mensuel.', [
    EtapeTba('Rapprochement bancaire', ecran: 'm12-banques'),
    EtapeTba('Balance et grand livre', ecran: 'm12-balance'),
    EtapeTba('États financiers', ecran: 'm12-etats-financiers'),
    EtapeTba('Compte rendu à la hiérarchie', poste: 'DAF'),
  ]),
];
