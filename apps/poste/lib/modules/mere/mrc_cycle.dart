import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/config_poste.dart';
import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import 'mrc_commun.dart';
import 'mrc_sources.dart';

/// Cycle de vie de la mère : « Assistant de première mise en service » (M-20), « Mises à jour et compatibilité » (M-21), « Import de migration » (M-22).

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-mise-en-service
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Assistant en cinq étapes NUMÉROTÉES et reprenables : l'état de chaque étape se relit sur l'état réel (service, comptes, appareils) ou sur une confirmation
/// consignée, jamais sur une progression mémorisée à part. Il ne fait rien d'irréversible sans confirmation nommée ; une étape dont un prérequis manque
/// refuse de s'ouvrir en nommant ce prérequis.
class EcranMereMiseEnService extends StatefulWidget with EcranMaquette {
  const EcranMereMiseEnService({super.key, required this.config});
  final ConfigPoste config;
  @override
  String get titre => 'Assistant de première mise en service';
  @override
  String get description =>
      'Du serveur vide à la clinique prête : identité, administrateur, jeu de départ, activation de la mère, premier appairage.';
  @override
  State<EcranMereMiseEnService> createState() => _EtatMiseEnService();
}

class _EtatMiseEnService extends MrcEtatEcran<EcranMereMiseEnService> {
  EtatMere? _etat;
  Map<String, bool?> _constats = {};

  @override
  Future<void> lire() async {
    Object? err;
    _etat = null;
    try {
      _etat = await src.etat();
    } catch (e) {
      err = e;
    }
    _constats = await src.constats(widget.config, _etat);
    if (err != null) throw err;
  }

  Map<String, MrcEtatEtape> get _etats => mrcEtatsEtapes(_constats);

  Color _teinte(MrcEtatEtape e) => switch (e) {
        MrcEtatEtape.fait => JetonsShell.success600,
        MrcEtatEtape.bloquee => JetonsShell.danger600,
        MrcEtatEtape.aFaire => JetonsShell.slate700,
        MrcEtatEtape.nonVerifiee => JetonsShell.warning600,
      };

  Future<void> _ouvrir(MrcEtape e) async {
    final etats = _etats;
    if (!mrcEtapeOuvrable(e.id, etats)) {
      final m = mrcPrealablesManquants(e.id, etats).map((x) => 'étape ${x.numero} « ${x.libelle} »').join(', ');
      annoncer('Étape ${e.numero} « ${e.libelle} » bloquée : à faire d’abord, $m.', type: TypeToast.erreur);
      return;
    }
    await afficherModale<void>(context,
        titre: 'Étape ${e.numero} : ${e.libelle}',
        sousTitre: mrcLibelleEtat(etats[e.id]!),
        corps: _CorpsEtape(
            etape: e,
            etat: etats[e.id]!,
            peutAgir: mrcPeutAgir(c),
            aller: (id) {
              Navigator.of(context, rootNavigator: true).pop();
              c.aller(id);
            },
            consigner: (choix) async {
              final r = src.consigner(e.id, choix: choix, par: c.agent.nom);
              if (!mounted) return;
              Navigator.of(context, rootNavigator: true).pop();
              annoncerResultat(r);
              await actualiser();
            },
            confirmer: (titre, message, phrase) async {
              if (phrase == null) {
                return confirmerSigh(context, titre: titre, message: message, libelleOk: 'Consigner');
              }
              return (await mrcConfirmerNommee(context, titre: titre, message: message, phrase: phrase, libelleOk: 'Consigner')).ok;
            }));
  }

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final etats = _etats;
    final p = mrcProgression(etats);
    final lignes = [
      for (final e in mrcEtapes) {'n': '${e.numero}', 'etape': e.libelle, 'contenu': e.contenu, 'etat': etats[e.id]!, 'def': e}
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(colonnes: 2, kpis: [
        KpiSigh(
            libelle: 'Étapes faites',
            valeur: charge ? '${p.faites} sur ${p.total}' : '…',
            icone: LucideIcons.listChecks,
            ton: p.faites == p.total ? TonSigh.succes : TonSigh.navy,
            indice: 'relues sur l’état réel du serveur, pas sur une progression mémorisée'),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: [boutonActualiser()]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Parcours',
          sansRemplissage: true,
          child: MrcTableau(colonnes: [
            MrcColonne('#', (l) => '${l['n']}'),
            MrcColonne('Étape', (l) => '${l['etape']}'),
            MrcColonne('Contenu', (l) => '${l['contenu']}'),
            MrcColonne('État', (l) => mrcLibelleEtat(l['etat']! as MrcEtatEtape),
                rendu: (l) => Text(mrcLibelleEtat(l['etat']! as MrcEtatEtape),
                    style: TextStyle(color: _teinte(l['etat']! as MrcEtatEtape), fontSize: 14, fontWeight: FontWeight.w600))),
            MrcColonne('', (l) => '',
                rendu: (l) => BoutonSigh(libelle: 'Ouvrir', taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _ouvrir(l['def']! as MrcEtape))),
          ], lignes: lignes)),
      const SizedBox(height: 16),
      const NoteSigh(
          'Ce que l’assistant ne vérifie pas : l’identité de la clinique (aucune donnée du poste ne dit qu’elle a été saisie, l’état reste « non vérifié » jusqu’à la confirmation consignée) et le vidage du jeu de départ (il se fait à « Réinitialisation de production », avec sa fenêtre, son second profil et sa sauvegarde préalable). Une étape « non vérifié » ne compte pas comme faite.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}

class _CorpsEtape extends StatelessWidget {
  const _CorpsEtape({required this.etape, required this.etat, required this.peutAgir, required this.aller, required this.consigner, required this.confirmer});
  final MrcEtape etape;
  final MrcEtatEtape etat;
  final bool peutAgir;
  final void Function(String ecran) aller;
  final Future<void> Function(String? choix) consigner;
  final Future<bool> Function(String titre, String message, String? phrase) confirmer;

  Widget _texte(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10), child: Text(t, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)));

  @override
  Widget build(BuildContext context) {
    final fait = etat == MrcEtatEtape.fait;
    final actions = <Widget>[];
    switch (etape.id) {
      case 'identite':
        actions.add(BoutonSigh(libelle: 'Ouvrir l’en-tête officiel', variante: VarianteBouton.secondaire, onPressed: () => aller('cfg-entetes')));
        if (peutAgir && !fait) {
          actions.add(BoutonSigh(
              libelle: 'Consigner : identité vérifiée',
              onPressed: () async {
                if (await confirmer('Consigner l’identité ?', 'Vous confirmez avoir relu la dénomination, l’IFU, le RCCM et la devise de l’en-tête officiel.', null)) {
                  await consigner(null);
                }
              }));
        }
      case 'administrateur':
        actions.add(BoutonSigh(libelle: 'Ouvrir la gestion des comptes', variante: VarianteBouton.secondaire, onPressed: () => aller('m14-utilisateurs')));
      case 'jeu_depart':
        actions.add(BoutonSigh(libelle: 'Ouvrir la réinitialisation de production', variante: VarianteBouton.secondaire, onPressed: () => aller('mere-reinit')));
        if (peutAgir && !fait) {
          actions.add(BoutonSigh(
              libelle: 'Consigner : jeu de démonstration conservé',
              variante: VarianteBouton.secondaire,
              onPressed: () async {
                if (await confirmer('Conserver le jeu de démonstration ?', 'Le jeu de démonstration reste en place. Ce choix est consigné avec votre nom.', null)) {
                  await consigner('demonstration');
                }
              }));
          actions.add(BoutonSigh(
              libelle: 'Consigner : essentiels seulement',
              variante: VarianteBouton.danger,
              onPressed: () async {
                if (await confirmer('Ne garder que les essentiels ?',
                    'Vous consignez que l’activité de démonstration a été vidée en ne gardant que les essentiels (référentiels, comptes, droits, tarifs). Le vidage lui-même se fait à « Réinitialisation de production » : il n’est pas fait ici.',
                    etape.phrase)) {
                  await consigner('essentiels');
                }
              }));
        }
      case 'activation':
        actions.add(BoutonSigh(libelle: 'Ouvrir les réglages du poste', variante: VarianteBouton.secondaire, onPressed: () => aller('cfg-poste')));
      case 'appairage':
        actions.add(BoutonSigh(libelle: 'Ouvrir les appareils', variante: VarianteBouton.secondaire, onPressed: () => aller('mere-appareils')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _texte(etape.contenu),
      if (etape.id == 'administrateur' || etape.id == 'activation' || etape.id == 'appairage')
        _texte('Cette étape se constate sur l’état réel du serveur : elle devient « Fait » d’elle-même, sans confirmation à consigner.'),
      if (etat == MrcEtatEtape.nonVerifiee) _texte('Aucune source ne permet de dire si cette étape est faite.'),
      Wrap(spacing: 8, runSpacing: 8, children: actions),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-mises-a-jour
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La compatibilité se juge sur la version de SCHÉMA (spec §14, `426 schema_incompatible`). Le moteur de la mère n'enregistre ni la version d'application
/// ni la version de schéma des appareils, et n'a pas de numéro de schéma propre : ces valeurs sont « non disponibles » tant qu'une source ne les fournit pas ;
/// la règle, elle, est écrite et testée (domaine).
class EcranMereMisesAJour extends StatefulWidget with EcranMaquette {
  const EcranMereMisesAJour({super.key});
  @override
  String get titre => 'Mises à jour et compatibilité';
  @override
  String get description => 'Version de l’application et du schéma par poste ; refus nommé d’un poste trop ancien ; déploiement planifié.';
  @override
  State<EcranMereMisesAJour> createState() => _EtatMisesAJour();
}

class _EtatMisesAJour extends MrcEtatEcran<EcranMereMisesAJour> {
  EtatMere? _etat;

  @override
  Future<void> lire() async {
    _etat = null;
    _etat = await src.etat();
  }

  Future<void> _planifier() async => annoncerResultat(await src.planifierDeploiement());

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final sm = src.schemaMere();
    final appareils = (_etat?.appareils ?? const <Appareil>[]).where((a) => !a.revoque).toList();
    final lignes = <Map<String, Object?>>[];
    final refus = <String>[];
    var aJour = 0, refuses = 0, connus = 0;
    for (final a in appareils) {
      final nom = a.etiquette.isEmpty ? a.uuid : a.etiquette;
      final sa = src.schemaAppareil(a.uuid);
      final compat = mrcCompatibilite(schemaMere: sm.valeur, schemaAppareil: sa.valeur);
      if (compat != MrcCompat.inconnu) connus++;
      if (compat == MrcCompat.aJour) aJour++;
      if (compat == MrcCompat.tropAncien) {
        refuses++;
        refus.add(mrcMotifRefusSchema(nom, sa.valeur!, sm.valeur!));
      }
      lignes.add({'appareil': nom, 'application': src.versionAppareil(a.uuid).texte(), 'schema': sa.texte(), 'etat': mrcLibelleCompat(compat)});
    }
    MrcValeur<int> compte(int n) => _etat == null
        ? const MrcValeur.indisponible('le service de la mère ne répond pas')
        : (connus == 0
            ? MrcValeur.indisponible(appareils.isEmpty ? 'aucun appareil appairé' : 'la version de schéma des appareils et de la mère n’est pas connue')
            : MrcValeur.de(n));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(kpis: [
        mrcKpi<String>('Version de la mère', src.versionMere(), icone: LucideIcons.package),
        mrcKpi<int>('Schéma', sm, icone: LucideIcons.layers, forme: (n) => '$n'),
        mrcKpi<int>('Postes à jour', compte(aJour), icone: LucideIcons.circleCheck, ton: TonSigh.succes, forme: (n) => '$n'),
        mrcKpi<int>('Postes refusés', compte(refuses), icone: LucideIcons.ban, ton: refuses > 0 ? TonSigh.danger : TonSigh.succes, forme: (n) => '$n'),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mrcPeutAgir(c)) BoutonSigh(libelle: 'Planifier le déploiement', icone: LucideIcons.calendarClock, variante: VarianteBouton.secondaire, onPressed: _planifier),
        boutonActualiser(),
      ]),
      if (refus.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (final m in refus) Padding(padding: const EdgeInsets.only(bottom: 8), child: NoteSigh(m, ton: TonSigh.danger, icone: LucideIcons.ban)),
      ],
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Versions par appareil',
          sansRemplissage: true,
          child: MrcTableau(
              colonnes: [
                MrcColonne('Appareil', (l) => '${l['appareil']}'),
                MrcColonne('Application', (l) => '${l['application']}'),
                MrcColonne('Schéma', (l) => '${l['schema']}'),
                MrcColonne('État', (l) => '${l['etat']}'),
              ],
              lignes: lignes,
              vide: _etat == null ? 'Non disponible : le service de la mère ne répond pas.' : 'Aucun appareil appairé.')),
      const SizedBox(height: 16),
      const NoteSigh(
          'Ce que cet écran ne vérifie pas : le moteur n’enregistre ni la version d’application ni la version de schéma des appareils, et ne refuse encore aucun poste trop ancien (le code 426 schema_incompatible est défini par la spécification, pas appliqué). Un état « Inconnu » ne rassure jamais. Aucun mécanisme de distribution des mises à jour n’existe (installateur, E8) : « Planifier le déploiement » est refusé en le disant.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-import
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Import de migration : un fichier CSV analysé EN ENTIER avant la moindre écriture. Une ligne fautive refuse tout le fichier en la nommant (numéro de ligne,
/// colonne, valeur, motif) ; un lot accepté s'écrit d'un seul geste, avec `source`, `lotImport` et `validePar` sur chaque fiche. Jamais de saisie manuelle de
/// l'inventaire : le fichier est la seule voie.
class EcranMereImport extends StatefulWidget with EcranMaquette {
  const EcranMereImport({super.key});
  @override
  String get titre => 'Import de migration';
  @override
  String get description => 'Reprise des données existantes (SAGE, classeurs, jeux de départ) avec traçabilité complète.';
  @override
  State<EcranMereImport> createState() => _EtatImport();
}

class _EtatImport extends MrcEtatEcran<EcranMereImport> {
  @override
  Future<void> lire() async {}

  Future<void> _importer() async {
    await afficherModale<void>(context,
        titre: 'Importer un fichier',
        sousTitre: 'Fichier CSV, séparateur point-virgule, première ligne = en-têtes',
        taille: TailleModale.lg,
        corps: _ModaleImport(src: src, par: c.agent.nom, contexteEcran: context, apres: actualiser));
  }

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final lots = src.lots();
    final importes = lots.where((l) => l['etat'] == 'importé');
    final rejetees = lots.fold<int>(0, (s, l) => s + ((l['rejetees'] as num?)?.toInt() ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(colonnes: 2, kpis: [
        KpiSigh(libelle: 'Lots importés', valeur: '${importes.length}', icone: LucideIcons.packageCheck, ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Lignes rejetées',
            valeur: '$rejetees',
            icone: LucideIcons.fileX,
            ton: rejetees > 0 ? TonSigh.attention : TonSigh.succes,
            indice: 'lignes fautives des fichiers refusés (rien n’a été écrit)'),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mrcPeutAgir(c)) BoutonSigh(libelle: 'Importer un fichier', icone: LucideIcons.upload, onPressed: _importer),
        boutonActualiser(),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Lots',
          sansRemplissage: true,
          child: MrcTableau(
              colonnes: [
                MrcColonne('Lot', (l) => '${l['reference']}'),
                MrcColonne('Source', (l) => '${l['source']}'),
                MrcColonne('Date', (l) => '${l['date'] ?? 'non disponible'}'),
                MrcColonne('Lignes', (l) => '${l['lignes']}'),
                MrcColonne('Validé par', (l) => l['validePar'] == null || '${l['validePar']}'.isEmpty ? 'non renseigné' : '${l['validePar']}'),
                MrcColonne('État', (l) => '${l['etat']}'),
              ],
              lignes: lots,
              vide: 'Aucun lot importé ni refusé sur ce poste.')),
      const SizedBox(height: 16),
      const NoteSigh(
          'Profil disponible : inventaire SAGE (Grand Stock). Colonnes : reference; designation; quantite; pr_unitaire; categorie (unite facultative). Le prix de revient nul signale un article non valorisé, jamais valorisé d’office ; le prix de vente reprend le prix d’achat (RG-02) ; aucun seuil d’alerte n’est inventé. Les classeurs Excel ne se lisent pas encore : les exporter en CSV. Le sélecteur de fichier natif est absent (D5) : on saisit le chemin.',
          icone: LucideIcons.info),
    ]);
  }
}

class _ModaleImport extends StatefulWidget {
  const _ModaleImport({required this.src, required this.par, required this.contexteEcran, required this.apres});
  final MrcSources src;
  final String par;
  final BuildContext contexteEcran;
  final Future<void> Function() apres;
  @override
  State<_ModaleImport> createState() => _EtatModaleImport();
}

class _EtatModaleImport extends State<_ModaleImport> {
  final _chemin = TextEditingController();
  MrcAnalyse? _analyse;
  String? _erreur;
  String? _fichier;
  bool _occupe = false;
  String? _resultat;

  Future<void> _analyser() async {
    final chemin = _chemin.text.trim();
    setState(() {
      _analyse = null;
      _erreur = null;
      _resultat = null;
    });
    if (chemin.isEmpty) {
      setState(() => _erreur = 'Chemin du fichier vide : rien à analyser.');
      return;
    }
    final String texte;
    try {
      texte = await widget.src.lireFichier(chemin);
    } catch (e) {
      if (mounted) setState(() => _erreur = 'Fichier illisible : $chemin ($e). Rien n’a été écrit.');
      return;
    }
    final a = mrcAnalyserImport(texte, mrcProfilSage, codesExistants: widget.src.codesExistants(mrcProfilSage));
    if (!a.accepte) widget.src.consignerRefus(a, fichier: chemin, par: widget.par);
    if (!mounted) return;
    setState(() {
      _analyse = a;
      _fichier = chemin;
    });
    if (!a.accepte) await widget.apres();
  }

  Future<void> _valider() async {
    final a = _analyse!;
    final ok = await confirmerSigh(context,
        titre: 'Valider et importer ce lot ?',
        message:
            '${a.lignes.length} ligne(s) du fichier « $_fichier » vont s’écrire dans « ${a.profil.collection} » en un seul geste, au nom de ${widget.par} (validé par). Un article importé s’archive, il ne se supprime pas (RG-14).',
        libelleOk: 'Valider et importer');
    if (!ok || !mounted) return;
    setState(() => _occupe = true);
    final r = widget.src.importer(a, fichier: _fichier!, par: widget.par);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _resultat = r.ok ? r.message : 'Refusé : ${r.message}';
      if (r.ok) _analyse = null;
    });
    await widget.apres();
  }

  @override
  Widget build(BuildContext context) {
    final a = _analyse;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Text('Profil : Inventaire SAGE (Grand Stock)', style: TextStyle(color: JetonsShell.slate700, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      TextField(
          key: const Key('mrc-chemin'),
          controller: _chemin,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Chemin du fichier CSV')),
      const SizedBox(height: 10),
      Row(children: [BoutonSigh(libelle: 'Analyser', icone: LucideIcons.fileSearch, onPressed: _analyser)]),
      if (_erreur != null) ...[const SizedBox(height: 12), NoteSigh(_erreur!, ton: TonSigh.danger, icone: LucideIcons.triangleAlert)],
      if (_resultat != null) ...[const SizedBox(height: 12), NoteSigh(_resultat!, ton: TonSigh.succes, icone: LucideIcons.circleCheck)],
      if (a != null && !a.accepte) ...[
        const SizedBox(height: 12),
        NoteSigh('Fichier refusé en entier : ${a.nbRefusees} ligne(s) fautive(s). Rien n’a été écrit. Corriger le fichier puis le ré-analyser.',
            ton: TonSigh.danger, icone: LucideIcons.fileX),
        const SizedBox(height: 8),
        for (final r in a.refus)
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(r.toString(), key: const Key('mrc-refus'), style: const TextStyle(color: JetonsShell.danger700, fontSize: 13))),
        if (a.nbRefusees > a.refus.length) MrcMotif('… et ${a.nbRefusees - a.refus.length} autre(s) ligne(s) fautive(s), non listées.'),
      ],
      if (a != null && a.accepte) ...[
        const SizedBox(height: 12),
        NoteSigh(
            'Fichier accepté : ${a.lignes.length} ligne(s), ${a.lignes.fold<int>(0, (s, l) => s + (l['quantite'] as int))} unité(s). Rien n’est encore écrit : la validation écrit le lot en un seul geste.',
            ton: TonSigh.succes,
            icone: LucideIcons.circleCheck),
        const SizedBox(height: 10),
        Row(children: [BoutonSigh(libelle: 'Valider et importer', icone: LucideIcons.packageCheck, onPressed: _occupe ? null : _valider)]),
      ],
    ]);
  }
}
