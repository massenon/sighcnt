import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart' show fichiersFileEnvoi;
import 'package:sigh_poste/donnees/ocr_poste.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'fichiers_direct_sync_test.dart' show Clinique, Poste, droit, fx;

/// LE TEXTE LU PAR MACHINE PAR LA SYNCHRONISATION, CONTRE LA VRAIE MÈRE (lot OCR-prep) : deux vrais fileuls (moteur de synchronisation, pont d'activité, stockage sur disque, service de transfert,
/// service de lecture OCR) et la vraie mère Dart. Le moteur est FACTICE : ce qui est éprouvé, c'est tout ce qui entoure le moteur.
///  1. une lecture écrite par un poste ARRIVE chez l'autre par le journal : il ne relit pas (aucun appel du moteur), il lit « lu par machine, à vérifier » ;
///  2. deux postes qui lisent le MÊME scan avec le même moteur avant de se parler ne font qu'UNE version, sans refus à « traiter » ;
///  3. deux moteurs qui rendent des textes différents font DEUX versions, et la version courante est la même sur les deux postes ;
///  4. la FILE reste locale : elle n'arrive ni à la mère ni à l'autre poste ;
///  5. JAMAIS vers un téléphone : ni dans ce qu'il tire du journal, ni dans un lot de tournée ;
///  6. le texte d'un scan de ZONE 2 reste de zone 2 : le poste dont l'agent ne lit pas la zone n'en reçoit rien à l'écran, et sa file n'y touche pas.
typedef M = Map<String, Object?>;

const texteA = 'Hyperglycémie sévère : père déjà traité à Natitingou';
const texteB = 'Seconde lecture : paludisme grave à Tanguiéta';

class Lecteur {
  Lecteur(this.poste, String texte, {String id = 'factice'}) : moteur = MoteurOcrFactice(id: id, texteParDefaut: texte) {
    ocr = OcrPoste(poste.fp, roleCourant: () => poste.role, droitDe: droit)
      ..automatique = false
      ..installer();
    ocr.enregistrer(moteur);
    final r = ocr.definirReglage(role: 'admin', actif: true, moteur: id, langue: 'fra', motif: 'sonde de synchronisation');
    expect(r.ok, isTrue, reason: '${r.refus}');
    ocr.arreter();
  }
  final Poste poste;
  final MoteurOcrFactice moteur;
  late final OcrPoste ocr;
  List<M> get lectures => poste.magasin.collection(ocrLectures).toutes;
}

Future<int> compteMere(Clinique c, String collection) async {
  final r = await http.get(Uri.parse('http://127.0.0.1:${c.port}/admin/compte?collection=$collection'), headers: {'x-admin': 'secret-test'});
  return (jsonDecode(r.body) as Map)['n'] as int;
}

void main() {
  late Directory tmp;
  late Clinique c;
  var port = 9760;
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sigh-ocr-sync-');
    c = Clinique(port++, tmp);
    await c.demarrerMere();
  });
  tearDown(() async {
    await c.arreter();
    tmp.deleteSync(recursive: true);
  });

  test('1. une lecture arrive chez l’autre poste par le journal : il ne relit pas, il lit « lu par machine, à vérifier » ; un redémarrage ne relit rien', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    final l1 = Lecteur(f1, texteA);
    final l2 = Lecteur(f2, texteA);
    f1.courrier('C1');
    expect((await f1.deposerCourrier('C1', 'scan.png')).ok, isTrue);
    final sha = sha256Octets(fx('scan.png'));
    expect(await l1.ocr.vider(), 1);
    expect(l1.moteur.appels, 1);
    await c.converger(() => l2.lectures.isNotEmpty && f2.magasin.collection('courriers').toutes.any((f) => fichierDe(f)?['sha256'] == sha), 'la lecture arrive chez F2');
    expect(l2.lectures, hasLength(1));
    expect(l2.lectures.single['texteBrut'], texteA);
    expect(l2.lectures.single['moteur'], 'factice');
    final x = fichierDe(f2.magasin.collection('courriers').toutes.firstWhere((f) => fichierDe(f)?['sha256'] == sha))!;
    final e = l2.ocr.etatDe(x);
    expect(e.etat, EtatIndexation.ocrIndexe);
    expect(e.marque, isTrue);
    // F2 ne relit pas : le balayage ne met rien en file, le moteur n'est jamais appelé
    expect(l2.ocr.balayer(), 0);
    expect(await l2.ocr.vider(), 0);
    expect(l2.moteur.appels, 0);
    expect(f2.magasin.collection(ocrFile).toutes, isEmpty);
    expect(fichierCorrespond(f2.fp.texteDe(sha), 'HYPERGLYCEMIE'), isTrue, reason: 'la recherche de F2 lit le texte arrivé par le journal');
    // un REDÉMARRAGE de F1 (nouveau service sur le même magasin) ne relit pas non plus
    final autre = OcrPoste(f1.fp, roleCourant: () => f1.role, droitDe: droit)
      ..automatique = false
      ..enregistrer(l1.moteur);
    expect(autre.balayer(), 0);
    expect(await autre.vider(), 0);
    expect(l1.moteur.appels, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('2. deux postes qui lisent le MÊME scan avec le même moteur avant de se parler ne font qu’UNE version ; la mère n’en garde qu’une, aucun refus', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    final l1 = Lecteur(f1, texteA);
    final l2 = Lecteur(f2, texteA);
    f1.courrier('C1');
    f2.courrier('C2');
    await f1.deposerCourrier('C1', 'scan.png');
    await f2.deposerCourrier('C2', 'scan.png');
    expect(await l1.ocr.vider(), 1);
    expect(await l2.ocr.vider(), 1, reason: 'chacun lit chez lui avant que le journal ne passe : deux lectures réelles');
    expect(l1.lectures.single['id'], l2.lectures.single['id'], reason: 'identifiant déterministe : empreinte, moteur, version, langue, texte normalisé');
    await c.converger(() => f1.pont.erreur.value == null && f2.pont.erreur.value == null, 'les deux postes se parlent', max: const Duration(seconds: 20));
    for (var i = 0; i < 6; i++) {
      for (final p in c.postes) {
        await p.tour();
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect(await compteMere(c, 'lecturesOcr'), 1, reason: 'la seconde création est acceptée SANS EFFET : une fiche à la mère');
    expect(l1.lectures, hasLength(1));
    expect(l2.lectures, hasLength(1));
    expect(f1.pont.erreur.value, isNull);
    expect(f2.pont.erreur.value, isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('3. deux moteurs, deux textes : DEUX versions partout, et la version courante est la MÊME sur les deux postes (date puis identifiant)', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    final l1 = Lecteur(f1, texteA, id: 'moteur-a');
    final l2 = Lecteur(f2, texteB, id: 'moteur-b');
    f1.courrier('C1');
    f2.courrier('C2');
    await f1.deposerCourrier('C1', 'scan.png');
    await f2.deposerCourrier('C2', 'scan.png');
    await l1.ocr.vider();
    await l2.ocr.vider();
    final sha = sha256Octets(fx('scan.png'));
    await c.converger(() => l1.lectures.length == 2 && l2.lectures.length == 2, 'les deux versions partout');
    expect(await compteMere(c, 'lecturesOcr'), 2);
    expect(l1.ocr.versionCourante(sha)!['id'], l2.ocr.versionCourante(sha)!['id'], reason: 'tous les postes retrouvent le même ordre : jamais deux textes courants différents');
    expect({for (final v in l1.lectures) v['moteur']}, {'moteur-a', 'moteur-b'});
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('4. la FILE reste locale : elle n’arrive ni à la mère ni à l’autre poste', () async {
    final f1 = await c.fileul('F1');
    final f2 = await c.fileul('F2');
    final l1 = Lecteur(f1, texteA);
    Lecteur(f2, texteA);
    f1.courrier('C1');
    await f1.deposerCourrier('C1', 'scan.jpg');
    expect(f1.magasin.collection(ocrFile).toutes, hasLength(1));
    await c.converger(() => f2.magasin.collection('courriers').toutes.isNotEmpty, 'la fiche arrive');
    for (var i = 0; i < 4; i++) {
      for (final p in c.postes) {
        await p.tour();
      }
    }
    expect(f2.magasin.collection(ocrFile).toutes, isEmpty);
    expect(await compteMere(c, ocrFile), 0);
    await l1.ocr.vider();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('5. JAMAIS vers un téléphone : ni dans ce qu’il tire du journal, ni dans un lot de tournée', () async {
    final f1 = await c.fileul('F1');
    final l1 = Lecteur(f1, texteA);
    f1.courrier('C1');
    await f1.deposerCourrier('C1', 'scan.png');
    await l1.ocr.vider();
    await c.converger(() => f1.magasin.collection(fichiersFileEnvoi).toutes.every((l) => l['etat'] == 'confirme') && f1.pont.erreur.value == null, 'envoi');
    await c.converger(() => true, 'tour', max: const Duration(seconds: 5));
    await f1.tour();
    final base = 'http://127.0.0.1:${c.port}';
    final code = jsonDecode((await http.post(Uri.parse('$base/admin/code'), headers: {'x-admin': 'secret-test', 'content-type': 'application/json'}, body: jsonEncode({'etiquette': 'Tel', 'role': 'mobile', 'profil': 'reception'}))).body)['code'];
    final app = jsonDecode((await http.post(Uri.parse('$base/appairage'), headers: {'content-type': 'application/json'}, body: jsonEncode({'code': code, 'uuid': 'tel-ocr-1', 'plateforme': 'test'}))).body) as Map;
    final id = l1.lectures.single['id'];
    final lot = await http.post(Uri.parse('$base/admin/lot'),
        headers: {'x-admin': 'secret-test', 'content-type': 'application/json'}, body: jsonEncode({'uuid': 'tel-ocr-1', 'fiches': [{'collection': 'lecturesOcr', 'id': id}], 'ttl_ms': 60000}));
    expect(lot.statusCode, 422);
    expect(jsonDecode(lot.body)['code'], 'fichiers_interdits_au_mobile');
    final pull = jsonDecode((await http.get(Uri.parse('$base/sync/pull?depuis=0&limite=500&epoch=1'), headers: {'authorization': 'Bearer ${app['jeton']}'})).body) as Map;
    final collections = {for (final o in (pull['ops'] as List)) (o as Map)['collection']};
    expect(collections, isNot(contains('lecturesOcr')), reason: 'un téléphone ne reçoit AUCUN texte lu : $collections');
    final pullPoste = jsonDecode((await http.get(Uri.parse('$base/sync/pull?depuis=0&limite=500&epoch=1'), headers: {'authorization': 'Bearer ${f1.moteur.jeton}'})).body) as Map;
    expect({for (final o in (pullPoste['ops'] as List)) (o as Map)['collection']}, contains('lecturesOcr'), reason: 'un poste, lui, les voit dans le journal');
    expect(collectionsFichiersJamaisMobile, contains('lecturesOcr'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('6. le texte d’un scan de ZONE 2 reste de zone 2 : le poste dont l’agent ne lit pas la zone n’en lit rien, et sa file n’y touche pas', () async {
    final f1 = await c.fileul('F1', role: 'medecin');
    final f2 = await c.fileul('F2', role: 'reception');
    final l1 = Lecteur(f1, texteA);
    final l2 = Lecteur(f2, texteA);
    f1.doc('D1', 'Compte rendu médical');
    expect((await f1.deposerDoc('D1', 'scan.png')).ok, isTrue);
    expect(await l1.ocr.vider(), 1);
    final sha = sha256Octets(fx('scan.png'));
    await c.converger(() => l2.lectures.isNotEmpty, 'la lecture arrive chez F2 (métadonnée du journal)');
    expect(f1.fp.texteDe(sha, famille: 'patient', type: 'Compte rendu médical'), contains('hyperglycemie'));
    expect(f2.fp.texteDe(sha, famille: 'patient', type: 'Compte rendu médical'), '', reason: 'zone 2 : l’accueil n’en lit pas un mot');
    expect(f2.fp.texteDe(sha, famille: 'patient', type: 'Pièce d’identité'), contains('hyperglycemie'), reason: 'la règle suit la zone du TYPE de document');
    // la file de l'accueil n'y touche pas : le binaire ne lui est jamais parvenu (ZONE_REFUSEE) et le droit de zone l'écarte
    expect(await f2.stockage.existe(sha), isFalse, reason: 'RG-13 : le binaire d’une pièce de zone 2 ne va pas à un poste dont le rôle ne la lit pas');
    expect(l2.moteur.appels, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
