import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'tba_commun.dart';

/// `dash-pharmacien` — « Tableau de bord — Pharmacie » : le compte Pharmacie est FERMÉ depuis le 24/08/2026 (la pharmacie est tenue par la caisse) ;
/// le premier regard le DIT au lieu de faire comme si de rien n'était. Les ordonnances à délivrer, les ruptures et les péremptions (FEFO, RG-05) restent.
class EcranDashPharmacien extends StatelessWidget with EcranMaquette {
  const EcranDashPharmacien({super.key});

  @override
  String get titre => 'Tableau de bord — Pharmacie';

  @override
  String get description =>
      'Stock de détail, dispensation, alertes de rupture et suivi des péremptions selon le principe FEFO.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: tbaEcoute(c, ['produits', 'lots', 'mouvements', 'taches']),
      builder: (context, _) {
        final produits = tbaActives(c, 'produits'), lots = tbaActives(c, 'lots');
        List<num> mois(List<Fiche> rows) => parMois(rows, 'date', champValeur: 'quantite', ref: c.aujourdhui).valeurs;
        final etiquettes = parMois(const [], 'date', ref: c.aujourdhui).etiquettes;
        final d = tbaPharmacien(produits: produits, lots: lots, mouvements: tbaActives(c, 'mouvements'), parMoisQuantite: mois);
        return TbaDash(
          alerte: tbaFileDuPoste(c, 'dispensation',
              titre: 'Ordonnances à délivrer',
              vide: 'Aucune ordonnance en attente de délivrance.',
              action: 'Ouvrir la dispensation',
              ecran: 'm6-dispensation',
              alertes: tbaBandeauAlertes(produits, lots)),
          premier: d.premier,
          rapides: [
            tbaAccesRapides(c, const [
              ('m6-dispensation', 'hand-heart', 'Dispensation', 'Servir une ordonnance'),
              ('m6-lots', 'calendar-x', 'Lots & péremptions', 'Application du FEFO'),
              ('m6-transferts', 'arrow-left-right', 'Transfert gros → détail', 'Réapprovisionner la pharmacie'),
              ('m6-inventaire', 'clipboard-check', 'Inventaire', 'Physique contre théorique'),
            ]),
          ],
          kpis: d.kpis,
          sections: [
            tbaCarte(
                'Produits à réapprovisionner en priorité',
                d.aReapprovisionner.isEmpty
                    ? const VideSigh('Aucun produit sous le seuil d’alerte.', icone: LucideIcons.circleCheck)
                    : tbaMiniTableau([
                        ColonneMini('Code', (p) => '${p['code'] ?? ''}', rendu: (p) => tbaMono(p['code'])),
                        ColonneMini('Désignation', (p) => '${p['designation'] ?? ''}'),
                        ColonneMini('Stock', (p) => '${p['stock'] ?? ''}', droite: true),
                        ColonneMini('Seuil', (p) => '${p['seuilAlerte'] ?? ''}', droite: true),
                        ColonneMini('Emplacement', (p) => '${p['emplacement'] ?? ''}'),
                        ColonneMini('État', (p) => '',
                            rendu: (p) => nombreOuZero(p['stock']) == 0
                                ? const BadgeSigh('Rupture', ton: TonSigh.danger)
                                : const BadgeSigh('Critique', ton: TonSigh.attention)),
                      ], d.aReapprovisionner),
                actions: [tbaLien(c, 'm7-besoins', 'Exprimer un besoin', 'clipboard-list')],
                sansRemplissage: d.aReapprovisionner.isNotEmpty),
            tbaDeuxCartes(
              CarteSigh(
                  titre: 'Mouvements de stock (12 mois)',
                  child: GraphiqueBarres(etiquettes: etiquettes, series: [
                    SerieGraphique('Entrées', d.entrees, couleur: JetonsShell.success500),
                    SerieGraphique('Sorties', d.sorties, couleur: JetonsShell.navy900),
                  ])),
              CarteSigh(
                  titre: 'Péremptions à venir',
                  child: GraphiqueAnneau(
                      etiquettes: const ['Périmés', 'Moins de 90 jours', 'Au-delà de 90 jours'],
                      valeurs: d.peremptions,
                      couleurs: const [JetonsShell.danger500, JetonsShell.warning500, JetonsShell.success500])),
            ),
          ],
        );
      },
    );
  }
}
