/// LA COPIE HORS SITE DE LA MÈRE (lot 5, ADR-0007) : le planificateur (copie horaire des fichiers, copie et contrôle de nuit), le journal technique, les alertes, l'état pour l'écran, la
/// restauration. Les règles pures sont dans `sigh_domaine`, le client et les destinations dans `sauvegarde_horssite.dart`.
///
/// Le réglage est un PARAMÈTRE EN BASE (famille `horssite`, versionné par date, défauts semés : désactivée par défaut), lu à chaque passe de la collection `parametres` de la mère. La clé de la
/// clinique est celle du journal : elle n'est JAMAIS envoyée ni stockée à la destination. Le journal technique ne porte JAMAIS un nom de fichier, un nom de patient ni un contenu : des
/// codes, des compteurs, des tailles, des empreintes abrégées (RG-12 ; texte médical hors de la clinique : jamais).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'depot.dart';
import 'sauvegarde_horssite.dart';
import 'stockage_fichiers.dart';

/// La mère vue par la copie hors site : ce dont elle a besoin, sans importer `mere.dart` (pas de cycle).
class HorsSiteMere {
  HorsSiteMere({
    required this.base,
    required this.verrou,
    required this.cle,
    required this.relais,
    required this.secretRelais,
    required this.dossierSauvegardes,
    required this.evenement,
    this.stockage,
    this.cleStockage,
    DateTime Function()? horloge,
    this.intervalle = const Duration(minutes: 1),
  }) : _horloge = horloge ?? DateTime.now;

  final Depot base;
  final Verrou verrou;

  /// La clé de la clinique (32 octets), lue à chaque usage (elle peut être posée après la création).
  final List<int> Function() cle;
  final String relais;
  final String secretRelais;
  final String dossierSauvegardes;
  final void Function(String niveau, String source, String message) evenement;
  final StockageFichiers? stockage;
  final List<int>? cleStockage;
  final DateTime Function() _horloge;
  final Duration intervalle;
  Timer? _minuterie;
  final Set<String> _enCours = {};

  void demarrer() {
    _minuterie ??= Timer.periodic(intervalle, (_) => unawaited(passe()));
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  // --- le réglage, lu de la base ----------------------------------------------------------------------------------------------------------------

  /// Le réglage en vigueur AUJOURD'HUI : la valeur de la base, à défaut le défaut semé (désactivée).
  Future<ReglageHorsSite> reglage() async {
    final lignes = await verrou.executer(() => base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [parCollectionParametres]));
    final versions = <Parametre>[];
    for (final r in lignes) {
      try {
        final p = Parametre.fromJson((jsonDecode(r['data'] as String) as Map).cast<String, Object?>());
        if (p.cle.startsWith('horssite.')) versions.add(p);
      } catch (_) {/* une fiche illisible n'est pas une version */}
    }
    final jour = parametreDateIso(_horloge());
    Object? v(String cle) {
      final res = Parametres.resoudre(cle, versions.where((x) => x.cle == cle).toList(), jour, definition: definitionDeParametre(cle));
      return res.ok ? res.valeur!.valeur : definitionDeParametre(cle)?.defaut;
    }

    int entier(String cle, int defaut) {
      final x = v(cle);
      return x is num ? x.toInt() : defaut;
    }

    String texte(String cle) => '${v(cle) ?? ''}';
    return ReglageHorsSite(
      actif: v(shCleActif) == true,
      magasin: ReglageType(destination: texte(shCleDestinationMagasin), dossier: texte(shCleDossierMagasin), copies: entier(shCleCopiesMagasin, shCopiesMagasinDefaut)),
      fichiers: ReglageType(destination: texte(shCleDestinationFichiers), dossier: texte(shCleDossierFichiers), copies: entier(shCleCopiesFichiers, shCopiesFichiersDefaut)),
      frequenceMinutes: entier(shCleFrequence, shFrequenceDefaut),
      heureControle: entier(shCleHeureControle, shHeureControleDefaut),
      tailleBloc: entier(shCleTailleBloc, shTailleBlocDefaut),
      blocsControles: entier(shCleBlocsControles, shBlocsControlesDefaut),
    );
  }

  /// La destination d'un type, ou le refus nommé (relais non relié, dossier absent).
  DestinationSauvegarde destination(String type, ReglageHorsSite r) {
    final x = r.de(type);
    switch (x.destination) {
      case 'relais':
        if (relais.isEmpty) {
          throw ErreurSauvegarde(const RefusSauvegarde('RELAIS_NON_CONFIGURE', 'la mère n\'est pas reliée au relais web', 'Relier la mère au relais (adresse et secret de la mère) avant de choisir le relais comme destination.'));
        }
        return DestinationRelais(relais, secretRelais);
      case 'dossier':
        return DestinationDossier(x.dossier);
      default:
        throw ErreurSauvegarde(RefusSauvegarde('DESTINATION_ABSENTE', 'aucune destination n\'est réglée pour la copie $type', 'Choisir le relais ou un dossier distant à l\'écran « Sauvegarde hors site ».'));
    }
  }

  // --- l'état persistant (méta de la base) : ce que la dernière passe a fait ------------------------------------------------------------------------

  Future<Map<String, Object?>> _lireEtat(String type) async {
    final s = await verrou.executer(() => base.meta('horssite:$type'));
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _poserEtat(String type, Map<String, Object?> e) => verrou.executer(() => base.poserMeta('horssite:$type', jsonEncode(e)));

  File get _fichierIndex => File('$dossierSauvegardes/horssite-index-fichiers.json');

  IndexBlocs _lireIndex() {
    try {
      final j = (jsonDecode(_fichierIndex.readAsStringSync()) as Map).cast<String, Object?>();
      return {for (final e in j.entries) e.key: [for (final b in (e.value as List)) (b as Map).cast<String, Object?>()]};
    } catch (_) {
      return {};
    }
  }

  void _ecrireIndex(IndexBlocs i) {
    Directory(dossierSauvegardes).createSync(recursive: true);
    final t = File('${_fichierIndex.path}.tmp');
    t.writeAsStringSync(jsonEncode(i), flush: true);
    t.renameSync(_fichierIndex.path);
  }

  void _alerter(String message) => evenement('alerte', 'sauvegarde', message);

  // --- une copie ------------------------------------------------------------------------------------------------------------------------------------

  /// Une copie du [type] vers sa destination. Rend le compte rendu (jamais un nom de fichier) ; un refus nommé est ENREGISTRÉ (état, journal, alerte) puis relancé : jamais un « ok » silencieux.
  Future<Map<String, Object?>> lancer(String type, {bool manuel = false}) async {
    if (!shTypes.contains(type)) throw ErreurSauvegarde(RefusSauvegarde('TYPE_INCONNU', 'le type « $type » n\'existe pas', 'Choisir magasin ou fichiers.'));
    final r = await reglage();
    if (!r.actif) {
      throw const ErreurSauvegarde(RefusSauvegarde('HORSSITE_DESACTIVEE', 'la copie hors site est désactivée', 'L\'administrateur ou la Directrice Administrative l\'active à l\'écran « Sauvegarde hors site ».'));
    }
    if (_enCours.contains(type)) {
      throw ErreurSauvegarde(RefusSauvegarde('COPIE_EN_COURS', 'une copie $type est déjà en cours', 'Attendre la fin de la copie en cours.'));
    }
    _enCours.add(type);
    final t0 = _horloge();
    try {
      await _poserEtat(type, {...await _lireEtat(type), 'tentative': t0.millisecondsSinceEpoch});
      final dest = destination(type, r);
      final ctrl = shVerifierReglageClinique(r);
      if (ctrl != null) throw ErreurSauvegarde(ctrl);
      final elements = type == 'magasin' ? await _elementsMagasin() : await _elementsFichiers();
      final index = type == 'fichiers' ? _lireIndex() : null;
      final res = await sauvegarderHorsSite(
          dest: dest, cle: cle(), type: type, elements: elements.liste, tailleBloc: r.tailleBloc, garder: r.de(type).copies, index: index, date: t0.millisecondsSinceEpoch);
      if (index != null) _ecrireIndex(index);
      final rapport = {
        'ok': true,
        'quand': _horloge().millisecondsSinceEpoch,
        'duree': _horloge().difference(t0).inMilliseconds,
        'copie': res.copie.substring(0, 12),
        'rejeu': res.rejeu,
        'deposes': res.deposes,
        'dejaLa': res.dejaLa,
        'octetsDeposes': res.octetsDeposes,
        'blocs': res.blocs,
        'elements': elements.liste.length - res.illisibles,
        'illisibles': elements.illisibles + res.illisibles,
        'destination': dest.libelle,
        'manuel': manuel,
      };
      final avant = await _lireEtat(type);
      await _poserEtat(type, {...avant, 'dernier': rapport, 'erreur': null, 'alerte': null});
      evenement('info', 'sauvegarde', 'Copie hors site $type (${dest.libelle}) : ${res.deposes} bloc(s) déposé(s), ${res.dejaLa} déjà présent(s), ${elements.liste.length - res.illisibles} élément(s)${res.rejeu ? ', état déjà sauvegardé' : ''}'
          '${elements.illisibles + res.illisibles > 0 ? ', ${elements.illisibles + res.illisibles} élément(s) illisible(s) à la source (non copiés)' : ''}');
      if (elements.illisibles + res.illisibles > 0) _alerter('Copie hors site $type : ${elements.illisibles + res.illisibles} élément(s) illisible(s) à la source, non copiés (voir le contrôle des fichiers numérisés)');
      return rapport;
    } on ErreurSauvegarde catch (e) {
      final erreur = {'quand': _horloge().millisecondsSinceEpoch, 'code': e.code, 'motif': e.refus.motif, 'geste': e.refus.geste};
      final avant = await _lireEtat(type);
      await _poserEtat(type, {...avant, 'erreur': erreur});
      // le même refus qui se répète (nouvelle tentative toutes les dix minutes) n'inonde ni le journal ni les alertes : il est dit à son premier passage et quand il change
      if ((avant['erreur'] as Map?)?['code'] != e.code) {
        evenement('erreur', 'sauvegarde', 'Copie hors site $type refusée : ${e.code}');
        if (e.code == 'ESPACE_RELAIS_INSUFFISANT' || e.code == 'SAUVEGARDE_TROP_GROSSE') {
          _alerter('Copie hors site $type impossible : ${e.code} (${e.refus.geste})');
        } else {
          _alerter('Copie hors site $type en échec : ${e.code}');
        }
      }
      rethrow;
    } catch (e) {
      final erreur = {'quand': _horloge().millisecondsSinceEpoch, 'code': 'DESTINATION_INJOIGNABLE', 'motif': 'la destination n\'a pas répondu', 'geste': 'Vérifier la liaison Internet ou le montage du dossier distant ; la copie reprendra à la prochaine tentative.'};
      final avant = await _lireEtat(type);
      await _poserEtat(type, {...avant, 'erreur': erreur});
      if ((avant['erreur'] as Map?)?['code'] != 'DESTINATION_INJOIGNABLE') evenement('erreur', 'sauvegarde', 'Copie hors site $type : destination injoignable (${e.runtimeType})');
      rethrow;
    } finally {
      _enCours.remove(type);
    }
  }

  Future<({List<ElementASauver> liste, int illisibles})> _elementsMagasin() async {
    final chemin = await verrou.executer(() => base.sauvegarder('horssite', dossier: dossierSauvegardes));
    final f = File(chemin);
    try {
      final octets = f.readAsBytesSync();
      return (liste: [ElementASauver(ref: 'magasin', taille: octets.length, lire: () async => octets)], illisibles: 0);
    } finally {
      try {
        f.deleteSync();
      } catch (_) {/* au mieux : le fichier en clair n'existe que le temps de la copie */}
    }
  }

  Future<({List<ElementASauver> liste, int illisibles})> _elementsFichiers() async {
    final s = stockage;
    if (s == null) return (liste: <ElementASauver>[], illisibles: 0);
    final liste = <ElementASauver>[];
    var illisibles = 0;
    await for (final sha in s.empreintes()) {
      final m = await s.meta(sha);
      if (m == null) {
        illisibles++;
        continue;
      }
      liste.add(ElementASauver(
          ref: '$sha.${m.ext}',
          taille: m.taille,
          meta: m.toJson(),
          shaClair: sha,
          lire: () async {
            try {
              return await s.lire(sha);
            } on ErreurFichier {
              throw const ElementIllisible();
            }
          }));
    }
    // Un fichier altéré à la source n'est jamais propagé : il est écarté (compté) et la copie des autres continue.
    final sains = <ElementASauver>[];
    for (final e in liste) {
      try {
        if (e.shaClair != null && !await s.existe(e.shaClair!)) {
          illisibles++;
          continue;
        }
        sains.add(e);
      } catch (_) {
        illisibles++;
      }
    }
    return (liste: sains, illisibles: illisibles);
  }

  // --- le contrôle de nuit --------------------------------------------------------------------------------------------------------------------------

  /// Le contrôle : pour chaque type actif, la dernière copie est relue et [ReglageHorsSite.blocsControles] blocs sont téléchargés et vérifiés de bout en bout.
  Future<Map<String, Object?>> controler() async {
    final r = await reglage();
    final sortie = <String, Object?>{};
    for (final t in shTypes) {
      if (!r.actif || !r.de(t).actifPossible) continue;
      try {
        final refus = await controlerHorsSite(dest: destination(t, r), cle: cle(), type: t, nbBlocs: r.blocsControles);
        final e = await _lireEtat(t);
        final ctrl = refus == null ? {'ok': true, 'quand': _horloge().millisecondsSinceEpoch} : {'ok': false, 'quand': _horloge().millisecondsSinceEpoch, 'code': refus.code, 'motif': refus.motif, 'geste': refus.geste};
        await _poserEtat(t, {...e, 'controle': ctrl});
        sortie[t] = ctrl;
        if (refus != null) {
          evenement('erreur', 'sauvegarde', 'Contrôle de la copie hors site $t : ${refus.code}');
          _alerter('Contrôle de la copie hors site $t en échec : ${refus.code} (${refus.geste})');
        } else {
          evenement('info', 'sauvegarde', 'Contrôle de la copie hors site $t : ${r.blocsControles} bloc(s) vérifié(s) de bout en bout');
        }
      } on ErreurSauvegarde catch (e) {
        sortie[t] = {'ok': false, 'code': e.code, 'motif': e.refus.motif};
        evenement('erreur', 'sauvegarde', 'Contrôle de la copie hors site $t impossible : ${e.code}');
      } catch (_) {
        sortie[t] = {'ok': false, 'code': 'DESTINATION_INJOIGNABLE'};
        evenement('erreur', 'sauvegarde', 'Contrôle de la copie hors site $t : destination injoignable');
      }
    }
    return sortie;
  }

  // --- le planificateur -----------------------------------------------------------------------------------------------------------------------------

  /// Une passe de la minuterie : ce qui est dû est fait ; ce qui est en retard est signalé UNE fois. Désactivée : rien.
  Future<void> passe() async {
    final r = await reglage();
    if (!r.actif) return;
    final maintenant = _horloge();
    for (final t in shTypes) {
      if (!r.de(t).actifPossible) continue;
      final e = await _lireEtat(t);
      final dernier = (e['dernier'] as Map?)?['quand'];
      final dernierMs = dernier is num ? dernier.toInt() : 0;
      final tentative = e['tentative'];
      final tentativeMs = tentative is num ? tentative.toInt() : 0;
      final age = maintenant.millisecondsSinceEpoch - dernierMs;
      // après un échec, nouvelle tentative au plus toutes les dix minutes (jamais une rafale contre une destination absente)
      final apresPause = maintenant.millisecondsSinceEpoch - tentativeMs >= _pauseApresTentative.inMilliseconds;
      final dueFichiers = t == 'fichiers' && age >= r.frequenceMinutes * 60000;
      // la copie du magasin est une copie de NUIT : une par jour, à partir de l'heure réglée (la première, dès l'activation si l'heure est passée)
      final dueNuit = t == 'magasin' && maintenant.hour >= r.heureControle && (dernierMs == 0 || !_memeJour(DateTime.fromMillisecondsSinceEpoch(dernierMs), maintenant));
      if ((dueFichiers || dueNuit) && apresPause && !_enCours.contains(t)) {
        try {
          await lancer(t);
        } catch (_) {/* déjà enregistré et alerté par lancer */}
      }
    }
    // le contrôle de nuit : une fois par jour, à partir de l'heure réglée
    final ctrl = (await _lireEtat('controle'))['quand'];
    final ctrlMs = ctrl is num ? ctrl.toInt() : 0;
    if (maintenant.hour >= r.heureControle && (ctrlMs == 0 || !_memeJour(DateTime.fromMillisecondsSinceEpoch(ctrlMs), maintenant))) {
      await _poserEtat('controle', {'quand': maintenant.millisecondsSinceEpoch});
      await controler();
    }
    await _alerterRetards(r);
  }

  static const Duration _pauseApresTentative = Duration(minutes: 10);
  static bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// L'âge limite d'une copie : deux fréquences pour les fichiers, 30 heures pour le magasin (copie de nuit).
  Duration _limiteRetard(String type, ReglageHorsSite r) => type == 'magasin' ? const Duration(hours: 30) : Duration(minutes: r.frequenceMinutes * 2 + 5);

  Future<void> _alerterRetards(ReglageHorsSite r) async {
    final maintenant = _horloge().millisecondsSinceEpoch;
    for (final t in shTypes) {
      if (!r.de(t).actifPossible) continue;
      final e = await _lireEtat(t);
      final dernier = (e['dernier'] as Map?)?['quand'];
      final enRetard = dernier is num ? maintenant - dernier.toInt() > _limiteRetard(t, r).inMilliseconds : false;
      final jamais = dernier == null;
      // « jamais faite » ne s'alerte qu'après la première échéance : une mère qui vient d'être réglée n'alerte pas tout de suite
      if (enRetard && e['alerte'] != 'retard') {
        await _poserEtat(t, {...e, 'alerte': 'retard'});
        _alerter('Copie hors site $t en retard : la dernière copie réussie date de plus de ${_limiteRetard(t, r).inHours} heure(s)');
      } else if (!enRetard && !jamais && e['alerte'] == 'retard') {
        await _poserEtat(t, {...e, 'alerte': null});
      }
    }
  }

  // --- l'état pour l'écran ---------------------------------------------------------------------------------------------------------------------------

  /// Ce que l'écran montre : le réglage, par type la dernière copie réussie, la dernière erreur, le dernier contrôle, le retard. Jamais un contenu, jamais un nom de fichier.
  Future<Map<String, Object?>> etat() async {
    final r = await reglage();
    final maintenant = _horloge().millisecondsSinceEpoch;
    final types = <String, Object?>{};
    for (final t in shTypes) {
      final e = await _lireEtat(t);
      final dernier = (e['dernier'] as Map?)?['quand'];
      types[t] = {
        'destination': r.de(t).destination,
        'dernier': e['dernier'],
        'erreur': e['erreur'],
        'controle': e['controle'],
        'enCours': _enCours.contains(t),
        'enRetard': r.actif && r.de(t).actifPossible && dernier is num && maintenant - dernier.toInt() > _limiteRetard(t, r).inMilliseconds,
        'jamaisFaite': dernier == null,
      };
    }
    return {
      'actif': r.actif,
      'frequenceMinutes': r.frequenceMinutes,
      'heureControle': r.heureControle,
      'relaisRelie': relais.isNotEmpty,
      'types': types,
      'controle': await _lireEtat('controle'),
    };
  }

  /// Les copies d'un type vues par sa destination (identifiant abrégé, état, date, taille), pour choisir la copie à restaurer.
  Future<List<Map<String, Object?>>> copies(String type) async {
    final r = await reglage();
    final liste = await destination(type, r).copies(type);
    return [
      for (final c in liste)
        {'id': c['id'], 'etat': c['etat'], 'date': c['date'], 'taille': c['taille'], 'nbBlocs': c['nb_blocs'], 'motif': c['motif']}
    ];
  }

  // --- la restauration ---------------------------------------------------------------------------------------------------------------------------------

  /// RESTAURE une copie dans une cible NEUVE (jamais la base ni le dossier en service). Magasin : `<cible>/magasin`. Fichiers : `<cible>/fichiers/<aa>/<sha>.<ext>`, rangés dans un stockage neuf
  /// avec leurs usages. Tout est vérifié AVANT d'écrire ; un bloc altéré ou manquant est refusé et nommé, rien n'est posé à moitié.
  Future<Map<String, Object?>> restaurer({required String type, required String copie, required String cible}) async {
    final r = await reglage();
    final dest = destination(type, r);
    Future<void> Function(String, List<Map<String, Object?>>)? apres;
    if (type == 'fichiers') {
      apres = (travail, elements) async {
        final neuf = StockageFichiers('$travail/fichiers', cle: cleStockage);
        for (final e in elements) {
          final ref = '${e['ref']}';
          final brut = File('$travail/$ref');
          final octets = brut.readAsBytesSync();
          final meta = (e['meta'] as Map?)?.cast<String, Object?>();
          final usages = [for (final u in (meta?['usages'] as List? ?? const [])) (u as Map).cast<String, Object?>()];
          if (usages.isEmpty) throw ErreurSauvegarde(RefusSauvegarde('METADONNEES_ABSENTES', 'un fichier de la copie n\'a aucun usage enregistré', 'Choisir une autre copie.', {'element': ref.substring(0, 12)}));
          for (final u in usages) {
            try {
              await neuf.ranger(octets, famille: '${u['famille']}', zone: (u['zone'] as num?)?.toInt() ?? 0, deposePar: meta?['deposePar'] as String?);
            } on ErreurFichier catch (x) {
              throw ErreurSauvegarde(RefusSauvegarde('FICHIER_REFUSE', '${x.refus.code} : ${x.refus.motif}', x.refus.geste, {'element': ref.substring(0, 12)}));
            }
          }
          brut.deleteSync();
        }
      };
    }
    final res = await restaurerHorsSite(dest: dest, cle: cle(), copieId: copie, cible: cible, apresVerification: apres);
    evenement('alerte', 'sauvegarde', 'Restauration de la copie hors site $type vers une cible neuve : ${res.elements} élément(s), ${res.octets} octet(s) vérifiés');
    return {'ok': true, 'type': type, 'elements': res.elements, 'octets': res.octets, 'cible': cible};
  }

}
