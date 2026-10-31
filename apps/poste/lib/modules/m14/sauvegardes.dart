import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m14.dart';

/// Écrit un fichier de sauvegarde et rend son chemin. Posé en variable pour que les tests n'écrivent pas sur le disque de la machine.
/// Par défaut : `$SIGH_EXPORTS`, sinon le dossier « Downloads » / « Téléchargements » de l'utilisateur, sinon le dossier temporaire.
Future<String> Function(String nom, String contenu) enregistrerSauvegarde = (nom, contenu) async {
  Directory dossier = Directory.systemTemp;
  final env = Platform.environment;
  final cible = env['SIGH_EXPORTS'];
  if (cible != null && cible.isNotEmpty) {
    dossier = Directory(cible);
  } else {
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home != null) {
      for (final n in ['Downloads', 'Téléchargements']) {
        final d = Directory('$home${Platform.pathSeparator}$n');
        if (d.existsSync()) {
          dossier = d;
          break;
        }
      }
    }
  }
  await dossier.create(recursive: true);
  final f = File('${dossier.path}${Platform.pathSeparator}$nom');
  await f.writeAsString(contenu);
  return f.path;
};

/// L'état COURANT du magasin du poste : une table = une collection du jeu, fiches archivées comprises (RG-14).
Map<String, List<Fiche>> etatDuMagasin(Magasin m) => {
      for (final n in Magasin.collectionsDuJeu) n: m.collection(n).toutes,
    };

String _contenu(Magasin m) => const JsonEncoder.withIndent('  ').convert(etatDuMagasin(m));

/// `m14-sauvegardes` — « Sauvegardes & restauration ».
///
/// CE QUI EST RÉEL ET CE QUI NE L'EST PAS. L'historique de 34 jours est CALCULÉ, comme dans la maquette (graine 3517) : aucune copie n'existe derrière.
/// « Restaurer » est SIMULÉ (journal + message) : le magasin du poste n'a pas d'opération de remplacement d'une table et RG-14 interdit de supprimer.
/// « Générer une sauvegarde », « Lancer une sauvegarde manuelle », « Télécharger » et « Tester une restauration » travaillent sur le magasin RÉEL du poste
/// (fichier JSON écrit sur le disque, relecture vérifiée). « Importer par module » n'est pas porté. La planification nocturne appartient au serveur
/// de la maquette (`api/cron.php`) : voir m14-taches.
class EcranSauvegardes extends StatelessWidget with EcranMaquette {
  const EcranSauvegardes({super.key});

  @override
  String get description =>
      'Sauvegardes quotidiennes locales, sauvegardes hebdomadaires externalisées et procédure de restauration.';

  @override
  String get regle =>
      'Politique appliquée : sauvegarde quotidienne sur disque local dédié, sauvegarde hebdomadaire externalisée, historique glissant de 30 jours et journalisation de chaque opération avec alerte en cas d’échec.';

  @override
  Widget build(BuildContext context) => const _VueSauvegardes();
}

class _VueSauvegardes extends StatefulWidget {
  const _VueSauvegardes();
  @override
  State<_VueSauvegardes> createState() => _VueSauvegardesState();
}

class _VueSauvegardesState extends State<_VueSauvegardes> {
  CollectionMagasin? _col;
  bool _seme = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('fichiersSauvegarde');
    if (!identical(col, _col)) {
      _col?.removeListener(_maj);
      _col = col..addListener(_maj);
    }
    // La maquette amorce six fichiers hebdomadaires quand la collection est vide (graine 88).
    if (!_seme && col.toutes.isEmpty) {
      _seme = true;
      final semes = secFichiersSauvegardeSemes(c.aujourdhui, Magasin.collectionsDuJeu.length);
      for (final f in semes.reversed) {
        col.inserer(f, prefixe: 'BKP');
      }
    }
  }

  @override
  void dispose() {
    _col?.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  static Fiche _ligne(SauvegardeSec r) => {
        'id': r.reference,
        'reference': r.reference,
        'date': r.date,
        'heure': r.heure,
        'type': r.type,
        'support': r.support,
        'taille': r.taille,
        'duree': r.duree,
        'succes': r.succes,
        'message': r.message,
      };

  Future<void> _telecharger(BuildContext ctx, ContexteEcran c, Fiche r) async {
    try {
      final chemin = await enregistrerSauvegarde('${r['fichier']}', _contenu(c.magasin));
      if (!ctx.mounted) return;
      // Le fichier est l'état COURANT du poste, non celui de la date de la ligne (la maquette fait de même) : on le dit.
      ToastsSigh.afficher(ctx, 'Sauvegarde téléchargée.',
          type: TypeToast.succes,
          detail: '$chemin — état courant du poste, non celui du ${dateFrOuVide(r['date'])}');
    } catch (e) {
      if (!ctx.mounted) return;
      ToastsSigh.afficher(ctx, 'Téléchargement impossible depuis ce poste.',
          type: TypeToast.erreur, detail: '${r['fichier']}');
    }
  }

  void _generer(BuildContext ctx, ContexteEcran c) {
    final contenu = _contenu(c.magasin);
    final nom = secNomFichierSauvegarde(c.aujourdhui, _col!.toutes.length);
    final tables = Magasin.collectionsDuJeu.length;
    final r = _col!.inserer({
      'fichier': nom,
      'date': iso(c.aujourdhui),
      'heure': heure(c.aujourdhui),
      'portee': 'Base complète',
      'tables': tables,
      'taille': contenu.length,
      'genereePar': c.utilisateur,
      'statut': 'actif',
    }, prefixe: 'BKP');
    ToastsSigh.afficher(ctx, 'Sauvegarde $nom générée.',
        type: TypeToast.succes,
        detail: '$tables tables — ${secPoidsFichier(contenu.length)}',
        annuler: r.annuler);
  }

  Future<void> _manuelle(BuildContext ctx, ContexteEcran c) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Lancer une sauvegarde immédiate ?',
        message:
            'Une sauvegarde complète de la base de données sera effectuée sur le disque local dédié. L’opération est journalisée.',
        libelleOk: 'Lancer la sauvegarde');
    if (!ok || !ctx.mounted) return;
    final debut = DateTime.now();
    try {
      final contenu = _contenu(c.magasin);
      final nom = 'BK-MANUELLE-${iso(c.aujourdhui).replaceAll('-', '')}.json';
      final chemin = await enregistrerSauvegarde(nom, contenu);
      final ms = DateTime.now().difference(debut).inMilliseconds;
      journaliserM14(c, 'Création', 'Sauvegarde', 'BK-MANUELLE', apres: {'type': 'manuelle'});
      if (!ctx.mounted) return;
      ToastsSigh.afficher(ctx, 'Sauvegarde effectuée avec succès.',
          type: TypeToast.succes,
          detail: 'Volume : ${secPoidsFichier(contenu.length)} — durée : $ms ms — $chemin');
    } catch (e) {
      journaliserM14(c, 'Création', 'Sauvegarde', 'BK-MANUELLE', apres: {'type': 'manuelle', 'erreur': '$e'});
      if (!ctx.mounted) return;
      ToastsSigh.afficher(ctx, 'Sauvegarde impossible depuis ce poste.',
          type: TypeToast.erreur, detail: '$e');
    }
  }

  /// « Tester une restauration » : le magasin est sérialisé puis RELU, et chaque table doit revenir à l'identique. Le poste n'a pas d'environnement de
  /// test où restaurer (la maquette annonce, elle, « l'intégrité vérifiée sur l'environnement de test » sans rien vérifier).
  Future<void> _tester(BuildContext ctx, ContexteEcran c) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Tester la procédure de restauration ?',
        message:
            'La restauration sera effectuée sur l’environnement de test, sans incidence sur les données de production.',
        libelleOk: 'Lancer le test');
    if (!ok || !ctx.mounted) return;
    final etat = etatDuMagasin(c.magasin);
    final relu = (jsonDecode(jsonEncode(etat)) as Map).cast<String, Object?>();
    var fiches = 0;
    final ecarts = <String>[];
    for (final e in etat.entries) {
      final l = (relu[e.key] as List?) ?? const [];
      fiches += e.value.length;
      if (l.length != e.value.length || jsonEncode(l) != jsonEncode(e.value)) ecarts.add(e.key);
    }
    if (ecarts.isEmpty) {
      ToastsSigh.afficher(ctx, 'Test de restauration réussi.',
          type: TypeToast.succes,
          detail:
              'Relecture vérifiée : ${etat.length} tables, $fiches fiches identiques. Le poste n’a pas d’environnement de test : rien n’a été restauré.');
    } else {
      ToastsSigh.afficher(ctx, 'Test de restauration échoué.',
          type: TypeToast.erreur, detail: 'Tables relues différemment : ${ecarts.join(', ')}');
    }
  }

  void _importer(BuildContext ctx) {
    ToastsSigh.afficher(ctx, 'Import par module non porté sur le poste.',
        type: TypeToast.attention,
        detail:
            'Le magasin du poste n’a pas d’opération de remplacement d’une table (RG-14 : rien ne se supprime) ; reprendre une base entière exige une restauration, pas un import.');
  }

  Future<void> _restaurer(BuildContext ctx, ContexteEcran c, Fiche r) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Restaurer la sauvegarde du ${dateFrOuVide(r['date'])} ?',
        message:
            'Cette opération remplacera les données actuelles par celles de la sauvegarde sélectionnée. Elle doit être réalisée sous le contrôle de l’Administrateur système et est journalisée.',
        libelleOk: 'Restaurer',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    journaliserM14(c, 'Restauration', 'Sauvegarde', '${r['reference']}', apres: {'motif': motif});
    ToastsSigh.afficher(ctx, 'Restauration simulée avec succès.',
        type: TypeToast.succes,
        detail: 'Simulation : aucune donnée n’est effectivement remplacée sur le poste.');
  }

  void _imprimerJournal(BuildContext ctx, ContexteEcran c, List<SauvegardeSec> rows) {
    final echecs = rows.where((r) => !r.succes).length;
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Journal des sauvegardes',
          sousTitre: 'Historique glissant — situation au ${dateFR(c.aujourdhui)}',
          reference: referenceImpression(c),
          utilisateur: c.utilisateur,
          edite: c.aujourdhui,
          cartouche: [
            ('Sauvegardes conservées', nombre(rows.length)),
            ('Dernière sauvegarde', '${dateFrOuVide(rows.first.date)} à ${rows.first.heure}'),
            ('Échecs', nombre(echecs)),
            ('Volume moyen', '${secVolumeMoyen(rows)} Mo'),
          ],
          tableaux: [
            TableauEtat(colonnes: [
              ColonneEtat(libelle: 'Référence', valeur: (r) => '${r['reference']}'),
              ColonneEtat(libelle: 'Date', valeur: (r) => dateFrOuVide(r['date'])),
              ColonneEtat(libelle: 'Heure', valeur: (r) => '${r['heure']}'),
              ColonneEtat(libelle: 'Type', valeur: (r) => '${r['type']}'),
              ColonneEtat(libelle: 'Support', valeur: (r) => '${r['support']}'),
              ColonneEtat(libelle: 'Volume', droite: true, valeur: (r) => '${r['taille']} Mo'),
              ColonneEtat(libelle: 'Durée', droite: true, valeur: (r) => '${r['duree']} s'),
              ColonneEtat(libelle: 'Résultat', valeur: (r) => r['succes'] == true ? 'Succès' : 'Échec'),
            ], lignes: [for (final r in rows) _ligne(r)])
          ],
          signatures: const [
            Signature('L’Administrateur système'),
            Signature('La Directrice Administrative', nom: 'TAKI Alimatou'),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final rows = secHistoriqueSauvegardes(c.aujourdhui);
    final echecs = rows.where((r) => !r.succes).length;
    final premiere = rows.first;
    final fichiers = _col!.actives;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Sauvegardes conservées',
            valeur: nombre(rows.length),
            icone: LucideIcons.databaseBackup,
            ton: TonSigh.navy,
            indice: 'Historique glissant 30 jours'),
        KpiSigh(
            libelle: 'Dernière sauvegarde',
            valeur: dateFrOuVide(premiere.date),
            icone: LucideIcons.calendarCheck,
            ton: premiere.succes ? TonSigh.succes : TonSigh.danger,
            indice: premiere.heure),
        KpiSigh(
            libelle: 'Échecs constatés',
            valeur: nombre(echecs),
            icone: LucideIcons.triangleAlert,
            ton: echecs > 0 ? TonSigh.danger : TonSigh.succes),
        KpiSigh(
            libelle: 'Volume moyen',
            valeur: '${secVolumeMoyen(rows)} Mo',
            icone: LucideIcons.hardDrive,
            ton: TonSigh.neutre),
      ]),
      if (echecs > 0) ...[
        const SizedBox(height: 16),
        NoteSigh(
            '$echecs sauvegarde(s) en échec. Une alerte est adressée à l’Administrateur système à chaque échec ; la procédure de restauration doit être testée périodiquement.',
            ton: TonSigh.danger,
            icone: LucideIcons.triangleAlert),
      ],
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Fichiers de sauvegarde disponibles',
        lignes: fichiers,
        taillePage: 10,
        triInitial: 'date',
        sensInitial: 'desc',
        nomExport: 'fichiers-sauvegarde',
        messageVide: 'Aucun fichier de sauvegarde.',
        colonnes: [
          ColonneTableau(
              cle: 'fichier',
              libelle: 'Fichier',
              rendu: (_, r) => Text('${r['fichier']}', style: styleMono)),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date',
              sansCoupure: true,
              texte: (r) => dateFrOuVide(r['date']),
              rendu: (_, r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(dateFrOuVide(r['date']),
                            style: const TextStyle(
                                color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
                        Text('${r['heure']} — ${secPoidsFichier((r['taille'] as num?) ?? 0)}',
                            style: const TextStyle(
                                color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                      ])),
          ColonneTableau(
              cle: 'tables',
              libelle: 'Tables',
              droite: true,
              texte: (r) => '${nombre(r['tables'])} table(s)'),
          ColonneTableau(
              cle: 'portee',
              libelle: 'Portée',
              rendu: (_, r) => BadgeSigh('${r['portee']}', ton: TonSigh.navy)),
        ],
        actionsLigne: (context, r) => [
          BoutonIcone(
              icone: LucideIcons.download,
              libelle: 'Télécharger',
              onPressed: () => _telecharger(context, c, r)),
        ],
        actions: [
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Générer une sauvegarde',
                icone: LucideIcons.databaseBackup,
                taille: TailleBouton.sm,
                onPressed: () => _generer(context, c)),
          if (c.droit.editer)
            BoutonSigh(
                libelle: 'Importer par module',
                icone: LucideIcons.upload,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _importer(context)),
        ],
      ),
      const SizedBox(height: 16),
      const NoteSigh(
          'La sauvegarde hebdomadaire est automatique ; l’utilisateur est invité à en télécharger une copie sur un support externe. Une sauvegarde qui reste sur le poste ne protège de rien.',
          ton: TonSigh.info,
          icone: LucideIcons.databaseBackup),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Lancer une sauvegarde manuelle',
              icone: LucideIcons.databaseBackup,
              onPressed: () => _manuelle(context, c)),
        BoutonSigh(
            libelle: 'Tester une restauration',
            icone: LucideIcons.rotateCcw,
            variante: VarianteBouton.secondaire,
            onPressed: () => _tester(context, c)),
        BoutonSigh(
            libelle: 'Exporter le journal des sauvegardes',
            icone: LucideIcons.printer,
            variante: VarianteBouton.secondaire,
            onPressed: () => _imprimerJournal(context, c, rows)),
      ]),
      const SizedBox(height: 16),
      TableauSigh(
        titre: 'Historique des sauvegardes',
        lignes: [for (final r in rows) _ligne(r)],
        taillePage: 15,
        triInitial: 'date',
        sensInitial: 'desc',
        nomExport: 'sauvegardes',
        filtres: [
          const FiltreTableau(nom: 'type', libelle: 'Type', options: [
            OptionChamp('Quotidienne locale'),
            OptionChamp('Hebdomadaire externalisée'),
          ]),
          FiltreTableau(
              nom: 'succes',
              libelle: 'Résultat',
              options: const [OptionChamp('ok', 'Succès'), OptionChamp('ko', 'Échec')],
              correspond: (r, v) => v == 'ok' ? r['succes'] == true : r['succes'] != true),
        ],
        colonnes: [
          ColonneTableau(
              cle: 'reference',
              libelle: 'Référence',
              sansCoupure: true,
              rendu: (_, r) => Text('${r['reference']}', style: styleMono)),
          ColonneTableau(
              cle: 'date',
              libelle: 'Date',
              sansCoupure: true,
              texte: (r) => dateFrOuVide(r['date'])),
          const ColonneTableau(cle: 'heure', libelle: 'Heure', sansCoupure: true),
          ColonneTableau(
              cle: 'type',
              libelle: 'Type',
              rendu: (_, r) => BadgeSigh('${r['type']}',
                  ton: '${r['type']}'.startsWith('Hebdo') ? TonSigh.navy : TonSigh.neutre)),
          const ColonneTableau(cle: 'support', libelle: 'Support'),
          ColonneTableau(
              cle: 'taille', libelle: 'Volume', droite: true, texte: (r) => '${r['taille']} Mo'),
          ColonneTableau(
              cle: 'duree', libelle: 'Durée', droite: true, texte: (r) => '${r['duree']} s'),
          ColonneTableau(
              cle: 'succes',
              libelle: 'Résultat',
              texte: (r) => r['succes'] == true ? 'Succès' : 'Échec',
              rendu: (_, r) => r['succes'] == true
                  ? const BadgeSigh('Succès', ton: TonSigh.succes)
                  : const BadgeSigh('Échec', ton: TonSigh.danger)),
          const ColonneTableau(cle: 'message', libelle: 'Message'),
        ],
        actionsLigne: (context, r) => [
          if (r['succes'] == true && c.droit.editer)
            BoutonSigh(
                libelle: 'Restaurer',
                icone: LucideIcons.rotateCcw,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _restaurer(context, c, r)),
        ],
      ),
      const SizedBox(height: 16),
      const NoteSigh(
          'Limite du poste : l’historique ci-dessus est calculé (aucune copie n’existe derrière) et « Restaurer » est une simulation journalisée. « Générer », « Lancer une sauvegarde manuelle » et « Télécharger » écrivent l’état réel du poste dans un fichier JSON ; « Importer par module » n’est pas porté.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}
