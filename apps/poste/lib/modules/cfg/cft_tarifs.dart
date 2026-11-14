import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/tarifs_poste.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../kit/validation_poste.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'tarifs_ecran.dart';

/// `cfg-tarifs` — « Tarifs et prix » (PRD-TARIFS, lot T6) : l'écran UNIQUE du référentiel de prix. Il remplace `cfa_tarifs.dart` (référentiel tarifaire) et
/// `cfa_catalogue.dart` (catalogue à deux prix) : la caisse, la prescription, les soins, l'imagerie et les certificats lisent UNE liste, au prix EN VIGUEUR à la date de
/// la pièce. Il n'écrit que dans `tarifs` et `versionsTarif` (par `TarifsPoste` : mère) ou dépose une demande que la mère applique (fileul).
///
/// PROPOSER (le droit d'éditer l'écran) et DÉCIDER (Oui ou Non : la liste de rôles de la famille, jamais `editer`) sont deux droits. Une commande d'écriture est ABSENTE sans
/// le droit, jamais grisée. Une proposition ne change rien avant le Oui ; une pièce émise garde son prix.
class EcranTarifsEtPrix extends StatefulWidget with EcranMaquette {
  const EcranTarifsEtPrix({super.key});

  @override
  String get titre => 'Tarifs et prix';
  @override
  String get description => 'Le référentiel de prix unique : prestations, analyses et imagerie, l’historique de chaque prix et les changements en attente de décision.';
  @override
  String get regle =>
      'Une seule liste de prix est lue par la caisse, la prescription, les soins, l’imagerie et les certificats. Le prix d’une pièce est celui qui était en vigueur à la date de la pièce : un changement ne touche jamais une pièce déjà émise, il se versionne par date d’effet. '
      'Proposer un changement et le valider (Oui ou Non) sont deux droits distincts ; une proposition ne change rien avant le Oui. Un prix absent se dit « à valider », jamais zéro.';

  /// L'onglet demandé de l'extérieur (une proposition enregistrée mène aux alertes) : le kit ne porte pas d'ancre globale.
  static final ValueNotifier<String?> versOnglet = ValueNotifier<String?>(null);

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      // La commande d'écriture est ABSENTE sans le droit d'éditer (jamais grisée).
      if (c.droit.editer) BoutonSigh(libelle: 'Nouvelle prestation', icone: LucideIcons.plus, onPressed: () => _modaleProposition(context, c, null)),
      BoutonSigh(
          libelle: 'Imprimer la grille',
          icone: LucideIcons.printer,
          variante: VarianteBouton.secondaire,
          onPressed: () => _imprimerGrille(context, c, [for (final l in _lignes(c, (_) => true)) if (l['etat'] != 'Sans prix en vigueur') l], 'Grille tarifaire')),
    ];
  }

  @override
  State<EcranTarifsEtPrix> createState() => _EtatTarifs();
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les données de l'écran
// ---------------------------------------------------------------------------------------------------------------------------------------------

const _famillesPrestations = [
  ('CONSULTATION', 'Consultations'),
  ('ACTE', 'Actes'),
  ('HOSPITALISATION', 'Hospitalisation'),
  ('AMI', 'Actes médico-infirmiers'),
  ('GYNECO', 'Gynéco-obstétrique et kits'),
  ('CERTIFICAT', 'Certificats et attestations'),
];
const _etatsPrix = ['En vigueur', 'Proposition en attente', 'Changement à venir', 'Provisoire', 'Sans prix en vigueur'];
const _libelleOrigine = {
  'migration': 'Migration des listes d’avant',
  'semence-grille': 'Grille imprimée des analyses',
  'ecran': 'Saisie à l’écran',
  'import': 'Importation',
};

TarifsPoste _tarifs(ContexteEcran c) => tarifsDeEcran(c);

String _jour(ContexteEcran c) => tarIso(c.aujourdhui);
String _argent(Object? x) => x == null ? 'Non renseigné' : money(x, avecDevise: false);

/// Les lignes du tableau : une par prestation, avec ce qui est en vigueur AUJOURD'HUI et ce qui attend.
List<Map<String, Object?>> _lignes(ContexteEcran c, bool Function(Map<String, Object?>) filtre) {
  final h = TarifsPoste.lire(c.magasin);
  final jour = _jour(c);
  return [
    for (final p in h.tarifs)
      if (p['statut'] != 'archive' && filtre(p))
        () {
          final s = h.instantane(p, jour);
          final vs = h.versionsDe('${p['code']}');
          final attente = vs.where((v) => v['statut'] == 'propose').length;
          final avenir = vs.where((v) => v['statut'] == 'valide' && v['dateEffet'] != null && '${v['dateEffet']}'.compareTo(jour) > 0).length;
          final etat = s == null
              ? 'Sans prix en vigueur'
              : attente > 0
                  ? 'Proposition en attente'
                  : avenir > 0
                      ? 'Changement à venir'
                      : s.provisoire
                          ? 'Provisoire'
                          : 'En vigueur';
          final couv = p['assurable'] == 'sos'
              ? 'SOS seule'
              : (p['assurable'] == false || (s != null && s.nc))
                  ? 'Non couvert'
                  : 'Toutes compagnies';
          return <String, Object?>{
            'id': p['id'],
            'code': p['code'],
            'libelle': p['libelle'],
            'famille': p['famille'],
            'secteur': p['secteur'],
            'na': s?.na,
            'pa': s?.pa,
            'etatAssure': s?.etatAssure,
            'nc': s?.nc ?? false,
            'depuis': s?.dateEffet,
            'version': s?.version,
            'attente': attente,
            'avenir': avenir,
            'etat': etat,
            'couverture': couv,
            'libelleGrille': p['libelleGrille'],
            'alias': ((p['codesAlias'] as List?) ?? const []).join(', '),
            'source': p['source'],
          };
        }()
  ];
}

String _libelleFamille(Object? f) {
  for (final x in _famillesPrestations) {
    if (x.$1 == f) return x.$2;
  }
  return f == 'LABO' ? 'Analyses' : (f == 'IMAGERIE' ? 'Imagerie' : '$f');
}

BadgeSigh _badgeEtat(Map<String, Object?> r) => BadgeSigh('${r['etat']}',
    ton: switch (r['etat']) {
      'En vigueur' => TonSigh.succes,
      'Proposition en attente' => TonSigh.attention,
      'Changement à venir' => TonSigh.info,
      'Provisoire' => TonSigh.attention,
      'Sans prix en vigueur' => TonSigh.danger,
      _ => TonSigh.neutre,
    });

String _texteAssure(Map<String, Object?> r) {
  if (r['etat'] == 'Sans prix en vigueur') return 'à valider';
  if (r['etatAssure'] == 'nc') return 'NON COUVERT';
  if (r['etatAssure'] == 'manquant') return 'à valider';
  if (r['etatAssure'] == 'unique') return 'prix unique';
  return money(r['pa'], avecDevise: false);
}

Widget _celluleAssure(Map<String, Object?> r) {
  final t = _texteAssure(r);
  if (t == 'NON COUVERT') return const BadgeSigh('NON COUVERT', ton: TonSigh.attention);
  if (t == 'à valider') return const Text('à valider', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.danger600));
  if (t == 'prix unique') return const Text('prix unique', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500));
  return Text(t, style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700));
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'écran
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _EtatTarifs extends State<EcranTarifsEtPrix> {
  String? _ancre;
  int _cle = 0;

  @override
  void initState() {
    super.initState();
    EcranTarifsEtPrix.versOnglet.addListener(_versOnglet);
    _versOnglet();
  }

  @override
  void dispose() {
    EcranTarifsEtPrix.versOnglet.removeListener(_versOnglet);
    super.dispose();
  }

  void _versOnglet() {
    final o = EcranTarifsEtPrix.versOnglet.value;
    if (o == null) return;
    EcranTarifsEtPrix.versOnglet.value = null;
    setState(() {
      _ancre = o;
      _cle++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('tarifs'), m.collection('versionsTarif'), m.collection('produits')]),
        builder: (ctx, _) {
          final tous = _lignes(c, (_) => true);
          final h = TarifsPoste.lire(m);
          final peutDecider = tarPeutDecider(c.role);
          final enAttente = [for (final v in h.versions) if (v['statut'] == 'propose') v];
          final sansPrix = tous.where((r) => r['etat'] == 'Sans prix en vigueur').length;
          int nb(Iterable<String> f) => tous.where((r) => f.contains(r['famille'])).length;
          final produits = m.collection('produits').actives;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Prestations tarifées', valeur: nombre(tous.length), icone: LucideIcons.tags, indice: 'au jour du ${dateFR(c.aujourdhui)}'),
              KpiSigh(libelle: 'Prix en vigueur', valeur: nombre(tous.length - sansPrix), icone: LucideIcons.badgeCheck, ton: TonSigh.succes),
              KpiSigh(
                  libelle: 'Propositions en attente',
                  valeur: nombre(enAttente.length),
                  icone: LucideIcons.hourglass,
                  ton: enAttente.isNotEmpty ? TonSigh.attention : TonSigh.succes,
                  indice: 'Oui ou Non à donner'),
              KpiSigh(
                  libelle: 'Sans prix en vigueur',
                  valeur: nombre(sansPrix),
                  icone: LucideIcons.triangleAlert,
                  ton: sansPrix > 0 ? TonSigh.danger : TonSigh.succes,
                  indice: 'ligne non facturable'),
            ]),
            const SizedBox(height: 16),
            OngletsSigh(
              key: ValueKey('tarifs-$_cle'),
              ancre: _ancre,
              alChangement: (id) => _ancre = id,
              onglets: [
                OngletDef(
                    id: 'prestations',
                    libelle: 'Prestations',
                    compte: nb(_famillesPrestations.map((f) => f.$1)),
                    construire: (_) => _OngletPrestations(c: c, familles: [for (final f in _famillesPrestations) f.$1], note: _notePrestations, vide: 'Aucune prestation dans cette famille.')),
                OngletDef(id: 'analyses', libelle: 'Analyses', compte: nb(const ['LABO']), construire: (_) => _OngletAnalyses(c: c)),
                OngletDef(id: 'imagerie', libelle: 'Imagerie', compte: nb(const ['IMAGERIE']), construire: (_) => _OngletImagerie(c: c)),
                OngletDef(id: 'produits', libelle: 'Produits', compte: produits.length, construire: (_) => _OngletProduits(c: c)),
                OngletDef(id: 'alertes', libelle: 'Alertes', compte: enAttente.length, construire: (_) => _OngletAlertes(c: c, peutDecider: peutDecider)),
                OngletDef(id: 'historique', libelle: 'Historique', construire: (_) => _OngletHistorique(c: c)),
              ],
            ),
          ]);
        });
  }
}

const _notePrestations =
    'Consultations, actes, hospitalisation (la journée par type de chambre), actes médico-infirmiers, gynéco-obstétrique et certificats. Le libellé de facturation est celui sur lequel les conventions d’assurance s’appuient pour leurs exclusions : il ne se change pas à la légère.';

// --- Un tableau de prestations (commun aux trois premiers onglets) ----------------------------------------------------------------------------

class _TableauPrestations extends StatelessWidget {
  const _TableauPrestations({required this.c, required this.lignes, required this.vide});
  final ContexteEcran c;
  final List<Map<String, Object?>> lignes;
  final String vide;

  @override
  Widget build(BuildContext context) => TableauSigh(
        lignes: trierPar(lignes, (r) => r['code']),
        taillePage: 15,
        nomExport: 'tarifs-et-prix',
        messageVide: vide,
        filtres: [
          FiltreTableau(nom: 'etat', libelle: 'État du prix', options: [for (final e in _etatsPrix) OptionChamp(e)]),
          FiltreTableau(nom: 'couverture', libelle: 'Couverture', options: const [OptionChamp('Toutes compagnies'), OptionChamp('SOS seule'), OptionChamp('Non couvert')]),
        ],
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (r) => '${r['code']}', rendu: (_, r) => cfaCode(r['code'])),
          const ColonneTableau(cle: 'libelle', libelle: 'Libellé de facturation'),
          ColonneTableau(cle: 'famille', libelle: 'Famille', texte: (r) => _libelleFamille(r['famille'])),
          ColonneTableau(
              cle: 'secteur',
              libelle: 'Secteur',
              texte: (r) => '${r['secteur'] ?? 'Non renseigné'}',
              rendu: (_, r) => r['secteur'] == null || r['secteur'] == ''
                  ? const Text('Non renseigné', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.slate400))
                  : Text('${r['secteur']}')),
          ColonneTableau(
              cle: 'na',
              libelle: 'Prix non assuré',
              droite: true,
              valeur: (r) => r['na'] ?? -1,
              texte: (r) => r['na'] == null ? 'à valider' : money(r['na'], avecDevise: false),
              rendu: (_, r) => r['na'] == null
                  ? const Text('à valider', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.danger600))
                  : Text(money(r['na'], avecDevise: false), style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate700))),
          ColonneTableau(cle: 'pa', libelle: 'Prix assuré', droite: true, texte: _texteAssure, rendu: (_, r) => _celluleAssure(r)),
          const ColonneTableau(cle: 'couverture', libelle: 'Couverture'),
          ColonneTableau(
              cle: 'depuis',
              libelle: 'En vigueur depuis',
              sansCoupure: true,
              texte: (r) => r['version'] == null ? '' : (r['depuis'] != null ? dateFR(DateTime.parse('${r['depuis']}')) : 'L’origine')),
          ColonneTableau(cle: 'version', libelle: 'Version', droite: true, texte: (r) => r['version'] == null ? '' : 'v${r['version']}'),
          ColonneTableau(cle: 'etat', libelle: 'État', texte: (r) => '${r['etat']}', rendu: (_, r) => _badgeEtat(r)),
        ],
        actionsLigne: (ctx, r) => [
          BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _tiroirPrestation(ctx, c, r)),
          // « Proposer » est une commande d'ÉCRITURE : absente sans le droit d'éditer.
          if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Proposer un changement', onPressed: () => _modaleProposition(ctx, c, r)),
          ..._boutonValider(ctx, c, '${r['code']}'),
        ],
      );
}

/// La commande « Valider » des familles « Tarifs des actes » et « Tarifs des analyses » : l'élément de la fiche de lecture qui porte encore son marquage « tarif d'attente ».
List<Widget> _boutonValider(BuildContext ctx, ContexteEcran c, String code) {
  final h = TarifsPoste.lire(c.magasin);
  final p = h.parCode[code];
  if (p == null) return const [];
  final vp = ValidationPoste(c);
  for (final x in [('actes', p['codeActe']), ('analyses', p['codeAnalyse'])]) {
    if (x.$2 == null) continue;
    final fiche = c.magasin.collection(x.$1).actives.where((f) => f['code'] == x.$2).firstOrNull;
    if (fiche == null) continue;
    final e = vp.etat(x.$1, fiche['id']);
    if (e != null && e.enAttente) return vp.boutons(ctx, x.$1, fiche['id']);
  }
  return const [];
}

// --- Les onglets -------------------------------------------------------------------------------------------------------------------------------

class _OngletPrestations extends StatelessWidget {
  const _OngletPrestations({required this.c, required this.familles, required this.note, required this.vide});
  final ContexteEcran c;
  final List<String> familles;
  final String note;
  final String vide;

  @override
  Widget build(BuildContext context) => cfaPile([
        NoteSigh(note),
        _TableauPrestations(c: c, lignes: _lignes(c, (p) => familles.contains(p['famille'])), vide: vide),
      ], espace: 12);
}

class _OngletAnalyses extends StatelessWidget {
  const _OngletAnalyses({required this.c});
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) {
    final h = TarifsPoste.lire(c.magasin);
    final sansGrille = [for (final p in h.tarifs) if (p['codeAnalyse'] != null && p['codeGrille'] == null) '${p['code']}'];
    final sansAnalyse = [for (final p in h.tarifs) if (p['famille'] == 'LABO' && p['codeGrille'] != null && p['codeAnalyse'] == null && p['codeActe'] == null) '${p['code']}'];
    return cfaPile([
      const NoteSigh(
          'Le prix des analyses se propose et se décide ici. La désignation, l’échantillon, le délai et le modèle de résultat restent au catalogue des analyses du laboratoire. Les prix de la grille imprimée sont des propositions (onglet Alertes) : le prix facturé aujourd’hui reste celui de la caisse tant que la Direction n’a pas répondu Oui.'),
      if (sansGrille.isNotEmpty || sansAnalyse.isNotEmpty)
        NoteSigh(
            'Écarts entre les sources. ${sansGrille.length} analyse(s) n’ont aucune ligne de grille de même libellé (${sansGrille.join(', ')}) : un seul prix, celui de la caisse. ${sansAnalyse.length} ligne(s) de grille LABO n’ont pas d’analyse (${sansAnalyse.isEmpty ? 'aucune' : sansAnalyse.join(', ')}).',
            ton: TonSigh.attention,
            icone: LucideIcons.scale),
      Align(
          alignment: Alignment.centerLeft,
          child: BoutonSigh(
              libelle: 'Ouvrir le catalogue des analyses',
              icone: LucideIcons.listChecks,
              variante: VarianteBouton.secondaire,
              onPressed: () => c.aller('m5-catalogue'))),
      _TableauPrestations(c: c, lignes: _lignes(c, (p) => p['famille'] == 'LABO'), vide: 'Aucune analyse.'),
    ], espace: 12);
  }
}

class _OngletImagerie extends StatelessWidget {
  const _OngletImagerie({required this.c});
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) => cfaPile([
        const NoteSigh(
            'Les prix des examens d’imagerie. Le modèle de compte rendu (variables, modalités) reste au catalogue de l’imagerie. Les seize tarifs d’attente (radiographie, mammographie, scanner, IRM) sont marqués « provisoire » tant que la Direction ne les a pas arrêtés.',
            icone: LucideIcons.scanLine),
        Align(
            alignment: Alignment.centerLeft,
            child: BoutonSigh(
                libelle: 'Ouvrir le catalogue de l’imagerie',
                icone: LucideIcons.scanLine,
                variante: VarianteBouton.secondaire,
                onPressed: () => c.aller('cfg-imagerie-catalogue'))),
        _TableauPrestations(c: c, lignes: _lignes(c, (p) => p['famille'] == 'IMAGERIE'), vide: 'Aucun examen d’imagerie.'),
      ], espace: 12);
}

class _OngletProduits extends StatelessWidget {
  const _OngletProduits({required this.c});
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) {
    final produits = c.magasin.collection('produits').actives;
    final peutOuvrir = c.donnees?.matrice.peutVoir(c.role, 'm6-produits') ?? false;
    String categorie(Object? id) {
      for (final k in categoriesProduit) {
        if (k.id == id) return k.label;
      }
      return '$id';
    }

    return cfaPile([
      const NoteSigh(
          'Lecture seule. RG-02 : un médicament se facture au prix d’achat, sans marge. Les prix affichés sont ceux de la version EN VIGUEUR aujourd’hui (jamais la fiche) ; ils se changent au référentiel des produits (« Changer le prix d’achat »).',
          icone: LucideIcons.pill),
      if (peutOuvrir)
        Align(
            alignment: Alignment.centerLeft,
            child: BoutonSigh(
                libelle: 'Ouvrir le référentiel des produits',
                icone: LucideIcons.pill,
                variante: VarianteBouton.secondaire,
                onPressed: () => c.aller('m6-produits'))),
      TableauSigh(
        lignes: produits,
        taillePage: 15,
        triInitial: 'designation',
        nomExport: 'produits-lecture',
        filtres: [FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [for (final k in categoriesProduit) OptionChamp(k.id, k.label)])],
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (p) => '${p['code'] ?? ''}', rendu: (_, p) => cfaCode(p['code'])),
          const ColonneTableau(cle: 'designation', libelle: 'Désignation'),
          ColonneTableau(cle: 'categorie', libelle: 'Catégorie', texte: (p) => categorie(p['categorie'])),
          ColonneTableau(
              cle: 'prixAchat',
              libelle: 'Prix d’achat',
              droite: true,
              valeur: (p) => achatDuJour(c, p),
              texte: (p) => aValoriser(c, p) ? 'À valoriser' : _argent(achatDuJour(c, p))),
          ColonneTableau(
              cle: 'prixVente',
              libelle: 'Prix de vente',
              droite: true,
              valeur: (p) => venteDuJour(c, p),
              texte: (p) => aValoriser(c, p) ? 'À valoriser' : _argent(venteDuJour(c, p)),
              rendu: (_, p) => Text(aValoriser(c, p) ? 'À valoriser' : _argent(venteDuJour(c, p)), style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate700))),
          ColonneTableau(
              cle: 'marge',
              libelle: 'Marge',
              droite: true,
              valeur: (p) => nombreOuZero(venteDuJour(c, p)) - nombreOuZero(achatDuJour(c, p)),
              texte: (p) => nombreOuZero(venteDuJour(c, p)) - nombreOuZero(achatDuJour(c, p)) == 0 ? 'Sans marge' : money(nombreOuZero(venteDuJour(c, p)) - nombreOuZero(achatDuJour(c, p)), avecDevise: false),
              rendu: (_, p) {
                final mg = nombreOuZero(venteDuJour(c, p)) - nombreOuZero(achatDuJour(c, p));
                return mg == 0
                    ? const BadgeSigh('Sans marge', ton: TonSigh.succes)
                    : Text(money(mg, avecDevise: false), style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.warning600));
              }),
        ],
      ),
    ], espace: 12);
  }
}

// --- Les alertes : les changements en attente de Oui ou Non ------------------------------------------------------------------------------------

/// La comparaison LIGNE À LIGNE des propositions : ancien et nouveau prix, variation, colonne assurée, date d'effet, pièces des 30 derniers jours.
List<Map<String, Object?>> _comparaison(ContexteEcran c, List<Map<String, Object?>> versions) {
  final h = TarifsPoste.lire(c.magasin);
  final jour = _jour(c);
  final pieces = TarifsPoste.pieces(c.magasin);
  String assure(String? etat, Object? montant, {bool courant = false}) => switch (etat) {
        'nc' => 'NON COUVERT',
        'unique' => 'prix unique',
        'montant' => money(montant, avecDevise: false),
        _ => courant ? 'Sans prix' : 'à valider',
      };
  return [
    for (final v in versions)
      () {
        final p = h.parCode['${v['code']}'] ?? const <String, Object?>{};
        final s = p.isEmpty ? null : h.instantane(p, (v['dateEffet'] as String?) ?? jour);
        return <String, Object?>{
          'v': v,
          'id': v['id'],
          'code': v['code'],
          'libelle': p['libelle'] ?? v['code'],
          'actuelNA': s?.na,
          'propose': v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure'],
          'pct': tarVariationPct(h, v, jour),
          'actuelA': s == null ? 'Sans prix' : assure(s.etatAssure, s.pa),
          'proposeA': assure('${v['etatAssure']}', v['prixAssure']),
          'pieces': p.isEmpty ? 0 : tarPiecesRecentes(p, 30, pieces, aujourdhui: jour),
        };
      }()
  ];
}

String _texteVariation(Object? pct) {
  if (pct == null) return 'non comparable';
  final x = pct as num;
  final t = x.toString().replaceAll('.', ',');
  return '${x > 0 ? '+' : ''}${t.endsWith(',0') ? t.substring(0, t.length - 2) : t} %';
}

class _OngletAlertes extends StatefulWidget {
  const _OngletAlertes({required this.c, required this.peutDecider});
  final ContexteEcran c;
  final bool peutDecider;

  @override
  State<_OngletAlertes> createState() => _EtatAlertes();
}

class _EtatAlertes extends State<_OngletAlertes> {
  final GlobalKey<TableauSighState> _tableau = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final h = TarifsPoste.lire(c.magasin);
    final enAttente = [for (final v in h.versions) if (v['statut'] == 'propose') v];
    final cmp = _comparaison(c, enAttente);
    final lignes = [
      for (final r in cmp)
        () {
          final v = r['v'] as Map<String, Object?>;
          return <String, Object?>{
            ...r,
            'lot': _libelleOrigine[v['origine']] ?? v['origine'],
            'dateEffet': v['dateEffet'] ?? '',
            'par': v['proposePar'] ?? '',
            'motif': v['motif'] ?? '',
          };
        }()
    ];
    return cfaPile([
      if (widget.peutDecider && enAttente.isNotEmpty)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          BoutonSigh(
              libelle: 'Oui à tout',
              icone: LucideIcons.checkCheck,
              variante: VarianteBouton.secondaire,
              onPressed: () {
                final choisies = _tableau.currentState?.lignesFiltrees ?? lignes;
                if (choisies.isEmpty) {
                  ToastsSigh.afficher(context, 'Aucune proposition affichée.', type: TypeToast.attention);
                  return;
                }
                _ouiATout(context, c, [for (final r in choisies) r['v'] as Map<String, Object?>]);
              }),
          const Text('Porte sur les lignes affichées (filtres et recherche compris) ; la comparaison ligne à ligne s’affiche avant toute acceptation en bloc.',
              style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
        ]),
      NoteSigh(
          'Chaque ligne est un changement de prix en attente : l’ancien prix reste en vigueur, le nouveau ne s’applique qu’après le Oui, à sa date d’effet. Un Non exige son motif. '
          '${widget.peutDecider ? 'Vous pouvez décider.' : 'Décider revient à la Direction, à la Directrice Administrative et à l’administrateur : vous lisez les propositions sans les trancher.'}',
          ton: TonSigh.attention,
          icone: LucideIcons.hourglass),
      TableauSigh(
        key: _tableau,
        lignes: lignes,
        taillePage: 15,
        nomExport: 'prix-en-attente',
        messageVide: 'Aucun changement de prix en attente.',
        filtres: [FiltreTableau(nom: 'lot', libelle: 'Origine', options: [for (final o in _libelleOrigine.values) OptionChamp(o)])],
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (r) => '${r['code']}', rendu: (_, r) => cfaCode(r['code'])),
          const ColonneTableau(cle: 'libelle', libelle: 'Prestation'),
          ColonneTableau(cle: 'actuelNA', libelle: 'Non assuré en vigueur', droite: true, texte: (r) => _argent(r['actuelNA'])),
          ColonneTableau(
              cle: 'propose',
              libelle: 'Non assuré proposé',
              droite: true,
              texte: (r) => _argent(r['propose']),
              rendu: (_, r) => Text(_argent(r['propose']), style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate700))),
          ColonneTableau(cle: 'pct', libelle: 'Variation', droite: true, texte: (r) => _texteVariation(r['pct'])),
          ColonneTableau(cle: 'proposeA', libelle: 'Assuré proposé', droite: true),
          ColonneTableau(
              cle: 'dateEffet',
              libelle: 'Date d’effet',
              sansCoupure: true,
              texte: (r) => r['dateEffet'] == '' ? 'à fixer au Oui' : dateFR(DateTime.parse('${r['dateEffet']}')),
              rendu: (_, r) => r['dateEffet'] == ''
                  ? const Text('à fixer au Oui', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.slate500))
                  : Text(dateFR(DateTime.parse('${r['dateEffet']}')))),
          ColonneTableau(
              cle: 'pieces',
              libelle: 'Pièces (30 jours)',
              droite: true,
              texte: (r) => nombre(r['pieces']),
              rendu: (_, r) => Tooltip(
                  message: 'Pièces de vente portant cette prestation sur les trente derniers jours : ce que le changement touchera', child: Text(nombre(r['pieces'])))),
          const ColonneTableau(cle: 'lot', libelle: 'Origine'),
          const ColonneTableau(cle: 'par', libelle: 'Proposée par'),
          ColonneTableau(
              cle: 'motif',
              libelle: 'Motif',
              texte: (r) => '${r['motif']}',
              rendu: (_, r) => Text('${r['motif']}'.length > 90 ? '${'${r['motif']}'.substring(0, 90)}…' : '${r['motif']}',
                  style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600))),
        ],
        // Les boutons Oui et Non sont ABSENTS hors de la liste de rôles de la famille ; le moteur refuse de toute façon.
        actionsLigne: (ctx, r) => !widget.peutDecider
            ? const []
            : [
                BoutonSigh(libelle: 'Oui', icone: LucideIcons.check, taille: TailleBouton.sm, onPressed: () => _decider(ctx, c, r['v'] as Map<String, Object?>, 'oui')),
                BoutonSigh(
                    libelle: 'Non', icone: LucideIcons.x, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _decider(ctx, c, r['v'] as Map<String, Object?>, 'non')),
              ],
      ),
    ], espace: 12);
  }
}

// --- L'historique ------------------------------------------------------------------------------------------------------------------------------

class _OngletHistorique extends StatefulWidget {
  const _OngletHistorique({required this.c});
  final ContexteEcran c;

  @override
  State<_OngletHistorique> createState() => _EtatHistorique();
}

class _EtatHistorique extends State<_OngletHistorique> {
  late final ControleurFormulaire _choix;

  @override
  void initState() {
    super.initState();
    final h = TarifsPoste.lire(widget.c.magasin);
    _choix = ControleurFormulaire([
      ChampDef(
          nom: 'code',
          libelle: 'Prestation',
          type: TypeChamp.select,
          col: ColChamp.plein,
          indicatif: 'Choisir une prestation',
          options: [
            for (final p in trierPar([for (final p in h.tarifs) if (p['statut'] != 'archive') p], (p) => p['code'])) OptionChamp('${p['code']}', '${p['code']} : ${p['libelle']}')
          ]),
    ]);
  }

  @override
  void dispose() {
    _choix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => cfaPile([
        const NoteSigh('Toutes les versions d’un prix, y compris les propositions refusées ou retirées : l’historique ne vit pas au journal d’audit, qui est plafonné.', icone: LucideIcons.history),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 576), child: FormulaireSigh(controleur: _choix)),
        ListenableBuilder(
            listenable: _choix,
            builder: (_, __) {
              final code = '${_choix['code'] ?? ''}';
              return code.isEmpty ? const SizedBox.shrink() : _BlocHistorique(c: widget.c, code: code);
            }),
      ], espace: 12);
}

String _colonneAssure(Map<String, Object?> v) => switch (v['etatAssure']) {
      'nc' => 'NON COUVERT',
      'manquant' => 'à valider',
      'unique' => 'prix unique',
      _ => money(v['prixAssure'], avecDevise: false),
    };

/// L'historique d'un prix : toutes les versions, la comparaison de deux d'entre elles.
class _BlocHistorique extends StatefulWidget {
  const _BlocHistorique({required this.c, required this.code});
  final ContexteEcran c;
  final String code;

  @override
  State<_BlocHistorique> createState() => _EtatBloc();
}

class _EtatBloc extends State<_BlocHistorique> {
  int? _a, _b;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final h = TarifsPoste.lire(c.magasin);
    final vs = h.versionsDe(widget.code);
    if (vs.isEmpty) return const NoteSigh('Aucune version de prix pour cette prestation.');
    final jour = _jour(c);
    final enVigueur = h.enVigueur(widget.code, jour);
    BadgeSigh etat(Map<String, Object?> v) {
      if (v['statut'] == 'propose') return const BadgeSigh('Proposée', ton: TonSigh.attention);
      if (v['statut'] == 'refuse') return const BadgeSigh('Refusée', ton: TonSigh.danger);
      if (v['statut'] == 'retire') return const BadgeSigh('Retirée', ton: TonSigh.neutre);
      if (enVigueur != null && enVigueur['id'] == v['id']) return const BadgeSigh('En vigueur', ton: TonSigh.succes);
      if (v['dateEffet'] != null && '${v['dateEffet']}'.compareTo(jour) > 0) return const BadgeSigh('À venir', ton: TonSigh.info);
      return const BadgeSigh('Remplacée', ton: TonSigh.neutre);
    }

    String na(Map<String, Object?> v) => _argent(v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure']);
    final liste = vs.reversed.toList();
    final a = vs.firstWhere((v) => v['version'] == (_a ?? (vs.length > 1 ? vs[vs.length - 2]['version'] : vs.last['version'])), orElse: () => vs.first);
    final b = vs.firstWhere((v) => v['version'] == (_b ?? vs.last['version']), orElse: () => vs.last);
    String ecart(num? x, num? y) {
      if (x == null || y == null) return 'non comparable';
      final d = y - x;
      return '${d >= 0 ? '+' : ''}${money(d, avecDevise: false)}${x != 0 ? ' (${_texteVariation(((d / x) * 1000).roundToDouble() / 10).replaceAll(' %', '')} %)' : ''}';
    }

    num? nv(Map<String, Object?> v) => v['etatNonAssure'] == 'manquant' ? null : v['prixNonAssure'] as num?;
    return cfaPile([
      TableauSigh(
        lignes: liste,
        recherche: false,
        taillePage: 20,
        nomExport: 'historique-prix-${widget.code}',
        colonnes: [
          const ColonneTableau(cle: 'version', libelle: 'Version', droite: true, sansCoupure: true),
          ColonneTableau(
              cle: 'dateEffet',
              libelle: 'Date d’effet',
              sansCoupure: true,
              texte: (v) => v['dateEffet'] != null ? dateFR(DateTime.parse('${v['dateEffet']}')) : (v['aDater'] == true ? 'à fixer à la décision' : 'Depuis l’origine')),
          ColonneTableau(cle: 'prixNonAssure', libelle: 'Non assuré', droite: true, texte: na),
          ColonneTableau(cle: 'prixAssure', libelle: 'Assuré', droite: true, texte: _colonneAssure),
          ColonneTableau(cle: 'statut', libelle: 'Statut', texte: (v) => '${v['statut']}', rendu: (_, v) => etat(v)),
          ColonneTableau(cle: 'origine', libelle: 'Origine', texte: (v) => _libelleOrigine[v['origine']] ?? '${v['origine'] ?? 'Non renseigné'}'),
          ColonneTableau(
              cle: 'proposePar',
              libelle: 'Proposée par',
              texte: (v) => v['proposePar'] != null ? '${v['proposePar']}${v['proposeLe'] != null ? ' le ${dateFR(DateTime.parse('${v['proposeLe']}'))}' : ''}' : 'Non renseigné'),
          ColonneTableau(
              cle: 'decidePar',
              libelle: 'Décidée par',
              texte: (v) => v['decidePar'] != null
                  ? '${v['decidePar']}${v['roleDecision'] != null ? ' (${v['roleDecision']})' : ''}${v['decideLe'] != null ? ' le ${dateFR(DateTime.parse('${v['decideLe']}'))}' : ''}'
                  : (v['statut'] == 'propose' ? 'En attente' : 'Non renseigné')),
          ColonneTableau(cle: 'motif', libelle: 'Motif', texte: (v) => v['motifDecision'] != null ? '${v['motif']} / ${v['motifDecision']}' : '${v['motif'] ?? 'Non renseigné'}'),
        ],
      ),
      if (vs.length > 1)
        CarteSigh(
            titre: 'Comparer deux versions',
            child: cfaPile([
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                _SelectVersion(libelle: 'Version de départ', vs: vs, valeur: a['version'] as int, alChange: (x) => setState(() => _a = x)),
                const Text('vers', style: TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate500)),
                _SelectVersion(libelle: 'Version comparée', vs: vs, valeur: b['version'] as int, alChange: (x) => setState(() => _b = x)),
              ]),
              DescListeSigh([
                ('Prix non assuré', '${na(a)} vers ${na(b)}'),
                ('Variation du non assuré', ecart(nv(a), nv(b))),
                ('Prix assuré', '${_colonneAssure(a)} vers ${_colonneAssure(b)}'),
                ('Variation de l’assuré', a['etatAssure'] == 'montant' && b['etatAssure'] == 'montant' ? ecart(a['prixAssure'] as num?, b['prixAssure'] as num?) : 'non comparable'),
              ]),
            ], espace: 12)),
    ], espace: 12);
  }
}

class _SelectVersion extends StatelessWidget {
  const _SelectVersion({required this.libelle, required this.vs, required this.valeur, required this.alChange});
  final String libelle;
  final List<Map<String, Object?>> vs;
  final int valeur;
  final ValueChanged<int> alChange;

  @override
  Widget build(BuildContext context) => SelecteurSigh(
      libelle: libelle,
      recherche: false,
      valeur: '$valeur',
      options: [
        for (final v in vs)
          OptionChamp('${v['version']}', 'Version ${v['version']}${v['dateEffet'] != null ? ' (${dateFR(DateTime.parse('${v['dateEffet']}'))})' : ''}'),
      ],
      surChange: (x) {
        final n = int.tryParse(x);
        if (n != null) alChange(n);
      });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les gestes : consulter, proposer, décider, tout accepter, imprimer
// ---------------------------------------------------------------------------------------------------------------------------------------------

void _tiroirPrestation(BuildContext ctx, ContexteEcran c, Map<String, Object?> r) => afficherTiroir<void>(ctx,
    titre: '${r['code']} : ${r['libelle']}',
    sousTitre: 'Version en vigueur et historique des prix',
    largeurMax: 768,
    corps: cfaPile([
      DescListeSigh([
        ('Code', '${r['code']}'),
        ('Libellé de facturation', '${r['libelle']}'),
        ('Libellé de la grille', '${r['libelleGrille'] ?? 'Identique'}'),
        ('Famille', '${r['famille']}'),
        ('Autres codes', '${r['alias'] == '' ? 'Aucun' : r['alias']}'),
        ('Secteur', '${r['secteur'] ?? 'Non renseigné'}'),
        ('Couverture', '${r['couverture']}'),
        ('Origine du prix', '${r['source'] ?? 'Non renseigné'}'),
      ]),
      if ((r['attente'] as int) > 0)
        NoteSigh('${r['attente']} proposition(s) en attente pour cette prestation : le prix en vigueur ne change pas avant le Oui.', ton: TonSigh.attention, icone: LucideIcons.hourglass),
      _BlocHistorique(c: c, code: '${r['code']}'),
    ]));

void _imprimerGrille(BuildContext ctx, ContexteEcran c, List<Map<String, Object?>> lignes, String titre) => cfaImprimer(ctx,
    titre: titre,
    sousTitre: 'Prix en vigueur au ${dateFR(c.aujourdhui)} : ${lignes.length} prestations',
    blocs: [
      BlocTableau(TableauEtat(colonnes: [
        ColonneEtat(libelle: 'Code', valeur: (r) => r['code']),
        ColonneEtat(libelle: 'Libellé', valeur: (r) => r['libelle']),
        ColonneEtat(libelle: 'Non assuré', droite: true, valeur: (r) => _argent(r['na'])),
        ColonneEtat(libelle: 'Assuré', droite: true, valeur: (r) => r['etatAssure'] == 'nc' ? 'NON COUVERT' : (r['etatAssure'] == 'unique' ? 'prix unique' : _argent(r['pa']))),
        ColonneEtat(libelle: 'Version', droite: true, valeur: (r) => r['version'] == null ? '' : '${r['version']}'),
      ], lignes: lignes)),
    ],
    signatures: const [cfaSignDa, Signature('La Direction')]);

/// La modale de proposition d'un changement de prix (ou, sans [ligne], d'une nouvelle prestation).
void _modaleProposition(BuildContext ctx, ContexteEcran c, Map<String, Object?>? ligne) {
  final h = TarifsPoste.lire(c.magasin);
  final p = ligne == null ? null : h.parCode['${ligne['code']}'];
  final s = p == null ? null : h.instantane(p, _jour(c));
  final tarifs = _tarifs(c);
  final peutPassee = tarRolesDatePassee.contains(c.role);
  final peutValider = tarPeutDecider(c.role);
  final defs = <ChampDef>[
    if (ligne == null) ...[
      const ChampDef(nom: 'code', libelle: 'Code', requis: true),
      const ChampDef(nom: 'libelle', libelle: 'Libellé de facturation', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'famille', libelle: 'Famille', type: TypeChamp.select, requis: true, options: [
        for (final f in _famillesPrestations) OptionChamp(f.$1, f.$2),
        const OptionChamp('LABO', 'Analyses de laboratoire'),
        const OptionChamp('IMAGERIE', 'Imagerie médicale'),
      ]),
      const ChampDef(nom: 'secteur', libelle: 'Secteur'),
    ],
    const ChampDef(nom: 'prixNonAssure', libelle: 'Prix non assuré (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'Un montant entier, strictement positif.'),
    const ChampDef(nom: 'etatAssure', libelle: 'Colonne assurée', type: TypeChamp.select, requis: true, options: [
      OptionChamp('montant', 'Un montant'),
      OptionChamp('nc', 'NON COUVERT par les assurances'),
      OptionChamp('manquant', 'Non renseignée (ligne non facturable à l’assuré)'),
      OptionChamp('unique', 'Prix unique (aucune colonne assurée)'),
    ]),
    const ChampDef(nom: 'prixAssure', libelle: 'Prix assuré (FCFA)', type: TypeChamp.nombre, aide: 'Renseigné seulement quand la colonne assurée est un montant.'),
    ChampDef(
        nom: 'dateEffet',
        libelle: 'Date d’effet',
        type: TypeChamp.date,
        requis: true,
        aide: peutPassee
            ? 'Aujourd’hui ou plus tard ; une date antérieure se coche ci-dessous et se motive. Le prix en vigueur ne change qu’à cette date, et seulement après un Oui.'
            : 'Au plus tôt aujourd’hui. Le prix en vigueur ne change qu’à cette date, et seulement après un Oui.'),
    if (peutPassee)
      const ChampDef(
          nom: 'datePassee',
          libelle: 'Date antérieure à aujourd’hui (refusée si une pièce porte déjà cette prestation depuis cette date)',
          type: TypeChamp.case_,
          col: ColChamp.plein),
    const ChampDef(nom: 'motif', libelle: 'Motif du changement', type: TypeChamp.textarea, requis: true, col: ColChamp.plein),
  ];
  final ctl = ControleurFormulaire(defs, {
    'etatAssure': s?.etatAssure ?? 'montant',
    'dateEffet': _jour(c),
    if (s?.na != null) 'prixNonAssure': '${s!.na}',
    if (s != null && s.etatAssure == 'montant' && s.pa != null) 'prixAssure': '${s.pa}',
  });
  // L'INFO-BULLE (T6, Direction, 11/11/2026) : l'utilisateur qui modifie un prix apprend que la date passée est une autorité de la DAF et de la Direction ; les profils sont
  // lus du moteur, jamais écrits ici.
  final msgInfo = peutPassee
      ? 'Vous détenez l’autorité de la date d’effet antérieure : cochez la case et motivez. Elle est refusée si une pièce porte déjà cette prestation depuis cette date.'
      : 'Une date d’effet antérieure à aujourd’hui est une autorité de ${tarProfilsDatePassee(ValidationPoste(c).libelles)} : demandez-la à l’un de ces profils.';
  void envoyer(BuildContext modale, VoidCallback fermer, bool valider) {
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(modale, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final d = DemandeProposition(
      code: ligne != null ? '${ligne['code']}' : '${v['code']}'.trim(),
      prixNonAssure: v['prixNonAssure'],
      etatAssure: '${v['etatAssure']}',
      prixAssure: v['prixAssure'],
      dateEffet: '${v['dateEffet']}',
      motif: '${v['motif'] ?? ''}',
      datePassee: v['datePassee'] == true,
      valider: valider,
      creation: ligne == null
          ? {'libelle': v['libelle'], 'famille': v['famille'], 'secteur': (v['secteur'] ?? '') == '' ? null : v['secteur'], 'source': 'Saisi à l’écran « Tarifs et prix »'}
          : null,
    );
    final r = tarifs.proposer(d);
    if (!r.ok) {
      ToastsSigh.afficher(modale, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
      return;
    }
    fermer();
    if (r.depose) {
      ToastsSigh.afficher(ctx, 'Demande déposée à la mère : elle l’applique après avoir refait les contrôles.',
          type: TypeToast.succes, detail: 'Ce poste ne peut pas écrire une version de prix (la mère seule écrit) ; le verdict revient ici.');
    } else if (r.valideeEnUnGeste) {
      ToastsSigh.afficher(ctx, 'Changement de prix validé : il prend effet le ${dateFR(DateTime.parse('${r.version!['dateEffet']}'))}.',
          type: TypeToast.succes, detail: 'Validé en un geste par votre rôle ; les pièces déjà émises gardent leur prix.');
    } else {
      ToastsSigh.afficher(ctx, 'Proposition enregistrée : elle attend la décision (Oui ou Non).',
          type: TypeToast.succes, detail: 'Le prix en vigueur ne change pas avant le Oui.');
      EcranTarifsEtPrix.versOnglet.value = 'alertes';
    }
  }

  afficherModale<void>(ctx,
      titre: ligne != null ? 'Proposer un changement de prix' : 'Nouvelle prestation',
      sousTitre: ligne != null ? '${ligne['code']} : ${ligne['libelle']}' : null,
      corps: cfaPile([
        NoteSigh(ligne != null
            ? 'Prix en vigueur aujourd’hui : ${_argent(s?.na)} non assuré. Une proposition ne change rien tant que la Direction, la Directrice Administrative ou l’administrateur n’a pas répondu Oui ; les pièces déjà émises gardent leur prix.'
            : 'La prestation est créée sans prix en vigueur : elle ne se facture qu’après le Oui qui valide sa première version.'),
        NoteSigh(
            'Deux états, visibles : « Enregistrer » dépose une proposition (à valider : rien ne change) ; ${peutValider ? '« Valider » la met en vigueur à sa date d’effet, en un geste tracé avec votre rôle.' : '« Valider » est réservé à la Direction, à la Directrice Administrative et à l’administrateur : leur décision suit votre proposition.'}',
            icone: LucideIcons.gitCompare),
        Tooltip(message: msgInfo, child: FormulaireSigh(controleur: ctl)),
        Row(children: [
          const Icon(LucideIcons.info, size: 14, color: JetonsShell.slate400),
          const SizedBox(width: 6),
          Expanded(child: Text(msgInfo, key: const Key('tarifs:info-date-passee'), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))),
        ]),
      ], espace: 12),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            Builder(builder: (modale) => BoutonSigh(libelle: 'Enregistrer', icone: LucideIcons.send, variante: VarianteBouton.secondaire, onPressed: () => envoyer(modale, fermer, false))),
            // La commande « Valider » est ABSENTE hors de la liste de rôles de la famille ; le moteur refuse de toute façon (VALIDATION_RESERVEE).
            if (peutValider) Builder(builder: (modale) => BoutonSigh(libelle: 'Valider', icone: LucideIcons.shieldCheck, onPressed: () => envoyer(modale, fermer, true))),
          ]);
}

Future<void> _decider(BuildContext ctx, ContexteEcran c, Map<String, Object?> v, String decision) async {
  final tarifs = _tarifs(c);
  void issue(IssueTarif r, String ok) {
    if (!r.ok) {
      ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
      return;
    }
    ToastsSigh.afficher(ctx, r.depose ? 'Demande de décision déposée à la mère : elle l’applique et le verdict revient ici.' : ok, type: TypeToast.succes);
    EcranTarifsEtPrix.versOnglet.value = 'alertes';
  }

  if (decision == 'oui') {
    final date = ControleurFormulaire([const ChampDef(nom: 'date', libelle: 'Date d’effet', type: TypeChamp.date, requis: true, col: ColChamp.plein)], {'date': _jour(c)});
    final msg = 'Le prix ${v['code']} passera à ${_argent(v['prixNonAssure'])} non assuré'
        '${v['etatAssure'] == 'montant' ? ' et ${money(v['prixAssure'], avecDevise: false)} assuré' : ''}'
        '${v['dateEffet'] != null ? ', à partir du ${dateFR(DateTime.parse('${v['dateEffet']}'))}' : ', à la date que vous fixez ci-dessous'}. Les pièces déjà émises gardent leur prix.';
    await afficherModale<void>(ctx,
        titre: 'Valider ce changement de prix ?',
        taille: TailleModale.sm,
        corps: cfaPile([NoteSigh(msg), if (v['dateEffet'] == null) FormulaireSigh(controleur: date)], espace: 12),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Oui, valider',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final r = tarifs.decider('${v['id']}', 'oui', dateEffet: v['dateEffet'] == null ? '${date['date']}' : null);
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
                      return;
                    }
                    fermer();
                    issue(r, 'Changement de prix validé.');
                  }),
            ]);
    return;
  }
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Refuser ce changement de prix ?',
      message: 'Le prix de ${v['code']} ne change pas. Le refus reste lisible à l’historique avec son motif.',
      libelleOk: 'Non, refuser',
      dangereux: true);
  if (motif == null) return;
  if (!ctx.mounted) return;
  issue(tarifs.decider('${v['id']}', 'non', motif: motif), 'Changement de prix refusé.');
}

/// « Oui à tout », ENCADRÉ : jamais sans la comparaison ligne à ligne sous les yeux. Chaque ligne passe par la décision ordinaire ; celles qui ne passent pas sont nommées.
Future<void> _ouiATout(BuildContext ctx, ContexteEcran c, List<Map<String, Object?>> versions) async {
  final tarifs = _tarifs(c);
  final lignes = _comparaison(c, versions);
  final seuil = tarifs.seuilVariation();
  final aDater = versions.any((v) => v['dateEffet'] == null);
  final date = ControleurFormulaire([const ChampDef(nom: 'date', libelle: 'Date d’effet des propositions à dater', type: TypeChamp.date, requis: true, col: ColChamp.plein)], {'date': _jour(c)});
  await afficherModale<void>(ctx,
      titre: 'Oui à tout : comparaison ligne à ligne',
      taille: TailleModale.xl,
      corps: Column(key: const Key('tarifs:comparaison-oui-a-tout'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoteSigh(
            '${lignes.length} changement(s) de prix vont être acceptés après lecture de cette comparaison. Chaque ligne passe par le contrôle d’usage : celles qu’une pièce déjà émise empêche sont refusées en nommant la pièce, les autres prennent effet. Les pièces déjà émises gardent leur prix.'
            '${seuil != null ? ' Une variation au-delà de $seuil % n’est jamais acceptée en bloc : elle se décide seule.' : ''}',
            ton: TonSigh.attention,
            icone: LucideIcons.triangleAlert),
        if (aDater) ...[const SizedBox(height: 12), FormulaireSigh(controleur: date)],
        const SizedBox(height: 12),
        ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 384),
            child: SingleChildScrollView(
                child: MiniTableauSigh(colonnes: [
              ColonneMini('Code', (r) => '${r['code']}'),
              ColonneMini('Prestation', (r) => '${r['libelle']}'),
              ColonneMini('Non assuré en vigueur', (r) => _argent(r['actuelNA']), droite: true),
              ColonneMini('Non assuré proposé', (r) => _argent(r['propose']), droite: true),
              ColonneMini('Variation', (r) => _texteVariation(r['pct']), droite: true),
              ColonneMini('Assuré en vigueur', (r) => '${r['actuelA']}'),
              ColonneMini('Assuré proposé', (r) => '${r['proposeA']}'),
              ColonneMini('Date d’effet', (r) => (r['v'] as Map)['dateEffet'] != null ? dateFR(DateTime.parse('${(r['v'] as Map)['dateEffet']}')) : 'à fixer'),
              ColonneMini('Pièces (30 jours)', (r) => nombre(r['pieces']), droite: true),
            ], lignes: lignes))),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Oui à tout (${lignes.length})',
                icone: LucideIcons.checkCheck,
                onPressed: () {
                  final r = tarifs.deciderTous(comparaisonAffichee: true, ids: [for (final v in versions) '${v['id']}'], dateEffet: aDater ? '${date['date']}' : null);
                  if (!r.ok) {
                    ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
                    return;
                  }
                  fermer();
                  final b = r.rapport!;
                  ToastsSigh.afficher(ctx,
                      '${b.acceptees.length} changement(s) accepté(s)${b.refusees.isNotEmpty ? ', ${b.refusees.length} refusé(s) par le moteur' : ''}${b.exclues.isNotEmpty ? ', ${b.exclues.length} à décider seul(s)' : ''}.',
                      type: b.refusees.isNotEmpty || b.exclues.isNotEmpty ? TypeToast.attention : TypeToast.succes,
                      detail: b.refusees.take(3).map((x) => '${x['code']} : ${x['refus']}').join(' ; '));
                  EcranTarifsEtPrix.versOnglet.value = 'alertes';
                }),
          ]);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// `cfg-catalogue` : la page de renvoi (hors ruban, l'entrée reste au manifeste : retirer une entrée casserait tout lien qui la vise)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranCatalogueRenvoi extends StatelessWidget with EcranMaquette {
  const EcranCatalogueRenvoi({super.key});
  @override
  String get titre => 'Catalogue tarifaire (deux prix)';
  @override
  String get description => 'Page de renvoi : les deux prix de chaque prestation figurent à « Tarifs et prix ».';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const NoteSigh(
                      'Le catalogue tarifaire à deux prix a rejoint le référentiel de prix unique : « Tarifs et prix » porte, pour chaque prestation, le prix non assuré, le prix assuré (ou NON COUVERT), la version en vigueur, l’historique et les changements en attente de décision. Un prix corrigé ici n’aurait atteint aucune facture : il se propose désormais là où la caisse le lit.',
                      icone: LucideIcons.merge),
                  const SizedBox(height: 16),
                  Center(child: BoutonSigh(libelle: 'Ouvrir « Tarifs et prix »', icone: LucideIcons.tag, onPressed: () => c.aller('cfg-tarifs'))),
                ]))));
  }
}
