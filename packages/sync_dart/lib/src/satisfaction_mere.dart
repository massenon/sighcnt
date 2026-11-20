/// LA SATISFACTION EN LIGNE DE LA MÈRE (lot SAT, ADR-0009) : une passe chaque minute (désactivée par défaut : réglage `satisfaction.enLigne`). Elle PUBLIE au relais la clé publique de la
/// clinique et les liens anonymes (avec leur questionnaire), RELÈVE les enveloppes, les OUVRE (clé dérivée de la clé de la clinique, jamais envoyée), les FAIT JUGER par le domaine
/// (`qualJugerReponseEnLigne` : 15 refus nommés dont tout champ d'identité) et ÉCRIT `reponsesEnquetes` (famille B, identité `REPW-<id>`), que les postes reçoivent par le pont.
///
/// Le journal technique ne porte JAMAIS le contenu d'une réponse ni un commentaire : des codes de refus, des compteurs (RG-12 ; aucune donnée de santé hors de la clinique).
/// Un refus n'arrête pas la passe : le curseur avance, l'enveloppe refusée est comptée et dite.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'depot.dart';
import 'satisfaction_sceau.dart';

class SatisfactionMere {
  SatisfactionMere({
    required this.base,
    required this.verrou,
    required this.cle,
    required this.relais,
    required this.secretRelais,
    required this.evenement,
    required this.ecrireReponse,
    DateTime Function()? horloge,
    this.intervalle = const Duration(minutes: 1),
  }) : _horloge = horloge ?? DateTime.now;

  final Depot base;
  final Verrou verrou;
  final List<int> Function() cle;
  final String relais;
  final String secretRelais;
  final void Function(String niveau, String source, String message) evenement;

  /// Écrit une fiche `reponsesEnquetes` par le chemin de la mère (journal, famille B) ; rend le statut (`acceptee` ou un refus).
  final Future<Map<String, Object?>> Function(String id, Map<String, Object?> champs) ecrireReponse;
  final DateTime Function() _horloge;
  final Duration intervalle;
  Timer? _minuterie;
  bool _enCours = false;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  void demarrer() {
    _minuterie ??= Timer.periodic(intervalle, (_) => unawaited(passe()));
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  Future<List<Map<String, Object?>>> _fiches(String collection) async {
    final lignes = await verrou.executer(() => base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [collection]));
    return [for (final r in lignes) (jsonDecode(r['data'] as String) as Map).cast<String, Object?>()];
  }

  /// Les réglages en vigueur aujourd'hui (valeur de la base, à défaut le défaut semé).
  Future<({bool actif, List<({String code, String libelle})> points})> reglage() async {
    final versions = <Parametre>[];
    for (final d in await _fiches(parCollectionParametres)) {
      try {
        final p = Parametre.fromJson(d);
        if (p.cle.startsWith('satisfaction.')) versions.add(p);
      } catch (_) {/* une fiche illisible n'est pas une version */}
    }
    final jour = parametreDateIso(_horloge());
    Object? v(String cle) {
      final res = Parametres.resoudre(cle, versions.where((x) => x.cle == cle).toList(), jour, definition: definitionDeParametre(cle));
      return res.ok ? res.valeur!.valeur : definitionDeParametre(cle)?.defaut;
    }

    return (actif: v(qualCleEnLigne) == 'oui', points: qualPointsDepuisParametre(v(qualClePointsCollecte)));
  }

  Future<Map<String, Object?>> _rel(String methode, String chemin, [Map<String, Object?>? corps]) async {
    final req = await _http.openUrl(methode, Uri.parse('$relais$chemin')).timeout(const Duration(seconds: 10));
    req.headers.set('x-mere', secretRelais);
    if (corps != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(corps)));
    }
    final rep = await req.close().timeout(const Duration(seconds: 10));
    final texte = await utf8.decoder.bind(rep).join().timeout(const Duration(seconds: 10));
    final j = texte.isEmpty ? <String, Object?>{} : (jsonDecode(texte) as Map).cast<String, Object?>();
    if (rep.statusCode >= 400) throw Err(rep.statusCode, '${j['code'] ?? 'http_${rep.statusCode}'}', '${j['motif'] ?? ''}');
    return j;
  }

  Future<Map<String, Object?>> _lireEtat() async {
    final s = await verrou.executer(() => base.meta('satisfaction:etat'));
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _poserEtat(Map<String, Object?> e) => verrou.executer(() => base.poserMeta('satisfaction:etat', jsonEncode(e)));

  /// L'état pour l'écran et les tests : réglage, curseur, compteurs, refus par code. Jamais un contenu.
  Future<Map<String, Object?>> etat() async {
    final r = await reglage();
    return {'actif': r.actif, 'relaisRelie': relais.isNotEmpty, ...await _lireEtat()};
  }

  /// Une passe : publier, relever, ouvrir, juger, écrire. Rend ce qu'elle a fait.
  Future<Map<String, Object?>> passe() async {
    if (_enCours) return {'etat': 'en_cours'};
    _enCours = true;
    try {
      final r = await reglage();
      if (!r.actif) return {'etat': 'desactive'};
      if (relais.isEmpty) return {'etat': 'relais_non_relie'};
      final etat = await _lireEtat();
      final paire = await paireSatisfaction(cle());
      final pub = (await paire.extractPublicKey()).bytes;
      final jour = parametreDateIso(_horloge());
      final enquetes = await _fiches('enquetes'), jetons = await _fiches('jetonsEnquete');
      final p = qualLiensAPublier(jetons: jetons, enquetes: enquetes, aLaDate: jour, points: r.points);
      final charge = {'cle': base64.encode(pub), 'liens': p.liens};
      final digest = sha256Octets(utf8.encode(jsonEncode(charge)));
      final maintenant = _horloge().millisecondsSinceEpoch;
      var publies = (etat['liensPublies'] as num?)?.toInt() ?? 0;
      if (digest != etat['digest'] || maintenant - ((etat['publieLe'] as num?)?.toInt() ?? 0) > 10 * 60 * 1000) {
        await _rel('POST', '/satisfaction/publier', charge);
        etat['digest'] = digest;
        etat['publieLe'] = maintenant;
        publies = p.liens.length;
        if (p.ignores > 0) evenement('alerte', 'satisfaction', '${p.ignores} lien(s) de collecte dépassent la limite de $qualLiensMax : révoquer des liens');
      }
      etat['liensPublies'] = publies;
      etat['liensIgnores'] = p.ignores;
      var curseur = (etat['curseur'] as num?)?.toInt() ?? 0;
      var acceptees = 0, doublons = 0, refusees = 0;
      final refus = ((etat['refus'] as Map?) ?? {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
      for (var tour = 0; tour < 50; tour++) {
        final rel = await _rel('GET', '/satisfaction/releve?apres=$curseur&limite=100');
        final lot = [for (final x in (rel['reponses'] as List? ?? const [])) (x as Map).cast<String, Object?>()];
        if (lot.isEmpty) break;
        for (final e in lot) {
          final id = '${e['id']}';
          Object? clair;
          String? code;
          try {
            clair = await ouvrirEnveloppe((e['bloc'] as Map), id, paire);
          } on EnveloppeIllisible {
            code = 'enveloppe_illisible';
          }
          if (code == null) {
            // Les liens et les enquêtes sont ceux lus au début de la passe (une passe dure moins d'une minute).
            final j = qualJugerReponseEnLigne(clair: clair, idRelais: id, empreinteLien: '${e['lien']}', recuMs: (e['recu'] as num).toInt(), jetons: jetons, enquetes: enquetes, points: r.points);
            if (j.refus != null) {
              code = j.refus!.code;
            } else {
              final fiche = j.reponse!;
              final existe = await verrou.executer(() => base.select('SELECT 1 FROM fiches WHERE collection=? AND id=?', ['reponsesEnquetes', fiche['id']]));
              if (existe.isNotEmpty) {
                doublons++;
              } else {
                final st = await ecrireReponse('${fiche['id']}', {...fiche}..remove('id'));
                if (st['statut'] == 'acceptee') {
                  acceptees++;
                } else {
                  code = '${st['code'] ?? 'ecriture_refusee'}';
                }
              }
            }
          }
          if (code != null) {
            refusees++;
            refus[code] = (refus[code] ?? 0) + 1;
            evenement('warn', 'satisfaction', 'Enveloppe refusée : $code');
          }
          curseur = (e['seq'] as num).toInt();
          etat['curseur'] = curseur;
        }
        if ((rel['reste'] as num? ?? 0) == 0) break;
      }
      etat['refus'] = refus;
      etat['recues'] = ((etat['recues'] as num?)?.toInt() ?? 0) + acceptees + refusees + doublons;
      etat['acceptees'] = ((etat['acceptees'] as num?)?.toInt() ?? 0) + acceptees;
      etat['dernierePasse'] = maintenant;
      await _poserEtat(etat);
      return {'etat': 'ok', 'publies': publies, 'acceptees': acceptees, 'doublons': doublons, 'refusees': refusees, 'curseur': curseur};
    } on Err catch (e) {
      evenement('warn', 'satisfaction', 'Passe interrompue : ${e.code}');
      return {'etat': 'erreur', 'code': e.code};
    } catch (e) {
      evenement('warn', 'satisfaction', 'Passe interrompue : ${e.runtimeType}');
      return {'etat': 'erreur', 'code': '${e.runtimeType}'};
    } finally {
      _enCours = false;
    }
  }
}
