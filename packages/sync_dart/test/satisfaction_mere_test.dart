// LA SATISFACTION EN LIGNE DE LA MÈRE (lot SAT, ADR-0009), contre le VRAI relais Laravel (apps/web, serveur PHP intégré, base SQLite jetable) : désactivée par défaut, publication de la clé
// publique et des liens anonymes (jamais le jeton), réponse scellée comme le fait le navigateur, relevé, ouverture, jugement (refus nommés), écriture `reponsesEnquetes` (famille B,
// `REPW-<id>`), doublon sans effet, opacité du relais, jamais vers un téléphone. L'enveloppe d'un VRAI Chrome (page servie par le relais) est ouverte par `satisfaction_navigateur_test`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/satisfaction_sceau.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

const secret = 'secret-mere';
final web = '${Directory.current.path}/../../apps/web';
final amorce = '$web/tests/outils/amorce_arbre.php';
final routeur = '$web/tests/outils/routeur_arbre.php';

List<int> cleDeTest() => List<int>.generate(32, (i) => (i * 11 + 5) & 0xff);

class RelaisLaravel {
  RelaisLaravel(this.dir, this.proc, this.port, this.db);
  final Directory dir;
  final Process proc;
  final int port;
  final String db;
  String get base => 'http://127.0.0.1:$port';
  Future<void> arreter() async {
    proc.kill(ProcessSignal.sigkill);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

bool phpDisponible() {
  try {
    return File(amorce).existsSync() && File('$web/vendor/autoload.php').existsSync() && Process.runSync('php', ['-v']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<RelaisLaravel> lancerRelais() async {
  final dir = Directory.systemTemp.createTempSync('sigh-sat-relais-');
  final db = '${dir.path}/relais.sqlite';
  File(db).createSync();
  final port = 9802 + Random().nextInt(7);
  final env = {
    ...Platform.environment,
    'APP_KEY': 'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
    'APP_ENV': 'local',
    'APP_DEBUG': 'false',
    'DB_CONNECTION': 'sqlite',
    'DB_DATABASE': db,
    'SESSION_DRIVER': 'array',
    'CACHE_STORE': 'array',
    'QUEUE_CONNECTION': 'sync',
    'LOG_CHANNEL': 'stderr',
    'RELAIS_SECRET_MERE': secret,
    'RELAIS_BANC': 'false',
    'RELAIS_SAUVEGARDES_DIR': '${dir.path}/sauv',
  };
  final m = Process.runSync('php', ['-d', 'auto_prepend_file=$amorce', 'artisan', 'migrate', '--force', '--no-interaction'], workingDirectory: web, environment: env);
  if (m.exitCode != 0) throw StateError('migration impossible : ${m.stderr}${m.stdout}');
  final proc = await Process.start('php', ['-S', '127.0.0.1:$port', '-t', '.', routeur], workingDirectory: '$web/public', environment: env);
  final r = RelaisLaravel(dir, proc, port, db);
  for (var i = 0; i < 80; i++) {
    try {
      final c = HttpClient();
      final rep = await (await c.getUrl(Uri.parse('${r.base}/up'))).close();
      await rep.drain<void>();
      c.close();
      return r;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
  await r.arreter();
  throw StateError('relais Laravel injoignable');
}

Future<(int, String)> http(String methode, String url, {Object? corps, Map<String, String> entetes = const {}}) async {
  final c = HttpClient();
  final req = await c.openUrl(methode, Uri.parse(url));
  entetes.forEach(req.headers.set);
  if (corps != null) {
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(corps)));
  }
  final rep = await req.close();
  final t = await utf8.decoder.bind(rep).join();
  c.close();
  return (rep.statusCode, t);
}

Future<void> regler(Mere m, Map<String, Object?> valeurs) async {
  for (final e in valeurs.entries) {
    final d = definitionDeParametre(e.key)!;
    await m.ecrire(parCollectionParametres, '${e.key}@2020-01-01@1', Fiche({
      'cle': e.key, 'famille': d.famille, 'type': d.type.name, 'valeur': e.value, 'defaut': d.defaut, 'dateEffet': '2020-01-01', 'version': 1, 'auteur': 'admin', 'creeLe': '2026-11-16T08:00:00Z', 'mobile': false, 'sensible': false,
    }, {}, false));
  }
}

const jeton = 'jetonsatisfaction0123456a';
const idRep = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

void main() {
  final saute = phpDisponible() ? null : 'php ou apps/web/vendor absent';
  late Mere m;
  late RelaisLaravel relais;
  late Directory tmp;
  late List<int> pub;

  setUp(() async {
    relais = await lancerRelais();
    tmp = Directory.systemTemp.createTempSync('sigh-sat-mere-');
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: '${tmp.path}/mere.sqlite', relais: relais.base, secretRelais: secret, dossierFichiers: '${tmp.path}/f', dossierSauvegardes: '${tmp.path}/s', cleBase64: base64.encode(cleDeTest())));
    pub = await clePubliqueSatisfaction(cleDeTest());
    await m.ecrire('enquetes', 'ENQ0001', Fiche({
      'id': 'ENQ0001', 'statut': 'actif', 'titre': 'Satisfaction des patients', 'creeLe': '2026-08-01',
      'questions': [
        {'code': 'Q_A', 'type': 'note', 'libelle': 'Accueil'},
        {'code': 'Q_R', 'type': 'choix', 'libelle': 'Recommanderiez-vous ?', 'options': ['Oui', 'Non']},
        {'code': 'Q_T', 'type': 'texte', 'libelle': 'Avis'},
      ],
    }, {}, false));
    await m.ecrire('jetonsEnquete', 'JET1', Fiche({'id': 'JET1', 'jeton': jeton, 'enqueteId': 'ENQ0001', 'enLigne': true, 'point': 'laboratoire', 'creeLe': '2026-08-02', 'expireLe': '2999-12-31', 'revoqueLe': null, 'anonyme': true}, {}, false));
  });
  tearDown(() async {
    m.satisfaction.arreter();
    await relais.arreter();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, Object?> clair([Map<String, Object?> plus = const {}, String id = idRep]) => {
        'id': id, 'enquete': 'ENQ0001', 'version': 'V1', 'point': 'laboratoire', 'langue': 'fr',
        'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_T': 'Très bon accueil au laboratoire'}, ...plus,
      };

  Future<int> deposer(Map<String, Object?> donnees, String id, {List<int>? cle}) async {
    final env = await sceller(donnees, id, cle ?? pub);
    final (st, _) = await http('POST', '${relais.base}/s/$jeton', corps: env);
    return st;
  }

  Future<List<Map<String, Object?>>> reponses() async => [
        for (final r in await m.base.select("SELECT data FROM fiches WHERE collection='reponsesEnquetes'")) (jsonDecode(r['data'] as String) as Map).cast<String, Object?>()
      ];

  group('désactivée par défaut', () {
    test('sans réglage : aucune publication, aucune réponse ; le relais ne connaît aucun lien', () async {
      expect((await m.satisfaction.reglage()).actif, isFalse);
      expect((await m.satisfaction.passe())['etat'], 'desactive');
      final (st, _) = await http('GET', '${relais.base}/s/$jeton');
      expect(st, 404);
    }, skip: saute);
  });

  group('le cycle complet contre le relais Laravel', () {
    setUp(() => regler(m, {qualCleEnLigne: 'oui'}));

    test('la mère publie la clé publique et le lien (jamais le jeton) ; la page publique s’ouvre sans cookie', () async {
      final r = await m.satisfaction.passe();
      expect(r['etat'], 'ok');
      expect(r['publies'], 1);
      final (st, html) = await http('GET', '${relais.base}/s/$jeton');
      expect(st, 200);
      expect(html, contains('Satisfaction des patients'));
      expect(html, contains('Laboratoire'));
      final bd = sql.sqlite3.open(relais.db, mode: sql.OpenMode.readOnly);
      try {
        final liens = bd.select('SELECT * FROM relais_sat_liens').map((x) => x.toString()).join();
        expect(liens, isNot(contains(jeton)), reason: 'le relais ne connaît le jeton que par son empreinte');
        expect(liens, contains(qualEmpreinteJeton(jeton)));
        expect(bd.select('SELECT cle FROM relais_sat_cle').first['cle'], base64.encode(pub));
      } finally {
        bd.dispose();
      }
    }, skip: saute);

    test('une réponse scellée dans le navigateur : relevée, ouverte, jugée, écrite REPW-<id> en famille B ; le doublon est sans effet', () async {
      await m.satisfaction.passe();
      expect(await deposer(clair(), idRep), 200);
      final r = await m.satisfaction.passe();
      expect(r['acceptees'], 1);
      final rep = await reponses();
      expect(rep.length, 1);
      expect(rep.first['enqueteId'], 'ENQ0001');
      expect(rep.first['canal'], 'Lien public');
      expect(rep.first['point'], 'laboratoire');
      expect(rep.first['version'], 'V1');
      expect((rep.first['reponses'] as Map)['Q_A'], 5);
      expect(rep.first['saisiPar'], contains('anonyme'));
      final ligne = (await m.base.select("SELECT id FROM fiches WHERE collection='reponsesEnquetes'")).first['id'];
      expect(ligne, 'REPW-$idRep');
      expect((await m.base.select("SELECT famille FROM operations WHERE collection='reponsesEnquetes'")).first['famille'], 'B');
      // le même identifiant déposé de nouveau (réseau instable) : une seule réponse
      expect(await deposer(clair(), idRep), 200);
      await m.satisfaction.passe();
      expect((await reponses()).length, 1);
      // une passe de plus ne relit rien (curseur)
      final r3 = await m.satisfaction.passe();
      expect(r3['acceptees'], 0);
    }, skip: saute);

    test('les refus sont nommés, comptés, jamais écrits : champ d’identité, question inconnue, enveloppe scellée pour une autre clé', () async {
      await m.satisfaction.passe();
      expect(await deposer(clair({'nom': 'Awa K.'}, 'b1b2c3d4e5f60718293a4b5c6d7e8f90'), 'b1b2c3d4e5f60718293a4b5c6d7e8f90'), 200);
      expect(await deposer(clair({'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_Z': 1}}, 'c1b2c3d4e5f60718293a4b5c6d7e8f90'), 'c1b2c3d4e5f60718293a4b5c6d7e8f90'), 200);
      final autre = await clePubliqueSatisfaction(List<int>.generate(32, (i) => i));
      expect(await deposer(clair({}, 'd1b2c3d4e5f60718293a4b5c6d7e8f90'), 'd1b2c3d4e5f60718293a4b5c6d7e8f90', cle: autre), 200);
      expect(await deposer(clair(), idRep), 200);
      final r = await m.satisfaction.passe();
      expect(r['refusees'], 3);
      expect(r['acceptees'], 1);
      final etat = await m.satisfaction.etat();
      expect(etat['refus'], {'champ_identite': 1, 'question_inconnue': 1, 'enveloppe_illisible': 1});
      expect((await reponses()).length, 1, reason: 'seule la réponse valide est écrite');
      final journal = [for (final x in await m.base.select("SELECT message FROM evenements WHERE source='satisfaction'")) '${x['message']}'].join('|');
      expect(journal, contains('champ_identite'));
      expect(journal, isNot(contains('Awa')), reason: 'le journal ne porte jamais un contenu');
      expect(journal, isNot(contains('laboratoire')));
    }, skip: saute);

    test('OPACITÉ : la base du relais ne laisse lire ni la réponse ni le commentaire, et la clé privée n’y est jamais', () async {
      await m.satisfaction.passe();
      for (var i = 0; i < 6; i++) {
        final id = '${i}1b2c3d4e5f60718293a4b5c6d7e8f90';
        // adresses différentes : la limite de débit est par adresse
        final env = await sceller(clair({}, id), id, pub);
        final c = HttpClient();
        final req = await c.postUrl(Uri.parse('${relais.base}/s/$jeton'));
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(env)));
        await (await req.close()).drain<void>();
        c.close();
      }
      final bd = sql.sqlite3.open(relais.db, mode: sql.OpenMode.readOnly);
      try {
        final tout = bd.select('SELECT * FROM relais_sat_reponses').map((x) => x.toString()).join('|');
        for (final mot in ['laboratoire', 'accueil', 'Très bon', 'Q_A', 'reponses', 'enquete']) {
          expect(tout, isNot(contains(mot)));
        }
        final cts = [for (final x in bd.select('SELECT bloc FROM relais_sat_reponses')) base64.decode((jsonDecode(x['bloc'] as String) as Map)['ct'] as String)];
        expect(cts, isNotEmpty);
        final h = cts.map((b) {
          final f = List<int>.filled(256, 0);
          for (final o in b) {
            f[o]++;
          }
          return -f.where((n) => n > 0).fold<double>(0, (a, n) => a + (n / b.length) * (log(n / b.length) / ln2));
        }).reduce((a, b) => a + b) / cts.length;
        expect(h, greaterThan(7.6), reason: 'entropie moyenne (bits par octet) d’un texte chiffré de 1 Kio');
        expect(cts.every((b) => const [1040, 2064, 4112, 8208].contains(b.length)), isTrue, reason: 'rembourrage à 1, 2, 4 ou 8 Kio');
      } finally {
        bd.dispose();
      }
      final privee = (await (await paireSatisfaction(cleDeTest())).extractPrivateKeyBytes());
      final baseRelais = File(relais.db).readAsBytesSync();
      expect(_contient(baseRelais, privee), isFalse);
      expect(_contient(baseRelais, cleDeTest()), isFalse);
    }, skip: saute);

    test('un lien révoqué à la mère : le relais ne le sert plus après la passe suivante, les réponses déjà reçues restent', () async {
      await m.satisfaction.passe();
      expect(await deposer(clair(), idRep), 200);
      final f = (await m.lire('jetonsEnquete', 'JET1'))!;
      await m.ecrire('jetonsEnquete', 'JET1', Fiche({...f.data, 'revoqueLe': '2026-08-10'}, f.fieldseq, false));
      await m.satisfaction.passe();
      expect((await http('GET', '${relais.base}/s/$jeton')).$1, 404);
      expect((await reponses()).length, 0, reason: 'revoqué le 10/08 : une réponse reçue après est refusée (lien_revoque)');
      expect((await m.satisfaction.etat())['refus'], {'lien_revoque': 1});
    }, skip: saute);

    test('un appareil appairé est refusé en le nommant (403 satisfaction_reservee_mere) ; réponses et liens ne vont jamais vers un téléphone', () async {
      final (st, corps) = await http('GET', '${relais.base}/satisfaction/releve', entetes: {'Authorization': 'Bearer abc.def'});
      expect(st, 403);
      expect(jsonDecode(corps)['code'], 'satisfaction_reservee_mere');
      expect(qualCollectionsJamaisMobile, {'reponsesEnquetes', 'jetonsEnquete'});
      expect(familleDeBase['reponsesEnquetes'], 'B');
      expect(familleDeBase['jetonsEnquete'], 'A');
    }, skip: saute);
  });
}

bool _contient(List<int> foin, List<int> aiguille) {
  outer:
  for (var i = 0; i + aiguille.length <= foin.length; i++) {
    for (var j = 0; j < aiguille.length; j++) {
      if (foin[i + j] != aiguille[j]) continue outer;
    }
    return true;
  }
  return false;
}
