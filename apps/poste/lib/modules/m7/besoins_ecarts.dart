import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'besoins_commun.dart';

/// L'état des manquants imprimé : le total de la valeur est refait depuis les lignes.
PieceA4 pieceEcarts(List<Fiche> rows,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  return PieceA4(
    titre: 'État des écarts de livraison',
    sousTitre: 'Manquants à reporter sur les prochaines livraisons',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('Écarts constatés', nombre(rows.length)),
      ('Valeur totale', money(rows.fold<num>(0, (a, r) => a + n(r['valeur'])))),
      ('Date d’édition', dateFR(edite)),
      ('Établi par', utilisateur),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'N° BL', valeur: (r) => r['bl']),
        ColonneEtat(libelle: 'Fournisseur', valeur: (r) => r['fournisseur']),
        ColonneEtat(libelle: 'Article', valeur: (r) => r['produit']),
        ColonneEtat(libelle: 'Commandé', valeur: (r) => r['commande_qte'], droite: true),
        ColonneEtat(libelle: 'Livré', valeur: (r) => r['livree'], droite: true),
        ColonneEtat(libelle: 'Écart', valeur: (r) => r['ecart'], droite: true),
        ColonneEtat(
            libelle: 'Valeur',
            valeur: (r) => m(r['valeur']),
            droite: true,
            somme: (r) => n(r['valeur'])),
      ], lignes: rows)),
    ],
    signatures: const [
      Signature('Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri'),
      Signature('La Directrice Administrative', nom: directriceAdministrative),
    ],
  );
}

/// `m7-ecarts` — « Écarts de livraison » : la différence entre quantités commandées et reçues, lue sur les bordereaux « avec écart ». Écran en lecture
/// seule : l'écart se corrige en modifiant la réception correspondante. Limite de la maquette portée telle quelle (E76) : le report « automatique » sur la
/// livraison suivante est annoncé, aucun code ne le fait.
class EcranEcarts extends StatelessWidget with EcranMaquette {
  const EcranEcarts({super.key});

  @override
  String get titre => 'Écarts de livraison';

  @override
  String get description =>
      'Suivi des manquants entre commande et livraison, avec prise en compte automatique lors de la livraison suivante.';

  @override
  String get regle =>
      'Écran en lecture seule. Les écarts sont la différence entre quantités commandées et reçues : ils se corrigent en modifiant la réception correspondante.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('livraisons');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final r = registreEcarts(col.actives);
        final k = indicateursEcarts(r);
        final rows = [for (final l in r.lignes) l.toFiche()];
        final fournisseurs = ({for (final l in r.lignes) '${l.fournisseur}'}.toList()
          ..sort());
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Écarts constatés',
                    valeur: nombre(k.ecarts),
                    icone: LucideIcons.triangleAlert,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Livraisons concernées',
                    valeur: nombre(k.livraisons),
                    icone: LucideIcons.packageX,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Valeur des manquants',
                    valeur: money(k.valeur),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Fournisseurs concernés',
                    valeur: nombre(k.fournisseurs),
                    icone: LucideIcons.truck,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              const NoteSigh(
                  'Les manquants sont notifiés au fournisseur et reportés automatiquement sur la livraison suivante, conformément au processus de la clinique.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.repeat),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Écarts entre commande et livraison',
                lignes: rows,
                taillePage: 15,
                nomExport: 'ecarts-livraison',
                messageVide: 'Aucun écart de livraison constaté.',
                filtres: [
                  FiltreTableau(
                      nom: 'fournisseur',
                      libelle: 'Fournisseur',
                      options: [for (final f in fournisseurs) OptionChamp(f)]),
                ],
                actions: [
                  BoutonSigh(
                      libelle: 'Éditer l’état des manquants',
                      icone: LucideIcons.printer,
                      taille: TailleBouton.sm,
                      onPressed: () => imprimerPiece(
                          context,
                          (c) => pieceEcarts(rows,
                              utilisateur: c.utilisateur,
                              edite: c.aujourdhui,
                              reference: refEtat(c)))),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'bl',
                      libelle: 'N° BL',
                      sansCoupure: true,
                      texte: (x) => '${x['bl']}',
                      rendu: (_, x) => refMono(x['bl'], gras: false)),
                  ColonneTableau(
                      cle: 'commande',
                      libelle: 'Commande',
                      sansCoupure: true,
                      texte: (x) => '${x['commande'] ?? ''}',
                      rendu: (_, x) => refMono(x['commande'],
                          gras: false, couleur: JetonsShell.slate500)),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (x) => dateDe(x['date'])),
                  const ColonneTableau(cle: 'fournisseur', libelle: 'Fournisseur'),
                  const ColonneTableau(cle: 'produit', libelle: 'Article'),
                  const ColonneTableau(
                      cle: 'commande_qte', libelle: 'Commandé', droite: true),
                  const ColonneTableau(cle: 'livree', libelle: 'Livré', droite: true),
                  ColonneTableau(
                      cle: 'ecart',
                      libelle: 'Écart',
                      droite: true,
                      texte: (x) => '${x['ecart']}',
                      rendu: (_, x) => Text('${x['ecart']}',
                          style: const TextStyle(
                              color: JetonsShell.danger600,
                              fontSize: 14,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'valeur',
                      libelle: 'Valeur',
                      droite: true,
                      texte: (x) => m(x['valeur'])),
                ],
              ),
            ]);
      },
    );
  }
}
