import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_fichiers.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LES FICHIERS NUMÉRISÉS PAR LA SYNCHRONISATION, CONTRE LA VRAIE MÈRE (lot D5, EF-SYNC-18) : deux ou trois vrais fileuls (moteur de synchronisation, pont d'activité, stockage sur
/// disque, service de transfert) et la vraie mère Dart (routes `/fichiers/*`, stockage chiffré au repos), arrêtée puis relancée sur sa base.
///  1. métadonnées d'abord (la fiche arrive avant le binaire : « en cours de transfert », jamais un écran vide), puis le binaire par morceaux, l'empreinte de l'ensemble vérifiée ;
///  2. REPRISE : une coupure au milieu, une mère redémarrée, un transfert qui repart du dernier morceau vérifié sans renvoyer ce que la mère a ;
///  3. un morceau altéré en route (dans les deux sens) est refusé et renvoyé ;
///  4. le même fichier déposé de deux côtés : une copie, une fiche de registre, un compteur de références déduit (jamais doublé) ;
///  5. les droits de zone : un poste dont le rôle ne lit pas la zone ne reçoit PAS le binaire, et la mère le lui refuserait aussi (RG-13) ;
///  6. JAMAIS vers un téléphone : ni le binaire, ni les fiches, ni le registre ;
///  7. un poste sans mère : tout reste local, sans erreur ; une mère coupée : le fichier reste « non disponible hors ligne ».
typedef M = Map<String, Object?>;
const fixtures = 'test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();
final donnees = DonneesNavigation.depuisDossier();
Droit droit(String role, String ecran) => donnees.matrice.droit(role, ecran);

Magasin nouveauMagasin() => Magasin({
      'courriers': const <M>[],
      'documentsPatient': const <M>[],
      'fichiers': const <M>[],
      'patients': const <M>[],
      'audit': const <M>[],
    }, 'POSTE')
      ..horloge = () => DateTime.utc(2026, 11, 13, 9);

class Intercepteur {
  /// Échoue (mère « coupée ») après [coupureApres] requêtes de morceaux envoyées.
  int? coupureApres;
  int _put = 0;

  /// Altère l'octet de la Nième requête PUT (1 = la première), une fois.
  int? alterePut;

  /// Altère le Nième morceau SERVI (GET), une fois.
  int? altereGet;
  int _get = 0;
  bool coupeTout = false;
  final List<String> journal = [];
  int get puts => _put;

  AppelFichiers entoure(MoteurFileul m) => (methode, chemin, {corps, entetes = const {}, typeContenu = 'application/octet-stream'}) async {
        if (coupeTout) throw const SocketException('mère coupée (test)');
        journal.add('$methode ${chemin.split('?').first}');
        var c = corps;
        if (methode == 'PUT') {
          _put++;
          if (coupureApres != null && _put > coupureApres!) {
            throw const SocketException('coupure réseau au milieu du transfert (test)');
          }
          if (alterePut != null && _put == alterePut) {
            c = [...corps!]..[10] ^= 0xff;
            alterePut = null;
          }
        }
        final r = await m.requeteBinaire(methode, chemin, corps: c, entetes: entetes, typeContenu: typeContenu);
        var o = r.corps;
        if (methode == 'GET' && chemin.startsWith('/fichiers/morceau') && r.statut == 200) {
          _get++;
          if (altereGet != null && _get == altereGet) {
            o = Uint8List.fromList(o)..[5] ^= 0xff;
            altereGet = null;
          }
        }
        return ReponseFichiers(r.statut, o, r.entetes);
      };
}

class Poste {
  Poste(this.nom, this.port, this.dossier, {this.role = 'admin', int morceau = 4096}) {
    moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    stockage = StockageFichiers('$dossier/$nom');
    fp = FichiersPoste(magasin, stockage)..installer();
    pont = PontActivite(
        magasin, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: nom);
    service = ServiceFichiers(
        magasin: magasin, fichiers: fp, appel: inter.entoure(moteur), roleCourant: () => role, droitDe: droit, tailleMorceau: morceau, intervalle: const Duration(milliseconds: 50));
  }
  final String nom, dossier;
  final int port;
  String? role;
  final Magasin magasin = nouveauMagasin();
  final Intercepteur inter = Intercepteur();
  late final MoteurFileul moteur;
  late final StockageFichiers stockage;
  late final FichiersPoste fp;
  late final PontActivite pont;
  late final ServiceFichiers service;

  /// `false` : ce poste ne fait que ses métadonnées (le pont d'activité), pas encore ses transferts de fichiers : de quoi VOIR la fiche arriver avant le binaire.
  bool avecService = true;

  Future<void> tour() async {
    try {
      await pont.cycle();
    } catch (_) {}
    if (avecService) await service.cycle();
  }

  Future<ResultatFichier> deposerCourrier(String ficheId, String nom, {Uint8List? octets, String? roleDepot}) => fp.deposer(
      famille: 'courrier', ficheId: ficheId, nom: nom, octets: octets ?? fx(nom), role: roleDepot ?? role ?? 'admin', droit: droit(roleDepot ?? role ?? 'admin', 'm13-courriers'));
  Future<ResultatFichier> deposerDoc(String ficheId, String nom, {Uint8List? octets, String? roleDepot}) => fp.deposer(
      famille: 'patient', ficheId: ficheId, nom: nom, octets: octets ?? fx(nom), role: roleDepot ?? role ?? 'admin', droit: droit(roleDepot ?? role ?? 'admin', 'm1-documents'));
  void courrier(String id, {String date = '2026-08-20'}) =>
      magasin.collection('courriers').inserer({'id': id, 'statut': 'actif', 'reference': 'ARR-2026-$id', 'sens': 'arrivee', 'date': date, 'correspondant': 'X', 'objet': 'Y'});
  void doc(String id, String type) => magasin.collection('documentsPatient').inserer({'id': id, 'statut': 'actif', 'reference': 'GED-$id', 'patientId': 'P1', 'code': 'CNT/1/26', 'type': type, 'date': '2026-08-12'});
  Fiche? fiche(String col, String id) => magasin.collection(col).toutes.where((f) => f['id'] == id || f['idSync'] == id).firstOrNull;
}

class Clinique {
  Clinique(this.port, this.tmp);
  final int port;
  final Directory tmp;
  late Mere mere;
  late ClientMere console;
  final postes = <Poste>[];
  ConfigMere config() => ConfigMere(
      port: port,
      dbChemin: '${tmp.path}/mere.db',
      admin: 'secret-test',
      dossierSauvegardes: '${tmp.path}/sauvegardes',
      dossierFichiers: '${tmp.path}/fichiers-mere',
      cleStockage: List.generate(64, (i) => '${(i * 3 + 1) % 16 >= 10 ? 'abcdef'[((i * 3 + 1) % 16) - 10] : (i * 3 + 1) % 16}').join());

  Future<void> demarrerMere() async {
    mere = await Mere.creer(config());
    await mere.demarrer();
    console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
  }

  Future<void> redemarrerMere() async {
    await mere.arreter();
    await demarrerMere();
  }

  Future<Poste> fileul(String nom, {String role = 'admin', int morceau = 4096}) async {
    final p = Poste(nom, port, tmp.path, role: role, morceau: morceau);
    final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
    await p.moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    p.moteur.demarrer();
    postes.add(p);
    return p;
  }

  Future<void> converger(bool Function() fini, String quoi, {Duration max = const Duration(seconds: 60)}) async {
    final fin = DateTime.now().add(max);
    while (!fini()) {
      for (final p in postes) {
        await p.tour();
      }
      if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (${[for (final p in postes) '${p.nom}: ${p.service.erreur.value} ${p.pont.erreur.value}']})');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> arreter() async {
    for (final p in postes) {
      p.service.arreter();
    }
    try {
      await mere.arreter();
    } catch (_) {}
  }

  int copiesAuDisque(String dossierFichiers) {
    final d = Directory(dossierFichiers);
    if (!d.existsSync()) return 0;
    return d.listSync(recursive: true).whereType<File>().where((f) => RegExp(r'[0-9a-f]{64}\.(pdf|jpg|png|webp)$').hasMatch(f.path)).length;
  }
}

void main() {
  late Directory tmp;
  late Clinique c;
  var port = 9710;
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sigh-fsync-');
    c = Clinique(port++, tmp);
    await c.demarrerMere();
  });
  tearDown(() async {
    await c.arreter();
    tmp.deleteSync(recursive: true);
  });

  test('1. métadonnées D’ABORD, binaire ensuite : la fiche arrive avant le fichier (« en cours de transfert »), puis le binaire par morceaux, empreinte vérifiée', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2')..avecService = false;
    f1.courrier('C1');
    final r = await f1.deposerCourrier('C1', 'courrier-texte.pdf');
    expect(r.ok, isTrue, reason: '${r.refus}');
    final sha = sha256Octets(fx('courrier-texte.pdf'));
    // Seul le PONT travaille (F1 n'a pas encore envoyé le binaire) : la fiche et le registre partent ; le binaire non.
    f1.avecService = false;
    await c.converger(() => f2.magasin.collection('courriers').toutes.any((f) => fichierDe(f)?['sha256'] == sha) && f2.magasin.collection('fichiers').toutes.isNotEmpty, 'la fiche arrive chez F2', max: const Duration(seconds: 30));
    f1.avecService = true;
    expect(f2.magasin.collection('fichiers').parId(fichierIdRegistre(sha)), isNotNull, reason: 'le registre par empreinte (texte indexé) voyage par le journal');
    final fiche = f2.magasin.collection('courriers').toutes.firstWhere((f) => fichierDe(f)?['sha256'] == sha);
    expect(await f2.stockage.existe(sha), isFalse);
    expect(await f2.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.nonDisponibleHorsLigne, reason: 'avant tout contact avec la mère par le service : jamais un écran vide');
    f2.avecService = true;
    final lu = await f2.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'));
    expect(lu.refus!.code, 'FICHIER_ABSENT');
    expect(lu.refus!.geste, contains('synchronisation'));
    // la recherche dans le texte marche déjà (le texte voyage avec les métadonnées)
    expect(fichierCorrespond(f2.fp.texteRecherche(fiche), 'hyperglycemie'), isTrue);
    // Le binaire ensuite : F1 l'envoie, F2 vient le chercher.
    await c.converger(() => f1.service.enAttente.isEmpty && f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'F1 a envoyé');
    expect(await f2.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), anyOf(EtatFichierPoste.enCoursDeTransfert, EtatFichierPoste.present));
    for (var i = 0; i < 30 && !await f2.stockage.existe(sha); i++) {
      await f2.tour();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await f2.stockage.lire(sha), fx('courrier-texte.pdf'));
    expect(await f2.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.present);
    final ok = await f2.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'));
    expect(ok.ok, isTrue);
    expect(ok.octets, fx('courrier-texte.pdf'));
    // la mère a UNE copie, chiffrée au repos
    expect(c.copiesAuDisque('${tmp.path}/fichiers-mere'), 1);
    final surMere = File((await c.mere.stockageFichiers!.cheminDe(sha))!).readAsBytesSync();
    expect(surMere, isNot(fx('courrier-texte.pdf')));
    expect(f1.service.morceauxEnvoyes, (fx('courrier-texte.pdf').length / 4096).ceil());
    expect(f2.service.morceauxRecus, f1.service.morceauxEnvoyes);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('2. REPRISE : une coupure au milieu puis une mère redémarrée ; le transfert repart du dernier morceau vérifié, sans renvoyer ce que la mère a', () async {
    final f1 = await c.fileul('F1');
    f1.courrier('C1');
    final octets = fx('scan.jpg');
    final sha = sha256Octets(octets);
    final n = (octets.length / 4096).ceil();
    expect(n, greaterThan(10));
    await f1.deposerCourrier('C1', 'scan.jpg');
    f1.inter.coupureApres = 6;
    for (var i = 0; i < 3; i++) {
      await f1.tour();
    }
    expect(f1.service.morceauxEnvoyes, 6, reason: 'six morceaux sont partis, puis la coupure');
    expect(f1.service.erreur.value, contains('injoignable'));
    expect(f1.service.mereJoignable, isFalse);
    expect(await c.mere.stockageFichiers!.existe(sha), isFalse, reason: 'rien n’est rangé tant que l’ensemble n’est pas vérifié');
    expect(await c.mere.stockageFichiers!.morceauxRanges(sha), [0, 1, 2, 3, 4, 5]);
    // la MÈRE redémarre (sa mémoire de dépôt est perdue, les morceaux vérifiés sont sur disque)
    await c.redemarrerMere();
    f1.inter.coupureApres = null;
    final avant = f1.service.morceauxEnvoyes;
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'la reprise aboutit');
    expect(f1.service.morceauxEnvoyes - avant, n - 6, reason: 'seuls les morceaux manquants repartent : la reprise ne recommence pas de zéro');
    expect(await c.mere.stockageFichiers!.lire(sha), octets);
    expect(await c.mere.stockageFichiers!.morceauxRanges(sha), isEmpty, reason: 'les morceaux sont effacés une fois le fichier rangé');
    expect(c.copiesAuDisque('${tmp.path}/fichiers-mere'), 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('2 bis. REPRISE à la réception : le fileul coupé en plein téléchargement reprend après son propre redémarrage (nouvelle instance, mêmes morceaux sur disque)', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2')..avecService = false;
    f1.courrier('C1');
    final octets = fx('scan.jpg');
    final sha = sha256Octets(octets);
    final n = (octets.length / 4096).ceil();
    await f1.deposerCourrier('C1', 'scan.jpg');
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme') && f2.magasin.collection('courriers').toutes.isNotEmpty, 'envoi et métadonnées');
    // F2 reçoit 5 morceaux puis la liaison tombe
    f2.inter.coupureApres = null;
    var recus = 0;
    final appelCoupable = f2.inter.entoure(f2.moteur);
    final service2 = ServiceFichiers(
        magasin: f2.magasin,
        fichiers: f2.fp,
        appel: (m, ch, {corps, entetes = const {}, typeContenu = 'application/octet-stream'}) async {
          if (m == 'GET' && ch.startsWith('/fichiers/morceau')) {
            if (recus >= 5) throw const SocketException('coupure');
            recus++;
          }
          return appelCoupable(m, ch, corps: corps, entetes: entetes, typeContenu: typeContenu);
        },
        roleCourant: () => 'admin',
        droitDe: droit,
        tailleMorceau: 4096);
    await service2.cycle();
    expect(service2.morceauxRecus, 5);
    expect(await f2.stockage.existe(sha), isFalse);
    // « redémarrage » de F2 : une NOUVELLE instance du stockage et du service sur le même dossier
    final stock = StockageFichiers('${tmp.path}/F2');
    expect(await stock.morceauxRanges(sha), [0, 1, 2, 3, 4]);
    final fp = FichiersPoste(f2.magasin, stock);
    final service3 = ServiceFichiers(magasin: f2.magasin, fichiers: fp, appel: f2.inter.entoure(f2.moteur), roleCourant: () => 'admin', droitDe: droit, tailleMorceau: 4096);
    await service3.cycle();
    expect(service3.morceauxRecus, n - 5, reason: 'la reprise ne redemande pas les cinq morceaux déjà vérifiés');
    expect(await stock.lire(sha), octets);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('3. un morceau ALTÉRÉ en route est refusé et renvoyé : à l’envoi (la mère le refuse) et à la réception (le fileul le refuse)', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    f1.courrier('C1');
    final octets = fx('scan.png');
    final sha = sha256Octets(octets);
    await f1.deposerCourrier('C1', 'scan.png');
    f1.inter.alterePut = 3;
    f2.inter.altereGet = 2;
    for (var i = 0; i < 60 && !await f2.stockage.existe(sha); i++) {
      await f1.tour();
      await f2.tour();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(f1.service.morceauxRenvoyes, 1, reason: 'la mère a refusé le morceau altéré en route (409 MORCEAU_ALTERE) et F1 l’a renvoyé');
    expect(f2.service.morceauxRenvoyes, 1, reason: 'F2 a refusé le morceau altéré servi et l’a redemandé');
    expect(await c.mere.stockageFichiers!.lire(sha), octets);
    expect(await f2.stockage.lire(sha), octets, reason: 'rien d’altéré n’a été rangé');
    expect(f1.inter.journal.where((j) => j == 'PUT /fichiers/morceau').length, (octets.length / 4096).ceil() + 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('4. le MÊME fichier déposé des deux côtés : une copie sur la mère, une fiche de registre, un compteur de références déduit des fiches (jamais doublé)', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    f1.courrier('C1');
    f2.courrier('C2', date: '2026-09-01');
    final sha = sha256Octets(fx('courrier-texte.pdf'));
    expect((await f1.deposerCourrier('C1', 'courrier-texte.pdf')).ok, isTrue);
    expect((await f2.deposerCourrier('C2', 'courrier-texte.pdf')).ok, isTrue);
    await c.converger(
        () =>
            f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme') &&
            f2.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme') &&
            [f1, f2].every((p) => p.magasin.collection('courriers').toutes.where((f) => fichierDe(f)?['sha256'] == sha).length == 2 && p.magasin.collection('fichiers').toutes.isNotEmpty),
        'les deux dépôts convergent');
    expect(c.copiesAuDisque('${tmp.path}/fichiers-mere'), 1, reason: 'une seule copie du fichier sur la mère');
    for (final p in [f1, f2]) {
      final reg = p.magasin.collection('fichiers').toutes.where((f) => f['sha256'] == sha).toList();
      expect(reg.length, 1, reason: '${p.nom} : une seule fiche de registre pour l’empreinte');
      expect(fichierNbReferences(p.magasin.collection('courriers').toutes, sha), 2, reason: '${p.nom} : deux références, déduites des fiches');
      expect(reg.single.containsKey('nbReferences'), isFalse, reason: 'jamais de compteur synchronisé');
    }
    expect((await c.mere.stockageFichiers!.meta(sha))!.usages, [
      {'famille': 'courrier', 'zone': 0}
    ]);
    // aucun refus à « traiter » chez les fileuls pour la seconde création du registre
    for (final p in [f1, f2]) {
      final refus = (await p.moteur.refusees()).where((r) => r['code'] == 'fiche_existe');
      expect(refus, isEmpty, reason: '${p.nom} : la seconde création de la fiche de registre est acceptée sans effet');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('5. DROITS DE ZONE : un poste dont le rôle ne lit pas la zone ne reçoit PAS le binaire, et la mère le lui refuse aussi (RG-13)', () async {
    final f1 = await c.fileul('F1', role: 'medecin');
    final f2 = await c.fileul('F2', role: 'reception');
    final f3 = await c.fileul('F3', role: 'infirmier');
    f1.doc('D1', 'Compte rendu médical');
    f1.doc('D2', 'Pièce d’identité');
    expect((await f1.deposerDoc('D1', 'scan.png')).ok, isTrue);
    expect((await f1.deposerDoc('D2', 'scan.jpg')).ok, isTrue);
    final shaCR = sha256Octets(fx('scan.png')), shaId = sha256Octets(fx('scan.jpg'));
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'envoi');
    for (var i = 0; i < 40 && !(await f3.stockage.existe(shaCR) && await f2.stockage.existe(shaId)); i++) {
      for (final p in c.postes) {
        await p.tour();
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    expect(await f3.stockage.existe(shaCR), isTrue, reason: 'l’infirmier est un profil clinique : il reçoit le compte rendu (zone 2)');
    expect(await f2.stockage.existe(shaId), isTrue, reason: 'l’accueil reçoit la pièce d’identité (zone 1)');
    expect(await f2.stockage.existe(shaCR), isFalse, reason: 'l’accueil ne reçoit PAS le compte rendu (zone 2)');
    expect(f2.service.refuses, isEmpty, reason: 'le poste ne DEMANDE même pas ce qu’il ne peut pas lire : aucun refus à dire');
    expect(f2.service.enAttente, isNot(contains(shaCR)), reason: 'l’accueil n’attend pas un compte rendu qu’il ne lit pas');
    // La mère le lui refuserait aussi : appel direct sous le rôle de l'accueil.
    final jeton = (await f2.moteur.requeteBinaire('GET', '/fichiers/info?sha256=$shaCR&famille=patient', entetes: {'x-sigh-role': 'reception'}));
    expect(jeton.statut, 403);
    final j = jsonDecode(utf8.decode(jeton.corps)) as Map;
    expect(j['code'], 'ZONE_REFUSEE');
    expect(j['motif'], contains('RG-13'));
    final morceau = await f2.moteur.requeteBinaire('GET', '/fichiers/morceau?sha256=$shaCR&i=0&famille=patient', entetes: {'x-sigh-role': 'reception'});
    expect(morceau.statut, 403);
    expect(morceau.corps.length, lessThan(1000), reason: 'aucun octet de la pièce n’est servi');
    // et il ne peut pas déposer un compte rendu
    final depot = await f2.moteur.requeteBinaire('POST', '/fichiers/ouvrir',
        corps: utf8.encode(jsonEncode({'famille': 'patient', 'type': 'Compte rendu médical', 'description': DescriptionFichier.deOctets(fx('scan.webp')).toJson()})),
        entetes: {'x-sigh-role': 'reception'},
        typeContenu: 'application/json');
    expect(depot.statut, 403);
    // Sans rôle déclaré, la mère refuse.
    final sans = await f2.moteur.requeteBinaire('GET', '/fichiers/info?sha256=$shaId&famille=patient');
    expect(sans.statut, 400);
    // Quand l'agent connecté change de rôle (le médecin se connecte au poste de l'accueil), le binaire arrive.
    f2.role = 'medecin';
    for (var i = 0; i < 20 && !await f2.stockage.existe(shaCR); i++) {
      await f2.tour();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await f2.stockage.existe(shaCR), isTrue);
    // mais l'écran refuse encore de le montrer à l'accueil (la lecture applique la zone du rôle de l'agent)
    final fiche = f2.magasin.collection('documentsPatient').toutes.firstWhere((f) => f['reference'] == 'GED-D1');
    final lu = await f2.fp.lire(famille: 'patient', fiche: fiche, role: 'reception', droit: droit('reception', 'm1-documents'));
    expect(lu.refus!.code, 'ZONE_REFUSEE');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('6. JAMAIS vers un téléphone : ni le binaire, ni les fiches, ni le registre (RG-13)', () async {
    final f1 = await c.fileul('F1', role: 'admin');
    f1.courrier('C1');
    f1.doc('D2', 'Pièce d’identité');
    await f1.deposerCourrier('C1', 'scan.png');
    await f1.deposerDoc('D2', 'scan.jpg');
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'envoi');
    final sha = sha256Octets(fx('scan.png'));
    // un téléphone (profil réception) s'appaire
    final base = 'http://127.0.0.1:${c.port}';
    final code = jsonDecode((await http.post(Uri.parse('$base/admin/code'), headers: {'x-admin': 'secret-test', 'content-type': 'application/json'}, body: jsonEncode({'etiquette': 'Tel', 'role': 'mobile', 'profil': 'reception'}))).body)['code'];
    final app = jsonDecode((await http.post(Uri.parse('$base/appairage'), headers: {'content-type': 'application/json'}, body: jsonEncode({'code': code, 'uuid': 'tel-0001', 'plateforme': 'test'}))).body) as Map;
    final h = {'authorization': 'Bearer ${app['jeton']}', 'x-sigh-role': 'admin'};
    for (final (m, ch, corps) in [
      ('GET', '/fichiers/info?sha256=$sha&famille=courrier', null),
      ('GET', '/fichiers/morceau?sha256=$sha&i=0&famille=courrier', null),
      ('POST', '/fichiers/ouvrir', jsonEncode({'famille': 'courrier', 'description': DescriptionFichier.deOctets(fx('scan.png')).toJson()})),
      ('PUT', '/fichiers/morceau?sha256=$sha&i=0', 'x'),
      ('POST', '/fichiers/terminer', jsonEncode({'sha256': sha})),
    ]) {
      final r = await (http.Request(m, Uri.parse('$base$ch'))
            ..headers.addAll(h)
            ..body = corps ?? '')
          .send();
      final texte = await r.stream.bytesToString();
      expect(r.statusCode, 403, reason: '$m $ch');
      expect(jsonDecode(texte)['code'], 'FICHIERS_INTERDITS_AU_MOBILE');
    }
    // le lot de tournée d'un téléphone ne peut pas NOMMER une fiche de fichier : refus nommé, rien n'est publié
    final lot = await http.post(Uri.parse('$base/admin/lot'),
        headers: {'x-admin': 'secret-test', 'content-type': 'application/json'}, body: jsonEncode({'uuid': 'tel-0001', 'fiches': [{'collection': 'courriers', 'id': 'C1'}, {'collection': 'documentsPatient', 'id': 'D2'}], 'ttl_ms': 60000}));
    expect(lot.statusCode, 422);
    expect(jsonDecode(lot.body)['code'], 'fichiers_interdits_au_mobile');
    // le journal qu'un téléphone tire ne contient aucune fiche de fichier : ni courrier, ni document du patient (pièce d'identité comprise), ni registre
    final pull = jsonDecode((await http.get(Uri.parse('$base/sync/pull?depuis=0&limite=500&epoch=1'), headers: {'authorization': 'Bearer ${app['jeton']}'})).body) as Map;
    final collections = {for (final o in (pull['ops'] as List)) (o as Map)['collection']};
    expect(collections.intersection(collectionsFichiersJamaisMobile), isEmpty, reason: 'un téléphone ne reçoit aucune fiche de fichier : $collections');
    // et le poste, lui, les voit bien dans le journal
    final pullPoste = jsonDecode((await http.get(Uri.parse('$base/sync/pull?depuis=0&limite=500&epoch=1'), headers: {'authorization': 'Bearer ${f1.moteur.jeton}'})).body) as Map;
    final cp = {for (final o in (pullPoste['ops'] as List)) (o as Map)['collection']};
    expect(cp, containsAll(['courriers', 'documentsPatient', 'fichiers']));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('7. sans mère : tout reste local, sans erreur ; mère coupée : « non disponible hors ligne » ; la mère revient : le fichier arrive', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2')..avecService = false;
    f1.courrier('C1');
    await f1.deposerCourrier('C1', 'courrier-texte.pdf');
    final sha = sha256Octets(fx('courrier-texte.pdf'));
    // Un poste AUTONOME (aucune mère) : dépôt, lecture, retrait sans une erreur.
    final seul = Magasin({'courriers': const <M>[], 'audit': const <M>[], 'fichiers': const <M>[]}, 'SEUL');
    seul.collection('courriers').inserer({'id': 'S1', 'statut': 'actif', 'reference': 'ARR-2026-0001', 'sens': 'arrivee', 'date': '2026-08-20'});
    final fps = FichiersPoste(seul, StockageFichiers('${tmp.path}/seul'));
    final d = await fps.deposer(famille: 'courrier', ficheId: 'S1', nom: 'scan.png', octets: fx('scan.png'), role: 'admin', droit: droit('admin', 'm13-courriers'));
    expect(d.ok, isTrue);
    final lu = await fps.lire(famille: 'courrier', fiche: seul.collection('courriers').parId('S1')!, role: 'admin', droit: droit('admin', 'm13-courriers'));
    expect(lu.ok, isTrue);
    // F2 reçoit la fiche mais la mère est COUPÉE avant le binaire
    await c.converger(() => f2.magasin.collection('courriers').toutes.any((f) => fichierDe(f)?['sha256'] == sha), 'la fiche arrive chez F2');
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'F1 a envoyé');
    f2.inter.coupeTout = true;
    await f2.service.cycle();
    expect(f2.service.mereJoignable, isFalse);
    expect(f2.service.erreur.value, contains('injoignable'));
    final fiche = f2.magasin.collection('courriers').toutes.firstWhere((f) => fichierDe(f)?['sha256'] == sha);
    expect(await f2.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.nonDisponibleHorsLigne);
    expect(fichierLibelleEtatPoste(EtatFichierPoste.nonDisponibleHorsLigne, sha: sha), contains('non disponible hors ligne'));
    // la mère REVIENT
    f2.inter.coupeTout = false;
    f2.avecService = true;
    for (var i = 0; i < 30 && !await f2.stockage.existe(sha); i++) {
      await f2.tour();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await f2.stockage.existe(sha), isTrue);
    expect(f2.service.mereJoignable, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('8. la mère ARRÊTÉE puis relancée sur sa base : les fichiers sont toujours là (chiffrés au repos) et un nouveau fileul les reçoit', () async {
    final f1 = await c.fileul('F1');
    f1.courrier('C1');
    await f1.deposerCourrier('C1', 'scan.jpg');
    final sha = sha256Octets(fx('scan.jpg'));
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme'), 'envoi');
    await c.redemarrerMere();
    expect(await c.mere.stockageFichiers!.lire(sha), fx('scan.jpg'));
    final f3 = await c.fileul('F3');
    for (var i = 0; i < 40 && !await f3.stockage.existe(sha); i++) {
      await f3.tour();
      await f1.tour();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    expect(await f3.stockage.lire(sha), fx('scan.jpg'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
