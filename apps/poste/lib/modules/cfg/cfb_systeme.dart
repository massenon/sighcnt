import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';

const _mono = 'LiberationMono';
const _idReinit = 'reinitAutorisee';
const _idBareme = 'baremeModifiable';

/// Les collections que le poste tient pour SIENNES mais que la maquette ne connaît pas : la matrice et le manifeste engendrés, et les réglages
/// d'exploitation. Elles survivent à tout vidage et ne figurent ni au « Contenu du jeu de données » ni à la corbeille.
const cfbCollectionsTechniques = {'rolesBase', 'modulesManifeste', 'reglages'};

/// Les noms des collections du poste (celles de la maquette qu'il connaît).
List<String> cfbNomsCollections() => [for (final n in Magasin.collectionsDuJeu) if (!cfbCollectionsTechniques.contains(n)) n];

/// L'état de la persistance du poste : `disponible` reste faux tant que la base locale chiffrée n'est pas branchée derrière le magasin (plan S4).
class CfbPersistance {
  const CfbPersistance._();
  static bool Function() disponible = () => false;
}

/// Où l'export JSON est écrit. Le poste n'a pas de sélecteur de fichier natif : le dossier personnel de l'agent, sinon le dossier temporaire du système.
class CfbExport {
  const CfbExport._();
  static Future<String> Function(String nom, String contenu) ecrire = (nom, contenu) async {
    final dossier = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final base = (dossier != null && Directory(dossier).existsSync()) ? Directory(dossier) : Directory.systemTemp;
    final f = File('${base.path}${Platform.pathSeparator}$nom');
    await f.writeAsString(contenu);
    return f.path;
  };
}

/// D'où la régénération du jeu de démonstration relit ses collections : les assets du poste (injectable pour un test).
class CfbJeu {
  const CfbJeu._();
  static Future<String> Function(String nom) charger = (nom) => rootBundle.loadString('assets/donnees/jeu/$nom.json');
}

/// `S.viderActivite(motif)` : vide les données d'ACTIVITÉ, garde l'essentiel (paramétrage, référentiels, comptes, droits, catalogues, journal), et le DIT au
/// journal — l'entrée de vidage est la première du journal conservé (RG-12). Le calendrier fiscal, dérivé d'un document, revient aussitôt SANS règlement.
CfbPlanVidage cfbViderActivite(Magasin m, String motif) {
  final conservees = {...cfbEssentielles, ...cfbCollectionsTechniques};
  final plan = cfbPlanVidage({for (final n in cfbNomsCollections()) n: m.collection(n).toutes.length}, conservees);
  for (final n in plan.collections) {
    final col = m.collection(n);
    if (n == 'echeancesFiscales') {
      col.remplacerContenu([
        for (final f in col.toutes) {...f, 'paye': false, 'datePaiement': null, 'reference': null, 'valideePar': null}
      ]);
    } else {
      col.remplacerContenu(const []);
    }
  }
  m.journaliser('Réinitialisation des jeux de test', 'CFG', 'Base', 'vidage', null, {'tables': plan.tables, 'enregistrements': plan.enregistrements, 'motif': motif});
  return plan;
}

/// `S.reset()` : la base revient au jeu initial, paramétrage compris. L'autorisation de réinitialiser (une bascule du poste, non une donnée du jeu) survit.
Future<void> cfbRegenererJeu(Magasin m, String motif) async {
  for (final n in cfbNomsCollections()) {
    final lignes = [for (final f in (jsonDecode(await CfbJeu.charger(n)) as List)) (f as Map).cast<String, Object?>()];
    m.collection(n).remplacerContenu(lignes);
  }
  final reglages = m.collection('reglages');
  reglages.remplacerContenu([for (final f in reglages.toutes) if (f['id'] == _idReinit) f]);
  m.journaliser('Régénération du jeu de démonstration', 'CFG', 'Base', 'jeu complet', null, {'motif': motif});
}

/// Quand et par qui une fiche a été archivée : ses marques `_archiveLe` / `_archivePar` / `_motifArchivage` (jeu de la maquette) ou, à défaut, la dernière
/// entrée « Archivage » du journal qui la nomme (le magasin du poste n'écrit pas ces marques sur la fiche, il les journalise).
({String? le, String par, String? motif}) cfbInfosArchivage(Magasin m, CollectionMagasin col, Fiche f) {
  if (f['_archiveLe'] != null || f['_archivePar'] != null || f['_motifArchivage'] != null) {
    return (le: f['_archiveLe'] == null ? null : '${f['_archiveLe']}', par: '${f['_archivePar'] ?? '—'}', motif: f['_motifArchivage'] == null ? null : '${f['_motifArchivage']}');
  }
  final ref = '${f['numero'] ?? f['reference'] ?? f['code'] ?? f['id']}';
  final entite = col.entite ?? col.nom;
  final a = m.collection('audit').toutes.where((x) => x['action'] == 'Archivage' && x['entite'] == entite && x['reference'] == ref).firstOrNull;
  return a == null ? (le: null, par: '—', motif: null) : (le: '${a['dateHeure']}', par: '${a['utilisateur'] ?? '—'}', motif: null);
}

/// `S.corbeille()` : toutes les fiches archivées, tous modules confondus, la plus récente d'abord.
List<CfbLigneCorbeille> cfbCorbeille(Magasin m) {
  final out = <CfbLigneCorbeille>[];
  for (final n in cfbNomsCollections()) {
    final col = m.collection(n);
    final (mod, ent) = cfbLibelleCollection(n);
    for (final f in col.archivees) {
      final i = cfbInfosArchivage(m, col, f);
      out.add(CfbLigneCorbeille(collection: n, module: mod, entite: ent, libelle: cfbLibelleElement(f), refId: '${f['id']}', archiveLe: i.le, archivePar: i.par, motif: i.motif));
    }
  }
  return cfbTrierCorbeille(out);
}

/// `cfg-systeme` — « Paramètres système » : l'installation et le contenu des données, la CORBEILLE (RG-14 : rien n'est jamais supprimé, tout ce qui a été
/// archivé dans n'importe quel module se retrouve et se restaure ici), la porte du barème NS 131 et les jeux de test.
class EcranSysteme extends StatefulWidget with EcranMaquette {
  const EcranSysteme({super.key});
  @override
  String get titre => 'Paramètres système';
  @override
  String get description => 'Configuration technique, environnement d’exécution et outils de maintenance du prototype.';
  @override
  String get regle =>
      'Les paramètres décrivent l’installation technique et ne se saisissent pas ici. L’onglet Corbeille, lui, agit : RG-14 — rien n’est jamais supprimé, tout ce qui a été archivé dans n’importe quel module s’y retrouve et s’y restaure.';

  @override
  State<EcranSysteme> createState() => _EtatSysteme();
}

class _EtatSysteme extends State<EcranSysteme> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final noms = cfbNomsCollections();
    // Toute écriture d'une collection (archivage, restauration, vidage) recompose l'écran : le compteur de la corbeille doit suivre.
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in noms) c.magasin.collection(n), c.magasin.collection('reglages')]),
        builder: (ctx, _) => OngletsSigh(onglets: [
              OngletDef(id: 'installation', libelle: 'Installation et données', construire: (_) => _Installation(c: c, rafraichir: () => setState(() {}))),
              OngletDef(id: 'corbeille', libelle: 'Corbeille', compte: cfbCorbeille(c.magasin).length, construire: (_) => _Corbeille(c: c)),
              OngletDef(id: 'bareme', libelle: 'Barème NS 131', construire: (_) => _Bareme(c: c)),
              OngletDef(id: 'reinitialisation', libelle: 'Jeux de test', construire: (_) => _JeuxDeTest(c: c, rafraichir: () => setState(() {}))),
            ]));
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Installation et données »
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Installation extends StatelessWidget {
  const _Installation({required this.c, required this.rafraichir});
  final ContexteEcran c;
  final VoidCallback rafraichir;

  Future<void> _reinitialiser(BuildContext ctx) async {
    // La maquette laisse ce bouton à tout profil et le fait passer outre la bascule des jeux de test. Le poste tient la doctrine : fermée, l'effacement est
    // REFUSÉ en le disant (E889) — le bouton reste visible pour que le refus ait un endroit où se dire.
    if (cfbReglage(c.magasin, _idReinit, false) != true) {
      ToastsSigh.afficher(ctx, 'Réinitialisation verrouillée.', type: TypeToast.erreur, detail: 'Autoriser d’abord l’effacement des jeux de test, à l’onglet « Jeux de test ».');
      return;
    }
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Réinitialiser toutes les données de démonstration ?',
        message:
            'Les données de test — patients, consultations, factures, mouvements, écritures — seront retirées. Le paramétrage, les référentiels, les comptes, la matrice des droits et les catalogues sont conservés. L’opération est journalisée et irréversible : générer une sauvegarde d’abord.',
        libelleOk: 'Réinitialiser',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final bilan = cfbViderActivite(c.magasin, motif);
    ToastsSigh.afficher(ctx, cfbToastVidage(bilan), type: TypeToast.succes, detail: 'Paramétrage, référentiels, comptes et droits conservés.');
    rafraichir();
  }

  Future<void> _exporter(BuildContext ctx) async {
    try {
      final contenu = const JsonEncoder.withIndent('  ').convert({for (final n in cfbNomsCollections()) n: c.magasin.collection(n).toutes});
      final chemin = await CfbExport.ecrire('sigh-cnt-donnees-${cfbIso(c.aujourdhui)}.json', contenu);
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Export JSON généré.', type: TypeToast.succes, detail: chemin);
    } catch (e) {
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Export impossible : $e', type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = c.magasin;
    final noms = cfbNomsCollections();
    final stats = [for (final n in noms) cfbStatCollection(n, m.collection(n).toutes)];
    final total = stats.fold<int>(0, (a, s) => a + s.total);
    final persistant = CfbPersistance.disponible();
    return cfaPile([
      cfaKpis([
        CfaKpi('Collections de données', nombre(noms.length), 'database', 'navy'),
        CfaKpi('Enregistrements', nombre(total), 'layers', 'info'),
        CfaKpi('Persistance', persistant ? 'Base locale' : 'Mémoire', 'hard-drive', persistant ? 'success' : 'warning', persistant ? 'Stockage local actif' : 'Stockage local indisponible'),
        const CfaKpi('Version du prototype', 'v1.0', 'tag', 'neutral'),
      ]),
      if (!persistant)
        cfbNote(
            'La base locale chiffrée du poste n’est pas encore branchée derrière le magasin : le poste fonctionne en mémoire. Les modifications restent pleinement opérationnelles mais ne survivent pas à la fermeture du poste.',
            ton: 'warning',
            icone: LucideIcons.hardDrive),
      // ARCHITECTURE CIBLE — PROPOSITION, ET L'ÉCRAN LE DIT : la maquette décrit l'hébergement web ; le poste (hors ligne d'abord) relève des ADR 0002 et 0005.
      CarteSigh(
          titre: 'Architecture cible — proposition',
          child: const DescListeSigh([
            ('Application', 'Web — Laravel 12 (PHP 8.3) avec Vue 3 via Inertia'),
            ('Postes de travail', 'Navigateur ; application installable (PWA) sur chaque poste'),
            ('Base de données', 'PostgreSQL, hébergée avec l’application'),
            ('Hébergement', 'Serveur mutualisé cPanel — déploiement Git, SSL automatique'),
            ('Poste caisse', 'Enveloppe Tauri si l’imprimante ticket ou la MECeF l’exigent'),
            ('Reporting', 'Gabarits d’impression du navigateur ; PDF archivés côté serveur'),
            ('Sauvegarde', 'Export chiffré planifié HORS de l’hébergeur — jamais un seul dépositaire'),
            ('Continuité électrique', 'Onduleurs aux postes critiques, box sur onduleur, secours 4G, mode dégradé papier'),
            ('Ce prototype', 'HTML, CSS et JavaScript — sans dépendance réseau'),
          ])),
      cfbNote(
          'Cette architecture est une proposition technique, pas une décision : elle attend l’arbitrage écrit de la Direction. Deux conséquences y sont attachées et doivent être assumées avec elle — l’exploitation dépend désormais de la connexion Internet de la clinique et de la disponibilité de l’hébergeur, d’où les onduleurs, la liaison de secours et le mode dégradé papier ; et les sauvegardes doivent sortir de chez l’hébergeur, des données de santé ne pouvant reposer sur un seul prestataire.',
          ton: 'warning',
          icone: LucideIcons.flag),
      CarteSigh(
          titre: 'Contenu du jeu de données',
          sansRemplissage: true,
          child: TableauSigh(
            lignes: [
              for (final s in stats) {'id': s.nom, 'collection': s.nom, 'nb': s.total, 'actifs': s.actifs, 'archives': s.archives}
            ],
            taillePage: 30,
            triInitial: 'nb',
            sensInitial: 'desc',
            nomExport: 'collections',
            colonnes: [
              ColonneTableau(
                  cle: 'collection',
                  libelle: 'Collection',
                  rendu: (_, r) => Text('${r['collection']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, color: JetonsShell.slate900))),
              const ColonneTableau(cle: 'nb', libelle: 'Enregistrements', droite: true),
              const ColonneTableau(cle: 'actifs', libelle: 'Actifs', droite: true),
              ColonneTableau(
                  cle: 'archives',
                  libelle: 'Archivés',
                  droite: true,
                  texte: (r) => (r['archives'] as int) > 0 ? '${r['archives']}' : '—',
                  rendu: (_, r) => (r['archives'] as int) > 0 ? Text('${r['archives']}', style: const TextStyle(fontSize: 14, color: JetonsShell.warning600)) : const Text('—')),
            ],
          )),
      CarteSigh(
          titre: 'Maintenance du prototype',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.droit.editer) BoutonSigh(libelle: 'Réinitialiser le jeu de données', icone: LucideIcons.rotateCcw, variante: VarianteBouton.danger, onPressed: () => _reinitialiser(context)),
            BoutonSigh(libelle: 'Exporter les données', icone: LucideIcons.download, variante: VarianteBouton.secondaire, onPressed: () => _exporter(context)),
            BoutonSigh(libelle: 'Plan du site', icone: LucideIcons.map, variante: VarianteBouton.secondaire, onPressed: () => c.aller('plan-du-site')),
            BoutonSigh(libelle: 'Sauvegardes', icone: LucideIcons.databaseBackup, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m14-sauvegardes')),
          ])),
      cfbNote(
          'Ce prototype fonctionne intégralement hors ligne : la feuille de style, les polices, la bibliothèque de graphiques et les icônes sont hébergées dans le dossier du projet. Aucune requête réseau n’est émise.',
          ton: 'success',
          icone: LucideIcons.wifiOff),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Corbeille » (RG-14)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Corbeille extends StatelessWidget {
  const _Corbeille({required this.c});
  final ContexteEcran c;

  Future<void> _restaurer(BuildContext ctx, CfbLigneCorbeille r) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Restaurer « ${r.libelle} » ?',
        message: 'La fiche réapparaîtra dans ${r.entite} (${r.module}) et redeviendra modifiable. La restauration est journalisée (RG-12).',
        libelleOk: 'Restaurer');
    if (!ok || !ctx.mounted) return;
    c.magasin.collection(r.collection).restaurer(r.refId);
    ToastsSigh.afficher(ctx, 'Fiche restaurée dans ${r.entite}.', type: TypeToast.succes);
  }

  @override
  Widget build(BuildContext context) {
    final rows = cfbCorbeille(c.magasin);
    final modules = {for (final r in rows) r.module};
    return cfaPile([
      cfaKpis([
        CfaKpi('Fiches archivées', nombre(rows.length), 'trash-2', rows.isNotEmpty ? 'warning' : 'success'),
        CfaKpi('Modules concernés', nombre(modules.length), 'layers', 'info'),
        const CfaKpi('Suppression définitive', 'Impossible', 'shield-check', 'success', 'RG-14 — archivage logique'),
      ]),
      cfbNote(
          'RG-14 — aucune donnée n’est jamais supprimée physiquement. Archiver retire la fiche des listes de travail ; la restaurer la remet exactement où elle était, et l’opération est journalisée dans les deux sens.'),
      if (rows.isEmpty)
        const CarteSigh(titre: 'Corbeille', child: VideSigh('La corbeille est vide — aucune fiche archivée.', icone: LucideIcons.trash2))
      else
        CarteSigh(
            titre: 'Fiches archivées',
            sansRemplissage: true,
            child: TableauSigh(
              lignes: [
                for (final r in rows)
                  {'id': r.id, 'collection': r.collection, 'module': r.module, 'entite': r.entite, 'libelle': r.libelle, 'refId': r.refId, 'archiveLe': r.archiveLe, 'archivePar': r.archivePar, 'motif': r.motif}
              ],
              taillePage: 15,
              triInitial: 'archiveLe',
              sensInitial: 'desc',
              nomExport: 'corbeille',
              filtres: [FiltreTableau(nom: 'module', libelle: 'Module', options: [for (final mo in (modules.toList()..sort())) OptionChamp(mo)])],
              colonnes: [
                ColonneTableau(cle: 'module', libelle: 'Module', sansCoupure: true, rendu: (_, r) => BadgeSigh('${r['module']}')),
                const ColonneTableau(cle: 'entite', libelle: 'Type de fiche'),
                ColonneTableau(
                    cle: 'libelle',
                    libelle: 'Élément',
                    texte: (r) => '${r['libelle']} ${r['refId']}',
                    rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${r['libelle']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                          Text('${r['refId']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                        ])),
                ColonneTableau(
                    cle: 'archiveLe',
                    libelle: 'Archivée le',
                    sansCoupure: true,
                    valeur: (r) => '${r['archiveLe'] ?? ''}',
                    texte: (r) => r['archiveLe'] != null ? dateFR(DateTime.parse('${r['archiveLe']}').toLocal()) : '—'),
                const ColonneTableau(cle: 'archivePar', libelle: 'Par', sansCoupure: true),
                ColonneTableau(
                    cle: 'motif',
                    libelle: 'Motif',
                    texte: (r) => cfaOuTiret(r['motif']),
                    rendu: (_, r) => cfaVrai(r['motif']) ? Text('${r['motif']}') : const Text('—', style: TextStyle(color: JetonsShell.slate300))),
              ],
              actionsLigne: (ctx, r) => [
                if (c.droit.annuler)
                  BoutonIcone(
                      icone: LucideIcons.undo2,
                      libelle: 'Restaurer',
                      onPressed: () => _restaurer(
                          ctx,
                          rows.firstWhere((x) => x.id == r['id']))),
              ],
            )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Barème NS 131 » — LA PORTE du barème
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Bareme extends StatelessWidget {
  const _Bareme({required this.c});
  final ContexteEcran c;

  Future<void> _basculer(BuildContext ctx, bool ouverte) async {
    if (ouverte) {
      cfbPoserReglage(c.magasin, _idBareme, false);
      c.magasin.journaliser('Fermeture de la modification du barème', 'M10', 'Barème', cfbNs131.reference, null, const {});
      ToastsSigh.afficher(ctx, 'Modification du barème refermée.', type: TypeToast.succes, detail: 'Le barème redevient consultable seulement.');
      return;
    }
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Autoriser la modification du barème NS 131 ?',
        message:
            'Le barème fixe les retenues sur salaire. L’ouvrir rend ses critères et ses taux modifiables depuis l’écran « Évaluations ».\n\nChaque modification demandera sa portée — évaluations à venir seulement, ou évaluations déjà prononcées comprises. Refermer la porte après usage évite qu’elle reste ouverte des mois durant.',
        libelleOk: 'Autoriser la modification',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    cfbPoserReglage(c.magasin, _idBareme, true);
    c.magasin.journaliser('Ouverture de la modification du barème', 'M10', 'Barème', cfbNs131.reference, null, {'motif': motif});
    ToastsSigh.afficher(ctx, 'Modification du barème autorisée.',
        type: TypeToast.attention, detail: 'Le CRUD est ouvert à l’écran « Évaluations ». Penser à refermer après usage.', duree: const Duration(seconds: 8));
  }

  @override
  Widget build(BuildContext context) {
    final ouverte = cfbReglage(c.magasin, _idBareme, false) == true;
    return cfaPile([
      cfbNote(
          'Le barème d’évaluation ${cfbNs131.reference} fixe les retenues appliquées au salaire brut. Sa modification est fermée par défaut. L’ouvrir ici rend le barème modifiable à l’écran « Évaluations » — et l’ouverture est journalisée. Chaque modification demandera ensuite sa portée : évaluations à venir seulement, ou évaluations déjà prononcées comprises.',
          ton: ouverte ? 'warning' : 'info',
          icone: ouverte ? LucideIcons.lockOpen : LucideIcons.lock),
      CarteSigh(
          titre: 'Modification du barème',
          child: cfaPile([
            DescListeSigh([
              ('État', ouverte ? const BadgeSigh('Ouverte', ton: TonSigh.attention) : const BadgeSigh('Fermée', ton: TonSigh.succes)),
              ('Référence', cfbNs131.reference),
              ('En vigueur depuis', dateFR(DateTime.parse(cfbNs131.dateEffet))),
              ('Critères au barème', nombre(c.magasin.collection('baremeNS131').actives.length)),
              ('Versions antérieures', nombre(c.magasin.collection('historiqueBareme').actives.length)),
            ]),
            // La porte est une décision de l'institution : sans le droit d'écrire, la commande est ABSENTE.
            if (c.droit.editer)
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      libelle: ouverte ? 'Refermer la modification' : 'Autoriser la modification',
                      icone: ouverte ? LucideIcons.lock : LucideIcons.lockOpen,
                      variante: ouverte ? VarianteBouton.secondaire : VarianteBouton.danger,
                      onPressed: () => _basculer(context, ouverte))),
          ], espace: 12)),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Jeux de test » — la bascule fermée par défaut : fermée, le bouton est ABSENT et non grisé
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _JeuxDeTest extends StatelessWidget {
  const _JeuxDeTest({required this.c, required this.rafraichir});
  final ContexteEcran c;
  final VoidCallback rafraichir;

  bool get _autorisee => cfbReglage(c.magasin, _idReinit, false) == true;

  Future<void> _basculerAutorisation(BuildContext ctx, bool voulue) async {
    if (voulue) {
      final ok = await confirmerSigh(ctx,
          titre: 'Autoriser la réinitialisation des jeux de test ?',
          message:
              'Une fois autorisée, la réinitialisation devient possible depuis ce poste. Sur un poste en production, la laisser fermée est la seule position raisonnable : elle protège les données réelles de l’établissement.',
          libelleOk: 'Autoriser',
          dangereux: true);
      if (!ok || !ctx.mounted) return;
      cfbPoserReglage(c.magasin, _idReinit, true);
      c.magasin.journaliser('Déverrouillage', 'CFG', 'Réinitialisation', 'jeux de test', {'etat': 'verrouillée'}, {'etat': 'autorisée'});
    } else {
      cfbPoserReglage(c.magasin, _idReinit, false);
      c.magasin.journaliser('Verrouillage', 'CFG', 'Réinitialisation', 'jeux de test', {'etat': 'autorisée'}, {'etat': 'verrouillée'});
    }
    rafraichir();
  }

  Future<void> _vider(BuildContext ctx, CfbPlanVidage plan) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Vider les jeux de test ?',
        message:
            'Les ${plan.tables} tables d’activité seront vidées : patients, consultations, factures, mouvements, ordonnances. Les paramètres, les référentiels et le compte administrateur sont conservés. L’opération est journalisée et irréversible — générer une sauvegarde d’abord.',
        libelleOk: 'Vider les jeux de test',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final bilan = cfbViderActivite(c.magasin, motif);
    ToastsSigh.afficher(ctx, cfbToastVidage(bilan), type: TypeToast.succes, detail: 'Paramétrage, référentiels, comptes et droits conservés.');
    rafraichir();
  }

  Future<void> _regenerer(BuildContext ctx) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Régénérer entièrement le jeu de démonstration ?',
        message: 'Toute la base est remplacée par le jeu initial, paramétrage compris. À n’utiliser que sur un poste de démonstration.',
        libelleOk: 'Régénérer',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    try {
      await cfbRegenererJeu(c.magasin, motif);
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Jeu de démonstration régénéré.', type: TypeToast.succes);
    } catch (e) {
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Régénération impossible : $e', type: TypeToast.erreur);
    }
    rafraichir();
  }

  Widget _puces(String titre, List<String> puces, {required bool danger}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: danger ? JetonsShell.danger50 : JetonsShell.success50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: danger ? JetonsShell.danger200 : JetonsShell.success200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre.toUpperCase(), style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: danger ? JetonsShell.danger700 : JetonsShell.success700)),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final p in puces)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Text(p, style: TextStyle(fontSize: 10, height: 14 / 10, color: danger ? JetonsShell.danger700 : JetonsShell.success700))),
        ]),
      ]));

  @override
  Widget build(BuildContext context) {
    final m = c.magasin;
    final noms = cfbNomsCollections();
    final tailles = {for (final n in noms) n: m.collection(n).toutes.length};
    final plan = cfbPlanVidage(tailles, {...cfbEssentielles, ...cfbCollectionsTechniques});
    final conservees = [for (final n in cfbEssentielles) if (tailles.containsKey(n)) n];
    final autorisee = _autorisee;
    return cfaPile([
      cfaKpis([
        CfaKpi('Réinitialisation', autorisee ? 'Autorisée' : 'Verrouillée', autorisee ? 'unlock' : 'lock', autorisee ? 'danger' : 'success',
            autorisee ? 'Le poste accepte l’effacement des jeux de test' : 'Aucun effacement possible'),
        CfaKpi('Tables d’activité', nombre(plan.tables), 'database', 'info', '${nombre(plan.enregistrements)} enregistrements'),
        CfaKpi('Tables de paramétrage préservées', nombre(noms.length - plan.tables), 'shield-check', 'success', 'Tarifs, secteurs, conventions, comptes'),
      ]),
      CarteSigh(
          titre: 'Autorisation',
          child: Tooltip(
              message: 'Autoriser la réinitialisation des jeux de test sur ce poste',
              child: InkWell(
                  key: const Key('cfb:reinit:bascule'),
                  onTap: c.droit.editer ? () => _basculerAutorisation(context, !autorisee) : null,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(value: autorisee, onChanged: c.droit.editer ? (v) => _basculerAutorisation(context, v == true) : null, activeColor: JetonsShell.navy900, visualDensity: VisualDensity.compact)),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Autoriser la réinitialisation des jeux de test sur ce poste', style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                      Text('À laisser fermé sur un poste en service. Le déverrouillage et le verrouillage sont journalisés.', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                    ])),
                  ])))),
      CarteSigh(
          titre: 'Ce qui serait effacé, ce qui serait conservé',
          child: LayoutBuilder(builder: (_, k) {
            final a = _puces('Effacé — données d’activité', [for (final n in plan.collections.take(24)) '$n (${tailles[n]})'], danger: true);
            final b = _puces('Conservé — paramétrage et référentiels', [for (final n in conservees) '$n (${tailles[n]})'], danger: false);
            return k.maxWidth >= 640
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
                : cfaPile([a, b], espace: 12);
          })),
      cfbNote(
          'L’administrateur, les réglages et les référentiels administrés par la clinique ne sont jamais effacés. La réinitialisation ne retire que les données engendrées pour la démonstration — patients, consultations, factures, mouvements.'),
      if (autorisee)
        CarteSigh(
            titre: 'Réinitialisation',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.droit.editer) ...[
                BoutonSigh(libelle: 'Vider les jeux de test', icone: LucideIcons.trash2, variante: VarianteBouton.danger, onPressed: () => _vider(context, plan)),
                BoutonSigh(libelle: 'Régénérer le jeu de démonstration complet', icone: LucideIcons.rotateCcw, variante: VarianteBouton.secondaire, onPressed: () => _regenerer(context)),
              ]
            ]))
      else
        const CarteSigh(titre: 'Réinitialisation', child: VideSigh('Réinitialisation verrouillée — activer l’autorisation ci-dessus pour la rendre possible.', icone: LucideIcons.lock)),
    ]);
  }
}
