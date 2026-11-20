import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-caissier` — « Tableau de bord — Caisse » : la file de l'encaissement. Le caissier ne choisit pas ce qu'il fait — la file le lui dit ; la
/// pharmacie lui étant rattachée (décision du 24/08/2026), le parcours « Délivrer un médicament » est le sien.
class EcranDashCaissier extends StatelessWidget with EcranMaquette {
  const EcranDashCaissier({super.key});

  @override
  String get titre => 'Tableau de bord — Caisse';

  @override
  String get description =>
      'Encaissements du jour, factures à régler, reliquats et répartition des modes de paiement.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['taches', 'factures']),
      builder: (context, _) {
        final d = tbaCaissier(taches: tbaActives(c, 'taches'), factures: tbaActives(c, 'factures'), auj: c.aujourdhui);
        return TbaDash(
          alerte: tbaFileDuPoste(c, 'encaissement',
              titre: 'Prescriptions à encaisser',
              vide: 'Aucune prescription en attente de règlement.',
              action: 'Ouvrir la caisse',
              ecran: 'm8-caisse'),
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m8-facturation', 'file-plus-2', 'Nouvelle facture', 'Consultation, acte, produit'),
              ('m8-paiements', 'banknote', 'Encaisser un paiement', 'Espèces, mobile money, carte'),
              ('m8-reliquats', 'coins', 'Reliquats', 'Restes à recouvrer'),
              ('m8-caisse', 'calculator', 'État de caisse', 'Arrêté journalier à imprimer'),
            ]),
            tbaCarte('Ce que vous faites ici — vos parcours', const ParcoursSigh(_parcours)),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Dernières factures',
                tbaMiniTableau([
                  ColonneMini('N° facture', (f) => '${f['numero'] ?? ''}', rendu: (f) => tbaMono(f['numero'])),
                  ColonneMini('Patient', (f) => '${f['patient'] ?? ''}'),
                  ColonneMini('Type', (f) => '${f['type'] ?? ''}'),
                  ColonneMini('Montant', (f) => tbaMontant(f['montantTTC']), droite: true),
                  ColonneMini('Payé', (f) => tbaMontant(f['montantPaye']), droite: true),
                  ColonneMini('Reste', (f) => nombreOuZero(f['reliquat']) > 0 ? tbaMontant(f['reliquat']) : '—',
                      droite: true,
                      rendu: (f) => nombreOuZero(f['reliquat']) > 0
                          ? Text(tbaMontant(f['reliquat']),
                              style: const TextStyle(color: JetonsShell.danger600, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))
                          : const Text('—', style: TextStyle(color: JetonsShell.slate700, fontSize: 14))),
                  ColonneMini('Statut', (f) => '', rendu: (f) => statutBadge(f['statutPaiement'])),
                ], d.dernieres),
                actions: [
                  // Nouvelle facture est une ÉCRITURE : la commande n'existe que pour un profil qui peut ouvrir la facturation.
                  if (c.ouvre?.call('m8-facturation') ?? true) tbaLien(c, 'm8-facturation', 'Nouvelle facture', 'plus', primaire: true),
                  tbaLien(c, 'm8-caisse', 'État de caisse', 'printer'),
                ],
                sansRemplissage: true),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Encaissements par mode de paiement',
                  child: GraphiqueBarres(
                      horizontal: true,
                      hauteur: 260,
                      etiquettes: d.parMode.etiquettes,
                      series: [SerieGraphique('Montant encaissé', d.parMode.series.first.donnees)])),
              CarteSigh(
                  titre: 'Recettes quotidiennes du mois',
                  child: GraphiqueLigne(
                      etiquettes: d.recettesQuotidiennes.etiquettes,
                      series: [SerieGraphique('Encaissé', d.recettesQuotidiennes.series.first.donnees, couleur: JetonsShell.success500)])),
            ),
          ],
        );
      },
    );
  }
}

const _parcours = [
  ParcoursTba('Encaisser une prescription', 'coins', 'Encaisser', 'Le patient se présente avec son ordonnance.', [
    EtapeTba('Cocher les prestations réglées',
        ecran: 'm8-caisse', detail: 'Le patient peut ne payer qu’une partie : cochez CE QU’IL RÈGLE.'),
    EtapeTba('Imprimer le reçu détaillé', ecran: 'm8-caisse', detail: 'Il NOMME les prestations réglées et celles qui restent dues.'),
    EtapeTba('Le laboratoire est débloqué', poste: 'Laboratoire', detail: 'Exactement les examens payés, pas les autres.'),
    EtapeTba('La pharmacie est débloquée', poste: 'Pharmacie'),
    EtapeTba('L’écriture comptable est posée', poste: 'Comptabilité'),
  ]),
  ParcoursTba('Le patient revient payer le reste', 'wallet', 'Reprendre', 'Il avait réglé une partie.', [
    EtapeTba('Retrouver sa pièce du jour',
        ecran: 'm8-caisse', detail: 'Le registre dit ce qui est réglé et ce qui reste, prestation par prestation.'),
    EtapeTba('Encaisser le reste', ecran: 'm8-caisse'),
    EtapeTba('Réimprimer le reçu', ecran: 'm8-caisse'),
  ]),
  ParcoursTba('Délivrer un médicament', 'pill', 'Pharmacie', 'La pharmacie est rattachée à votre compte.', [
    EtapeTba('Voie orale — le patient emporte', ecran: 'm6-pharmacie-externe'),
    EtapeTba('Urgence — vers la salle de soins',
        ecran: 'm6-pharmacie-interne', detail: 'Le produit ne quitte pas la clinique : c’est le soignant qui l’administre.'),
    EtapeTba('Le stock est décrémenté avec justificatif', detail: 'RG-03.'),
  ]),
  ParcoursTba('Arrêter la caisse', 'calculator', 'Arrêté du jour', 'En fin de journée.', [
    EtapeTba('Éditer l’arrêté de caisse', ecran: 'm8-caisse'),
    EtapeTba('Vérifier le point des ventes du jour',
        ecran: 'm6-point-ventes', detail: 'Le détail par client : c’est là qu’un écart de caisse se retrouve.'),
    EtapeTba('Remettre à la Direction', poste: 'DAF'),
  ]),
];
