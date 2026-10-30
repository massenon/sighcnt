import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

const motifsAvoir = [
  'Erreur de facturation',
  'Interruption de soins',
  'Évacuation vers un autre centre',
  'Prestation non réalisée',
  'Autre (préciser en observations)',
];

String _suite(Object? r) => r == 'especes' ? 'Remboursé en espèces' : 'Créance réduite';

/// L'avoir à imprimer : la pièce qui contre-passe, avec ses lignes NOMMÉES et un total calculé (négatif).
PieceA4 pieceAvoir(Fiche a,
    {required String utilisateur,
    required DateTime edite,
    required String reference}) {
  final lignes = [
    for (final l in (a['lignesAnnulees'] as List? ?? const []))
      (l as Map).cast<String, Object?>()
  ];
  return PieceA4(
    titre: 'FACTURE D’AVOIR',
    sousTitre: '${a['reference']} — rectifie ${a['factureNumero']}',
    filigrane: 'AVOIR',
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    cartouche: [
      ('N° avoir', '${a['reference']}'),
      ('Date', dateDe(a['date'])),
      ('Facture rectifiée', '${a['factureNumero']}'),
      ('Client', '${a['patient'] ?? '—'}'),
      ('Motif', '${a['motif'] ?? '—'}'),
      (
        'Suite donnée',
        a['remboursement'] == 'especes'
            ? 'Remboursement en espèces'
            : 'Créance réduite'
      ),
    ],
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Prestation contre-passée', valeur: (l) => l['designation']),
        ColonneEtat(
            libelle: 'Montant',
            valeur: (l) => '− ${m(l['montant'])}',
            droite: true,
            somme: (l) => -n(l['montant'])),
      ], lignes: lignes)),
      if ('${a['observations'] ?? ''}'.isNotEmpty)
        BlocTexte('${a['observations']}', italique: true),
      const BlocTexte(
          'La présente pièce contre-passe la facture désignée ci-dessus, qui reste au registre. Écriture comptable en brouillon jusqu’à validation.'),
    ],
    signatures: const [
      Signature('Le Comptable'),
      Signature('La Directrice de l’Administration et des Finances',
          nom: 'TAKI Alimatou'),
    ],
  );
}

Future<void> imprimerAvoir(BuildContext ctx, Fiche a) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceAvoir(a,
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          reference:
              PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero())));
}

/// Le détail d'un avoir, tel que le tiroir de la maquette le lit.
Widget detailAvoir(Fiche a) {
  final lignes = [
    for (final l in (a['lignesAnnulees'] as List? ?? const []))
      (l as Map).cast<String, Object?>()
  ];
  final stat = a['statutMecef'];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      ('Référence', a['reference']),
      ('Date', dateDe(a['date'])),
      ('Facture rectifiée', a['factureNumero']),
      (
        'Client',
        '${a['patient'] ?? '—'}${a['patientCode'] != null ? ' — ${a['patientCode']}' : ''}'
      ),
      ('Montant contre-passé', '− ${money(a['montant'])}'),
      ('Motif', a['motif'] ?? '—'),
      ('Suite donnée', _suite(a['remboursement'])),
      (
        'Registre MECeF',
        stat == 'sans_objet' ? 'Sans objet (pièce non transmise)' : (stat ?? '—')
      ),
      ('Émis par', a['emisPar'] ?? '—'),
    ]),
    if (lignes.isNotEmpty) ...[
      const SizedBox(height: 16),
      SectionSigh(
          titre: 'Lignes contre-passées',
          child: MiniTableauSigh(colonnes: [
            ColonneMini('Prestation', (l) => '${l['designation']}'),
            ColonneMini('Montant', (l) => '− ${m(l['montant'])}', droite: true),
          ], lignes: lignes)),
    ],
    const SizedBox(height: 16),
    NoteSigh(
        'Contre-passation en brouillon : débit 706 Prestations, crédit ${a['remboursement'] == 'especes' ? '571 Caisse' : '411 Clients'}. La validation comptable reste un geste humain.',
        icone: LucideIcons.scale),
  ]);
}

/// `m8-facture-avoir` — « Factures d’avoir » : le canal de correction d'une pièce émise. Une pièce émise ne se modifie ni ne se supprime ; l'avoir la
/// CONTRE-PASSE (pièce numérotée, lignes nommées, écriture inverse en brouillon, registre MECeF alimenté). Une seule collection pour deux vues.
class EcranFactureAvoir extends StatelessWidget with EcranMaquette {
  const EcranFactureAvoir({super.key});

  @override
  String get titre => 'Factures d’avoir';

  @override
  String get description =>
      'Contre-passation d’une pièce émise : erreur, interruption de soins, évacuation après paiement.';

  @override
  String get regle =>
      'Une pièce émise ne se modifie ni ne se supprime — depuis la phase 5, la caisse n’annule plus (matrice cible) : la correction passe par l’avoir, pièce numérotée qui nomme ses lignes, contre-passe la recette en brouillon (RG-10) et alimente le registre MECeF. Une facture consolidée dans une mère émise est figée : l’avoir est refusé en nommant la mère.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('avoirs');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final caisse = rows.where((a) => a['origine'] == 'caisse').length;
        final rectifiees = {for (final a in rows) a['factureNumero']}.length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Avoirs émis',
                    valeur: nombre(rows.length),
                    icone: LucideIcons.undo2),
                KpiSigh(
                    libelle: 'Montant contre-passé',
                    valeur: money(rows.fold<num>(0, (a, r) => a + n(r['montant']))),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Depuis la caisse',
                    valeur: nombre(caisse),
                    icone: LucideIcons.receipt,
                    ton: TonSigh.info,
                    indice: 'le registre fiscal MECeF lit la même collection'),
                KpiSigh(
                    libelle: 'Factures rectifiées',
                    valeur: nombre(rectifiees),
                    icone: LucideIcons.fileX,
                    ton: TonSigh.neutre),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Registre des avoirs',
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'factures-avoir',
                messageVide: 'Aucun avoir émis.',
                indiceVide:
                    'Un avoir contre-passe une facture émise — erreur, interruption, évacuation.',
                lignes: rows,
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° avoir',
                      sansCoupure: true,
                      texte: (a) => '${a['reference']}',
                      rendu: (_, a) => Text('${a['reference']}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: JetonsShell.slate900))),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (a) => dateDe(a['date'])),
                  ColonneTableau(
                      cle: 'factureNumero',
                      libelle: 'Facture rectifiée',
                      sansCoupure: true,
                      texte: (a) => '${a['factureNumero']}',
                      rendu: (_, a) => Text('${a['factureNumero']}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: JetonsShell.slate700))),
                  const ColonneTableau(cle: 'patient', libelle: 'Client'),
                  ColonneTableau(
                      cle: 'montant',
                      libelle: 'Montant',
                      droite: true,
                      texte: (a) => m(a['montant']),
                      rendu: (_, a) => Text('− ${m(a['montant'])}',
                          style: const TextStyle(
                              color: JetonsShell.danger600,
                              fontSize: 14,
                              fontWeight: FontWeight.w600))),
                  const ColonneTableau(cle: 'motif', libelle: 'Motif'),
                  ColonneTableau(
                      cle: 'remboursement',
                      libelle: 'Remboursement',
                      texte: (a) => a['remboursement'] == 'especes'
                          ? 'Espèces'
                          : 'Créance réduite',
                      rendu: (_, a) => a['remboursement'] == 'especes'
                          ? const BadgeSigh('Espèces rendues', ton: TonSigh.attention)
                          : const BadgeSigh('Créance réduite', ton: TonSigh.info)),
                  ColonneTableau(
                      cle: 'origine',
                      libelle: 'Origine',
                      texte: (a) => a['origine'] == 'caisse' ? 'Caisse' : 'MECeF',
                      rendu: (_, a) => BadgeSigh(
                          a['origine'] == 'caisse' ? 'Caisse' : 'MECeF',
                          ton: a['origine'] == 'caisse'
                              ? TonSigh.navy
                              : TonSigh.neutre)),
                ],
                alClicLigne: (a) => _consulter(context, a),
                actionsLigne: (ctx, a) => [
                  BoutonIcone(
                      icone: LucideIcons.eye,
                      libelle: 'Consulter',
                      onPressed: () => _consulter(ctx, a)),
                  BoutonIcone(
                      icone: LucideIcons.printer,
                      libelle: 'Imprimer l’avoir',
                      onPressed: () => imprimerAvoir(ctx, a)),
                ],
                actions: [
                  if (c.droit.editer)
                    BoutonSigh(
                        libelle: 'Émettre un avoir',
                        icone: LucideIcons.undo2,
                        taille: TailleBouton.sm,
                        onPressed: () => _ouvrirEmission(context)),
                ],
              ),
            ]);
      },
    );
  }

  void _consulter(BuildContext ctx, Fiche a) => afficherTiroir<void>(ctx,
      titre: 'Avoir ${a['reference']}',
      sousTitre: '${a['factureNumero']} — ${a['patient'] ?? ''}',
      corps: detailAvoir(a),
      pied: (_) => [
            BoutonSigh(
                libelle: 'Imprimer l’avoir',
                icone: LucideIcons.printer,
                onPressed: () => imprimerAvoir(ctx, a))
          ]);

  void _ouvrirEmission(BuildContext ctx) {
    final c = ContexteEcran.of(ctx);
    final candidates = trierPar(
            c.magasin
                .collection('factures')
                .actives
                .where((f) => n(f['montantTTC']) > 0)
                .toList(),
            (f) => f['date'],
            descendant: true)
        .take(300)
        .toList();
    if (candidates.isEmpty) {
      ToastsSigh.afficher(ctx, 'Aucune facture à rectifier.',
          type: TypeToast.attention);
      return;
    }
    afficherModale<void>(ctx,
        titre: 'Émettre une facture d’avoir',
        sousTitre: 'La pièce d’origine reste intacte ; l’avoir la contre-passe.',
        taille: TailleModale.lg,
        corps: _ModaleAvoir(contexte: c, ecran: ctx, candidates: candidates),
        pied: null);
  }
}

class _ModaleAvoir extends StatefulWidget {
  const _ModaleAvoir(
      {required this.contexte, required this.ecran, required this.candidates});
  final ContexteEcran contexte;

  /// Le contexte de l'ÉCRAN : une modale vit au-dessus de la coque, hors du `ContexteEcran` — messages et impressions passent par lui.
  final BuildContext ecran;
  final List<Fiche> candidates;
  @override
  State<_ModaleAvoir> createState() => _EtatModaleAvoir();
}

class _EtatModaleAvoir extends State<_ModaleAvoir> {
  late final ControleurFormulaire _facture;
  late final ControleurFormulaire _form;
  final Set<int> _cochees = {};
  String _vue = '';

  @override
  void initState() {
    super.initState();
    _facture = ControleurFormulaire([
      ChampDef(
          nom: 'facture',
          libelle: 'Facture à rectifier',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          indicatif: 'Choisir la facture à rectifier',
          options: [
            for (final f in widget.candidates)
              OptionChamp('${f['id']}',
                  '${f['numero']} — ${f['patient'] ?? 'Sans dossier'}')
          ])
    ]);
    _form = ControleurFormulaire([
      ChampDef(
          nom: 'motif',
          libelle: 'Motif de l’avoir',
          type: TypeChamp.select,
          requis: true,
          options: [for (final x in motifsAvoir) OptionChamp(x)]),
      const ChampDef(
          nom: 'remboursement',
          libelle: 'Suite donnée',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('especes', 'Rembourser en espèces (crédit caisse)'),
            OptionChamp('creance', 'Réduire la créance (crédit clients)'),
          ]),
      const ChampDef(
          nom: 'observations',
          libelle: 'Observations',
          type: TypeChamp.textarea,
          col: ColChamp.plein,
          lignes: 2),
    ], {
      'remboursement': 'creance'
    });
    _facture.addListener(() {
      if ('${_facture['facture']}' != _vue) {
        _vue = '${_facture['facture']}';
        setState(_cochees.clear);
      }
    });
  }

  @override
  void dispose() {
    _facture.dispose();
    _form.dispose();
    super.dispose();
  }

  Fiche? get _fac => widget.candidates
      .where((f) => '${f['id']}' == '${_facture['facture']}')
      .firstOrNull;

  num _montantLigne(Fiche l) => n(l['montant'] ?? l['prixUnitaire']);

  void _emettre(VoidCallback fermer) {
    final c = widget.contexte;
    final v = _form.valider();
    if (v == null) return;
    final fac = _fac;
    if (fac == null) {
      ToastsSigh.afficher(widget.ecran, 'Choisir la facture à rectifier.',
          type: TypeToast.erreur);
      return;
    }
    final detail = [
      for (final l in (fac['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];
    final lignes = detail.isNotEmpty
        ? [
            for (final i in _cochees.toList()..sort())
              {
                'designation': detail[i]['designation'],
                'montant': _montantLigne(detail[i]),
              }
          ]
        : [
            {
              'designation': 'Avoir total — ${fac['numero']}',
              'montant': n(fac['montantTTC']),
            }
          ];
    final m = c.magasin;
    final avoirs = m.collection('avoirs');
    final idAvoir = 'AVR${(avoirs.toutes.length + 1).toString().padLeft(5, '0')}';
    final AvoirEmis r;
    try {
      r = emettreAvoir(
        facture: fac,
        idAvoir: idAvoir,
        lignes: lignes,
        motif: '${v['motif']}',
        remboursement: '${v['remboursement']}',
        observations: '${v['observations'] ?? ''}',
        jour: iso(c.aujourdhui),
        utilisateur: c.utilisateur,
        facturesMere: m.collection('facturesMere').actives,
        avoirs: avoirs.actives,
      );
    } on RefusAvoir catch (e) {
      ToastsSigh.afficher(widget.ecran, 'Avoir refusé.',
          type: TypeToast.erreur,
          detail: e.motif,
          duree: const Duration(seconds: 9));
      return;
    }
    final annulations = <VoidCallback>[];
    final ins = avoirs.inserer({...r.avoir, 'id': idAvoir, 'statut': 'actif'},
        prefixe: 'AVR');
    annulations.add(ins.annuler);
    final ecr = m.collection('ecritures');
    final ids = <String>[];
    for (final e in r.ecritures) {
      final x = ecr.inserer({...e, 'statut': 'brouillon'}, prefixe: 'ECR');
      ids.add('${x.fiche['id']}');
      annulations.add(x.annuler);
    }
    avoirs.mettreAJour(idAvoir, {'ecritureIds': ids});
    // La facture PORTE ses avoirs — elle n'est jamais réécrite : la pièce d'origine et sa correction se lisent côte à côte.
    annulations.add(m.collection('factures').mettreAJour(fac['id'], {
      'avoirIds': [...((fac['avoirIds'] as List?) ?? const []), idAvoir],
      'montantAvoirs': r.montantAvoirs,
    }));
    m.journaliser('Facture d’avoir émise', 'M8', 'Avoir',
        '${r.avoir['reference']}', null, {
      'facture': fac['numero'],
      'montant': r.avoir['montant'],
      'motif': r.avoir['motif'],
    });
    fermer();
    ToastsSigh.afficher(widget.ecran, 'Avoir ${r.avoir['reference']} émis.',
        type: TypeToast.succes,
        detail:
            '− ${money(r.avoir['montant'])} — contre-passation en brouillon.',
        annuler: () {
          for (final u in annulations.reversed) {
            u();
          }
        });
    imprimerAvoir(widget.ecran, ins.fiche);
  }

  @override
  Widget build(BuildContext context) {
    final fac = _fac;
    final detail = [
      for (final l in (fac?['lignes'] as List? ?? const []))
        (l as Map).cast<String, Object?>()
    ];
    return ListenableBuilder(
      listenable: _facture,
      builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormulaireSigh(controleur: _facture),
            const SizedBox(height: 12),
            if (fac == null)
              const Text('Choisir une facture pour voir ses lignes.',
                  style: TextStyle(color: JetonsShell.slate400, fontSize: 12))
            else if (detail.isEmpty)
              const NoteSigh(
                  'Cette pièce ne porte pas de détail par ligne (génération antérieure) : l’avoir portera son MONTANT TOTAL.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.fileQuestion)
            else ...[
              const LibelleChamp('Lignes à contre-passer *'),
              for (final (i, l) in detail.indexed)
                InkWell(
                  onTap: () => setState(() =>
                      _cochees.contains(i) ? _cochees.remove(i) : _cochees.add(i)),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        border: Border.all(color: JetonsShell.slate200),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(
                          _cochees.contains(i)
                              ? LucideIcons.squareCheck
                              : LucideIcons.square,
                          size: 18,
                          color: _cochees.contains(i)
                              ? JetonsShell.navy900
                              : JetonsShell.slate400),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('${l['designation']}',
                              style: const TextStyle(fontSize: 14))),
                      Text(m(_montantLigne(l)),
                          style: const TextStyle(
                              color: JetonsShell.slate600, fontSize: 14)),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            FormulaireSigh(controleur: _form),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: 'Émettre l’avoir',
                  icone: LucideIcons.undo2,
                  onPressed: () => _emettre(() => Navigator.of(context).pop())),
            ]),
          ]),
    );
  }
}
