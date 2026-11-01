// BOUT EN BOUT de la suite du mobile contre le banc de synchronisation : visite prénatale, visite post-natale, surveillance (téléphone de la
// sage-femme) et orientation (téléphone de la réception de secours) partent en opérations, la mère les accepte DANS LEURS COLLECTIONS, et le profil
// qui n'a pas le droit d'écrire dans une collection voit son opération refusée par la mère avec un code, un motif et un geste.
//
// La mère est celle du banc en Node par défaut ; SIGH_E2E_MERE=dart prend l'exécutable Dart de packages/sync_dart/build (construire.sh).
// SIGH_E2E=0 ou l'absence de Node saute le test, en le disant.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';
import 'package:sigh_sync/sigh_sync.dart';

final _racine = () {
  var d = Directory.current;
  while (!File('${d.path}/packages/sync/banc/run.js').existsSync()) {
    if (d.parent.path == d.path) return null;
    d = d.parent;
  }
  return d.path;
}();

Future<int> _portLibre() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<Map<String, Object?>> _appel(String methode, String url, [Map<String, Object?>? corps, Map<String, String> entetes = const {}]) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(methode, Uri.parse(url));
    req.headers.contentType = ContentType.json;
    entetes.forEach(req.headers.set);
    if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
    final rep = await req.close();
    final t = await utf8.decoder.bind(rep).join();
    final j = t.isEmpty ? <String, Object?>{} : jsonDecode(t);
    return j is Map ? j.cast<String, Object?>() : {'liste': j};
  } finally {
    c.close(force: true);
  }
}

Future<void> _attendre(Future<bool> Function() cond, String quoi, {int secondes = 30}) async {
  final fin = DateTime.now().add(Duration(seconds: secondes));
  while (DateTime.now().isBefore(fin)) {
    try {
      if (await cond()) return;
    } catch (_) {/* on réessaie */}
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  fail('délai dépassé : $quoi');
}

/// Les extensions du moteur réel, réduites à ce que le service de la réception lit (la source et l'agent).
class _Extensions implements ExtensionsMobile {
  _Extensions(this.source, this.agent);
  @override
  final SourceMobile source;
  @override
  final String agent;
  @override
  Future<String?> appareil() async => null;
  @override
  Future<void> actualiser() async {}
  @override
  Future<void> reinitialiserAppairage() async {}
}

void main() {
  final saute = _racine == null
      ? 'dépôt introuvable'
      : (Platform.environment['SIGH_E2E'] == '0' ? 'SIGH_E2E=0' : (Process.runSync('node', ['--version']).exitCode != 0 ? 'Node absent' : null));
  final mereDart = Platform.environment['SIGH_E2E_MERE'] == 'dart';

  test('suite du mobile de bout en bout : CPN, CPoN, surveillance, orientation acceptées par la mère ; un profil hors de sa collection est refusé en le nommant', () async {
    final tmp = Directory.systemTemp.createTempSync('sigh-e2e-suite-');
    final procs = <Process>[];
    final mobiles = <Mobile>[];
    addTearDown(() {
      for (final p in procs) {
        p.kill(ProcessSignal.sigkill);
      }
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final banc = '$_racine/packages/sync/banc';
    final portRelais = await _portLibre(), portMere = await _portLibre();
    procs.add(await Process.start('node', ['--no-warnings', '$banc/relais.js', '--port=$portRelais', '--db=${tmp.path}/relais.sqlite', '--banc=1']));
    final argsMere = ['--port=$portMere', '--db=${tmp.path}/mere.sqlite', '--admin=admin-banc', '--relais=http://127.0.0.1:$portRelais', '--secret-relais=secret-mere'];
    if (mereDart) {
      final exe = '$_racine/packages/sync_dart/build/mere_bundle/bundle/bin/mere';
      expect(File(exe).existsSync(), isTrue, reason: 'exécutable Dart de la mère absent : lancer packages/sync_dart/construire.sh mere');
      procs.add(await Process.start(exe, argsMere));
    } else {
      procs.add(await Process.start('node', ['--no-warnings', '$banc/mere.js', ...argsMere]));
    }
    for (final p in procs) {
      p.stdout.drain<void>();
      p.stderr.drain<void>();
    }
    final mere = 'http://127.0.0.1:$portMere';
    final admin = {'x-admin': 'admin-banc'};
    await _attendre(() async => (await _appel('GET', '$mere/admin/etat', null, admin))['epoch'] != null, 'la mère répond');
    Future<Map<String, Object?>> adminPost(String chemin, Map<String, Object?> corps) => _appel('POST', '$mere$chemin', corps, admin);
    Future<int> compte(String c) async => ((await _appel('GET', '$mere/admin/compte?collection=$c', null, admin))['n'] as num).toInt();

    Future<Mobile> appairer(String nom, String profil, {String? fonction}) async {
      final m = Mobile(ConfigMobile(port: 0, relais: 'http://127.0.0.1:$portRelais', dbChemin: '${tmp.path}/$nom.sqlite', nom: nom));
      mobiles.add(m);
      final c = await adminPost('/admin/code-mobile', {'etiquette': nom, 'profil': profil, if (fonction != null) 'fonction': fonction});
      final (statut, corps) = await m.commande('POST /appairer', {'code': c['code'], 'cle': c['cle']}, const {});
      expect(statut, 200, reason: '$corps');
      return m;
    }

    Future<void> synchroniser(Mobile m, {bool Function()? jusqua}) async {
      for (var i = 0; i < 400; i++) {
        await m.cycle();
        final (_, e) = await m.commande('GET /etat', const {}, const {});
        final etat = (e! as Map).cast<String, Object?>();
        final fini = (etat['en_attente'] as num) == 0 && (jusqua == null || jusqua());
        if (fini && etat['bienvenu'] == true) return;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      fail('le mobile ne se vide pas');
    }

    // --- la réception de secours ouvre un dossier puis ORIENTE le patient ---------------------------------------------------------------------------
    final accueil = await appairer('accueil', 'reception');
    await synchroniser(accueil);
    final srcAccueil = SourceSync(accueil);
    final dossier = await srcAccueil.creer('patients', {'nom': 'HOUNKPATIN', 'prenom': 'Ida', 'ageDeclare': 22, 'origine': 'reception_secours'});
    final reception = ServiceSuite.reception(_Extensions(srcAccueil, 'OROU YO Edmond'));
    expect((await reception.dossiersOuverts()).map((d) => d.nom), ['HOUNKPATIN Ida']);
    await reception.orienter(dossier, destination: 'Maternité', degre: 'Urgent');
    await synchroniser(accueil);
    await _attendre(() async => await compte('orientations') == 1 && await compte('patients') == 1, 'la mère a reçu le dossier et l\'orientation');

    // --- le téléphone de la sage-femme : CPN, CPoN, surveillance dans son lot -------------------------------------------------------------------------------
    final tel = await appairer('sagefemme', 'soignant', fonction: 'sage_femme');
    final a = await srcAccueil.creer('patients', {'nom': 'SOUROU', 'prenom': 'Mariam', 'ageDeclare': 31});
    await synchroniser(accueil);
    await _attendre(() async => await compte('patients') == 2, 'la mère a reçu la patiente');
    final uuid = (await tel.commande('GET /etat', const {}, const {})).$2! as Map;
    await adminPost('/admin/lot', {
      'uuid': uuid['uuid'],
      'fiches': [
        {'collection': 'patients', 'id': a}
      ],
      'ttl_ms': 600000,
    });
    final src = SourceSync(tel);
    await synchroniser(tel, jusqua: () => true);
    await _attendre(() async {
      await tel.cycle();
      return (await src.liste('patients')).length == 1;
    }, 'le lot est arrivé');
    final sf = ServiceSuite.depuisSoignant(ServiceSoignant(src, session: const SessionSoignant(agent: 'Sage-femme de garde', fonction: 'sage_femme')));
    await sf.enregistrerCpn(a, {'sa': '28', 'poids': '62', 'sys': '150', 'dia': '95', 'proteinurie': '++'});
    await sf.enregistrerCpon(a, {'ta': '12/8', 't': '37', 'pb': '3200'});
    await sf.enregistrerSurveillance(a, {'heure': 'H8', 'mta': '12/8', 'bfr': '40'});
    // Le contrôle est refait au moteur du téléphone : le médecin n'écrit pas la CPN, rien ne part.
    final medecin = ServiceSuite.depuisSoignant(ServiceSoignant(src, session: const SessionSoignant(agent: 'Dr YENI', fonction: 'medecin')));
    final refusMedecin = await medecin.enregistrerCpn(a, {'sa': '28', 'poids': '62', 'sys': '120', 'dia': '80'}).then<Object?>((_) => null, onError: (Object e) => e);
    expect((refusMedecin! as RefusMobile).code, 'ECRAN_FERME_AU_PROFIL');
    // ... et si l'écran était contourné, la MÈRE refuse selon le profil du téléphone : la réception n'écrit pas dans `cpn`, le soignant pas dans `orientations`.
    await srcAccueil.creer('cpn', {'patientId': dossier, 'termeSA': 30});
    await src.creer('orientations', {'patientId': a, 'destination': 'Laboratoire'});

    await synchroniser(tel);
    await synchroniser(accueil);
    await _attendre(() async => await compte('cpn') == 1 && await compte('cpon') == 1 && await compte('surveillances') == 1, 'la mère a reçu les trois lignes de la sage-femme');
    expect(await compte('orientations'), 1, reason: 'l\'orientation du soignant est refusée');

    for (final (nom, m) in [('réception', accueil), ('sage-femme', tel)]) {
      final (_, e) = await m.commande('GET /etat', const {}, const {});
      final refus = (((e! as Map)['a_traiter']) as List).cast<Map>();
      expect(refus.length, 1, reason: '$nom : $refus');
      expect(refus.single['motif'], contains('ne couvre pas la collection'));
      expect(refus.single['geste'], 'Utiliser un poste');
    }

    final relu = (await sf.soignant!.dossier(a)).fiche;
    expect(relu['nom'], 'SOUROU');
    final cpn = (await src.liste('cpn')).single.data;
    expect(cpn['redigePar'], 'Sage-femme de garde');
    expect(cpn['aRisque'], isTrue);
    expect(cpn['detail'], '28 SA · TA 150/95 · À RISQUE');
  }, skip: saute, timeout: const Timeout(Duration(seconds: 120)));
}
