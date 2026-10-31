import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/flux_commun.dart' show actionsFiche;
import 'ged_commun.dart';

/// `ged-archives` — « Archivage & conservation » : le cycle de vie documentaire (archives actives, archives définitives) et les durées légales de
/// conservation — 20 ans pour les documents patients, 10 ans pour les documents RH, 5 ans pour les documents administratifs et fournisseurs.
///
/// Portés fidèlement et signalés : l'échéance compte 365 jours par an (E565, 20 ans tombent 5 jours avant l'anniversaire) ; le formulaire
/// « Modifier » écrit cinq champs (`titre`, `categorie` en texte libre, `dureeConservation`, `emplacement`, `observations`) que ni le tableau ni
/// l'échéance ne lisent (E566) ; la conservation échue n'entraîne aucune destruction — l'écran le rappelle et renvoie à une procédure encadrée.
class EcranArchivesGed extends StatelessWidget with EcranMaquette {
  const EcranArchivesGed({super.key});

  @override
  String get titre => 'Archivage & conservation';

  @override
  String get description =>
      'Cycle de vie documentaire : archives actives, archives définitives et durées de conservation.';

  @override
  String get regle =>
      'Les durées de conservation appliquées sont : 20 ans pour les documents patients, 10 ans pour les documents RH et 5 ans pour les documents administratifs et fournisseurs.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = colDocuments(c.magasin);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final a = qualGedArchives(rows, c.aujourdhui);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KpiGrilleSigh(kpis: [
                  KpiSigh(
                      libelle: 'Archives actives',
                      valeur: nombre(a.actives),
                      icone: LucideIcons.folderOpen,
                      ton: TonSigh.succes),
                  KpiSigh(
                      libelle: 'Archives définitives',
                      valeur: nombre(a.definitives),
                      icone: LucideIcons.archive,
                      ton: TonSigh.navy),
                  KpiSigh(
                      libelle: 'Conservation échue',
                      valeur: nombre(a.echues),
                      icone: LucideIcons.calendarX,
                      ton: a.echues > 0 ? TonSigh.danger : TonSigh.neutre),
                  KpiSigh(
                      libelle: 'Volume total',
                      valeur: a.volume,
                      icone: LucideIcons.hardDrive,
                      ton: TonSigh.info),
                ]),
                const SizedBox(height: 16),
                _graphiques(rows),
                const SizedBox(height: 16),
                _tableau(context, c, col, rows),
                if (a.echues > 0) ...[
                  const SizedBox(height: 16),
                  NoteSigh(qualGedNoteEchus(a.echues),
                      ton: TonSigh.attention, icone: LucideIcons.calendarX),
                ],
              ]);
        });
  }

  Widget _graphiques(List<Fiche> rows) {
    final conservation = qualGedParConservation(rows);
    final categories = qualGedParCategorie(rows);
    return LayoutBuilder(builder: (context, c) {
      final deux = c.maxWidth >= 1024;
      final l = deux ? (c.maxWidth - 16) / 2 : c.maxWidth;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(
            width: l,
            child: CarteSigh(
                titre: 'Répartition par durée de conservation',
                child: GraphiqueAnneau(
                    etiquettes: [for (final e in conservation) e.$1],
                    valeurs: [for (final e in conservation) e.$2]))),
        SizedBox(
            width: l,
            child: CarteSigh(
                titre: 'Volume documentaire par catégorie',
                child: GraphiqueBarres(
                    horizontal: true,
                    hauteur: 320,
                    etiquettes: [for (final e in categories) e.$1],
                    series: [
                      SerieGraphique('Documents', [for (final e in categories) e.$2])
                    ]))),
      ]);
    });
  }

  Widget _tableau(BuildContext context, ContexteEcran c, CollectionMagasin col,
      List<Fiche> rows) {
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) => TableauSigh(
              titre: 'Cycle de vie des documents',
              lignes: rows,
              taillePage: 20,
              nomExport: 'ged-archives',
              triInitial: 'date',
              filtres: [
                FiltreTableau(
                    nom: 'archive',
                    libelle: 'Statut d’archivage',
                    options: const [
                      OptionChamp('oui', 'Archivés'),
                      OptionChamp('non', 'Actifs'),
                    ],
                    correspond: (d, v) =>
                        v == 'oui' ? d['archive'] == true : d['archive'] != true),
                FiltreTableau(
                    nom: 'conservation',
                    libelle: 'Durée de conservation',
                    options: const [
                      OptionChamp('5', '5 ans'),
                      OptionChamp('10', '10 ans'),
                      OptionChamp('20', '20 ans'),
                    ],
                    correspond: (d, v) => '${d['conservation']}' == v),
              ],
              colonnes: [
                colonneReference(),
                const ColonneTableau(cle: 'libelle', libelle: 'Document'),
                colonneCategorie(),
                ColonneTableau(
                    cle: 'date',
                    libelle: 'Date du document',
                    sansCoupure: true,
                    texte: (d) => dateDe(d['date'])),
                ColonneTableau(
                    cle: 'conservation',
                    libelle: 'Conservation',
                    droite: true,
                    texte: (d) => '${d['conservation']} ans'),
                ColonneTableau(
                    cle: 'echeance',
                    libelle: 'Échéance',
                    sansCoupure: true,
                    valeur: (d) => qualGedEcheance(d)?.millisecondsSinceEpoch,
                    texte: (d) => _echeance(d, c),
                    rendu: (_, d) => qualGedExpire(d, c.aujourdhui)
                        ? BadgeSigh(_echeance(d, c), ton: TonSigh.danger)
                        : Text(_echeance(d, c),
                            style: const TextStyle(
                                color: JetonsShell.slate700, fontSize: 14))),
                ColonneTableau(
                    cle: 'archive',
                    libelle: 'Statut',
                    texte: (d) =>
                        d['archive'] == true ? 'Archivé' : 'Actif',
                    rendu: (_, d) => d['archive'] == true
                        ? const BadgeSigh('Archive définitive')
                        : const BadgeSigh('Archive active', ton: TonSigh.succes)),
              ],
              actionsLigne: (ctx, d) => actionsFiche(context,
                  collection: col,
                  fiche: d,
                  champs: (_) => const [
                        ChampDef(
                            nom: 'titre',
                            libelle: 'Titre du document',
                            requis: true,
                            col: ColChamp.plein),
                        ChampDef(nom: 'categorie', libelle: 'Catégorie'),
                        ChampDef(
                            nom: 'dureeConservation',
                            libelle: 'Durée de conservation (années)',
                            type: TypeChamp.nombre),
                        ChampDef(nom: 'emplacement', libelle: 'Emplacement physique'),
                        ChampDef(
                            nom: 'observations',
                            libelle: 'Observations',
                            type: TypeChamp.textarea,
                            lignes: 2,
                            col: ColChamp.plein),
                      ]),
              actions: [
                BoutonSigh(
                    libelle: 'Éditer le bordereau d’archivage',
                    icone: LucideIcons.printer,
                    taille: TailleBouton.sm,
                    onPressed: () =>
                        imprimerGed(context, (e) => pieceBordereau(rows, e))),
              ],
            ));
  }

  String _echeance(Fiche d, ContexteEcran c) {
    final e = qualGedEcheance(d);
    if (e == null) return '';
    return qualGedExpire(d, c.aujourdhui) ? 'Échue le ${dateFR(e)}' : dateFR(e);
  }
}

/// Le bordereau d'archivage imprimé : situation à la date du jour, les 80 premiers documents par date croissante.
PieceA4 pieceBordereau(List<Fiche> rows, ContexteEcran c) {
  final a = qualGedArchives(rows, c.aujourdhui);
  final tries = trierPar(rows, (d) => d['date']).take(80).toList();
  String fr(Fiche d) => dateDe(qualGedEcheance(d)?.toIso8601String());
  return PieceA4(
    titre: 'Bordereau d’archivage documentaire',
    sousTitre: 'Situation au ${dateFR(c.aujourdhui)}',
    reference: referenceEtat(c),
    utilisateur: c.utilisateur,
    edite: c.aujourdhui,
    cartouche: [
      ('Documents', nombre(rows.length)),
      ('Archives actives', nombre(a.actives)),
      ('Archives définitives', nombre(a.definitives)),
      ('Conservation échue', nombre(a.echues)),
      ('Volume', a.volume),
      ('Date d’édition', dateFR(c.aujourdhui)),
    ],
    tableaux: [
      TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Référence', valeur: (d) => d['reference']),
        ColonneEtat(libelle: 'Document', valeur: (d) => d['libelle']),
        ColonneEtat(libelle: 'Catégorie', valeur: (d) => qualGedCategorieLabel(d['categorie'])),
        ColonneEtat(libelle: 'Date', valeur: (d) => dateDe(d['date'])),
        ColonneEtat(libelle: 'Conservation', valeur: (d) => '${d['conservation']} ans'),
        ColonneEtat(libelle: 'Échéance', valeur: fr),
        ColonneEtat(
            libelle: 'Statut',
            valeur: (d) => d['archive'] == true ? 'Archive définitive' : 'Archive active'),
      ], lignes: tries),
    ],
    signatures: signaturesGed(),
  );
}
