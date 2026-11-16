/// LES ENVOIS AUTOMATIQUES DE SMS DE LA MÈRE (lot SMS-R, ADR-0008). La mère CALCULE (agenda, dates de naissance, consentements : règles pures de `sigh_domaine`, `sms_auto.dart`), compose le
/// texte, puis DÉPOSE au relais des messages déjà composés ; le relais les garde planifiés et les envoie par son cron, puis efface le clair. Le relais ne reçoit jamais l'annuaire, une date de
/// naissance, un code patient ni un rendez-vous : l'identifiant d'un message est le HMAC-SHA256 de la clé de clinique (jamais envoyée) sur une clé naturelle qui reste à la mère.
///
/// Quand : au démarrage, chaque heure, quelques secondes après un changement de fiche (`signaler`). Idempotent : le relais connaît l'identifiant, un redépôt ne double rien. Un rendez-vous annulé
/// ou déplacé, un consentement retiré, un numéro corrigé retire l'envoi planifié (`/sms/annuler`) ; un envoi PARTI ne se retire pas (le relais le dit, la mère le garde « parti »).
/// Le réglage est EN BASE (paramètres de la famille `sms`), désactivé par défaut. Le journal technique ne porte jamais un numéro, un texte ni un nom.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'depot.dart';

/// Un refus NOMMÉ (code, motif, geste) venu de la mère ou du relais.
class ErreurSms implements Exception {
  const ErreurSms(this.code, this.motif, this.geste, [this.statut = 422]);
  final String code, motif, geste;
  final int statut;
  @override
  String toString() => '$code : $motif';
}

/// Les collections dont un changement déclenche un nouveau calcul.
const Set<String> collectionsSmsSurveillees = {'consultations', 'patients', 'deces', 'employes', 'parametres'};

class SmsMere {
  SmsMere({
    required this.base,
    required this.verrou,
    required this.cle,
    required this.relais,
    required this.secretRelais,
    required this.evenement,
    DateTime Function()? horloge,
    this.intervalle = const Duration(hours: 1),
    this.delaiChangement = const Duration(seconds: 5),
    this.delaiDemarrage = const Duration(seconds: 15),
  }) : _horloge = horloge ?? DateTime.now;

  final Depot base;
  final Verrou verrou;

  /// La clé de la clinique (32 octets) : sert à l'HMAC de l'identifiant opaque, JAMAIS envoyée.
  final List<int> Function() cle;
  final String relais, secretRelais;
  final void Function(String niveau, String source, String message) evenement;
  final DateTime Function() _horloge;
  final Duration intervalle, delaiChangement, delaiDemarrage;
  Timer? _minuterie, _debut, _changement;
  bool _enCours = false;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  Future<void> initialiser() => base.exec('CREATE TABLE IF NOT EXISTS sms_depots (id TEXT PRIMARY KEY, cle TEXT, type TEXT, heure TEXT, numero_masque TEXT, etat TEXT)');

  void demarrer() {
    _debut ??= Timer(delaiDemarrage, () => unawaited(_silencieuse()));
    _minuterie ??= Timer.periodic(intervalle, (_) => unawaited(_silencieuse()));
  }

  void arreter() {
    _debut?.cancel();
    _minuterie?.cancel();
    _changement?.cancel();
    _debut = _minuterie = _changement = null;
    _http.close(force: true);
  }

  /// Une fiche d'une collection surveillée a changé : un nouveau calcul part dans quelques secondes (regroupé).
  void signaler() {
    _changement?.cancel();
    _changement = Timer(delaiChangement, () => unawaited(_silencieuse()));
  }

  Future<void> _silencieuse() async {
    try {
      await passe();
    } catch (_) {/* l'erreur est déjà enregistrée par passe() */}
  }

  // --- le réglage, lu de la base ------------------------------------------------------------------------------------------------------------------

  Future<ReglageSmsAuto> reglage() async {
    final lignes = await verrou.executer(() => base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [parCollectionParametres]));
    final versions = <Parametre>[];
    for (final r in lignes) {
      try {
        final p = Parametre.fromJson((jsonDecode(r['data'] as String) as Map).cast<String, Object?>());
        if (p.cle.startsWith('sms.')) versions.add(p);
      } catch (_) {/* une fiche illisible n'est pas une version */}
    }
    final jour = parametreDateIso(_horloge());
    Object? v(String c) {
      final res = Parametres.resoudre(c, versions.where((x) => x.cle == c).toList(), jour, definition: definitionDeParametre(c));
      return res.ok ? res.valeur!.valeur : definitionDeParametre(c)?.defaut;
    }

    int entier(String c, int d) {
      final x = v(c);
      return x is num ? x.toInt() : d;
    }

    String texte(String c, String d) {
      final x = v(c);
      return x is String && x.trim().isNotEmpty ? x : d;
    }

    return ReglageSmsAuto(
      actif: v(smsCleActif) == true,
      rappelHeure: entier(smsCleRappelHeure, smsRappelHeureDefaut),
      rappelJoursAvant: entier(smsCleRappelJoursAvant, smsRappelJoursAvantDefaut),
      anniversaireHeure: entier(smsCleAnniversaireHeure, smsAnniversaireHeureDefaut),
      calmeDebut: entier(smsCleCalmeDebut, smsCalmeDebutDefaut),
      calmeFin: entier(smsCleCalmeFin, smsCalmeFinDefaut),
      horizonJours: entier(smsCleHorizonJours, smsHorizonJoursDefaut),
      toleranceMinutes: entier(smsCleToleranceMinutes, smsToleranceMinutesDefaut),
      modeleRappel: texte(smsCleModeleRappel, smsModeleRappelDefaut),
      modeleAnniversairePatient: texte(smsCleModeleAnniversairePatient, smsModeleAnniversairePatientDefaut),
      modeleAnniversairePersonnel: texte(smsCleModeleAnniversairePersonnel, smsModeleAnniversairePersonnelDefaut),
    );
  }

  Future<List<Map<String, Object?>>> _fiches(String collection) async {
    final lignes = await verrou.executer(() => base.select('SELECT id, data FROM fiches WHERE collection=? AND archive=0', [collection]));
    final out = <Map<String, Object?>>[];
    for (final r in lignes) {
      try {
        out.add({...(jsonDecode(r['data'] as String) as Map).cast<String, Object?>(), 'id': r['id']});
      } catch (_) {/* illisible : ignorée */}
    }
    return out;
  }

  /// L'identifiant OPAQUE d'un envoi : HMAC-SHA256 de la clé de clinique sur la clé naturelle (64 caractères hexadécimaux). Le relais ne peut ni le défaire ni le relier à une personne.
  String identifiantOpaque(String cleNaturelle) => Hmac(sha256, cle()).convert(utf8.encode('sigh-sms-id|1|$cleNaturelle')).toString();

  // --- le relais ------------------------------------------------------------------------------------------------------------------------------------

  Future<Map<String, Object?>> _relais(String methode, String chemin, [Object? corps]) async {
    if (relais.isEmpty) {
      throw const ErreurSms('RELAIS_NON_CONFIGURE', 'la mère n\'est pas reliée au relais web', 'Relier la mère au relais (adresse et secret de la mère) pour envoyer des SMS.', 409);
    }
    final int statut;
    final String brut;
    try {
      final req = await _http.openUrl(methode, Uri.parse('$relais$chemin')).timeout(const Duration(seconds: 20));
      req.headers.set('x-mere', secretRelais);
      if (corps != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(corps)));
      }
      final rep = await req.close().timeout(const Duration(seconds: 30));
      brut = await utf8.decodeStream(rep).timeout(const Duration(seconds: 30));
      statut = rep.statusCode;
    } catch (_) {
      throw const ErreurSms('RELAIS_INJOIGNABLE', 'le relais web ne répond pas', 'Vérifier la connexion Internet du poste mère et l\'adresse du relais ; le calcul reprend à la prochaine heure.', 503);
    }
    Map<String, Object?> j = {};
    try {
      if (brut.isNotEmpty) j = (jsonDecode(brut) as Map).cast<String, Object?>();
    } catch (_) {/* vide */}
    if (statut >= 400) throw ErreurSms('${j['code'] ?? 'ERREUR_RELAIS'}', '${j['motif'] ?? 'réponse $statut'}', '${j['geste'] ?? ''}', statut);
    return j;
  }

  static int _ms(DateTime d) => d.millisecondsSinceEpoch;

  // --- la passe : calculer, déposer, retirer -------------------------------------------------------------------------------------------------------

  /// Calcule et dépose maintenant. Rend le compte rendu (jamais un numéro, un texte ou un nom). Un refus nommé est ENREGISTRÉ (état, journal technique) puis relancé.
  Future<Map<String, Object?>> passe({bool manuel = false}) async {
    if (_enCours) throw const ErreurSms('PASSE_EN_COURS', 'un calcul des envois automatiques est déjà en cours', 'Attendre la fin du calcul en cours.', 409);
    final r = await reglage();
    if (!r.actif) {
      if (manuel) throw const ErreurSms('SMS_AUTO_DESACTIVES', 'les envois automatiques de SMS sont désactivés', 'L\'administrateur ou la Directrice Administrative les active à l\'écran « Passerelle SMS ».', 409);
      return {'ok': true, 'actif': false};
    }
    _enCours = true;
    try {
      final ctrl = smsVerifierReglage(r);
      if (ctrl != null) throw ErreurSms(ctrl.code, ctrl.motif, ctrl.geste);
      final maintenant = _horloge();
      final plan = smsPlanifier(
        maintenant: maintenant,
        reglage: r,
        consultations: await _fiches('consultations'),
        patients: await _fiches('patients'),
        deces: await _fiches('deces'),
        employes: await _fiches('employes'),
        clinique: IdentiteClinique.nomCourt,
        telephone: IdentiteClinique.telephoneRdv,
      );
      final ids = <String, EnvoiSmsPlanifie>{for (final e in plan.envois) identifiantOpaque(e.cle): e};

      final messages = [
        for (final e in ids.entries)
          {'id': e.key, 'numero': e.value.numero, 'texte': e.value.texte, 'type': e.value.type, 'heureEnvoi': _ms(e.value.heureEnvoi)}
      ];
      var planifies = 0, existants = 0;
      final refus = <String, int>{};
      for (var i = 0; i < messages.length; i += 100) {
        final lot = messages.sublist(i, i + 100 > messages.length ? messages.length : i + 100);
        final rep = await _relais('POST', '/sms/deposer', {'messages': lot});
        for (final x in (rep['messages'] as List).cast<Map>()) {
          final id = '${x['id']}';
          final e = ids[id]!;
          final etat = '${x['etat']}';
          if (etat == 'planifie') planifies++;
          if (etat == 'existant') existants++;
          if (etat == 'refuse') refus['${x['code']}'] = (refus['${x['code']}'] ?? 0) + 1;
          final local = etat == 'existant' ? '${x['etatMessage'] ?? 'planifie'}' : (etat == 'refuse' ? 'refuse' : 'planifie');
          await verrou.executer(() => base.exec('''INSERT INTO sms_depots(id,cle,type,heure,numero_masque,etat) VALUES(?,?,?,?,?,?)
              ON CONFLICT(id) DO UPDATE SET heure=excluded.heure, numero_masque=excluded.numero_masque, etat=excluded.etat''', [id, e.cle, e.type, _iso(e.heureEnvoi), smsMasquer(e.numero), local]));
        }
      }

      // Ce qui était planifié et ne l'est plus (rendez-vous annulé ou déplacé, consentement retiré, numéro corrigé) : retiré au relais. Un envoi PARTI ne se retire pas.
      final avant = await verrou.executer(() => base.select("SELECT id FROM sms_depots WHERE etat='planifie'"));
      final obsoletes = [for (final l in avant) '${l['id']}'].where((id) => !ids.containsKey(id)).toList();
      var retires = 0, partis = 0;
      for (var i = 0; i < obsoletes.length; i += 100) {
        final lot = obsoletes.sublist(i, i + 100 > obsoletes.length ? obsoletes.length : i + 100);
        final rep = await _relais('POST', '/sms/annuler', {'ids': lot});
        for (final x in (rep['messages'] as List).cast<Map>()) {
          final etat = '${x['etat']}';
          final local = etat == 'retire' ? 'retire' : (etat == 'deja_parti' ? 'parti' : 'retire');
          if (local == 'retire') retires++;
          if (local == 'parti') partis++;
          await verrou.executer(() => base.exec('UPDATE sms_depots SET etat=? WHERE id=?', [local, '${x['id']}']));
        }
      }
      final ecartes = <String, int>{};
      for (final e in plan.ecartes) {
        ecartes[e.raison] = (ecartes[e.raison] ?? 0) + 1;
      }
      final rapport = {
        'ok': true,
        'actif': true,
        'quand': _horloge().millisecondsSinceEpoch,
        'manuel': manuel,
        'calcules': plan.envois.length,
        'planifies': planifies,
        'existants': existants,
        'refusParLeRelais': refus,
        'retires': retires,
        'dejaPartis': partis,
        'ecartes': ecartes,
      };
      await verrou.executer(() async {
        await base.poserMeta('sms:dernier', jsonEncode(rapport));
        await base.poserMeta('sms:erreur', '');
      });
      evenement('info', 'sms', 'Envois automatiques : ${plan.envois.length} calculé(s), $planifies déposé(s), $existants déjà connu(s), $retires retiré(s), $partis déjà parti(s), ${plan.ecartes.length} écarté(s).');
      return rapport;
    } on ErreurSms catch (e) {
      final avant = await verrou.executer(() => base.meta('sms:erreur'));
      await verrou.executer(() => base.poserMeta('sms:erreur', jsonEncode({'quand': _horloge().millisecondsSinceEpoch, 'code': e.code, 'motif': e.motif, 'geste': e.geste})));
      // le même refus qui se répète (une passe par heure) n'inonde pas le journal technique : il est dit à son premier passage
      if (!(avant ?? '').contains('"code":"${e.code}"')) evenement('erreur', 'sms', 'Envois automatiques refusés : ${e.code}');
      rethrow;
    } finally {
      _enCours = false;
    }
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // --- ce que l'écran lit ---------------------------------------------------------------------------------------------------------------------------

  /// L'état pour l'écran : le réglage, ce que le relais dit de la passerelle (identifiants « définis » ou non, jamais leur valeur), les envois planifiés (numéro masqué), le dernier calcul.
  Future<Map<String, Object?>> etat() async {
    final r = await reglage();
    Map<String, Object?>? distant;
    Map<String, Object?>? erreurRelais;
    try {
      distant = await _relais('GET', '/sms/etat');
    } on ErreurSms catch (e) {
      erreurRelais = {'code': e.code, 'motif': e.motif, 'geste': e.geste};
    }
    final planifies = await verrou.executer(() => base.select("SELECT type, heure, numero_masque, etat FROM sms_depots WHERE etat='planifie' ORDER BY heure LIMIT 100"));
    String? lire(String? s) => s == null || s.isEmpty ? null : s;
    final dernier = lire(await verrou.executer(() => base.meta('sms:dernier')));
    final erreur = lire(await verrou.executer(() => base.meta('sms:erreur')));
    return {
      'relaisRelie': relais.isNotEmpty,
      'reglage': {
        'actif': r.actif,
        'rappelHeure': r.rappelHeure,
        'rappelJoursAvant': r.rappelJoursAvant,
        'anniversaireHeure': r.anniversaireHeure,
        'calmeDebut': r.calmeDebut,
        'calmeFin': r.calmeFin,
        'horizonJours': r.horizonJours,
        'toleranceMinutes': r.toleranceMinutes,
      },
      'passerelle': distant,
      'erreurRelais': erreurRelais,
      'planifies': [for (final p in planifies) {'type': p['type'], 'heure': p['heure'], 'numeroMasque': p['numero_masque']}],
      'dernier': dernier == null ? null : jsonDecode(dernier),
      'erreur': erreur == null ? null : jsonDecode(erreur),
    };
  }

  Future<Map<String, Object?>> tester(String numero) => _relais('POST', '/sms/tester', {'numero': numero});

  Future<List<Object?>> journal() async => ((await _relais('GET', '/sms/journal?limite=200'))['messages'] as List).cast<Object?>();
}
