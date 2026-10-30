import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Éléments communs aux écrans de stock de M6 (`stock_*.dart`) : cellules, colonnes, fiche produit, état imprimé. Les RÈGLES (état du stock, seuils,
/// échéances, FEFO, valeur au CUMP) sont dans `packages/domaine/lib/src/stock/` ; ce fichier ne fait que les mettre en page.

const typographieMono = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.navy800,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600);

/// Les noms qui signent les états de stock dans la maquette (`m6-stock.js`), repris tels quels.
const gestionnaireStock = 'MAMAN Zoukanéri';
const directriceAdministrative = 'TAKI Alimatou';
const pharmacien = 'DIEYABIDI Aïssatou';

num qte(Object? v) => nombreOuZero(v);
String mnt(Object? v) => money(v, avecDevise: false);
String dateFiche(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Libellé du badge d'un état du stock (`U.statut`) : rupture, critique, normal.
String libelleEtat(String etat) => statutsMetier[etat]?.$1 ?? etat;

Widget badgeEtat(String etat) => statutBadge(etat);

/// Cellule de quantité : rouge à zéro, orange sous le seuil (`colStock`). Sans seuil fixé, seul zéro est signalé.
Widget cellule(String texte,
        {Color couleur = JetonsShell.slate700,
        FontWeight poids = FontWeight.w400,
        bool droite = false}) =>
    Text(texte,
        textAlign: droite ? TextAlign.right : TextAlign.left,
        style: TextStyle(
            color: couleur,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: poids,
            fontFeatures: const [FontFeature.tabularFigures()]));

ColonneTableau colCode() => ColonneTableau(
      cle: 'code',
      libelle: 'Code',
      sansCoupure: true,
      texte: (p) => '${p['code'] ?? ''}',
      rendu: (_, p) => Text('${p['code'] ?? ''}', style: typographieMono),
    );

ColonneTableau colDesignation() => ColonneTableau(
      cle: 'designation',
      libelle: 'Désignation',
      texte: (p) =>
          '${p['designation'] ?? ''} ${libelleCategorie(p['categorie'])} ${p['unite'] ?? ''}',
      rendu: (_, p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${p['designation'] ?? ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: JetonsShell.slate800,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500)),
            Text('${libelleCategorie(p['categorie'])} — ${p['unite'] ?? ''}',
                style: const TextStyle(
                    color: JetonsShell.slate400,
                    fontSize: 12,
                    height: 16 / 12)),
          ]),
    );

ColonneTableau colStock(String cle, String libelle) => ColonneTableau(
      cle: cle,
      libelle: libelle,
      droite: true,
      texte: (p) => nombre(p[cle]),
      valeur: (p) => nombreOuZero(p[cle]),
      rendu: (_, p) {
        final v = qte(p[cle]);
        final couleur = v == 0
            ? JetonsShell.danger600
            : (sousSeuil(v, p['seuilAlerte'])
                ? JetonsShell.warning600
                : JetonsShell.slate700);
        return cellule(nombre(p[cle]),
            couleur: couleur,
            poids: couleur == JetonsShell.slate700
                ? FontWeight.w400
                : FontWeight.w600,
            droite: true);
      },
    );

/// Le seuil d'alerte : un seuil NON FIXÉ s'affiche « — » (jamais un zéro, qui est un seuil).
ColonneTableau colSeuil() => ColonneTableau(
      cle: 'seuilAlerte',
      libelle: 'Seuil',
      droite: true,
      texte: (p) => seuilFixe(p['seuilAlerte']) ? '${p['seuilAlerte']}' : '—',
      valeur: (p) =>
          seuilFixe(p['seuilAlerte']) ? nombreOuZero(p['seuilAlerte']) : null,
      rendu: (_, p) => cellule(
          seuilFixe(p['seuilAlerte']) ? '${p['seuilAlerte']}' : '—',
          droite: true),
    );

ColonneTableau colMontant(String cle, String libelle) => ColonneTableau(
      cle: cle,
      libelle: libelle,
      droite: true,
      texte: (p) => mnt(p[cle]),
      valeur: (p) => nombreOuZero(p[cle]),
      rendu: (_, p) => cellule(mnt(p[cle]), droite: true),
    );

ColonneTableau colEtat() => ColonneTableau(
      cle: 'etat',
      libelle: 'État',
      valeur: (p) => etatStock(p['stock'], p['seuilAlerte']),
      texte: (p) => libelleEtat(etatStock(p['stock'], p['seuilAlerte'])),
      rendu: (_, p) => badgeEtat(etatStock(p['stock'], p['seuilAlerte'])),
    );

List<OptionChamp> optionsCategories() =>
    [for (final c in categoriesProduit) OptionChamp(c.id, c.label)];

/// Le journal des produits et des lots n'a qu'un seul lecteur : l'écran. Il lit toujours les fiches ACTIVES (RG-14 : archiver, jamais supprimer).
List<Fiche> produitsActifs(Magasin m) => m.collection('produits').actives;
List<Fiche> lotsActifs(Magasin m) => m.collection('lots').actives;
List<Fiche> mouvementsActifs(Magasin m) => m.collection('mouvements').actives;

/// Statut d'un lot À LA DATE DU JOUR (écart E19) : `perime`, `alerte` ou `actif`.
String statutDuLot(Fiche l, DateTime auj) =>
    statutLot(joursAvantPeremption(auj, l['datePeremption']));

TonSigh tonDeBadge(String badge) => switch (badge) {
      'success' => TonSigh.succes,
      'navy' => TonSigh.navy,
      'info' => TonSigh.info,
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      _ => TonSigh.neutre,
    };

Widget badgeEcheance(int? jours, String texte) {
  final teinte = teinteEcheance(jours);
  if (teinte == 'neutre') {
    return cellule(texte, couleur: JetonsShell.slate600, droite: true);
  }
  return BadgeSigh(texte,
      ton: teinte == 'danger' ? TonSigh.danger : TonSigh.attention);
}

/// Bandeau des articles dont le seuil n'a pas été fixé : sans seuil, aucune alerte n'est possible (hors rupture), et un seuil absent n'est PAS un
/// seuil de zéro. Rien n'est affiché quand tous les seuils sont fixés.
Widget? noteSansSeuil(Iterable<Fiche> produits) {
  final sans = sansSeuilFixe(produits).toList();
  if (sans.isEmpty) return null;
  final noms = sans.take(5).map((p) => '${p['designation']}').join(', ');
  return NoteSigh(
      '${sans.length} article(s) sans seuil d’alerte fixé — aucune alerte de seuil n’est possible pour eux (seule la rupture est signalée) : $noms${sans.length > 5 ? '…' : ''}. Le seuil se fixe dans le référentiel produits.',
      ton: TonSigh.attention,
      icone: LucideIcons.triangleAlert);
}

PieceA4 _piece(BuildContext ctx,
    {required String titre,
    required String sousTitre,
    required List<(String, String)> cartouche,
    required List<BlocPiece> blocs,
    required List<Signature> signatures}) {
  final c = ContexteEcran.of(ctx);
  return PieceA4(
      titre: titre,
      sousTitre: sousTitre,
      cartouche: cartouche,
      blocs: blocs,
      signatures: signatures,
      reference:
          PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui);
}

/// `etat` du référentiel produits : la fiche article, avec ses lots classés FEFO.
Future<void> imprimerFicheArticle(BuildContext ctx, Fiche p) {
  final lots = trierStable([
    for (final l in lotsActifs(ContexteEcran.of(ctx).magasin))
      if (l['produitId'] == p['id']) l
  ], (l) => l['datePeremption']);
  return afficherApercu(
      ctx,
      _piece(ctx,
          titre: 'Fiche article',
          sousTitre: '${p['code']} — ${p['designation']}',
          cartouche: [
            ('Code', '${p['code'] ?? ''}'),
            ('Désignation', '${p['designation'] ?? ''}'),
            ('Catégorie', libelleCategorie(p['categorie'])),
            ('Unité', '${p['unite'] ?? ''}'),
            ('Emplacement', '${p['emplacement'] ?? ''}'),
            ('Fournisseur', '${p['fournisseur'] ?? ''}'),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Rubrique', valeur: (r) => r['k']),
              ColonneEtat(
                  libelle: 'Valeur', valeur: (r) => r['v'], droite: true),
            ], lignes: [
              {'k': 'Prix d’achat', 'v': mnt(p['prixAchat'])},
              {'k': 'Prix de vente', 'v': mnt(p['prixVente'])},
              {'k': 'Coût unitaire moyen pondéré (CUMP)', 'v': mnt(p['cump'])},
              {'k': 'Stock gros', 'v': nombre(p['stockGros'])},
              {'k': 'Stock détail', 'v': nombre(p['stockDetail'])},
              {'k': 'Stock total', 'v': nombre(p['stock'])},
              {
                'k': 'Seuil d’alerte',
                'v': seuilFixe(p['seuilAlerte'])
                    ? nombre(p['seuilAlerte'])
                    : 'Non fixé'
              },
              {
                'k': 'Valeur du stock',
                'v': mnt(qte(p['stock']) * qte(p['cump']))
              },
            ])),
            if (lots.isNotEmpty)
              BlocTableau(
                  TableauEtat(colonnes: [
                    ColonneEtat(
                        libelle: 'N° lot', valeur: (l) => l['numeroLot']),
                    ColonneEtat(
                        libelle: 'Péremption',
                        valeur: (l) => dateFiche(l['datePeremption'])),
                    ColonneEtat(
                        libelle: 'Quantité restante',
                        valeur: (l) => l['quantiteRestante'],
                        droite: true),
                    ColonneEtat(
                        libelle: 'Emplacement',
                        valeur: (l) => l['emplacement']),
                  ], lignes: lots),
                  titre: 'Lots en stock (classement FEFO)'),
          ],
          signatures: const [
            Signature('Le Gestionnaire de Stock', nom: gestionnaireStock)
          ]));
}

/// Détail d'un produit (`detailProduit`) : deux KPI, puis trois onglets — fiche, lots (FEFO), mouvements.
Widget detailProduit(BuildContext ctx, Fiche p) {
  final c = ContexteEcran.of(ctx);
  final auj = c.aujourdhui;
  final lots = trierStable([
    for (final l in lotsActifs(c.magasin))
      if (l['produitId'] == p['id']) l
  ], (l) => l['datePeremption']);
  final mvts = trierStable([
    for (final m in mouvementsActifs(c.magasin))
      if (m['produitId'] == p['id']) m
  ], (m) => m['date'], descendant: true);
  final etat = etatStock(p['stock'], p['seuilAlerte']);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    KpiGrilleSigh(colonnes: 2, kpis: [
      KpiSigh(
          libelle: 'Stock total',
          valeur: '${nombre(p['stock'])} ${p['unite'] ?? ''}',
          icone: LucideIcons.package,
          ton: etat == 'normal' ? TonSigh.succes : TonSigh.danger),
      KpiSigh(
          libelle: 'Valeur au CUMP',
          valeur: money(qte(p['stock']) * qte(p['cump'])),
          icone: LucideIcons.wallet),
    ]),
    const SizedBox(height: 16),
    OngletsSigh(onglets: [
      OngletDef(
          id: 'fiche',
          libelle: 'Fiche produit',
          construire: (_) => DescListeSigh([
                (
                  'Code article',
                  Text('${p['code'] ?? ''}', style: typographieMono)
                ),
                ('Désignation', '${p['designation'] ?? ''}'),
                ('Catégorie', libelleCategorie(p['categorie'])),
                ('Unité', '${p['unite'] ?? ''}'),
                ('Prix d’achat', money(p['prixAchat'])),
                (
                  'Prix de vente',
                  Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        cellule(money(p['prixVente']),
                            couleur: JetonsShell.slate800,
                            poids: FontWeight.w500),
                        if (p['categorie'] == 'medicament')
                          const BadgeSigh('Sans marge (RG-02)',
                              ton: TonSigh.info),
                      ])
                ),
                ('CUMP', money(p['cump'])),
                ('Stock gros', '${nombre(p['stockGros'])} ${p['unite'] ?? ''}'),
                (
                  'Stock détail',
                  '${nombre(p['stockDetail'])} ${p['unite'] ?? ''}'
                ),
                (
                  'Seuil d’alerte',
                  seuilFixe(p['seuilAlerte'])
                      ? nombre(p['seuilAlerte'])
                      : 'Non fixé — signalé à part'
                ),
                ('Emplacement', '${p['emplacement'] ?? ''}'),
                ('Fournisseur habituel', '${p['fournisseur'] ?? ''}'),
              ])),
      OngletDef(
          id: 'lots',
          libelle: 'Lots (FEFO)',
          compte: lots.length,
          construire: (_) => lots.isEmpty
              ? const VideSigh('Aucun lot enregistré pour ce produit.',
                  icone: LucideIcons.boxes)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('N° lot', (l) => '${l['numeroLot']}',
                      rendu: (l) => Text('${l['numeroLot']}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono', fontSize: 12))),
                  ColonneMini(
                      'Péremption', (l) => dateFiche(l['datePeremption'])),
                  ColonneMini('Reste', (l) => nombre(l['quantiteRestante']),
                      droite: true),
                  ColonneMini('État', (l) => '', rendu: (l) {
                    final j = joursAvantPeremption(auj, l['datePeremption']);
                    return BadgeSigh(texteEtatLotFiche(j),
                        ton: j != null && j < 0
                            ? TonSigh.danger
                            : (j != null && j <= delaiPreavisPeremption
                                ? TonSigh.attention
                                : TonSigh.succes));
                  }),
                  ColonneMini(
                      'Emplacement', (l) => '${l['emplacement'] ?? ''}'),
                ], lignes: lots)),
      OngletDef(
          id: 'mouvements',
          libelle: 'Mouvements',
          compte: mvts.length,
          construire: (_) => mvts.isEmpty
              ? const VideSigh('Aucun mouvement enregistré.',
                  icone: LucideIcons.arrowLeftRight)
              : MiniTableauSigh(colonnes: [
                  ColonneMini('Date', (m) => dateFiche(m['date'])),
                  ColonneMini('Type', (m) => '', rendu: (m) {
                    final t = typesMouvement
                        .where((x) => x.id == m['type'])
                        .firstOrNull;
                    return BadgeSigh('${m['typeLabel'] ?? m['type'] ?? ''}',
                        ton: tonDeBadge(t?.badge ?? 'neutral'));
                  }),
                  ColonneMini('Quantité', (m) => '${m['quantite'] ?? ''}',
                      droite: true),
                  ColonneMini(
                      'Justificatif', (m) => '${m['justificatif'] ?? ''}'),
                  ColonneMini('Opérateur', (m) => '${m['utilisateur'] ?? ''}'),
                ], lignes: mvts.take(20).toList())),
    ]),
  ]);
}
