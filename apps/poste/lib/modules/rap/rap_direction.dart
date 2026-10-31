import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rap_commun.dart';

/// `rapports-direction` — « États de la Direction » : le cahier de charge du 30/12/2024 énumère ce que la Directrice Administrative attend — points de
/// vente et de caisse par période (journalier à annuel) et par axe (client, nature de facture, assureur, article, famille, groupe), cumul global ou
/// détaillé, quantité vendue totalisée, impression de chaque état. UNE mécanique répond à tout : une PÉRIODE et un AXE.
///
/// Les états sont CALCULÉS depuis les factures émises (`rapAgreger`) : ils ne se saisissent pas. L'écran PRODUIT une pièce : il est fermé aux rôles qui
/// n'écrivent pas (direction, DAF, directeur médical, administrateur — vague 67).
class EcranRapDirection extends StatelessWidget with EcranMaquette {
  const EcranRapDirection({super.key});

  @override
  String get titre => 'États de la Direction';

  @override
  String get description =>
      'Points de vente et de caisse par période et par axe d’analyse, avec cumuls et impression.';

  @override
  String get regle =>
      'Les états sont calculés depuis les factures émises : ils ne se saisissent pas. Choisir une période et un axe suffit à produire les points demandés par le cahier de charge — par client, par article, par famille ou par groupe.';

  @override
  Widget build(BuildContext context) => const _VueDirection();
}

class _VueDirection extends StatefulWidget {
  const _VueDirection();
  @override
  State<_VueDirection> createState() => _VueDirectionState();
}

class _VueDirectionState extends State<_VueDirection> {
  ControleurFormulaire? _periode, _fin, _axe, _detaille;
  CollectionMagasin? _factures, _produits;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ContexteEcran.of(context);
    _periode ??= ControleurFormulaire([
      ChampDef(
          nom: 'periode',
          libelle: 'Périodicité',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            for (final p in rapPeriodesDirection) OptionChamp(p.id, p.libelle)
          ])
    ], {
      'periode': 'mois'
    });
    _fin ??= ControleurFormulaire([
      const ChampDef(
          nom: 'fin',
          libelle: 'Arrêté au',
          type: TypeChamp.date,
          col: ColChamp.plein)
    ], {
      'fin': iso(c.aujourdhui)
    });
    _axe ??= ControleurFormulaire([
      ChampDef(
          nom: 'axe',
          libelle: 'Axe d’analyse',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            for (final a in rapAxesDirection) OptionChamp(a.id, a.libelle)
          ])
    ], {
      'axe': 'client'
    });
    _detaille ??= ControleurFormulaire([
      const ChampDef(
          nom: 'detaille',
          libelle: 'Cumul détaillé',
          type: TypeChamp.case_,
          col: ColChamp.plein)
    ]);
    _factures = c.magasin.collection('factures');
    _produits = c.magasin.collection('produits');
  }

  @override
  void dispose() {
    for (final k in [_periode, _fin, _axe, _detaille]) {
      k?.dispose();
    }
    super.dispose();
  }

  String get _p => '${_periode!['periode']}';
  String get _a => '${_axe!['axe']}';
  bool get _det => _detaille!['detaille'] == true;

  void _imprimer(BuildContext ctx, ContexteEcran c) {
    final b = rapBornes(_p, _fin!['fin']);
    final axe = rapAxe(_a);
    final fac = rapFacturesPeriode(_factures!.actives, b);
    final rows = rapAgreger(fac, _produits!.actives, axe.id);
    final cum = rapCumul(rows);
    final titre =
        'Point ${b.libelle.toLowerCase()} — ${axe.libelle.toLowerCase()}';
    rapApercu(
        ctx,
        PieceA4(
          titre: titre,
          sousTitre: '${b.debutFR} au ${b.finFR}',
          reference: rapReference(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: rapCartoucheDirection(b, axe,
              pieces: fac.length, cumul: cum.montant),
          // Les filtres EN FORCE de la page : listes d'abord (périodicité, axe), puis les dates, comme `filtresDeLaPage()`.
          filtres: rapFiltresEnForce([
            ('Périodicité', b.libelle),
            ('Axe d’analyse', axe.libelle),
            ('Arrêté au', b.finMs == null ? '' : b.finFR),
          ]),
          tableaux: [rapTableauDirection(rows, axe)],
          signatures: const [
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
            Signature('Le Comptable', nom: 'KASSA Augustin'),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge(
            [_periode!, _fin!, _axe!, _detaille!, _factures!, _produits!]),
        builder: (context, _) {
          final b = rapBornes(_p, _fin!['fin']);
          final axe = rapAxe(_a);
          final fac = rapFacturesPeriode(_factures!.actives, b);
          final rows = rapAgreger(fac, _produits!.actives, axe.id);
          final cum = rapCumul(rows);
          final avecParts = _det && axe.niveauPiece;
          Widget champ(ControleurFormulaire k, double l) =>
              SizedBox(width: l, child: FormulaireSigh(controleur: k));
          final lignes = [
            for (final r in rows)
              <String, Object?>{
                'libelle': r.libelle,
                'pieces': r.pieces,
                'quantite': r.quantite,
                'montant': r.montant,
                'assureur': r.assureur,
                'patient': r.patient,
              }
          ];
          Widget droite(Widget w) =>
              Align(alignment: Alignment.centerRight, child: w);
          TextStyle gras() => const TextStyle(
              color: JetonsShell.slate900,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CarteSigh(
                    child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                      champ(_periode!, 176),
                      champ(_fin!, 176),
                      champ(_axe!, 256),
                      SizedBox(
                          width: 160,
                          child: FormulaireSigh(controleur: _detaille!)),
                      BoutonSigh(
                          libelle: 'Éditer l’état',
                          icone: LucideIcons.printer,
                          onPressed: () => _imprimer(context, c)),
                    ])),
                const SizedBox(height: 16),
                KpiGrilleSigh(kpis: [
                  KpiSigh(
                      libelle: 'Point ${b.libelle.toLowerCase()}',
                      valeur: money(fac.fold<double>(
                          0, (t, f) => t + nombreOuZero(f['montantTTC']))),
                      icone: LucideIcons.chartNoAxesCombined,
                      ton: TonSigh.navy,
                      indice: '${b.debutFR} → ${b.finFR}'),
                  KpiSigh(
                      libelle: 'Encaissé',
                      valeur: money(fac.fold<double>(
                          0, (t, f) => t + nombreOuZero(f['montantPaye']))),
                      icone: LucideIcons.banknote,
                      ton: TonSigh.succes),
                  KpiSigh(
                      libelle: 'Pièces émises',
                      valeur: nombre(fac.length),
                      icone: LucideIcons.receipt,
                      ton: TonSigh.info),
                  KpiSigh(
                      libelle: axe.libellePostes,
                      valeur: nombre(rows.length),
                      icone: LucideIcons.layers,
                      ton: TonSigh.neutre,
                      indice: axe.detail),
                ]),
                if (axe.id == 'groupe') ...[
                  const SizedBox(height: 16),
                  const NoteSigh(
                      'Le regroupement en quatre groupes est une proposition : les documents de la clinique ne définissent que les sept familles de l’inventaire SAGE. À valider avant usage officiel.',
                      ton: TonSigh.attention,
                      icone: LucideIcons.circleHelp),
                ],
                const SizedBox(height: 16),
                TableauSigh(
                  key: ValueKey('${_p}_${axe.id}_$avecParts'),
                  titre:
                      'Point ${b.libelle.toLowerCase()} — ${axe.libelle.toLowerCase()}',
                  lignes: lignes,
                  taillePage: 25,
                  triInitial: 'montant',
                  sensInitial: 'desc',
                  nomExport: 'etat-direction-${axe.id}',
                  messageVide: 'Aucune vente sur la période.',
                  colonnes: [
                    ColonneTableau(cle: 'libelle', libelle: axe.colonne),
                    ColonneTableau(
                        cle: 'pieces',
                        libelle: 'Pièces',
                        droite: true,
                        texte: (r) => nombre(r['pieces']),
                        rendu: (_, r) =>
                            droite(Text(nombre(r['pieces']), style: _normal))),
                    ColonneTableau(
                        cle: 'quantite',
                        libelle: 'Quantité vendue',
                        droite: true,
                        texte: (r) => nombre(r['quantite']),
                        rendu: (_, r) =>
                            droite(Text(nombre(r['quantite']), style: gras()))),
                    ColonneTableau(
                        cle: 'montant',
                        libelle: 'Montant',
                        droite: true,
                        texte: (r) => '${r['montant']}',
                        rendu: (_, r) => droite(Text(
                            money(r['montant'], avecDevise: false),
                            style: gras()))),
                    if (avecParts) ...[
                      ColonneTableau(
                          cle: 'assureur',
                          libelle: 'Part assureur',
                          droite: true,
                          texte: (r) => money(r['assureur'], avecDevise: false),
                          rendu: (_, r) => droite(Text(
                              money(r['assureur'], avecDevise: false),
                              style: _normal))),
                      ColonneTableau(
                          cle: 'patient',
                          libelle: 'Part patient',
                          droite: true,
                          texte: (r) => money(r['patient'], avecDevise: false),
                          rendu: (_, r) => droite(Text(
                              money(r['patient'], avecDevise: false),
                              style: _normal))),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                NoteSigh(
                    'Cumul global : ${money(cum.montant)} sur ${nombre(cum.quantite)} unité(s) vendue(s), ${nombre(cum.postes)} poste(s) d’analyse.',
                    icone: LucideIcons.sigma),
              ]);
        });
  }

  static const TextStyle _normal =
      TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14);
}
