import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// PLAN étape 9 : la configuration de la mère voyage jusqu'au fileul. D'abord avec des faux (règles), puis avec les TROIS pièces réelles (mère, moteur
/// fileul, magasins).
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 2, 9);
const secret = 'Clinique#Natitingou26';

Magasin mere() => Magasin({
      'utilisateurs': [
        {'id': 'USR001', 'statut': 'actif', 'identifiant': 'k.adjovi', 'nomComplet': 'ADJOVI Koffi', 'role': 'admin', 'echecs': 0}
      ],
      'actes': [
        {'id': 'ACT1', 'code': 'CS', 'libelle': 'Consultation', 'prix': 3000},
        {'id': 'ACT2', 'code': 'PS', 'libelle': 'Pansement', 'prix': 9000},
      ],
      'personnel': [
        {'id': 'PER1', 'nom': 'AGBO', 'fonction': 'infirmier', 'salaireBase': 150000, 'cnss': '123456'}
      ],
      'patients': [
        {'id': 'P1', 'nom': 'BIO'}
      ],
    });

Magasin fileul() => Magasin({'utilisateurs': <M>[], 'actes': <M>[]});

void main() {
  setUp(() => ServiceIdentifiants.parametres = AccParametresHachage.tests);
  tearDown(() => ServiceIdentifiants.parametres = AccParametresHachage.production);

  group('publication par la mère', () {
    test('seules les collections de configuration partent ; la rémunération reste sur la mère (RG-13)', () async {
      final envoye = <String, M>{};
      final p = PublicateurConfiguration(mere(), (c, f, champs) async => envoye['$c/$f'] = champs, delai: Duration.zero);
      final n = await p.pousser();
      expect(n, greaterThanOrEqualTo(4));
      expect(envoye.keys, containsAll(['actes/ACT1', 'actes/ACT2', 'utilisateurs/USR001', 'personnel/PER1']));
      expect(envoye.keys.any((k) => k.startsWith('patients/')), isFalse, reason: 'l’activité ne part pas');
      expect(envoye['personnel/PER1']!.containsKey('salaireBase'), isFalse);
      expect(envoye['personnel/PER1']!.containsKey('cnss'), isFalse);
      expect(envoye['personnel/PER1']!['fonction'], 'infirmier');
    });

    test('une fiche inchangée n’est pas republiée ; une fiche modifiée repart seule', () async {
      final m = mere();
      var envois = 0;
      final p = PublicateurConfiguration(m, (c, f, champs) async => envois++, delai: Duration.zero);
      await p.pousser();
      final premier = envois;
      expect(await p.pousser(), 0);
      expect(envois, premier);
      m.collection('actes').mettreAJour('ACT1', {'prix': 3500});
      expect(await p.pousser(), 1);
    });

    test('un échec n’est pas perdu : il est dit, puis la fiche repart au tour suivant', () async {
      var panne = true;
      final recu = <String>[];
      final p = PublicateurConfiguration(mere(), (c, f, champs) async {
        if (panne) throw StateError('mère injoignable');
        recu.add('$c/$f');
      }, delai: const Duration(hours: 1));
      await p.pousser();
      expect(p.erreur.value, contains('mère injoignable'));
      expect(recu, isEmpty);
      panne = false;
      await p.pousser();
      expect(p.erreur.value, isNull);
      expect(recu, contains('actes/ACT1'));
    });
  });

  group('application par le fileul', () {
    Future<List<PieceSync>> depuis(Map<String, List<M>> diffuse) async => [];

    ApplicateurConfiguration appl(Magasin m, Map<String, List<M>> diffuse) =>
        ApplicateurConfiguration(m, (c) async => [for (final f in diffuse[c] ?? const <M>[]) PieceSync('${f['id']}', f)]);

    test('les fiches reçues sont appliquées sans journal local, et un second tour ne change rien', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'libelle': 'Consultation', 'prix': 3000}
        ]
      });
      expect(await a.tirer(), 1);
      expect(m.collection('actes').toutes.single['libelle'], 'Consultation');
      expect(m.collection('audit').toutes, isEmpty, reason: 'la mère a déjà journalisé');
      expect(await a.tirer(), 0);
      expect(a.recues.value, 1);
    });

    test('une configuration modifiée sur la mère remplace la copie du fileul', () async {
      final m = fileul();
      final diffuse = {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ]
      };
      final a = appl(m, diffuse);
      await a.tirer();
      diffuse['actes'] = [
        {'id': 'ACT1', 'prix': 3500}
      ];
      expect(await a.tirer(), 1);
      expect(m.collection('actes').parId('ACT1')!['prix'], 3500);
    });

    test('le fileul REFUSE d’écrire la configuration, en disant pourquoi ; les comptes restent écrivables', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ],
        'utilisateurs': [
          {'id': 'USR001', 'identifiant': 'k.adjovi', 'echecs': 0}
        ]
      });
      a.demarrer(intervalle: const Duration(hours: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100)); // le premier tour part avec `demarrer`
      a.arreter();
      expect(() => m.collection('actes').mettreAJour('ACT1', {'prix': 1}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('actes').inserer({'id': 'ACT9'}), throwsA(isA<EcritureRefusee>()));
      expect(m.collection('actes').parId('ACT1')!['prix'], 3000);
      try {
        m.collection('actes').archiver('ACT1');
      } on EcritureRefusee catch (e) {
        expect(e.motif, ApplicateurConfiguration.motifGarde);
      }
      m.collection('utilisateurs').mettreAJour('USR001', {'echecs': 1});
      expect(m.collection('utilisateurs').parId('USR001')!['echecs'], 1, reason: 'le compteur d’échecs est local au poste');
    });

    test('un compte local n’est jamais écrasé ; un haché n’est remplacé que par un haché plus récent', () async {
      final m = fileul();
      m.collection('utilisateurs').inserer({'id': 'USR001', 'identifiant': 'k.adjovi', 'echecs': 3});
      m.collection('identifiants').inserer({'id': 'USR001', 'hash': 'LOCAL', 'definiLe': '2026-11-02T10:00:00.000'});
      final diffuse = {
        'utilisateurs': [
          {'id': 'USR001', 'identifiant': 'k.adjovi', 'echecs': 0}
        ],
        'identifiants': [
          {'id': 'USR001', 'hash': 'ANCIEN', 'definiLe': '2026-11-02T09:00:00.000'}
        ]
      };
      final a = appl(m, diffuse);
      await a.tirer();
      expect(m.collection('utilisateurs').parId('USR001')!['echecs'], 3);
      expect(m.collection('identifiants').parId('USR001')!['hash'], 'LOCAL', reason: 'un mot de passe changé ici ne revient pas à l’ancien');
      diffuse['identifiants'] = [
        {'id': 'USR001', 'hash': 'REINIT', 'definiLe': '2026-11-02T11:00:00.000'}
      ];
      await a.tirer();
      expect(m.collection('identifiants').parId('USR001')!['hash'], 'REINIT', reason: 'une réinitialisation faite sur la mère arrive');
    });

    test('une fiche archivée sur la mère l’est sur le fileul (RG-14)', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ]
      });
      await a.tirer();
      expect(depuis, isNotNull);
      final b = ApplicateurConfiguration(m, (c) async => [if (c == 'actes') const PieceSync('ACT1', {'id': 'ACT1', 'prix': 3000}, archive: true)]);
      await b.tirer();
      expect(m.collection('actes').archivees.single['id'], 'ACT1');
    });
  });

  test('BOUT EN BOUT : mère réelle, moteur fileul réel, deux magasins ; le compte créé sur la mère se connecte sur le fileul', () async {
    const port = 19432;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cfg'));
    await mere0.demarrer();
    final mm = mere();
    await ServiceIdentifiants.de(mm).definir('USR001', secret, par: 'test', doitChanger: false, maintenant: auj);
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Caisse');
    final mf = fileul();
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    try {
      expect(await pub.pousser(), greaterThanOrEqualTo(4));
      expect(pub.erreur.value, isNull);
      final code = await console.codeAppareil('Caisse').timeout(const Duration(seconds: 20));
      // Le fileul ne connaît pas encore la mère : l'adresse est saisie à l'écran « Rejoindre », puis le code est consommé.
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      final fin = DateTime.now().add(const Duration(seconds: 25));
      while (mf.collection('actes').toutes.length < 2 || mf.collection('identifiants').toutes.isEmpty) {
        await appl.tirer();
        if (DateTime.now().isAfter(fin)) fail('la configuration n’est pas arrivée : ${mf.collection('actes').toutes.length} actes, ${mf.collection('identifiants').toutes.length} identifiants');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(mf.collection('actes').parId('ACT2')!['prix'], 9000);
      expect(mf.collection('utilisateurs').toutes.single['identifiant'], 'k.adjovi');
      // Le haché voyage : le mot de passe défini sur la mère ouvre la session sur le fileul.
      final r = await ServiceIdentifiants.de(mf).verifier(identifiant: 'k.adjovi', motDePasse: secret, rolesArchives: const {}, libelleRole: (x) => x, maintenant: auj);
      expect(r.decision.accepte, isTrue);
      // L'activité et la rémunération ne sont pas parties.
      expect(mf.collection('patients').toutes, isEmpty);
      expect(mf.collection('personnel').toutes.single.containsKey('salaireBase'), isFalse);
    } finally {
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('un MOBILE reçoit la configuration de la clinique mais JAMAIS les hachés des mots de passe (RG-13) ; un fileul reçoit tout', () async {
    const port = 19434;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cfg2'));
    await mere0.demarrer();
    final http0 = HttpClient();
    Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
      final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
      req.headers.contentType = ContentType.json;
      entetes.forEach(req.headers.set);
      if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
      final rep = await req.close();
      return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
    }

    try {
      final mm = mere();
      await ServiceIdentifiants.de(mm).definir('USR001', secret, par: 'test', doitChanger: false, maintenant: auj);
      final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
      await pub.pousser();
      // Une opération de la famille d'origine (produits), que le mobile a le droit de lire.
      await appel('POST', '/admin/referentiel', corps: {'collection': 'produits', 'fiche': 'PRD1', 'champs': {'libelle': 'Paracétamol'}}, entetes: {'x-admin': 'secret-test'});

      Future<List<String>> collectionsRecues(String role, Map<String, Object?> extra) async {
        final code = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final uuid = 'dev-$role';
        final jetons = await appel('POST', '/appairage', corps: {'code': code, 'uuid': uuid, 'plateforme': 'test'});
        final pull = await appel('GET', '/sync/pull?depuis=0&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
        return [for (final o in (pull['ops'] as List)) '${(o as Map)['collection']}'];
      }

      final fileul = await collectionsRecues('fileul', {});
      expect(fileul, containsAll(['utilisateurs', 'identifiants', 'actes', 'personnel', 'produits']));
      final mobile = await collectionsRecues('mobile', {'profil': 'reception'});
      expect(mobile, contains('produits'), reason: 'le référentiel que ses écrans lisent lui reste visible');
      expect(mobile, containsAll(['actes', 'utilisateurs', 'personnel']), reason: 'la configuration de la clinique arrive sur le téléphone');
      expect(mobile, isNot(contains('identifiants')), reason: 'un téléphone perdu ne doit pas emporter les empreintes des mots de passe');
    } finally {
      http0.close(force: true);
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
