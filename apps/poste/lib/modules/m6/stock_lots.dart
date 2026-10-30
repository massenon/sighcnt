import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'stock_commun.dart';
import 'stock_crud.dart';

const _libellesStatutLot = {
  'perime': 'Périmé',
  'alerte': 'Péremption proche',
  'actif': 'Normal'
};

/// `m6-lots` — « Lots & péremptions (FEFO) » : suivi des lots par date de péremption (RG-05), ordre de sortie « premier périmé, premier sorti »,
/// état des produits périmés (retour aux fournisseurs habilités, perte valorisée). L'échéance et le statut se calculent À LA DATE DU JOUR (écart E17/E19
/// de `ECARTS-MAQUETTE.md`) ; archiver ne supprime jamais un lot (RG-14).
class EcranLotsStock extends StatelessWidget with EcranMaquette {
  const EcranLotsStock({super.key});

  @override
  String get titre => 'Lots & péremptions (FEFO)';

  @override
  String get description =>
      'Suivi des lots par date de péremption, application du principe « premier périmé, premier sorti ».';

  @override
  String get regle =>
      'RG-05 — le rangement applique le principe FEFO (premier périmé, premier sorti). Les alertes sont déclenchées automatiquement $delaiPreavisPeremption jours avant échéance. Les produits périmés sont retournés aux fournisseurs habilités (CAME, SoBAPS) et la perte est valorisée en comptabilité.';

  @override
  List<Widget> actionsEntete(BuildContext context) => [
        BoutonSigh(
            libelle: 'État des produits périmés',
            icone: LucideIcons.printer,
            onPressed: () => _imprimerPerimes(context)),
      ];

  static void _imprimerPerimes(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final auj = c.aujourdhui;
    final prods = produitsActifs(c.magasin);
    final perimes = trierStable([
      for (final l in lotsActifs(c.magasin))
        if (statutDuLot(l, auj) == 'perime') l
    ], (l) => l['datePeremption']);
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'État des produits périmés',
            sousTitre:
                'Situation au ${dateFR(auj)} — retour fournisseur et valorisation de la perte',
            cartouche: [
              ('Lots concernés', nombre(perimes.length)),
              (
                'Unités totales',
                nombre(sommeChamp(perimes, 'quantiteRestante'))
              ),
              ('Date d’édition', dateFR(auj)),
              ('Établi par', c.utilisateur),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Produit', valeur: (l) => l['produit']),
                ColonneEtat(libelle: 'N° lot', valeur: (l) => l['numeroLot']),
                ColonneEtat(
                    libelle: 'Péremption',
                    valeur: (l) => dateFiche(l['datePeremption'])),
                ColonneEtat(
                    libelle: 'Quantité',
                    valeur: (l) => l['quantiteRestante'],
                    droite: true),
                ColonneEtat(
                    libelle: 'Valeur perdue',
                    valeur: (l) => mnt(valeurPerdue(l, prods)),
                    droite: true,
                    somme: (l) => valeurPerdue(l, prods)),
                ColonneEtat(
                    libelle: 'Emplacement', valeur: (l) => l['emplacement']),
              ], lignes: perimes)),
            ],
            signatures: const [
              Signature('Le Pharmacien', nom: pharmacien),
              Signature('Le Gestionnaire de Stock', nom: gestionnaireStock),
              Signature('La Directrice Administrative',
                  nom: directriceAdministrativeStock),
            ],
            reference:
                PieceA4.reference_(auj, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: auj));
  }

  static void _imprimerLot(BuildContext ctx, Fiche l) {
    final c = ContexteEcran.of(ctx);
    final auj = c.aujourdhui;
    final st = statutDuLot(l, auj);
    afficherApercu(
        ctx,
        PieceA4(
            titre: 'Fiche de lot',
            sousTitre: '${l['numeroLot']} — ${l['produit']}',
            cartouche: [
              ('Produit', '${l['produit'] ?? ''}'),
              ('N° lot', '${l['numeroLot'] ?? ''}'),
              ('Date de péremption', dateFiche(l['datePeremption'])),
              ('Quantité restante', nombre(l['quantiteRestante'])),
              ('Emplacement', '${l['emplacement'] ?? ''}'),
              (
                'État',
                st == 'perime'
                    ? 'PÉRIMÉ'
                    : (st == 'alerte' ? 'Péremption proche' : 'Valide')
              ),
            ],
            blocs: [
              BlocTexte(st == 'perime'
                  ? 'Ce lot est périmé. Il doit être retiré de la vente, retourné au fournisseur habilité (CAME ou SoBAPS) et la perte valorisée en comptabilité.'
                  : 'Ce lot doit être servi selon le principe FEFO (premier périmé, premier sorti).'),
            ],
            signatures: const [
              Signature('Le Pharmacien', nom: pharmacien),
              Signature('Le Gestionnaire de Stock', nom: gestionnaireStock),
            ],
            reference:
                PieceA4.reference_(auj, ImpressionPoste.prochainNumero()),
            utilisateur: c.utilisateur,
            edite: auj));
  }

  Widget _detail(BuildContext ctx, Fiche l) {
    final auj = ContexteEcran.of(ctx).aujourdhui;
    final j = joursAvantPeremption(auj, l['datePeremption']);
    return DescListeSigh([
      ('N° lot', Text('${l['numeroLot'] ?? ''}', style: typographieMono)),
      ('Produit', '${l['produit'] ?? ''}'),
      ('Péremption', dateFiche(l['datePeremption'])),
      ('Échéance', texteEcheance(j)),
      ('Quantité', nombre(l['quantiteRestante'])),
      ('Emplacement', '${l['emplacement'] ?? ''}'),
      ('État FEFO', _libellesStatutLot[statutDuLot(l, auj)]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final auj = c.aujourdhui;
    final cl = c.magasin.collection('lots');
    return ListenableBuilder(
      listenable: c.magasin.collection('produits'),
      builder: (context, _) => CrudStock(
        collection: cl,
        entite: 'lot',
        entiteP: 'lots',
        prefixeId: 'LOT',
        triInitial: 'datePeremption',
        colonnes: [
          ColonneTableau(
              cle: 'numeroLot',
              libelle: 'N° lot',
              sansCoupure: true,
              texte: (l) => '${l['numeroLot'] ?? ''}',
              rendu: (_, l) =>
                  Text('${l['numeroLot'] ?? ''}', style: typographieMono)),
          const ColonneTableau(cle: 'produit', libelle: 'Produit'),
          ColonneTableau(
              cle: 'datePeremption',
              libelle: 'Péremption',
              sansCoupure: true,
              texte: (l) => dateFiche(l['datePeremption']),
              valeur: (l) => l['datePeremption']),
          ColonneTableau(
              cle: 'restant',
              libelle: 'Échéance',
              droite: true,
              valeur: (l) => joursAvantPeremption(auj, l['datePeremption']),
              texte: (l) {
                final j = joursAvantPeremption(auj, l['datePeremption']);
                return j == null ? '—' : '$j j';
              },
              rendu: (_, l) {
                final j = joursAvantPeremption(auj, l['datePeremption']);
                return badgeEcheance(j, texteEcheance(j));
              }),
          ColonneTableau(
              cle: 'quantiteRestante',
              libelle: 'Quantité',
              droite: true,
              texte: (l) => '${l['quantiteRestante'] ?? ''}',
              valeur: (l) => l['quantiteRestante']),
          const ColonneTableau(cle: 'emplacement', libelle: 'Emplacement'),
          ColonneTableau(
              cle: 'statut2',
              libelle: 'État FEFO',
              valeur: (l) => statutDuLot(l, auj),
              texte: (l) => _libellesStatutLot[statutDuLot(l, auj)]!,
              rendu: (_, l) {
                final s = statutDuLot(l, auj);
                return statutBadge(s == 'actif' ? 'normal' : s);
              }),
        ],
        filtres: [
          FiltreTableau(
              nom: 'statut',
              libelle: 'État',
              options: const [
                OptionChamp('perime', 'Périmés'),
                OptionChamp('alerte', 'Péremption proche'),
                OptionChamp('actif', 'Valides'),
              ],
              correspond: (l, v) => statutDuLot(l, auj) == v),
        ],
        kpis: (ctx, rows) {
          final st = {for (final l in rows) l: statutDuLot(l, auj)};
          final perimes = rows.where((l) => st[l] == 'perime').toList();
          return [
            KpiSigh(
                libelle: 'Lots suivis',
                valeur: nombre(rows.length),
                icone: LucideIcons.boxes),
            KpiSigh(
                libelle: 'Périmés',
                valeur: nombre(perimes.length),
                icone: LucideIcons.calendarX,
                ton: TonSigh.danger,
                indice:
                    '${nombre(sommeChamp(perimes, 'quantiteRestante'))} unités à retourner'),
            KpiSigh(
                libelle: 'Péremption sous $delaiPreavisPeremption j',
                valeur: nombre(rows.where((l) => st[l] == 'alerte').length),
                icone: LucideIcons.clock,
                ton: TonSigh.attention,
                indice: 'Prioriser en sortie (FEFO)'),
            KpiSigh(
                libelle: 'Lots valides',
                valeur: nombre(rows.where((l) => st[l] == 'actif').length),
                icone: LucideIcons.circleCheck,
                ton: TonSigh.succes),
          ];
        },
        champs: (m) => [
          ChampDef(
              nom: 'produitId',
              libelle: 'Produit',
              type: TypeChamp.select,
              requis: true,
              col: ColChamp.plein,
              options: [
                for (final p
                    in trierStable(produitsActifs(m), (p) => p['designation']))
                  OptionChamp('${p['id']}', '${p['designation']}')
              ]),
          const ChampDef(
              nom: 'numeroLot', libelle: 'Numéro de lot', requis: true),
          const ChampDef(
              nom: 'datePeremption',
              libelle: 'Date de péremption',
              type: TypeChamp.date,
              requis: true),
          const ChampDef(
              nom: 'quantiteRestante',
              libelle: 'Quantité restante',
              type: TypeChamp.nombre,
              requis: true),
          const ChampDef(
              nom: 'emplacement',
              libelle: 'Emplacement (rayon / casier)',
              col: ColChamp.plein),
        ],
        valeursInitiales: () => const {},
        transformer: (ctx, v) => transformerLot(
            v, ContexteEcran.of(ctx).aujourdhui, produitsActifs(c.magasin)),
        detail: _detail,
        titreDetail: (l) => '${l['numeroLot']}',
        sousTitreDetail: (l) => '${l['produit']}',
        etat: _imprimerLot,
        ongletsSup: (ctx) => [
          OngletDef(
              id: 'fefo',
              libelle: 'Ordre de sortie FEFO',
              construire: (_) {
                final actifs = ordreFefo(cl.actives);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const NoteSigh(
                          'Les lots sont présentés dans l’ordre imposé par le principe FEFO : le lot dont la date de péremption est la plus proche doit être servi en premier.'),
                      const SizedBox(height: 12),
                      TableauSigh(
                        lignes: actifs,
                        taillePage: 20,
                        nomExport: 'ordre-fefo',
                        colonnes: [
                          ColonneTableau(
                              cle: 'rang',
                              libelle: 'Rang',
                              droite: true,
                              triable: false,
                              texte: (l) => '${actifs.indexOf(l) + 1}',
                              rendu: (_, l) => cellule(
                                  '${actifs.indexOf(l) + 1}',
                                  droite: true)),
                          const ColonneTableau(
                              cle: 'produit', libelle: 'Produit'),
                          ColonneTableau(
                              cle: 'numeroLot',
                              libelle: 'N° lot',
                              rendu: (_, l) => Text('${l['numeroLot'] ?? ''}',
                                  style: typographieMono),
                              texte: (l) => '${l['numeroLot'] ?? ''}'),
                          ColonneTableau(
                              cle: 'datePeremption',
                              libelle: 'Péremption',
                              texte: (l) => dateFiche(l['datePeremption']),
                              valeur: (l) => l['datePeremption']),
                          ColonneTableau(
                              cle: 'quantiteRestante',
                              libelle: 'Quantité',
                              droite: true,
                              texte: (l) => '${l['quantiteRestante'] ?? ''}'),
                          const ColonneTableau(
                              cle: 'emplacement', libelle: 'Emplacement'),
                        ],
                      ),
                    ]);
              }),
        ],
      ),
    );
  }
}
