import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/besoins_commun.dart' show ChronologieSigh;
import 'ged_commun.dart';

/// `ged-bibliotheque` — « Bibliothèque documentaire » : les documents numérisés de l'ÉTABLISSEMENT (contrats, pièces fournisseurs, dossiers du
/// personnel, procédures), indexés et rattachés. Les documents du dossier patient vivent dans leur propre bibliothèque, sous le module M1.
/// RG-14 : retirer une pièce l'archive. L'écran est en lecture : on y consulte et on y imprime la fiche, on y dépose rien (le dépôt est un geste
/// du workflow).
///
/// Les compteurs, l'explorateur et la traçabilité sont les règles du domaine (`qualGedBibliotheque`, `qualGedExplorateur`, `qualGedTrace`).
class EcranBibliothequeGed extends StatelessWidget with EcranMaquette {
  const EcranBibliothequeGed({super.key});

  @override
  String get titre => 'Bibliothèque documentaire';

  @override
  String get description =>
      'Ensemble des documents numérisés, indexés et rattachés à leur dossier patient, fournisseur ou employé.';

  @override
  String get regle =>
      'Bibliothèque de l’établissement — contrats, pièces fournisseurs, dossiers du personnel, procédures. Les documents du dossier patient vivent dans leur propre bibliothèque, sous le module M1. RG-14 — retirer une pièce l’archive, elle reste restaurable.';

  @override
  Widget build(BuildContext context) {
    final col = colDocuments(ContexteEcran.of(context).magasin);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final rows = col.actives;
          final b = qualGedBibliotheque(rows);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KpiGrilleSigh(kpis: [
                  KpiSigh(
                      libelle: 'Documents numérisés',
                      valeur: nombre(b.numerises),
                      icone: LucideIcons.files,
                      ton: TonSigh.navy),
                  KpiSigh(
                      libelle: 'Validés',
                      valeur: nombre(b.valides),
                      icone: LucideIcons.fileCheck2,
                      ton: TonSigh.succes),
                  KpiSigh(
                      libelle: 'En attente de validation',
                      valeur: nombre(b.enAttente),
                      icone: LucideIcons.fileClock,
                      ton: TonSigh.attention),
                  KpiSigh(
                      libelle: 'Rejetés',
                      valeur: nombre(b.rejetes),
                      icone: LucideIcons.fileX,
                      ton: TonSigh.danger),
                  KpiSigh(
                      libelle: 'Documents signés',
                      valeur: nombre(b.signes),
                      icone: LucideIcons.penTool,
                      ton: TonSigh.info),
                  KpiSigh(
                      libelle: 'Archivés',
                      valeur: nombre(b.archives),
                      icone: LucideIcons.archive,
                      ton: TonSigh.neutre),
                  KpiSigh(
                      libelle: 'Volume de stockage',
                      valeur: b.volume,
                      icone: LucideIcons.hardDrive,
                      ton: TonSigh.neutre),
                  KpiSigh(
                      libelle: 'Consultations cumulées',
                      valeur: nombre(b.consultations),
                      icone: LucideIcons.eye,
                      ton: TonSigh.info),
                ]),
                const SizedBox(height: 16),
                CarteSigh(
                    titre: 'Explorateur par nature de rattachement',
                    child: _Explorateur(rows)),
                const SizedBox(height: 16),
                _tableau(context, rows),
              ]);
        });
  }

  Widget _tableau(BuildContext context, List<Fiche> rows) => TableauSigh(
        titre: 'Documents',
        lignes: rows,
        taillePage: 20,
        nomExport: 'ged-documents',
        triInitial: 'date',
        sensInitial: 'desc',
        filtres: [
          FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [
            for (final c in qualGedCategories) OptionChamp(c.$1, c.$2)
          ]),
          FiltreTableau(nom: 'rattachement', libelle: 'Rattachement', options: [
            for (final r in qualGedRattachements) OptionChamp(r)
          ]),
          const FiltreTableau(
              nom: 'etatValidation',
              libelle: 'Validation',
              options: [
                OptionChamp('valide', 'Validé'),
                OptionChamp('en_attente', 'En attente'),
                OptionChamp('rejete', 'Rejeté'),
              ]),
          const FiltreTableau(nom: 'format', libelle: 'Format', options: [
            OptionChamp('PDF'),
            OptionChamp('JPEG'),
            OptionChamp('DOCX'),
            OptionChamp('XLSX'),
          ]),
        ],
        colonnes: [
          colonneReference(poids: FontWeight.w600),
          ColonneTableau(
              cle: 'libelle',
              libelle: 'Document',
              texte: (d) =>
                  '${d['libelle']} ${qualGedCategorieLabel(d['categorie'])}',
              rendu: (_, d) => Row(children: [
                    Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: JetonsShell.slate100,
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(iconeGed(qualGedCategorieIcone(d['categorie'])),
                            size: 14, color: JetonsShell.slate500)),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${d['libelle']}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: JetonsShell.slate800,
                                  fontSize: 14,
                                  height: 20 / 14)),
                          Text(qualGedCategorieLabel(d['categorie']),
                              style: const TextStyle(
                                  color: JetonsShell.slate400,
                                  fontSize: 12,
                                  height: 16 / 12)),
                        ])),
                  ])),
          const ColonneTableau(cle: 'rattacheA', libelle: 'Rattaché à'),
          ColonneTableau(
              cle: 'codeRattachement',
              libelle: 'Code',
              sansCoupure: true,
              texte: (d) => '${d['codeRattachement']}',
              rendu: (_, d) => cellMono('${d['codeRattachement']}',
                  couleur: JetonsShell.slate500)),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date',
              sansCoupure: true,
              texte: (d) => dateDe(d['date'])),
          ColonneTableau(
              cle: 'format',
              libelle: 'Format',
              texte: (d) => '${d['format']}',
              rendu: (_, d) => BadgeSigh('${d['format']}')),
          ColonneTableau(
              cle: 'taille',
              libelle: 'Taille',
              droite: true,
              texte: (d) => ko(d['taille'])),
          ColonneTableau(
              cle: 'version',
              libelle: 'Version',
              droite: true,
              texte: (d) => 'v${d['version']}'),
          ColonneTableau(
              cle: 'etatValidation',
              libelle: 'Validation',
              texte: (d) => qualGedValidations['${d['etatValidation']}']?.$1 ?? '—',
              rendu: (_, d) => badgeValidation(d['etatValidation'])),
          ColonneTableau(
              cle: 'signe',
              libelle: 'Signature',
              texte: (d) => d['signe'] == true ? 'Signé' : 'Non signé',
              rendu: (_, d) => d['signe'] == true
                  ? const BadgeSigh('Signé', ton: TonSigh.info)
                  : const Text('—',
                      style: TextStyle(color: JetonsShell.slate400, fontSize: 12))),
        ],
        alClicLigne: (d) => _consulter(context, d),
        actionsLigne: (ctx, d) => [
          BoutonIcone(
              icone: LucideIcons.eye,
              libelle: 'Prévisualiser',
              onPressed: () => _consulter(context, d)),
          BoutonIcone(
              icone: LucideIcons.printer,
              libelle: 'Imprimer la fiche',
              onPressed: () => imprimerGed(context, (c) => pieceFiche(d, c))),
        ],
      );

  void _consulter(BuildContext ctx, Fiche d) {
    afficherTiroir<void>(ctx,
        titre: '${d['libelle']}',
        sousTitre: '${d['reference']} — ${qualGedCategorieLabel(d['categorie'])}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              height: 224,
              decoration: BoxDecoration(
                  color: JetonsShell.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JetonsShell.slate300)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(iconeGed(qualGedCategorieIcone(d['categorie'])),
                    size: 40, color: JetonsShell.slate300),
                const SizedBox(height: 8),
                Text('Prévisualisation du document ${d['format']}',
                    style: const TextStyle(
                        color: JetonsShell.slate500, fontSize: 14, height: 20 / 14)),
                const SizedBox(height: 8),
                Text('${d['taille']} Ko — version ${d['version']}',
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12)),
              ])),
          const SizedBox(height: 16),
          DescListeSigh([
            ('Référence', '${d['reference']}'),
            ('Libellé', '${d['libelle']}'),
            ('Catégorie', qualGedCategorieLabel(d['categorie'])),
            ('Rattaché à', '${d['rattacheA']} (${d['codeRattachement']})'),
            ('Nature du rattachement', '${d['rattachement']}'),
            ('Date du document', dateDe(d['date'])),
            ('Format', '${d['format']}'),
            ('Taille', '${d['taille']} Ko'),
            ('Version', 'v${d['version']}'),
            ('Déposé par', '${d['deposePar']}'),
            ('Consultations', '${d['consultations']}'),
            ('Durée de conservation', '${d['conservation']} ans'),
            ('Signature électronique',
                d['signe'] == true
                    ? const BadgeSigh('Signé', ton: TonSigh.succes)
                    : const BadgeSigh('Non signé')),
            ('Archivage',
                d['archive'] == true
                    ? const BadgeSigh('Archivé')
                    : const BadgeSigh('Actif', ton: TonSigh.succes)),
          ]),
          const SizedBox(height: 16),
          CarteSigh(
              titre: 'Traçabilité',
              child: ChronologieSigh([
                for (final e in qualGedTrace(d))
                  (titre: e.$1, detail: e.$2, date: e.$3, ton: tonDe(e.$4)),
              ])),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer la fiche',
                  icone: LucideIcons.printer,
                  onPressed: () => imprimerGed(ctx, (c) => pieceFiche(d, c))),
            ]);
  }
}

/// `fiche(d)` : la fiche documentaire imprimée (rubrique / information).
PieceA4 pieceFiche(Fiche d, ContexteEcran c) => PieceA4(
      titre: 'Fiche documentaire',
      sousTitre: '${d['reference']}',
      reference: referenceEtat(c),
      utilisateur: c.utilisateur,
      edite: c.aujourdhui,
      cartouche: [
        ('Référence', '${d['reference']}'),
        ('Libellé', '${d['libelle']}'),
        ('Catégorie', qualGedCategorieLabel(d['categorie'])),
        ('Rattaché à', '${d['rattacheA']}'),
        ('Code de rattachement', '${d['codeRattachement']}'),
        ('Date', dateDe(d['date'])),
      ],
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Rubrique', valeur: (x) => x['k']),
          ColonneEtat(libelle: 'Information', valeur: (x) => x['v']),
        ], lignes: [
          {'k': 'Format', 'v': d['format']},
          {'k': 'Taille', 'v': '${d['taille']} Ko'},
          {'k': 'Version', 'v': 'v${d['version']}'},
          {'k': 'Déposé par', 'v': d['deposePar']},
          {'k': 'État de validation', 'v': qualGedValidations['${d['etatValidation']}']?.$1},
          {'k': 'Signature électronique', 'v': d['signe'] == true ? 'Oui' : 'Non'},
          {'k': 'Archivage', 'v': d['archive'] == true ? 'Archivé' : 'Actif'},
          {'k': 'Durée de conservation', 'v': '${d['conservation']} ans'},
          {'k': 'Consultations', 'v': '${d['consultations']}'},
        ]),
      ],
      signatures: signaturesGed(),
    );

/// L'explorateur : quatre cartes, une par nature de rattachement, avec le compte par catégorie.
class _Explorateur extends StatelessWidget {
  const _Explorateur(this.rows);
  final List<Fiche> rows;

  static const _icones = {
    'Patient': LucideIcons.user,
    'Employé': LucideIcons.idCard,
    'Fournisseur': LucideIcons.truck,
    'Administration': LucideIcons.building2,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final n = c.maxWidth >= 1024 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        final l = (c.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final r in qualGedRattachements) SizedBox(width: l, child: _carte(r)),
        ]);
      });

  Widget _carte(String r) {
    final e = qualGedExplorateur(rows, r);
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JetonsShell.slate200),
            boxShadow: JetonsShell.ombreCarte),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: JetonsShell.navy50,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(_icones[r], size: 16, color: JetonsShell.navy700)),
            const SizedBox(width: 8),
            Text('Dossiers ${r.toLowerCase()}',
                style: const TextStyle(
                    color: JetonsShell.slate800,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(nombre(e.total),
              style: const TextStyle(
                  color: JetonsShell.slate900,
                  fontSize: 24,
                  fontWeight: FontWeight.w600)),
          const Text('documents rattachés',
              style: TextStyle(color: JetonsShell.slate400, fontSize: 12)),
          const SizedBox(height: 8),
          for (final d in e.parCategorie)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                          child: Text(d.$1,
                              style: const TextStyle(
                                  color: JetonsShell.slate500, fontSize: 12))),
                      Text('${d.$2}',
                          style: const TextStyle(
                              color: JetonsShell.slate700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ])),
        ]));
  }
}
