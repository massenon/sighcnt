import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/liaison_maj.dart';
import '../../donnees/maj_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `m14-mise-a-jour` : « Mettre à jour le logiciel » (lot MAJ, PRD-MISE-A-JOUR). Au poste MÈRE comme au poste FILEUL : préparer la mise à jour, essai à blanc, migrer, annuler, exporter la base
/// (SGX2) et importer une base. Chaque commande est ABSENTE sans le geste réservé `lancer_mise_a_jour` de la fiche RBAC, et le moteur (`ServiceMiseAJour`) refuse aussi : masquer un bouton
/// ne protège rien. Tout refus se nomme (code, motif, geste). Une opération qui remplace le magasin demande de REDÉMARRER le poste : le magasin en mémoire n'est jamais réécrit par-dessus.
class EcranMiseAJour extends StatefulWidget with EcranMaquette {
  const EcranMiseAJour({super.key});
  @override
  String get titre => 'Mettre à jour le logiciel';
  @override
  String get description =>
      'Préparer la mise à jour, essai à blanc, migrer, annuler, exporter et importer la base : sans perdre une donnée.';
  @override
  String get regle =>
      'Aucune mise à jour sans copie vérifiée de moins de 24 h ; la mère est mise à jour avant les fileuls ; rien n’est supprimé, tout refus est nommé. '
      'Réservé au droit lancer_mise_a_jour de la fiche RBAC (administrateur et Directrice Administrative par défaut).';
  @override
  State<EcranMiseAJour> createState() => _EtatMiseAJour();
}

class _EtatMiseAJour extends State<EcranMiseAJour> {
  int? _format;
  PlanMigration? _plan;
  DateTime? _copie;
  RapportMaj? _rapport;
  String? _titreRapport;
  RefusMaj? _refus;
  bool _occupe = false;
  bool _redemarrage = false;
  bool _charge = false;

  ServiceMiseAJour? get _svc => LiaisonMaj.service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_charge) {
      _charge = true;
      _lire();
    }
  }

  Future<void> _lire() async {
    final s = _svc;
    if (s == null) return;
    final (f, p, c) = await LiaisonMaj.executer(() async => (
          await s.formatDonnees(),
          await s.plan(),
          await s.derniereCopieVerifiee()
        ));
    if (!mounted) return;
    setState(() {
      _format = f;
      _plan = p;
      _copie = c?.faiteLe;
    });
  }

  bool _geste(ContexteEcran c) =>
      c.donnees?.matrice.droitGeste(c.role, majGeste) ?? false;

  /// Lance une opération : fige le magasin, la joue, montre son rapport ou son refus NOMMÉ.
  Future<void> _jouer(
      String titre, Future<RapportMaj> Function(ServiceMiseAJour s) op,
      {bool remplace = false}) async {
    final s = _svc;
    if (s == null || _occupe) return;
    setState(() {
      _occupe = true;
      _refus = null;
    });
    try {
      await LiaisonMaj.figerMagasin();
      final r = await LiaisonMaj.executer(() => op(s));
      if (!mounted) return;
      setState(() {
        _rapport = r;
        _titreRapport = titre;
        if (remplace) _redemarrage = true;
      });
    } on RefusMajException catch (e) {
      if (mounted) setState(() => _refus = e.refus);
    } catch (e) {
      if (mounted) {
        setState(() => _refus = RefusMaj('MAJ_ERREUR', '$e', 'Aucune donnée n’a été modifiée sans contrôle ; relancer, ou appeler l’assistance'));
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
      await _lire();
    }
  }

  Future<void> _preparer() => _jouer('Préparer la mise à jour', (s) async {
        final dest = await s.preparer();
        final c = await s.derniereCopieVerifiee();
        final m = c?.manifeste['collections'] as Map? ?? const {};
        final total = m.values
            .fold<int>(0, (t, v) => t + ((v as Map)['compte'] as num).toInt());
        final releve = {
          for (final e in m.entries)
            '${e.key}': ReleveCollection(
                ((e.value as Map)['compte'] as num).toInt(),
                '${(e.value as Map)['empreinte']}')
        };
        return RapportMaj(
            comptes: comparerReleves(releve, releve),
            notes: [
              'Copie vérifiée : $total fiches relues à l’identique dans un dossier neuf.',
              'Dossier de la copie : $dest'
            ],
            copie: dest);
      });

  Future<void> _essai() =>
      _jouer('Essai à blanc de la migration', (s) => s.essaiABlanc());

  Future<void> _migrer(ContexteEcran c) =>
      _jouer('Migration des données', (s) => s.migrer(geste: _geste(c)),
          remplace: true);

  Future<void> _annuler(BuildContext ctx, ContexteEcran c) async {
    final s = _svc;
    if (s == null) return;
    setState(() => _refus = null);
    final p = await LiaisonMaj.executer(
        () => s.proposerRetourArriere(geste: _geste(c)));
    if (p.refus != null) {
      if (mounted) setState(() => _refus = p.refus);
      return;
    }
    if (!ctx.mounted) return;
    await afficherModale<void>(ctx,
        titre: 'Annuler la mise à jour',
        taille: TailleModale.lg,
        corps: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteSigh(
                  'Les données reviennent à la copie vérifiée du ${_dateHeure(p.copieDu!)}. Les ${p.saisies.length} saisie(s) faites depuis ne sont PAS perdues : l’état actuel est rangé à part avant la restauration.',
                  ton: p.saisies.isEmpty ? TonSigh.info : TonSigh.attention),
              const SizedBox(height: 8),
              _listeSaisies(p.saisies),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Garder les données actuelles',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  key: const Key('maj:retour-confirmer'),
                  libelle: 'Restaurer la copie',
                  icone: LucideIcons.undo2,
                  onPressed: () {
                    fermer();
                    _jouer('Annuler la mise à jour',
                        (s2) => s2.retourArriere(geste: _geste(c)),
                        remplace: true);
                  }),
            ]);
  }

  Future<void> _exporter(ContexteEcran c) async {
    final nom =
        'sigh-cnt-export-${c.aujourdhui.year}${c.aujourdhui.month.toString().padLeft(2, '0')}${c.aujourdhui.day.toString().padLeft(2, '0')}.sighexp';
    final dest = await LiaisonMaj.choisirDestination(nom);
    if (dest == null) return;
    await _jouer('Exporter la base', (s) async {
      if (!_geste(c)) {
        throw RefusMajException(const RefusMaj(
            CodeMaj.geste,
            'Exporter la base est un geste réservé de la fiche de droits.',
            'Demander à un profil habilité (fiche RBAC, geste « lancer_mise_a_jour »)'));
      }
      final chemin = await s.exporter(dest);
      return RapportMaj(comptes: const RapportComptes([]), notes: [
        'Export écrit : $chemin',
        'Fichier chiffré par la clé de clinique : sans elle il ne se relit pas.'
      ]);
    });
  }

  Future<void> _importer(BuildContext ctx, ContexteEcran c) async {
    final s = _svc;
    if (s == null) return;
    final source = await LiaisonMaj.choisirExport();
    if (source == null) return;
    setState(() => _refus = null);
    await LiaisonMaj.figerMagasin();
    final rattache = LiaisonMaj.fileulRattache();
    RapportMaj blanc;
    try {
      blanc = await LiaisonMaj.executer(() => s.importer(source,
          geste: _geste(c),
          fileulRattache: rattache,
          derniereSynchro: LiaisonMaj.derniereSynchro(),
          essaiABlanc: true));
    } on RefusMajException catch (e) {
      if (mounted) setState(() => _refus = e.refus);
      return;
    }
    if (!ctx.mounted) return;
    await afficherModale<void>(ctx,
        titre: 'Importer une base',
        taille: TailleModale.lg,
        corps: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteSigh(
                  'Essai à blanc : rien n’est encore écrit. ${blanc.comptes.phrase}.'),
              for (final a in blanc.avertissements) ...[
                const SizedBox(height: 8),
                NoteSigh(a,
                    ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
              ],
              if (blanc.saisies.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                    'Saisies de ce poste absentes ou différentes dans la base importée (listées, gardées dans la copie d’avant l’import) :'),
                _listeSaisies(blanc.saisies),
              ],
              const SizedBox(height: 8),
              const NoteSigh(
                  'L’import REMPLACE le magasin de ce poste (l’ancien est rangé à part) ; une copie vérifiée de moins de 24 h est exigée. Le poste redémarrera ensuite.'),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  key: const Key('maj:import-confirmer'),
                  libelle: 'Importer',
                  icone: LucideIcons.fileDown,
                  onPressed: () {
                    fermer();
                    _jouer('Importer une base', (s2) async {
                      final r = await s2.importer(source,
                          geste: _geste(c),
                          fileulRattache: rattache,
                          derniereSynchro: LiaisonMaj.derniereSynchro());
                      if (rattache) LiaisonMaj.rejouerJournal();
                      return r;
                    }, remplace: true);
                  }),
            ]);
  }

  static String _dateHeure(DateTime d) {
    final l = d.toLocal();
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(l.day)}/${d2(l.month)}/${l.year} ${d2(l.hour)}:${d2(l.minute)}';
  }

  Widget _listeSaisies(List<SaisiePosterieure> saisies) {
    if (saisies.isEmpty) return const Text('Aucune saisie postérieure.');
    return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(shrinkWrap: true, children: [
          for (final x in saisies.take(200))
            Text('${x.collection} / ${x.fiche} : ${switch (x.nature) {
              'creee' => 'créée',
              'modifiee' => 'modifiée',
              _ => 'absente maintenant'
            }}'),
          if (saisies.length > 200)
            Text('… et ${saisies.length - 200} autre(s).'),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final geste = _geste(c);
    final s = _svc;
    final rattache = LiaisonMaj.fileulRattache();
    final aMigrer =
        _plan != null && _plan!.refus == null && _plan!.etapes.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s == null)
        const NoteSigh(
            'Mise à jour indisponible sur ce poste : les données ne sont pas chiffrées (poste de développement). Le parcours exige la clé de clinique.',
            ton: TonSigh.attention,
            icone: LucideIcons.triangleAlert)
      else ...[
        KpiGrilleSigh(kpis: [
          KpiSigh(
              libelle: 'Format des données',
              valeur: _format == null ? 'non lu' : '$_format',
              indice: 'Ce logiciel écrit le format $formatDonneesCourant',
              icone: LucideIcons.layers,
              ton: TonSigh.navy),
          KpiSigh(
              libelle: 'Dernière copie vérifiée',
              valeur: _copie == null ? 'Aucune' : _dateHeure(_copie!),
              indice: _copie == null
                  ? 'Sans copie vérifiée, la migration refuse (MAJ_SANS_SAUVEGARDE)'
                  : 'Relue sur disque, signée par la clé de clinique',
              icone: LucideIcons.shieldCheck,
              ton: _copie == null ? TonSigh.attention : TonSigh.succes),
          KpiSigh(
              libelle: 'Rôle de ce poste',
              valeur: rattache ? 'Fileul rattaché' : 'Mère ou autonome',
              indice: 'La mère est mise à jour avant les fileuls',
              icone: LucideIcons.server,
              ton: TonSigh.navy),
        ]),
        const SizedBox(height: 12),
        if (_plan?.refus != null)
          NoteSigh(
              '${_plan!.refus!.code} : ${_plan!.refus!.motif} ${_plan!.refus!.geste}.',
              ton: TonSigh.danger,
              icone: LucideIcons.ban),
        if (aMigrer)
          NoteSigh(
              '${_plan!.etapes.length} migration(s) à passer (${_plan!.etapes.map((e) => e.id).join(', ')}) : format ${_plan!.de} vers ${_plan!.vers}.',
              ton: TonSigh.attention),
        if (_plan != null && _plan!.aRien)
          const NoteSigh(
              'Les données sont déjà au format courant : rien à migrer.',
              ton: TonSigh.succes),
        const SizedBox(height: 12),
        if (geste)
          Wrap(spacing: 8, runSpacing: 8, children: [
            BoutonSigh(
                key: const Key('maj:preparer'),
                libelle: 'Préparer la mise à jour',
                icone: LucideIcons.databaseBackup,
                onPressed: _occupe ? null : _preparer),
            BoutonSigh(
                key: const Key('maj:essai'),
                libelle: 'Essai à blanc',
                icone: LucideIcons.flaskConical,
                variante: VarianteBouton.secondaire,
                onPressed: _occupe ? null : _essai),
            BoutonSigh(
                key: const Key('maj:migrer'),
                libelle: 'Migrer les données',
                icone: LucideIcons.packageCheck,
                onPressed: _occupe ? null : () => _migrer(c)),
            BoutonSigh(
                key: const Key('maj:annuler'),
                libelle: 'Annuler la mise à jour',
                icone: LucideIcons.undo2,
                variante: VarianteBouton.secondaire,
                onPressed: _occupe ? null : () => _annuler(context, c)),
            BoutonSigh(
                key: const Key('maj:exporter'),
                libelle: 'Exporter la base',
                icone: LucideIcons.fileUp,
                variante: VarianteBouton.secondaire,
                onPressed: _occupe ? null : () => _exporter(c)),
            BoutonSigh(
                key: const Key('maj:importer'),
                libelle: 'Importer une base',
                icone: LucideIcons.fileDown,
                variante: VarianteBouton.secondaire,
                onPressed: _occupe ? null : () => _importer(context, c)),
          ])
        else
          const NoteSigh(
              'Lecture seule : lancer une mise à jour est un geste réservé de la fiche de droits (lancer_mise_a_jour).',
              icone: LucideIcons.lock),
        if (_occupe)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
        if (_refus != null) ...[
          const SizedBox(height: 12),
          NoteSigh(
              '${_refus!.code} : ${_refus!.motif}\nGeste : ${_refus!.geste}.',
              ton: TonSigh.danger,
              icone: LucideIcons.ban),
        ],
        if (_rapport != null) ...[
          const SizedBox(height: 16),
          CarteSigh(
              titre: _titreRapport ?? 'Rapport',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_rapport!.comptes.lignes.isNotEmpty)
                      Text(_rapport!.comptes.phrase,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final n in _rapport!.notes) Text(n),
                    for (final a in _rapport!.avertissements)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: NoteSigh(a,
                              ton: TonSigh.attention,
                              icone: LucideIcons.triangleAlert)),
                    if (_rapport!.saisies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${_rapport!.saisies.length} saisie(s) listée(s) :'),
                      _listeSaisies(_rapport!.saisies)
                    ],
                  ])),
        ],
        if (_redemarrage) ...[
          const SizedBox(height: 12),
          const NoteSigh(
              'Le magasin de ce poste a été remplacé : redémarrez le poste pour reprendre le travail sur les nouvelles données.',
              ton: TonSigh.attention),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  key: const Key('maj:redemarrer'),
                  libelle: 'Redémarrer le poste',
                  icone: LucideIcons.rotateCw,
                  onPressed: () => LiaisonMaj.redemarrer())),
        ],
      ],
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Parcours en six étapes',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, e) in const [
              'Préparer la mise à jour : copie chiffrée, restauration vérifiée dans un dossier neuf, comptes et empreintes consignés au journal d’audit (MAJ_SANS_SAUVEGARDE).',
              'Essai à blanc : dit ce qui changerait, sans rien écrire.',
              'Migrer les données : contrôle des comptes avant et après, toute différence nommée (DONNEES_PLUS_RECENTES).',
              'Annuler la mise à jour : dernière copie vérifiée, liste des saisies postérieures, rien écrasé en silence (RETOUR_SANS_COPIE_VERIFIEE).',
              'Exporter la base : un fichier chiffré unique (base, fichiers numérisés, manifeste signé, version du format).',
              'Importer une base : sur la mère ET sur un fileul, la clé de clinique est exigée (IMPORT_SANS_CLE, IMPORT_AUTRE_CLINIQUE, IMPORT_ALTERE, IMPORT_SANS_COPIE_PREALABLE).',
            ].indexed)
              Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${i + 1}. $e')),
            const SizedBox(height: 4),
            const Text(
                'Un fileul de format trop ancien reçoit 426 schema_incompatible : il n’envoie rien et garde ses saisies hors ligne. Un fileul qui importe une base plus ancienne que sa dernière synchronisation est averti (IMPORT_PLUS_ANCIEN_QUE_SYNC, non bloquant).'),
          ])),
    ]);
  }
}
