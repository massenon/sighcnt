import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m8/commun.dart' show n, m;

export '../m8/commun.dart' show n, m, dateDe;

/// Les tons de la maquette (`neutral`, `info`, `warning`, `navy`, `success`, `danger`) → ceux du kit.
TonSigh tonAchat(String ton) => switch (ton) {
      'info' => TonSigh.info,
      'warning' => TonSigh.attention,
      'navy' => TonSigh.navy,
      'success' => TonSigh.succes,
      'danger' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

/// Police fixe des références (`font-mono text-xs font-semibold`).
Widget refMono(Object? r, {bool gras = true, Color couleur = JetonsShell.slate900}) =>
    Text('${r ?? ''}',
        style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: gras ? FontWeight.w600 : FontWeight.w400,
            color: couleur));

/// Les articles proposés à la saisie : le référentiel actif, par désignation.
List<Fiche> articlesDuReferentiel(Magasin magasin) => trierPar(
    magasin.collection('produits').actives, (p) => p['designation']);

List<OptionChamp> optionsArticles(List<Fiche> produits) => [
      for (final p in produits)
        OptionChamp('${p['id']}', '${p['designation']} (${p['unite']})')
    ];

List<OptionChamp> optionsFournisseurs(Magasin magasin) => [
      for (final f in magasin.collection('fournisseurs').actives)
        OptionChamp('${f['code']}', '${f['nom']}')
    ];

/// Une fenêtre vit AU-DESSUS de la coque : les messages passent par le contexte de l'ÉCRAN.
void dire(BuildContext ecran, String message,
        {TypeToast type = TypeToast.info,
        String? detail,
        VoidCallback? annuler,
        Duration? duree}) =>
    ToastsSigh.afficher(ecran, message,
        type: type, detail: detail, annuler: annuler, duree: duree);

/// Une notification de POSTE (`PR.notifier`) : elle s'adresse à un poste, pas à une personne — le comptable peut être en congé, c'est le service qui voit passer l'information.
void notifierPoste(Magasin magasin, Fiche notif, DateTime maintenant) {
  magasin.collection('notifications').inserer({
    'type': notif['type'],
    'poste': notif['poste'] ?? 'tous',
    'destinataire': null,
    'libelle': notif['libelle'],
    'detail': notif['detail'],
    'priorite': notif['priorite'] ?? 'normale',
    'reference': notif['reference'],
    'lue': false,
    'creeLe': maintenant.toIso8601String(),
    'statut': 'actif',
  }, prefixe: 'NOT');
}

String refEtat(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

Future<void> imprimerPiece(BuildContext ctx, PieceA4 Function(ContexteEcran) fabrique) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(ctx, fabrique(c));
}

List<Fiche> lignesDeBonAchat(Fiche b) => [
      for (final l in (b['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];

/// `U.timeline` : une ligne par étape, pastille ton, détail et marque à droite.
class ChronologieSigh extends StatelessWidget {
  const ChronologieSigh(this.etapes, {super.key});
  final List<({String titre, String detail, String date, TonSigh ton})> etapes;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in etapes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  margin: const EdgeInsets.only(top: 5, right: 10),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: e.ton.icone600, shape: BoxShape.circle)),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(e.titre,
                        style: const TextStyle(
                            color: JetonsShell.slate800,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    Text(e.detail,
                        style: const TextStyle(
                            color: JetonsShell.slate500, fontSize: 12)),
                  ])),
              Text(e.date,
                  style: const TextStyle(
                      color: JetonsShell.slate400, fontSize: 12)),
            ]),
          ),
      ]);
}

/// Les lignes d'une demande ou d'une commande, éditées en modale : une barre d'ajout (article, quantités), le tableau des lignes, le total.
/// `commande: false` = bon de besoins (quantité demandée / accordée, valeur estimée) ; `true` = bon de commande (quantité, prix unitaire).
/// La liste [lignes] est détenue par la modale et modifiée en place ; [alChange] la prévient.
class EditeurLignes extends StatefulWidget {
  const EditeurLignes(
      {super.key,
      required this.ecran,
      required this.produits,
      required this.lignes,
      required this.commande,
      required this.alChange});
  final BuildContext ecran;
  final List<Fiche> produits;
  final List<Fiche> lignes;
  final bool commande;
  final VoidCallback alChange;

  @override
  State<EditeurLignes> createState() => _EtatEditeurLignes();
}

class _EtatEditeurLignes extends State<EditeurLignes> {
  late final ControleurFormulaire _article;
  late final ControleurFormulaire _q1;
  late final ControleurFormulaire _q2;

  Fiche? _produit(Object? id) =>
      widget.produits.where((p) => '${p['id']}' == '$id').firstOrNull;

  @override
  void initState() {
    super.initState();
    final opts = optionsArticles(widget.produits);
    _article = ControleurFormulaire([
      ChampDef(
          nom: 'article',
          libelle: 'Article',
          type: TypeChamp.select,
          col: ColChamp.plein,
          recherche: true,
          indicatif: 'Choisir un article',
          options: opts)
    ], {
      'article': opts.isEmpty ? '' : opts.first.valeur
    });
    final p0 = _produit(opts.isEmpty ? null : opts.first.valeur);
    _q1 = ControleurFormulaire([
      ChampDef(
          nom: 'q1',
          libelle: widget.commande ? 'Quantité' : 'Qté demandée',
          type: TypeChamp.nombre,
          col: ColChamp.plein)
    ], {'q1': '10'});
    _q2 = ControleurFormulaire([
      ChampDef(
          nom: 'q2',
          libelle: widget.commande ? 'Prix unitaire' : 'Qté accordée',
          type: TypeChamp.nombre,
          col: ColChamp.plein,
          indicatif: widget.commande ? null : '—')
    ], {
      'q2': widget.commande && p0 != null ? '${n(p0['prixAchat'])}' : ''
    });
    // Choisir un article propose son prix d'achat comme prix unitaire de la commande.
    _article.addListener(() {
      if (!widget.commande) return;
      final p = _produit(_article['article']);
      if (p != null) _q2.poser('q2', '${n(p['prixAchat'])}');
    });
  }

  @override
  void dispose() {
    _article.dispose();
    _q1.dispose();
    _q2.dispose();
    super.dispose();
  }

  void _ajouter() {
    final p = _produit(_article['article']);
    try {
      final l = widget.commande
          ? nouvelleLigneCommande(
              produit: p, quantite: _q1['q1'], prixUnitaire: _q2['q2'])
          : nouvelleLigneBesoin(
              produit: p, demandee: _q1['q1'], accordee: _q2['q2']);
      setState(() => widget.lignes.add(l));
      _q1.poser('q1', '10');
      if (!widget.commande) _q2.poser('q2', '');
      widget.alChange();
    } on RefusAchat catch (e) {
      dire(widget.ecran, e.motif, type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lignes;
    final total = widget.commande
        ? montantCommande(l)
        : montantEstimeLignes(l);
    Widget cel(Widget w, {bool droite = false, bool tete = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
            alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
            child: w));
    Widget tete(String t, {bool droite = false}) => cel(
        Text(t.toUpperCase(),
            style: const TextStyle(
                color: JetonsShell.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        droite: droite);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: JetonsShell.slate50,
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(flex: 3, child: FormulaireSigh(controleur: _article)),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: FormulaireSigh(controleur: _q1)),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: FormulaireSigh(controleur: _q2)),
          const SizedBox(width: 8),
          Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: BoutonSigh(
                  libelle: 'Ajouter',
                  icone: LucideIcons.plus,
                  onPressed: _ajouter)),
        ]),
      ),
      const SizedBox(height: 12),
      if (l.isEmpty)
        VideSigh(
            widget.commande
                ? 'Aucun article dans la commande.'
                : 'Aucun article dans la demande.',
            icone: widget.commande
                ? LucideIcons.truck
                : LucideIcons.clipboardList)
      else
        Container(
          decoration: BoxDecoration(
              border: Border.all(color: JetonsShell.slate200),
              borderRadius: BorderRadius.circular(8)),
          child: Table(
              columnWidths: widget.commande
                  ? const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1.4),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.4),
                      4: FixedColumnWidth(52)
                    }
                  : const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1.2),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.6),
                      4: FixedColumnWidth(52)
                    },
              children: [
                TableRow(
                    decoration:
                        const BoxDecoration(color: JetonsShell.slate50),
                    children: [
                      tete('Article'),
                      tete(widget.commande ? 'Quantité' : 'Demandée',
                          droite: true),
                      tete(widget.commande ? 'P.U.' : 'Accordée', droite: true),
                      tete(widget.commande ? 'Montant' : 'Montant estimé',
                          droite: true),
                      cel(const SizedBox()),
                    ]),
                for (final (i, x) in l.indexed)
                  TableRow(
                      decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: JetonsShell.slate100))),
                      children: [
                        cel(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${x['produit']}',
                                  style: const TextStyle(
                                      color: JetonsShell.slate700,
                                      fontSize: 14)),
                              Text('${x['unite']}',
                                  style: const TextStyle(
                                      color: JetonsShell.slate400,
                                      fontSize: 12)),
                            ])),
                        if (widget.commande) ...[
                          cel(Text('${nombre(x['quantite'])} ${x['unite']}'),
                              droite: true),
                          cel(Text(m(x['prixUnitaire'])), droite: true),
                          cel(
                              Text(m(x['montant']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              droite: true),
                        ] else ...[
                          cel(Text(nombre(x['quantiteDemandee'])), droite: true),
                          cel(
                              x['quantiteAccordee'] != null
                                  ? Text(nombre(x['quantiteAccordee']),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: n(x['quantiteAccordee']) <
                                                  n(x['quantiteDemandee'])
                                              ? JetonsShell.warning600
                                              : JetonsShell.success600))
                                  : const Text('—',
                                      style: TextStyle(
                                          color: JetonsShell.slate400)),
                              droite: true),
                          cel(
                              Text(m(n(x['quantiteDemandee']) *
                                  n(x['prixAchat']))),
                              droite: true),
                        ],
                        cel(BoutonIcone(
                            icone: LucideIcons.x,
                            libelle: 'Retirer',
                            onPressed: () {
                              setState(() => l.removeAt(i));
                              widget.alChange();
                            })),
                      ]),
                TableRow(
                    decoration: const BoxDecoration(
                        color: JetonsShell.slate50,
                        border: Border(
                            top: BorderSide(color: JetonsShell.slate200))),
                    children: [
                      cel(Text(widget.commande ? 'TOTAL' : 'TOTAL ESTIMÉ',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600))),
                      cel(const SizedBox()),
                      cel(const SizedBox()),
                      cel(
                          Text(m(total),
                              style: const TextStyle(
                                  color: JetonsShell.navy900,
                                  fontWeight: FontWeight.w700)),
                          droite: true),
                      cel(const SizedBox()),
                    ]),
              ]),
        ),
    ]);
  }
}
