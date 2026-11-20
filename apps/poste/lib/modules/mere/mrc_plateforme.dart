import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/config_poste.dart';
import '../../core/jetons_shell.dart';
import '../../core/parametres_poste.dart';
import '../../kit/kit.dart';
import '../../mere/client_mere.dart';
import '../../shell/contexte_ecran.dart';
import 'mrc_commun.dart';
import 'mrc_sources.dart';

/// Plateforme locale de la mère : « Service et démarrage » (M-15), « Base de données locale » (M-16), « Réseau local » (M-17). Les trois lisent ce que le
/// moteur expose (`/admin/etat`, `/admin/supervision`), l'état du service que le poste pilote, et le système (interfaces réseau) ; le reste est « non
/// disponible » avec son motif.

String _moteur(String depot) => switch (depot) {
      'pg' => 'PostgreSQL',
      'sqlite' => 'SQLite',
      _ => depot,
    };

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-service
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMereService extends StatefulWidget with EcranMaquette {
  const EcranMereService({super.key, required this.config});
  final ConfigPoste config;
  @override
  String get titre => 'Service et démarrage';
  @override
  String get description => 'Activation du mode mère sur ce serveur, démarrage automatique, ports, arrêt propre.';
  @override
  State<EcranMereService> createState() => _EtatMereService();
}

class _EtatMereService extends MrcEtatEcran<EcranMereService> {
  ParametresPoste? _param;
  Supervision? _sante;

  @override
  Future<void> lire() async {
    _param = await src.parametres();
    _sante = null;
    _sante = await src.supervision();
  }

  /// L'état du service, en croisant ce que le poste sait (processus démarré) et ce que le service répond.
  String _etatService() {
    if (!charge) return '…';
    final m = src.serviceEnMarche();
    final repond = _sante != null;
    if (m.disponible) {
      if (m.valeur == true) return repond ? 'En marche' : 'Démarré, ne répond pas';
      return 'Arrêté';
    }
    return repond ? 'Répond' : 'non disponible';
  }

  Future<void> _arreter() async {
    final ok = await confirmerSigh(context,
        titre: 'Arrêter proprement le service de la mère ?',
        message:
            'Les postes et les mobiles ne pourront plus synchroniser tant que le service est arrêté : leurs gestes restent en file locale et repartent au redémarrage. Les données de la mère sont conservées.',
        libelleOk: 'Arrêter proprement',
        dangereux: true);
    if (!ok) return;
    annoncerResultat(await src.arreter());
    await actualiser();
  }

  Future<void> _redemarrer() async {
    final ok = await confirmerSigh(context,
        titre: 'Redémarrer le service de la mère ?',
        message: 'Le service s’arrête puis redémarre : les postes sont déconnectés quelques secondes et se reconnectent seuls.',
        libelleOk: 'Redémarrer');
    if (!ok) return;
    annoncerResultat(await src.redemarrer());
    await actualiser();
  }

  Future<void> _desactiver() async {
    final r = await mrcConfirmerNommee(context,
        titre: 'Désactiver le mode mère ?',
        message:
            'Le service de synchronisation s’arrête, la place de mère est libérée au relais et ce poste redevient fileul. Les données sont conservées ; pour reprendre la mère sur une autre machine, passer par une restauration, jamais par copie de fichiers.',
        phrase: 'DÉSACTIVER LE MODE MÈRE',
        libelleOk: 'Désactiver le mode mère',
        libelleSecret: 'Secret de la mère (relais)');
    if (!r.ok || !mounted) return;
    annoncerResultat(await src.desactiver(r.secret));
    await actualiser();
  }

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final cfg = widget.config;
    final port = src.port();
    final lignes = <Map<String, Object?>>[
      {'p': 'Nom du poste', 'v': cfg.nomPoste},
      {'p': 'Identifiant du poste', 'v': _param?.uuidPoste ?? 'non disponible'},
      {'p': 'Relais', 'v': _param == null ? 'non disponible' : (_param!.relais.isEmpty ? 'aucun relais configuré' : _param!.relais)},
      {'p': 'Activé depuis', 'v': _param?.activeDepuis == null ? 'non disponible' : _param!.activeDepuis!.toIso8601String().substring(0, 16).replaceAll('T', ' ')},
      {'p': 'Adresse d’administration', 'v': src.adresseAdmin().texte()},
      {'p': 'Adresse d’écoute du service', 'v': src.adresseEcoute().texte()},
      {'p': 'Base de dépôt', 'v': _sante == null ? 'non disponible' : _moteur(_sante!.depot)},
      {'p': 'Démarrage automatique', 'v': src.demarrageAutomatique().texte()},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Mode de ce poste', valeur: cfg.estMere ? 'Poste mère' : 'Poste fileul', icone: LucideIcons.server, ton: cfg.estMere ? TonSigh.succes : TonSigh.neutre),
        KpiSigh(
            libelle: 'Service',
            valeur: _etatService(),
            icone: LucideIcons.power,
            ton: _etatService() == 'En marche' ? TonSigh.succes : (_etatService() == '…' ? TonSigh.neutre : TonSigh.attention)),
        mrcKpi('Démarrage automatique', src.demarrageAutomatique(), forme: (s) => s, icone: LucideIcons.rocket),
        mrcKpi<int>('Port', port, icone: LucideIcons.network),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mrcPeutAgir(c)) ...[
          BoutonSigh(libelle: 'Arrêter proprement', icone: LucideIcons.power, variante: VarianteBouton.secondaire, onPressed: _arreter),
          BoutonSigh(libelle: 'Redémarrer', icone: LucideIcons.refreshCw, variante: VarianteBouton.secondaire, onPressed: _redemarrer),
          BoutonSigh(libelle: 'Désactiver le mode mère', icone: LucideIcons.powerOff, variante: VarianteBouton.danger, onPressed: _desactiver),
        ],
        boutonActualiser(),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Configuration',
          sansRemplissage: true,
          child: MrcTableau(colonnes: [
            MrcColonne('Paramètre', (l) => '${l['p']}'),
            MrcColonne('Valeur', (l) => '${l['v']}'),
          ], lignes: lignes)),
      const SizedBox(height: 16),
      const NoteSigh(
          'Ce que cet écran ne vérifie pas : le démarrage automatique (le service Windows et l’unité systemd ne sont pas faits, E8) et le chiffrement de la base locale (SQLCipher non branché). Une valeur « non disponible » n’est pas un zéro : la source ne la fournit pas.',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-base
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMereBase extends StatefulWidget with EcranMaquette {
  const EcranMereBase({super.key});
  @override
  String get titre => 'Base de données locale';
  @override
  String get description => 'PostgreSQL du serveur : état, taille, version de schéma, migrations, parité avec le magasin.';
  @override
  State<EcranMereBase> createState() => _EtatMereBase();
}

class _EtatMereBase extends MrcEtatEcran<EcranMereBase> {
  Supervision? _sante;
  String? _parite;

  @override
  Future<void> lire() async {
    _sante = null;
    _sante = await src.supervision();
  }

  Controle? get _controleBase {
    final l = _sante?.controles.where((x) => x.nom == 'Base de données');
    return l == null || l.isEmpty ? null : l.first;
  }

  Future<void> _verifierParite() async {
    final r = await src.verifierParite();
    if (r.ok) setState(() => _parite = r.message);
    annoncerResultat(r);
  }

  Future<void> _reconstruire() async {
    if (!src.projectionDisponible().disponible) {
      annoncerResultat(await src.reconstruireTables());
      return;
    }
    final r = await mrcConfirmerNommee(context,
        titre: 'Reconstruire les tables ?',
        message: 'Les tables relationnelles sont reconstruites depuis le magasin ; le magasin lui-même n’est pas modifié. L’opération peut durer plusieurs minutes.',
        phrase: 'RECONSTRUIRE LES TABLES',
        libelleOk: 'Reconstruire');
    if (!r.ok || !mounted) return;
    annoncerResultat(await src.reconstruireTables());
    await actualiser();
  }

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final migrations = src.migrations();
    final lignes = migrations.disponible ? migrations.valeur! : const <Map<String, Object?>>[];
    final base = _controleBase;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(kpis: [
        mrcKpi<String>('Moteur', _sante != null ? MrcValeur.de(_moteur(_sante!.depot)) : (charge ? const MrcValeur.indisponible('le service de la mère ne répond pas') : null),
            icone: LucideIcons.database, indice: base?.detail),
        mrcKpi<String>('Taille', src.tailleBase(), icone: LucideIcons.hardDrive),
        mrcKpi<String>('Schéma', src.schemaBase(), icone: LucideIcons.layers),
        KpiSigh(
            libelle: 'Parité',
            valeur: _parite == null ? 'non vérifiée' : 'vérifiée',
            icone: LucideIcons.scale,
            ton: _parite == null ? TonSigh.neutre : TonSigh.succes,
            indice: _parite ?? 'aucune vérification depuis l’ouverture de cet écran'),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mrcPeutAgir(c)) ...[
          BoutonSigh(libelle: 'Vérifier la parité', icone: LucideIcons.scale, variante: VarianteBouton.secondaire, onPressed: _verifierParite),
          BoutonSigh(libelle: 'Reconstruire les tables', icone: LucideIcons.hammer, variante: VarianteBouton.secondaire, onPressed: _reconstruire),
        ],
        boutonActualiser(),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Migrations appliquées',
          sansRemplissage: true,
          child: MrcTableau(
              colonnes: [
                MrcColonne('Version', (l) => '${l['version']}'),
                MrcColonne('Date', (l) => '${l['date']}'),
                MrcColonne('Résumé', (l) => '${l['resume']}'),
              ],
              lignes: lignes,
              vide: migrations.disponible ? 'Aucune migration appliquée.' : 'Non disponible : ${migrations.motif}.')),
      const SizedBox(height: 16),
      const NoteSigh(
          'Ce que cet écran ne vérifie pas : la taille, la version de schéma, les migrations et la parité tables et magasin. Le moteur Dart de la mère ne les expose pas (la parité et la projection n’existent que dans la maquette, api/parite.php et api/projection.php).',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// mere-reseau
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranMereReseau extends StatefulWidget with EcranMaquette {
  const EcranMereReseau({super.key});
  @override
  String get titre => 'Réseau local';
  @override
  String get description => 'Adresses de la mère, accessibilité depuis les postes, certificat TLS du réseau local, aide pare-feu.';
  @override
  State<EcranMereReseau> createState() => _EtatMereReseau();
}

class _EtatMereReseau extends MrcEtatEcran<EcranMereReseau> {
  EtatMere? _etat;
  List<String> _adresses = const [];
  List<String> _resultatsTest = const [];

  @override
  Future<void> lire() async {
    _adresses = await src.adressesLocales();
    _etat = null;
    _etat = await src.etat();
  }

  ({int joignables, int total})? get _postes {
    final e = _etat;
    if (e == null) return null;
    final actifs = e.appareils.where((a) => !a.revoque && a.role != 'mobile').toList();
    final n = src.maintenant();
    return (joignables: actifs.where((a) => mrcPosteJoignable(a.dernierContact, n)).length, total: actifs.length);
  }

  Future<void> _tester() async {
    final port = src.port();
    if (!port.disponible) {
      annoncerResultat(MrcResultat.refus('le port du service est inconnu : ${port.motif}'));
      return;
    }
    final hotes = ['127.0.0.1', ..._adresses];
    final res = <String>[];
    for (final h in hotes) {
      final r = await src.testerAcces(h, port.valeur!);
      res.add('${r.ok ? 'Joignable' : 'Injoignable'} : ${r.message}');
    }
    if (!mounted) return;
    setState(() => _resultatsTest = res);
  }

  Future<void> _renouveler() async => annoncerResultat(await src.renouvelerCertificat());

  @override
  Widget build(BuildContext context) {
    if (!mrcRolesAdmin.contains(c.role)) return MrcAccesRefuse(role: c.role);
    final port = src.port();
    final postes = _postes;
    final ecoute = src.adresseEcoute();
    final p = port.disponible ? '${port.valeur}' : '<port>';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      mrcBandeauPanne(panne),
      KpiGrilleSigh(kpis: [
        KpiSigh(
            libelle: 'Adresse locale',
            valeur: !charge ? '…' : (_adresses.isEmpty ? 'non disponible' : _adresses.first),
            icone: LucideIcons.globe,
            ton: _adresses.isEmpty ? TonSigh.neutre : TonSigh.navy,
            indice: !charge
                ? null
                : (_adresses.isEmpty
                    ? 'aucune interface réseau IPv4 détectée sur ce serveur'
                    : (_adresses.length > 1 ? 'et ${_adresses.length - 1} autre(s) : ${_adresses.skip(1).join(', ')}' : null))),
        mrcKpi<int>('Port', port, icone: LucideIcons.network),
        mrcKpi<String>('Certificat TLS', src.certificatTls(), icone: LucideIcons.shieldCheck),
        KpiSigh(
            libelle: 'Postes joignables',
            valeur: postes == null ? (charge ? 'non disponible' : '…') : '${postes.joignables} sur ${postes.total}',
            icone: LucideIcons.monitorCheck,
            ton: postes == null ? TonSigh.neutre : (postes.joignables == postes.total ? TonSigh.succes : TonSigh.attention),
            indice: postes == null
                ? 'le service de la mère ne répond pas'
                : 'd’après le dernier contact (moins de $mrcSilencePosteMin min), pas un test réseau'),
      ]),
      const SizedBox(height: 16),
      if (ecoute.disponible && (ecoute.valeur ?? '').startsWith('127.')) ...[
        NoteSigh(
            'Le service n’écoute que sur ${ecoute.valeur} : aucun autre poste du réseau local ne peut le joindre tant que le moteur ne lie pas l’interface réseau. Les postes fileuls ne pourront pas synchroniser depuis une autre machine.',
            ton: TonSigh.danger,
            icone: LucideIcons.triangleAlert),
        const SizedBox(height: 16),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mrcPeutAgir(c)) ...[
          BoutonSigh(libelle: 'Tester depuis un poste', icone: LucideIcons.activity, variante: VarianteBouton.secondaire, onPressed: _tester),
          BoutonSigh(libelle: 'Renouveler le certificat', icone: LucideIcons.refreshCw, variante: VarianteBouton.secondaire, onPressed: _renouveler),
        ],
        boutonActualiser(),
      ]),
      if (_resultatsTest.isNotEmpty) ...[
        const SizedBox(height: 16),
        CarteSigh(
            titre: 'Résultat du test',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in _resultatsTest) Text(l, style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
              const SizedBox(height: 6),
              const MrcMotif('Test de connexion TCP lancé depuis CE serveur. Un test depuis un poste fileul n’est pas disponible : le moteur ne sollicite pas les postes.'),
            ])),
      ],
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Aide pare-feu',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Autoriser en entrée le port TCP $p sur le profil réseau privé du serveur, pour les seuls postes de la clinique.',
                style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14)),
            const SizedBox(height: 8),
            SelectableText('netsh advfirewall firewall add rule name="SIGH-CNT mere" dir=in action=allow protocol=TCP localport=$p profile=private',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, color: JetonsShell.slate700)),
            const SizedBox(height: 8),
            const MrcMotif(
                'Exemple Windows à adapter, jamais exécuté par le logiciel. Sans effet tant que le service n’écoute que sur la boucle locale. Sous Linux, ouvrir le même port avec le pare-feu du système.'),
          ])),
      const SizedBox(height: 16),
      const NoteSigh(
          'Ce que cet écran ne vérifie pas : l’accessibilité réelle depuis un poste fileul et l’état d’un certificat TLS (le service sert en HTTP, sans TLS).',
          ton: TonSigh.attention,
          icone: LucideIcons.triangleAlert),
    ]);
  }
}
