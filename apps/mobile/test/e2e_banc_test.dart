// BOUT EN BOUT contre le banc de synchronisation : le VRAI service soignant de l'application, sur le VRAI moteur `Mobile` de sigh_sync, parle à un
// relais et à une mère qui sont de vrais processus (packages/sync/banc). Ce que le test prouve : le lot arrive chiffré par le relais, l'agenda et le
// dossier se lisent dans ce lot, les gestes d'écriture partent en opérations et sont accusés, un refus de la mère revient avec son code, son motif
// et son geste, et un lot expiré refuse l'écriture puis s'efface du téléphone.
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

void main() {
  final saute = _racine == null
      ? 'dépôt introuvable'
      : (Platform.environment['SIGH_E2E'] == '0' ? 'SIGH_E2E=0' : (Process.runSync('node', ['--version']).exitCode != 0 ? 'Node absent' : null));
  final mereDart = Platform.environment['SIGH_E2E_MERE'] == 'dart';

  test('soignant de bout en bout : lot, agenda, dossier, constantes, note, prescription, refus nommé de la mère, lot expiré', () async {
    final tmp = Directory.systemTemp.createTempSync('sigh-e2e-');
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
    procs.add(await Process.start('node', ['--no-warnings', '$banc/relais.js', '--port=$portRelais', '--db=${tmp.path}/relais.sqlite', '--banc=1'], mode: ProcessStartMode.normal));
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
      // E1600 : le profil et la FONCTION sont portés par le code émis par la console de la mère ; le téléphone ne les déclare pas.
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

    // --- la clinique : un accueil de secours (mobile, profil réception) ouvre deux dossiers, un rendez-vous du jour et une constante ------------
    final accueil = await appairer('accueil', 'reception');
    await synchroniser(accueil);
    final aujourdhui = DateTime.now();
    String jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    Future<String> ecrireAccueil(String collection, Map<String, Object?> champs) async {
      final (_, r) = await accueil.commande('POST /ecrire', {'type': 'creer', 'collection': collection, 'champs': champs}, const {});
      return '${(r! as Map)['fiche']}';
    }

    final a = await ecrireAccueil('patients', {'nom': 'DOSSOU', 'prenom': 'Aline', 'quartier': 'Kouba', 'age': 67, 'assureur': 'NSIA', 'carteExpiration': '${aujourdhui.year + 1}-12-31', 'allergies': ['Pénicilline']});
    final b = await ecrireAccueil('patients', {'nom': 'HORS', 'prenom': 'Tournée'});
    final rdv = await ecrireAccueil('rendezvous', {'patientId': a, 'date': '${jour(aujourdhui)}T09:30', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'Suivi HTA'});
    final releve = await ecrireAccueil('constantes', {'patientId': a, 'dateHeure': '${jour(aujourdhui)}T08:00', 'temperature': 38.6, 'pouls': 96});
    await synchroniser(accueil);
    await _attendre(() async => await compte('patients') == 2 && await compte('rendezvous') == 1 && await compte('constantes') == 1, 'la mère a reçu les quatre fiches');

    // --- le soignant : appairage, lot de la tournée (le dossier B n'y est pas) ------------------------------------------------------------------
    // Le catalogue des produits de la clinique : il part avec le lot d'un soignant habilité à prescrire (E1559).
    await adminPost('/admin/referentiel', {'collection': 'produits', 'fiche': 'PRD0001', 'champs': {'designation': 'PARACETAMOL 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'prixAchat': 500, 'stockDetail': 40}});
    final tel = await appairer('medecin', 'soignant', fonction: 'medecin');
    // La mère n'affecte le catalogue qu'à un appareil dont elle CONNAÎT la fonction : on attend sa bienvenue (le banc de SYNC-R28 fait de même).
    await synchroniser(tel);
    final uuid = (await tel.commande('GET /etat', const {}, const {})).$2! as Map;
    await adminPost('/admin/lot', {
      'uuid': uuid['uuid'],
      'fiches': [
        {'collection': 'patients', 'id': a},
        {'collection': 'rendezvous', 'id': rdv},
        {'collection': 'constantes', 'id': releve},
      ],
      'ttl_ms': 600000,
    });
    final src = SourceSync(tel);
    ServiceSoignant service(String fonction, {String agent = 'Dr YENI M’PO Florent'}) => ServiceSoignant(src, session: SessionSoignant(agent: agent, fonction: fonction));
    await synchroniser(tel, jusqua: () => true);
    await _attendre(() async {
      await tel.cycle();
      return (await src.liste('patients')).length == 1 && (await src.liste('rendezvous')).length == 1 && (await src.liste('produits')).length == 1;
    }, 'le lot est arrivé');
    final medecin = service('medecin');
    expect((await medecin.produits()).map((p) => '${p.designation} ${p.stock}'), ['PARACETAMOL 500 MG 40'], reason: 'le catalogue du lot : le médicament se choisit, il ne se tape plus');
    expect((await tel.commande('GET /etat', const {}, const {})).$2! as Map, containsPair('fonction', 'medecin'), reason: 'la fonction est celle du code, reçue de la mère');
    expect((await medecin.patients()).map((p) => p.nom), ['DOSSOU Aline'], reason: 'le dossier hors tournée ne descend pas ($b)');

    // --- lecture : l'agenda du jour et le dossier se lisent dans le lot --------------------------------------------------------------------------
    final agenda = await medecin.agenda();
    expect(agenda.duJour.map((l) => '${l.heure} ${l.patient} ${l.motif}'), ['09h30 DOSSOU Aline Suivi HTA']);
    final dossier = await medecin.dossier(a);
    expect(dossier.resume.couverture, MobCouverture.carteValide);
    expect(dossier.resume.allergies, ['Pénicilline']);
    expect(dossier.resume.horsBornes, ['température']);
    expect(dossier.resume.code, startsWith('CNT/'));

    // --- écriture : un geste, une opération, nommée à l'agent ------------------------------------------------------------------------------------
    await medecin.enregistrerConstantes(a, {'temperature': '38,2', 'sys': '130', 'dia': '85'});
    final ordonnanceSansNote = await medecin.prescrireMedicament(a, {'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp x 3/j', 'duree': '5'}).then<Object?>((_) => null, onError: (Object e) => e);
    expect(ordonnanceSansNote, isA<RefusMobile>());
    expect((ordonnanceSansNote! as RefusMobile).code, 'SANS_NOTE');
    await medecin.enregistrerNote(a, {'motif': 'Suivi HTA', 'diagnostic': 'Hypertension artérielle', 'orientation': 'domicile'});
    await medecin.prescrireMedicament(a, {'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp x 3/j', 'duree': '5'});
    await medecin.prescrireAnalyses(a, ['NFS'], 'Non urgent');
    // Un infirmier ne prescrit pas : refus AU MOTEUR du téléphone, rien n'est écrit.
    final avant = (await src.liste('prescriptions')).length;
    final inf = await service('infirmier', agent: 'Infirmière').prescrireMedicament(a, {'med': 'PRD0001', 'quantite': '1', 'poso': 'y', 'duree': '1'}).then<Object?>((_) => null, onError: (Object e) => e);
    expect((inf! as RefusMobile).code, 'FONCTION_NON_HABILITEE');
    expect((await src.liste('prescriptions')).length, avant);
    // ... et si l'écran était contourné en déclarant une AUTRE fonction, la MÈRE refuse en la nommant : la fonction est celle de l'appairage (E1600).
    await src.creer('prescriptions', {'nature': 'medicament', 'patientId': a, 'fonction': 'infirmier', 'prescripteur': 'Infirmière', 'emise': true, 'lignes': <Object?>[]});

    await synchroniser(tel);
    await _attendre(() async => await compte('notes') == 1 && await compte('constantes') == 2 && await compte('prescriptions') == 2, 'la mère a reçu note, constante et deux prescriptions');
    final (_, e) = await tel.commande('GET /etat', const {}, const {});
    final etat = (e! as Map).cast<String, Object?>();
    final refus = (etat['a_traiter'] as List).cast<Map>();
    expect(refus.length, 1, reason: 'seule la prescription contournée est refusée : $refus');
    expect(refus.single['code'], 'fonction_falsifiee');
    expect(refus.single['motif'], allOf(contains('infirmier'), contains('medecin')));
    expect(refus.single['geste'], contains('nouveau code d’appairage'));
    // La fiche refusée n'a pas été rejouée telle quelle : la mère ne tient que les deux ordonnances du médecin.
    expect(await compte('prescriptions'), 2);

    // Le dossier relu après synchronisation porte la note et les prescriptions du médecin.
    final relu = await medecin.dossier(a);
    expect(relu.resume.notes.length, 1);
    expect(relu.resume.notes.single['redigePar'], 'Dr YENI M’PO Florent');
    expect(relu.resume.prescriptions.length, greaterThanOrEqualTo(2));

    // --- lot expiré : l'écriture est refusée en le disant, puis les dossiers s'effacent du téléphone ----------------------------------------------
    await adminPost('/admin/lot', {
      'uuid': uuid['uuid'],
      'fiches': [
        {'collection': 'patients', 'id': a},
        {'collection': 'rendezvous', 'id': rdv},
      ],
      'ttl_ms': 1,
    });
    await _attendre(() async {
      await tel.cycle();
      return mobLotExpire(await src.lotExpire(), DateTime.now());
    }, 'le lot de 1 ms est reçu et expiré');
    final expire = await medecin.enregistrerConstantes(a, {'temperature': '37'}).then<Object?>((_) => null, onError: (Object e) => e);
    expect((expire! as RefusMobile).code, 'LOT_EXPIRE');
    expect((expire as RefusMobile).geste, 'Se connecter pour recevoir le lot du jour');
    expect(await compte('constantes'), 2, reason: 'rien n\'est parti');
    await _attendre(() async {
      await tel.cycle();
      return (await src.liste('patients')).isEmpty;
    }, 'les dossiers du lot expiré s\'effacent du téléphone');
    final apres = await medecin.dossier(a).then<Object?>((_) => null, onError: (Object e) => e);
    expect((apres! as RefusMobile).code, 'PATIENT_HORS_LOT');
  }, skip: saute, timeout: const Timeout(Duration(seconds: 120)));
}
