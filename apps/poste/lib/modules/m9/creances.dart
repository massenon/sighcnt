import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'commun.dart';

/// `m9-creances` — « Créances assureurs » : la balance âgée, en lecture seule. Les créances sont le reliquat des factures prises en charge ;
/// elles évoluent avec les règlements des compagnies, jamais par saisie directe.
///
/// Les bornes portent sur la DATE DE LA FACTURE, l'ancienneté se compte TOUJOURS par rapport à aujourd'hui (les confondre ferait vieillir une
/// créance parce qu'on a rétréci la fenêtre). Les filtres en force sont portés sur l'état imprimé.
class EcranCreances extends StatefulWidget with EcranMaquette {
  const EcranCreances({super.key});

  @override
  String get titre => 'Créances assureurs';

  @override
  String get description =>
      'Suivi des montants dus par les compagnies, par ancienneté et par compagnie.';

  @override
  String get regle =>
      'Écran en lecture seule. Les créances sont le reliquat des factures prises en charge : elles évoluent avec les règlements des compagnies, jamais par saisie directe.';

  @override
  State<EcranCreances> createState() => _EtatCreances();
}

class _EtatCreances extends State<EcranCreances> {
  ControleurFormulaire? _du, _au, _compagnie, _anciennete, _seuil;

  List<ControleurFormulaire> get _tous =>
      [_du!, _au!, _compagnie!, _anciennete!, _seuil!];

  static const _seuils = [
    ('', 'Tout montant'),
    ('50000', 'Au moins 50 000 F'),
    ('200000', 'Au moins 200 000 F'),
    ('500000', 'Au moins 500 000 F'),
    ('1000000', 'Au moins 1 000 000 F'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    final c = ContexteEcran.of(context);
    ChampDef def(String nom, String libelle, TypeChamp type,
            {List<OptionChamp> options = const []}) =>
        ChampDef(
            nom: nom,
            libelle: libelle,
            type: type,
            options: options,
            col: ColChamp.plein);
    _du = champUnique(def('du', 'Factures émises du', TypeChamp.date), '');
    _au = champUnique(def('au', 'au', TypeChamp.date), '');
    _compagnie = champUnique(
        def('compagnie', 'Compagnie', TypeChamp.select, options: [
          const OptionChamp('', 'Toutes les compagnies'),
          for (final a in actives(c, 'assureurs'))
            OptionChamp('${a['code']}', '${a['code']} — ${a['nom']}')
        ]),
        '');
    _anciennete = champUnique(
        def('anciennete', 'Ancienneté retenue', TypeChamp.select, options: const [
          OptionChamp('', 'Toutes anciennetés'),
          OptionChamp('moins30', 'Moins de 30 jours'),
          OptionChamp('30a90', 'De 30 à 90 jours'),
          OptionChamp('plus90', 'Au-delà de 90 jours'),
        ]),
        '');
    _seuil = champUnique(
        def('seuil', 'Créance minimale', TypeChamp.select,
            options: [for (final s in _seuils) OptionChamp(s.$1, s.$2)]),
        '');
    for (final k in _tous) {
      k.addListener(_surChangement);
    }
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_du != null) {
      for (final k in _tous) {
        k.removeListener(_surChangement);
        k.dispose();
      }
    }
    super.dispose();
  }

  String _txt(ControleurFormulaire k, String nom) => '${k[nom] ?? ''}';

  List<AssLigneCreance> _lignes(ContexteEcran c) => assBalanceAgee(
      assureurs: actives(c, 'assureurs'),
      facturesAssurance: assFacturesAssurance(actives(c, 'factures')),
      auj: c.aujourdhui,
      du: _txt(_du!, 'du'),
      au: _txt(_au!, 'au'),
      compagnie: _txt(_compagnie!, 'compagnie'),
      anciennete: _txt(_anciennete!, 'anciennete'),
      seuil: num.tryParse(_txt(_seuil!, 'seuil')) ?? 0);

  /// Les filtres EN FORCE, relevés comme `P.etat` les relève sur la page.
  List<(String, String)> _filtresEnForce(ContexteEcran c) {
    String libelle(ControleurFormulaire k, String nom) => k.champs.first.options
        .firstWhere((o) => o.valeur == _txt(k, nom))
        .libelle;
    return [
      if (_txt(_du!, 'du').isNotEmpty)
        ('Factures émises du', dateFR(assDate(_txt(_du!, 'du')))),
      if (_txt(_au!, 'au').isNotEmpty) ('au', dateFR(assDate(_txt(_au!, 'au')))),
      if (_txt(_compagnie!, 'compagnie').isNotEmpty)
        ('Compagnie', libelle(_compagnie!, 'compagnie')),
      if (_txt(_anciennete!, 'anciennete').isNotEmpty)
        ('Ancienneté retenue', libelle(_anciennete!, 'anciennete')),
      if (_txt(_seuil!, 'seuil').isNotEmpty)
        ('Créance minimale', libelle(_seuil!, 'seuil')),
    ];
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<AssLigneCreance> rows) {
    final tri = trierPar<AssLigneCreance>(rows, (r) => r.total, descendant: true);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'État des créances — tiers payeurs',
            sousTitre: 'Balance âgée au ${dateFR(c.aujourdhui)}',
            cartouche: [
              (
                'Créances totales',
                money(rows.fold<num>(0, (a, r) => a + r.total))
              ),
              ('Compagnies concernées', nombre(rows.length)),
              (
                'Dont plus de 90 jours',
                money(rows.fold<num>(0, (a, r) => a + r.plus90))
              ),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            filtres: _filtresEnForce(c),
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Code', valeur: (r) => r['code']),
                ColonneEtat(libelle: 'Compagnie', valeur: (r) => r['nom']),
                ColonneEtat(
                    libelle: 'Factures', droite: true, valeur: (r) => r['nb']),
                ColonneEtat(
                    libelle: '< 30 j',
                    droite: true,
                    valeur: (r) => m(r['moins30']),
                    somme: (r) => n(r['moins30'])),
                ColonneEtat(
                    libelle: '30-90 j',
                    droite: true,
                    valeur: (r) => m(r['de30a90']),
                    somme: (r) => n(r['de30a90'])),
                ColonneEtat(
                    libelle: '> 90 j',
                    droite: true,
                    valeur: (r) => m(r['plus90']),
                    somme: (r) => n(r['plus90'])),
                ColonneEtat(
                    libelle: 'Total',
                    droite: true,
                    valeur: (r) => m(r['total']),
                    somme: (r) => n(r['total'])),
              ], lignes: [
                for (final r in tri)
                  {
                    'code': r.code,
                    'nom': r.nom,
                    'nb': r.nbFactures,
                    'moins30': r.moins30,
                    'de30a90': r.de30a90,
                    'plus90': r.plus90,
                    'total': r.total,
                  }
              ])
            ],
            signatures: const [
              Signature('Le Comptable', nom: 'KASSA Augustin'),
              signDaf
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'factures']),
      builder: (context, _) {
        final rows = _lignes(c);
        double som(double Function(AssLigneCreance) f) =>
            rows.fold(0.0, (a, r) => a + f(r));
        final tri = trierPar<AssLigneCreance>(rows, (r) => r.total, descendant: true);
        void reinitialiser() {
          for (final k in _tous) {
            k.poser(k.champs.first.nom, '');
          }
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                    commande(_du!, largeur: 170),
                    commande(_au!, largeur: 170),
                    commande(_compagnie!, largeur: 260),
                    commande(_anciennete!, largeur: 200),
                    commande(_seuil!, largeur: 200),
                    BoutonSigh(
                        libelle: 'Réinitialiser',
                        icone: LucideIcons.rotateCcw,
                        variante: VarianteBouton.secondaire,
                        onPressed: reinitialiser),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Créances totales',
                    valeur: money(som((r) => r.total)),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Moins de 30 jours',
                    valeur: money(som((r) => r.moins30)),
                    icone: LucideIcons.clock,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: '30 à 90 jours',
                    valeur: money(som((r) => r.de30a90)),
                    icone: LucideIcons.clockAlert,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Plus de 90 jours',
                    valeur: money(som((r) => r.plus90)),
                    indice: 'Relance impérative',
                    icone: LucideIcons.octagonAlert,
                    ton: TonSigh.danger),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Balance âgée des créances par compagnie',
                lignes: [
                  for (final r in rows)
                    {
                      'id': r.code,
                      'code': r.code,
                      'nom': r.nom,
                      'nbFactures': r.nbFactures,
                      'moins30': r.moins30,
                      'de30a90': r.de30a90,
                      'plus90': r.plus90,
                      'total': r.total,
                    }
                ],
                taillePage: 15,
                nomExport: 'creances-assureurs',
                triInitial: 'total',
                sensInitial: 'desc',
                actions: [
                  BoutonSigh(
                      libelle: 'Éditer l’état des créances',
                      icone: LucideIcons.printer,
                      taille: TailleBouton.sm,
                      onPressed: () => _imprimer(context, c, rows)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'code',
                      libelle: 'Code',
                      sansCoupure: true,
                      texte: (r) => '${r['code']}',
                      rendu: (_, r) => monoTexte(r['code'],
                          poids: FontWeight.w600)),
                  const ColonneTableau(cle: 'nom', libelle: 'Compagnie'),
                  const ColonneTableau(
                      cle: 'nbFactures', libelle: 'Factures', droite: true),
                  ColonneTableau(
                      cle: 'moins30',
                      libelle: '< 30 j',
                      droite: true,
                      texte: (r) => m(r['moins30'])),
                  ColonneTableau(
                      cle: 'de30a90',
                      libelle: '30 – 90 j',
                      droite: true,
                      texte: (r) => m(r['de30a90']),
                      rendu: (_, r) => Text(m(r['de30a90']),
                          style: TextStyle(
                              color: n(r['de30a90']) > 0
                                  ? JetonsShell.warning700
                                  : JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14))),
                  ColonneTableau(
                      cle: 'plus90',
                      libelle: '> 90 j',
                      droite: true,
                      texte: (r) => m(r['plus90']),
                      rendu: (_, r) => Text(m(r['plus90']),
                          style: TextStyle(
                              color: n(r['plus90']) > 0
                                  ? JetonsShell.danger600
                                  : JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: n(r['plus90']) > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400))),
                  ColonneTableau(
                      cle: 'total',
                      libelle: 'Total dû',
                      droite: true,
                      texte: (r) => m(r['total']),
                      rendu: (_, r) => Text(m(r['total']),
                          style: const TextStyle(
                              color: JetonsShell.navy900,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 16),
              deuxCartes(
                CarteSigh(
                    titre: 'Créances par compagnie',
                    child: ClassementSigh([
                      for (final r in tri) (libelle: r.nom, valeur: r.total)
                    ], ton: JetonsShell.warning500)),
                CarteSigh(
                    titre: 'Répartition par ancienneté',
                    child: GraphiqueAnneau(
                        etiquettes: const [
                          'Moins de 30 jours',
                          '30 à 90 jours',
                          'Plus de 90 jours'
                        ],
                        valeurs: [
                          som((r) => r.moins30),
                          som((r) => r.de30a90),
                          som((r) => r.plus90)
                        ],
                        couleurs: const [
                          JetonsShell.success500,
                          JetonsShell.warning500,
                          JetonsShell.danger600
                        ])),
              ),
              if (rows.isEmpty) ...[
                const SizedBox(height: 16),
                const NoteSigh(
                    'Aucune créance ne répond à cette sélection. Les filtres portent sur la date des factures ; l’ancienneté, elle, se compte toujours par rapport à aujourd’hui.',
                    icone: LucideIcons.filter),
              ],
            ]);
      },
    );
  }
}
