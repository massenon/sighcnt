import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';

/// `cfg-tarifs` — « Référentiel tarifaire » : UNE source de vérité tarifaire que lisent la pharmacie, la facturation, les assurances, les rapports et la
/// comptabilité. Quatre onglets : produits & médicaments (RG-02 : prix de vente = prix d'achat), analyses de laboratoire (valeurs d'attente à confirmer),
/// actes & hospitalisation (catalogue administrable, jamais de tarif inventé) et certificats (LUS depuis le catalogue, jamais dupliqués).
class EcranTarifs extends StatelessWidget with EcranMaquette {
  const EcranTarifs({super.key});
  @override
  String get titre => 'Référentiel tarifaire';
  @override
  String get description => 'Tarif unique consommé par la pharmacie, la facturation, les assurances, les rapports et la comptabilité.';
  @override
  String get regle =>
      'Règle d’or (draf1 §22) : une seule source de vérité tarifaire. Les prix ne sont jamais dupliqués entre modules — la pharmacie, la facturation et la comptabilité lisent le même référentiel.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final produits = c.magasin.collection('produits');
    final analyses = c.magasin.collection('analyses');
    final actes = c.magasin.collection('actes');
    final catalogue = c.magasin.collection('catalogueTarifs');
    return ListenableBuilder(
        listenable: Listenable.merge([produits, analyses, actes, catalogue]),
        builder: (ctx, _) {
          final nbCertificats = catalogue.actives.where((r) => r['famille'] == 'CERTIFICAT').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisTarifs(
                produits: produits.actives.length,
                analyses: analyses.actives.length,
                actes: actes.actives.length,
                secteurs: cfaSecteursActivite(c.magasin).length,
                aConfirmer: cfaTarifsAConfirmer(analyses.actives, actes.actives))),
            const SizedBox(height: 16),
            CarteSigh(titre: 'Propagation du tarif', child: _flux()),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'produits', libelle: 'Produits & médicaments', compte: produits.actives.length, construire: (_) => const _OngletProduits()),
              OngletDef(id: 'analyses', libelle: 'Analyses de laboratoire', compte: analyses.actives.length, construire: (_) => const _OngletAnalyses()),
              OngletDef(id: 'actes', libelle: 'Actes & hospitalisation', compte: actes.actives.length, construire: (_) => const _OngletActes()),
              OngletDef(id: 'certificats', libelle: 'Certificats et Attestations', compte: nbCertificats, construire: (_) => const _OngletCertificats()),
            ]),
          ]);
        });
  }

  Widget _flux() => Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.navy400, width: 2)),
            child: const Text('TARIF MASTER', style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.navy900))),
        const Icon(LucideIcons.arrowRight, size: 16, color: JetonsShell.slate300),
        for (final x in const [
          ('Pharmacie', LucideIcons.pill),
          ('Facturation', LucideIcons.receipt),
          ('Assurances', LucideIcons.shieldCheck),
          ('Rapports', LucideIcons.chartBar),
          ('Comptabilité', LucideIcons.bookCheck),
        ])
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(x.$2, size: 14, color: JetonsShell.slate700),
                const SizedBox(width: 6),
                Text(x.$1, style: const TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: JetonsShell.slate700)),
              ])),
      ]);
}

Widget _prix(Object? v, {bool gras = false, Color? couleur}) => Text(cfaMoney(v),
    textAlign: TextAlign.right,
    style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: gras ? FontWeight.w600 : FontWeight.w400, color: couleur ?? JetonsShell.slate700));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Produits & médicaments
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _libelleCategorie(Object? id) {
  for (final c in categoriesProduit) {
    if (c.id == id) return c.label;
  }
  return '$id';
}

class _OngletProduits extends StatelessWidget {
  const _OngletProduits();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('produits');
    return cfaPile([
      const NoteSigh('RG-02 — pour les médicaments, le prix de vente est strictement égal au prix d’achat : aucune marge n’est appliquée.'),
      CfaTableau(
        collection: 'produits',
        entite: 'Produit',
        titreCreation: 'Nouveau produit tarifé',
        prefixeId: 'PRD',
        taillePage: 15,
        triInitial: 'designation',
        nomExport: 'tarifs-produits',
        archivable: false,
        filtres: [FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [for (final k in categoriesProduit) OptionChamp(k.id, k.label)])],
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (p) => '${p['code'] ?? ''}', rendu: (_, p) => cfaCode(p['code'])),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
          ColonneTableau(cle: 'categorie', libelle: 'Catégorie', texte: (p) => _libelleCategorie(p['categorie']), rendu: (_, p) => BadgeSigh(_libelleCategorie(p['categorie']), ton: TonSigh.navy)),
          const ColonneTableau(cle: 'unite', libelle: 'Unité'),
          ColonneTableau(cle: 'prixAchat', libelle: 'Prix d’achat', droite: true, texte: (p) => cfaMoney(p['prixAchat']), rendu: (_, p) => _prix(p['prixAchat'])),
          ColonneTableau(cle: 'prixVente', libelle: 'Prix de vente', droite: true, texte: (p) => cfaMoney(p['prixVente']), rendu: (_, p) => _prix(p['prixVente'], gras: true)),
          ColonneTableau(
              cle: 'marge',
              libelle: 'Marge',
              droite: true,
              valeur: (p) => (cfaNombre(p['prixVente']) ?? 0) - (cfaNombre(p['prixAchat']) ?? 0),
              texte: (p) {
                final m = (cfaNombre(p['prixVente']) ?? 0) - (cfaNombre(p['prixAchat']) ?? 0);
                return m == 0 ? 'Sans marge' : cfaMoney(m);
              },
              rendu: (_, p) {
                final m = (cfaNombre(p['prixVente']) ?? 0) - (cfaNombre(p['prixAchat']) ?? 0);
                return m == 0 ? const BadgeSigh('Sans marge', ton: TonSigh.succes) : _prix(m, gras: true, couleur: JetonsShell.warning600);
              }),
        ],
        // Création : le formulaire complet (RG-02 appliqué). Modification : quatre champs, comme la maquette (écart E846 : RG-02 n'y est pas contrôlé).
        champs: (e) => e == null
            ? [
                const ChampDef(nom: 'designation', libelle: 'Désignation', requis: true, col: ColChamp.plein),
                const ChampDef(nom: 'categorie', libelle: 'Catégorie', type: TypeChamp.select, requis: true, options: [
                  OptionChamp('medicament', 'Médicament'),
                  OptionChamp('conso_medical', 'Consommable médical'),
                  OptionChamp('reactif', 'Réactif de laboratoire'),
                  OptionChamp('conso_labo', 'Consommable de laboratoire'),
                  OptionChamp('divers', 'Divers'),
                ]),
                const ChampDef(nom: 'code', libelle: 'Code article', aide: 'Laisser vide pour une attribution automatique.'),
                const ChampDef(nom: 'unite', libelle: 'Unité'),
                const ChampDef(nom: 'prixAchat', libelle: 'Prix d’achat (FCFA)', type: TypeChamp.nombre, requis: true),
                const ChampDef(nom: 'prixVente', libelle: 'Prix de vente (FCFA)', type: TypeChamp.nombre, aide: 'RG-02 — pour un médicament, il est aligné d’office sur le prix d’achat : aucune marge.'),
                const ChampDef(nom: 'seuilAlerte', libelle: 'Seuil d’alerte', type: TypeChamp.nombre),
              ]
            : [
                const ChampDef(nom: 'designation', libelle: 'Désignation', requis: true, col: ColChamp.plein),
                const ChampDef(nom: 'prixAchat', libelle: 'Prix d’achat (FCFA)', type: TypeChamp.nombre, requis: true),
                const ChampDef(nom: 'prixVente', libelle: 'Prix de vente (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'RG-02 — pour un médicament, le prix de vente doit rester égal au prix d’achat.'),
                const ChampDef(nom: 'unite', libelle: 'Unité'),
              ],
        valeursInitiales: () => {'categorie': 'medicament'},
        fiche: (s, e) {
          if (e == null) return matSansNulsCfa(cfaFicheProduit(s, col.toutes.length));
          return {...s, 'prixAchat': cfaNombre(s['prixAchat']), 'prixVente': cfaNombre(s['prixVente'])};
        },
      ),
    ], espace: 12);
  }
}

/// Les champs nuls ne s'écrivent pas (le magasin les relit absents).
Fiche matSansNulsCfa(Fiche f) => {for (final e in f.entries) if (e.value != null) e.key: e.value};

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Analyses de laboratoire
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletAnalyses extends StatelessWidget {
  const _OngletAnalyses();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('analyses');
    return cfaPile([
      const NoteSigh(
          'Les 48 désignations proviennent du document « Tarifs des analyses de laboratoire » de la clinique. Le document source ne renseignant pas la colonne des prix, les tarifs portés ici sont des valeurs d’attente à confirmer.',
          ton: TonSigh.attention,
          icone: LucideIcons.circleQuestionMark),
      ListenableBuilder(
          listenable: col,
          builder: (ctx, _) => CfaTableau(
                collection: 'analyses',
                entite: 'Analyse',
                titreCreation: 'Nouvelle analyse au catalogue',
                prefixeId: 'ANA',
                taillePage: 15,
                triInitial: 'n',
                nomExport: 'tarifs-analyses',
                filtres: [FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [for (final k in cfaDistincts(col.actives, 'categorie')) OptionChamp(k)])],
                colonnes: [
                  const ColonneTableau(cle: 'n', libelle: 'N°', droite: true, sansCoupure: true),
                  ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (a) => '${a['code'] ?? ''}', rendu: (_, a) => cfaCode(a['code'])),
                  const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
                  ColonneTableau(cle: 'categorie', libelle: 'Catégorie', texte: (a) => '${a['categorie'] ?? ''}', rendu: (_, a) => BadgeSigh('${a['categorie'] ?? ''}', ton: TonSigh.navy)),
                  ColonneTableau(cle: 'prix', libelle: 'Tarif', droite: true, texte: (a) => cfaMoney(a['prix']), rendu: (_, a) => _prix(a['prix'], gras: true)),
                  ColonneTableau(
                      cle: 'tarifProvisoire',
                      libelle: 'Statut',
                      texte: (a) => cfaVrai(a['tarifProvisoire']) ? 'À confirmer' : 'Confirmé',
                      rendu: (_, a) => cfaVrai(a['tarifProvisoire']) ? const BadgeSigh('À confirmer', ton: TonSigh.attention) : const BadgeSigh('Confirmé', ton: TonSigh.succes)),
                ],
                champs: (e) => e == null
                    ? [
                        const ChampDef(nom: 'designation', libelle: 'Désignation', requis: true, col: ColChamp.plein),
                        const ChampDef(nom: 'categorie', libelle: 'Catégorie', requis: true),
                        const ChampDef(nom: 'code', libelle: 'Code', aide: 'Laisser vide pour une attribution automatique.'),
                        const ChampDef(nom: 'prix', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'Le document source ne renseigne pas les prix : toute valeur saisie ici reste à confirmer.'),
                        const ChampDef(nom: 'echantillon', libelle: 'Échantillon'),
                        const ChampDef(nom: 'delai', libelle: 'Délai de rendu'),
                      ]
                    : [
                        const ChampDef(nom: 'designation', libelle: 'Désignation', requis: true, col: ColChamp.plein),
                        const ChampDef(nom: 'categorie', libelle: 'Catégorie'),
                        const ChampDef(nom: 'prix', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'Valeur d’attente : le document source ne renseigne pas la colonne des prix.'),
                        const ChampDef(nom: 'delai', libelle: 'Délai de rendu'),
                      ],
                fiche: (s, e) => e == null ? cfaFicheAnalyse(s, col.toutes.length) : {...s, 'prix': cfaNombre(s['prix'])},
              )),
    ], espace: 12);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Actes & hospitalisation
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletActes extends StatelessWidget {
  const _OngletActes();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('actes');
    final secteurs = [...cfaSecteursActivite(c.magasin), 'Hospitalisation'];
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = col.actives;
          final aValider = rows.where((a) => a['prix'] == null || cfaVrai(a['tarifProvisoire'])).length;
          return cfaPile([
            for (final n in cfaNotesActes(rows))
              NoteSigh(n.texte,
                  ton: cfaTonNote(n.ton),
                  icone: n.ton == 'succes' ? LucideIcons.circleCheck : n.ton == 'attention' ? LucideIcons.circleQuestionMark : LucideIcons.gitBranch),
            CfaTableau(
              collection: 'actes',
              entite: 'Acte',
              libelleNouveau: 'Nouveau',
              titreCreation: 'Nouvelle prestation',
              prefixeId: 'ACT',
              taillePage: 20,
              triInitial: 'secteur',
              nomExport: 'tarifs-actes',
              filtres: [
                FiltreTableau(nom: 'secteur', libelle: 'Secteur', options: [for (final k in cfaDistincts(rows, 'secteur')) OptionChamp(k)]),
                FiltreTableau(nom: 'tarife', libelle: 'Tarif', options: [for (final o in cfaFiltresTarifActe) OptionChamp(o.$1, o.$2)], correspond: (r, v) => cfaCorrespondTarifActe(r, v)),
              ],
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (a) => cfaOuTiret(a['code']), rendu: (_, a) => cfaCode(cfaOuTiret(a['code']))),
                const ColonneTableau(cle: 'libelle', libelle: 'Prestation'),
                ColonneTableau(cle: 'secteur', libelle: 'Secteur', texte: (a) => '${a['secteur'] ?? ''}', rendu: (_, a) => BadgeSigh('${a['secteur'] ?? ''}', ton: TonSigh.navy)),
                ColonneTableau(
                    cle: 'prix',
                    libelle: 'Tarif non assuré',
                    droite: true,
                    valeur: (a) => a['prix'] == null ? -1 : cfaNombre(a['prix']),
                    texte: (a) => a['prix'] == null ? 'à valider' : cfaMoney(a['prix']),
                    rendu: (_, a) {
                      if (a['prix'] == null) return const BadgeSigh('à valider', ton: TonSigh.attention);
                      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        _prix(a['prix'], gras: true, couleur: cfaVrai(a['tarifProvisoire']) ? JetonsShell.warning700 : JetonsShell.slate800),
                        if (cfaVrai(a['tarifProvisoire'])) const Text('valeur d’attente', style: TextStyle(fontSize: 10, height: 1.5, color: JetonsShell.warning600)),
                      ]);
                    }),
                ColonneTableau(
                    cle: 'prixAssure',
                    libelle: 'Tarif assuré',
                    droite: true,
                    valeur: (a) => a['prixAssure'] == null ? -1 : cfaNombre(a['prixAssure']),
                    texte: (a) => cfaVrai(a['nonCouvert']) ? 'non couvert' : (a['prixAssure'] == null ? '—' : cfaMoney(a['prixAssure'])),
                    rendu: (_, a) {
                      if (cfaVrai(a['nonCouvert'])) return const BadgeSigh('non couvert');
                      if (a['prixAssure'] == null) return const Text('—', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300));
                      final pa = cfaNombre(a['prix']), as = cfaNombre(a['prixAssure']);
                      final ecart = pa != null && as != null ? pa - as : null;
                      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        _prix(a['prixAssure'], gras: true, couleur: JetonsShell.success700),
                        if (ecart != null && ecart != 0) Text('− ${cfaMoney(ecart)}', style: const TextStyle(fontSize: 10, height: 1.5, color: JetonsShell.slate400)),
                      ]);
                    }),
                ColonneTableau(
                    cle: 'source',
                    libelle: 'Origine du tarif',
                    texte: (a) => '${a['source'] ?? ''} ${a['rapprochement'] ?? ''} ${a['motifPrix'] ?? ''}'.trim(),
                    rendu: (_, a) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          cfaVrai(a['source'])
                              ? Text('${a['source']}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))
                              : const Text('—', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300)),
                          if (cfaVrai(a['rapprochement'])) Text('rapproché par ${a['rapprochement']}', style: const TextStyle(fontSize: 10, height: 1.5, color: JetonsShell.slate400)),
                          if (cfaVrai(a['motifPrix'])) Text('${a['motifPrix']}', style: const TextStyle(fontSize: 10, height: 1.5, color: JetonsShell.info600)),
                        ])),
              ],
              champs: (e) => [
                const ChampDef(nom: 'libelle', libelle: 'Libellé de la prestation', requis: true, col: ColChamp.plein),
                ChampDef(
                    nom: 'secteur',
                    libelle: 'Secteur',
                    type: TypeChamp.select,
                    requis: true,
                    options: [for (final s in secteurs) OptionChamp(s)],
                    aide: 'Secteur qui exécute l’acte — sert aussi à l’évaluation de son activité.'),
                const ChampDef(nom: 'code', libelle: 'Code', aide: 'Laisser vide pour une attribution automatique.'),
                const ChampDef(nom: 'prix', libelle: 'Tarif (FCFA)', type: TypeChamp.nombre, aide: 'Laisser vide tant que la Direction n’a pas validé le tarif : l’acte est alors signalé « à valider ».'),
                const ChampDef(nom: 'source', libelle: 'Document d’origine', col: ColChamp.plein, aide: 'Traçabilité : d’où vient ce tarif (facture, note de service, décision).'),
              ],
              valeursInitiales: () => {'secteur': secteurs.first},
              fiche: (s, e) => e == null ? cfaFicheActe(s, col.toutes.length) : {...s, 'prix': cfaNombre(s['prix'])},
              actions: [
                BoutonSigh(
                    libelle: 'Imprimer la grille tarifaire',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    taille: TailleBouton.sm,
                    onPressed: () => cfaImprimer(context,
                        titre: 'Grille tarifaire des actes et prestations',
                        sousTitre: 'Catalogue par secteur — ${dateFR(c.aujourdhui)}',
                        cartouche: [
                          ('Prestations au catalogue', nombre(rows.length)),
                          ('Tarifs validés', nombre(rows.length - aValider)),
                          ('Tarifs à valider', nombre(aValider)),
                          ('Date d’édition', dateFR(c.aujourdhui)),
                        ],
                        blocs: [
                          BlocTableau(TableauEtat(colonnes: [
                            ColonneEtat(libelle: 'Code', valeur: (l) => l['code']),
                            ColonneEtat(libelle: 'Prestation', valeur: (l) => l['libelle']),
                            ColonneEtat(libelle: 'Secteur', valeur: (l) => l['secteur']),
                            ColonneEtat(libelle: 'Tarif', droite: true, valeur: (l) => l['prix'] == null ? 'à valider' : cfaMoney(l['prix'])),
                          ], lignes: cfaTrierParSecteur(rows))),
                        ],
                        signatures: const [cfaSignDa, cfaSignDm])),
              ],
            ),
            cfaSource('Répartition des activités permettant l’évaluation des différents secteurs de la clinique — complétée des types de chambre du CDCT.'),
          ], espace: 12);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Certificats et attestations (lecture : le catalogue et les types de pièce sont la source)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletCertificats extends StatelessWidget {
  const _OngletCertificats();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final tarifes = [for (final r in c.magasin.collection('catalogueTarifs').actives) if (r['famille'] == 'CERTIFICAT') r];
    final sansTarif = cfaNoteSansTarif(c.magasin.collection('typesPiece').actives);
    return cfaPile([
      const NoteSigh(
          'Les certificats ne sont couverts par aucune assurance à l’exception de SOS — mention manuscrite de la grille tarifaire. Les tarifs se corrigent au catalogue tarifaire, les pièces dans « Types de pièces certifiantes » : cet onglet les lit, il ne les duplique pas.',
          icone: LucideIcons.fileBadge),
      TableauSigh(
        lignes: tarifes,
        taillePage: 15,
        triInitial: 'libelle',
        nomExport: 'tarifs-certificats',
        messageVide: 'Aucun certificat tarifé au catalogue.',
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (t) => '${t['code'] ?? ''}', rendu: (_, t) => cfaCode(t['code'])),
          const ColonneTableau(cle: 'libelle', libelle: 'Pièce'),
          ColonneTableau(cle: 'prixNonAssure', libelle: 'Prix non assuré', droite: true, texte: (t) => cfaMoney(t['prixNonAssure']), rendu: (_, t) => _prix(t['prixNonAssure'])),
          ColonneTableau(
              cle: 'prixAssure',
              libelle: 'Prix assuré',
              droite: true,
              texte: (t) => t['assurable'] == 'sos' ? '${cfaMoney(t['prixAssure'])} (SOS)' : 'NON COUVERT',
              rendu: (_, t) => t['assurable'] == 'sos'
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${cfaMoney(t['prixAssure'])} ', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                      const BadgeSigh('SOS seule', ton: TonSigh.info),
                    ])
                  : const BadgeSigh('NON COUVERT', ton: TonSigh.attention)),
        ],
      ),
      if (sansTarif != null) NoteSigh(sansTarif, ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
    ], espace: 12);
  }
}
