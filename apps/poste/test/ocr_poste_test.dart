import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/ocr_poste.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LA LECTURE OCR DES SCANS AU POSTE, PRÉPARÉE (lot OCR-prep) : sans moteur l'état le dit, le moteur FACTICE branché, les six états, la file (un fichier à la fois, une par empreinte, reprise
/// après arrêt, délai), le marquage « à vérifier », la couche native qui prime, le droit de zone, la relance, l'immuabilité des lectures, le journal RG-12. AUCUN moteur réel, AUCUNE qualité
/// d'OCR mesurée : ce qui est éprouvé, c'est tout ce qui entoure le moteur.
const fixtures = 'test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();

/// Un scan distinct par `k` (même format : des octets en trop ne gênent ni PNG, ni JPEG, ni WEBP).
Uint8List variante(String n, int k) => Uint8List.fromList([...fx(n), k, k, k, k, 0, 0, 0, 0]);
final donnees = DonneesNavigation.depuisDossier();
Droit droit(String role, String ecran) => donnees.matrice.droit(role, ecran);
const texteLu = 'Hyperglycémie sévère : père déjà traité à Natitingou, œuf de ç';

class Banc {
  Banc(this.tmp) {
    magasin = Magasin({
      'courriers': [
        for (var i = 1; i <= 8; i++) {'id': 'C$i', 'statut': 'actif', 'reference': 'ARR-2026-004$i', 'sens': 'arrivee', 'date': '2026-08-20', 'correspondant': 'Préfecture', 'objet': 'Objet $i'},
      ],
      'documentsPatient': [
        {'id': 'D1', 'statut': 'actif', 'reference': 'GED-00007', 'patientId': 'P1', 'code': 'CNT/12/26', 'type': 'Compte rendu médical', 'date': '2026-08-12'},
        {'id': 'D2', 'statut': 'actif', 'reference': 'GED-00008', 'patientId': 'P1', 'code': 'CNT/12/26', 'type': 'Pièce d’identité', 'date': '2026-08-12'},
      ],
      'audit': const [],
    }, 'POSTE')
      ..utilisateur = 'Agent Test';
    magasin.horloge = () => DateTime.utc(2026, 10, 30, 10);
    stockage = StockageFichiers('${tmp.path}/fichiers');
    fp = FichiersPoste(magasin, stockage)..installer();
    ocr = nouveauService();
  }
  final Directory tmp;
  late final Magasin magasin;
  late final StockageFichiers stockage;
  late final FichiersPoste fp;
  late OcrPoste ocr;
  String role = 'admin';

  OcrPoste nouveauService() => OcrPoste(fp, roleCourant: () => role, droitDe: droit)
    ..automatique = false
    ..installer();

  Future<ResultatFichier> courrier(String id, Uint8List octets, String nom) =>
      fp.deposer(famille: 'courrier', ficheId: id, nom: nom, octets: octets, role: role, droit: droit(role, 'm13-courriers'));
  Future<ResultatFichier> doc(String id, Uint8List octets, String nom) =>
      fp.deposer(famille: 'patient', ficheId: id, nom: nom, octets: octets, role: role, droit: droit(role, 'm1-documents'));
  Map<String, Object?> fichier(String col, String id) => fichierDe(magasin.collection(col).parId(id))!;
  String sha(String col, String id) => '${fichier(col, id)['sha256']}';
  List<Map<String, Object?>> audit(String action) => [for (final f in magasin.collection('audit').toutes) if (f['action'] == action) f];

  /// Active la lecture avec [m] (administrateur).
  void activer(MoteurOcr m, {int? delaiMs}) {
    final avant = role;
    role = 'admin';
    ocr.enregistrer(m);
    final r = ocr.definirReglage(role: 'admin', actif: true, moteur: m.id, langue: 'fra', motif: 'sonde', delaiMs: delaiMs);
    expect(r.ok, isTrue, reason: '${r.refus}');
    ocr.arreter();
    role = avant;
  }
}

void main() {
  late Directory tmp;
  late Banc b;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-ocr-');
    b = Banc(tmp);
  });
  tearDown(() {
    b.ocr.arreter();
    tmp.deleteSync(recursive: true);
  });

  group('sans moteur : l’état le dit, rien ne se met en file, rien n’est indexé', () {
    test('un scan déposé : « aucun moteur d’OCR installé sur ce poste », pas de file, pas de lecture, jamais indexé', () async {
      expect((await b.courrier('C1', variante('scan.png', 1), 'scan.png')).ok, isTrue);
      final e = b.ocr.etatDe(b.fichier('courriers', 'C1'));
      expect(e.etat, EtatIndexation.nonIndexe);
      expect(e.raison, ocrRaisonSansMoteur);
      expect(e.disponible, isFalse);
      expect(e.source, isNull);
      expect(b.magasin.collection(ocrFile).toutes, isEmpty);
      expect(b.magasin.collection(ocrLectures).toutes, isEmpty);
      expect(b.ocr.pret, isFalse);
      expect(b.ocr.moteurInstalle, isFalse);
    });
    test('traiter la file sans moteur est refusé en le nommant (MOTEUR_ABSENT), jamais muet', () async {
      final r = await b.ocr.traiterSuivant();
      expect(r.ok, isFalse);
      expect(r.refus!.code, CodeOcr.moteurAbsent);
      expect(r.refus!.motif, ocrRaisonSansMoteur);
    });
    test('activer la lecture sans moteur installé est REFUSÉ (MOTEUR_ABSENT) ; le réglage reste désactivé', () {
      final r = b.ocr.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: 'essai');
      expect(r.ok, isFalse);
      expect(r.refus!.code, CodeOcr.moteurAbsent);
      expect(b.ocr.reglage.actif, isFalse);
      expect(b.ocr.reglage.regle, isFalse);
    });
    test('la relance n’est ni offerte ni acceptée, et la phrase sous « Aucun résultat » dit le bon nombre', () async {
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      await b.courrier('C2', variante('scan.png', 2), 'scan.png');
      final x = b.fichier('courriers', 'C1');
      expect(b.ocr.relancePossible(x, peutDeposer: true), isFalse);
      expect(b.ocr.relancer(x, peutDeposer: true, famille: 'courrier').refus!.code, CodeOcr.moteurAbsent);
      expect(b.fp.indiceNonIndexe(b.magasin.collection('courriers').toutes), contains('2 pièces sans texte lu : $ocrRaisonSansMoteur.'));
    });
  });

  group('réglage', () {
    test('réservé à l’administrateur et à la DAF, motivé, journalisé (RG-12), en base avec son auteur et sa date', () {
      b.ocr.enregistrer(MoteurOcrFactice());
      expect(b.ocr.definirReglage(role: 'agentadmin', actif: true, moteur: 'factice', langue: 'fra', motif: 'x').refus!.code, CodeOcr.reglageReserve);
      expect(b.ocr.definirReglage(role: 'medecin', actif: false, moteur: null, langue: 'fra', motif: 'x').refus!.code, CodeOcr.reglageReserve);
      expect(b.ocr.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: '  ').refus!.code, CodeOcr.motifRequis);
      expect(b.ocr.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'xxx', motif: 'x').refus!.code, CodeOcr.langueAbsente);
      expect(b.ocr.reglage.regle, isFalse, reason: 'aucun refus ne change le réglage');
      expect(b.ocr.definirReglage(role: 'da', actif: true, moteur: 'factice', langue: 'fra', motif: 'activation DA').ok, isTrue);
      b.ocr.arreter();
      expect(b.ocr.reglage.actif, isTrue);
      expect(b.ocr.reglage.moteur, 'factice');
      expect(b.ocr.reglage.reglePar, 'Agent Test');
      expect(b.ocr.reglage.regleLe, isNotNull);
      expect(b.audit('Réglage de la lecture OCR des scans'), hasLength(1));
      expect(b.ocr.peutRegler('admin'), isTrue);
      expect(b.ocr.peutRegler('da'), isTrue);
      expect(b.ocr.peutRegler('comptable'), isFalse);
    });
  });

  group('moteur factice : les états, la file, le marquage', () {
    test('l’activation rattrape un scan déjà déposé ; « en cours » puis « lu par machine, à vérifier », une version datée avec ses accents', () async {
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      final attente = Completer<void>();
      final m = MoteurOcrFactice(texteParDefaut: texteLu, attente: attente.future);
      b.activer(m);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.ocrEnAttente);
      final f = b.ocr.traiterSuivant();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.ocrEnCours);
      attente.complete();
      final r = await f;
      expect(r.fait, isTrue);
      final e = b.ocr.etatDe(b.fichier('courriers', 'C1'));
      expect(e.etat, EtatIndexation.ocrIndexe);
      expect(e.marque, isTrue);
      expect(e.source, 'ocr');
      final v = b.ocr.versionsDe(b.sha('courriers', 'C1')).single;
      expect(v['texteBrut'], texteLu);
      expect(v['moteur'], 'factice');
      expect(v['moteurVersion'], '0.1');
      expect(v['langue'], 'fra');
      expect(v['confiance'], 0.9);
      expect(v['ocrPar'], 'Agent Test');
      expect(v['ocrLe'], '2026-10-30T10:00:00.000Z');
      expect(v['nbMots'], greaterThan(5));
    });

    test('un seul scan à la fois : le second déposé pendant ce temps est en attente, le moteur n’en tient jamais deux', () async {
      final attente = Completer<void>();
      final m = MoteurOcrFactice(texteParDefaut: texteLu, attente: attente.future);
      b.activer(m);
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      final f1 = b.ocr.traiterSuivant();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await b.courrier('C2', variante('scan.png', 2), 'scan.png');
      expect(b.ocr.etatDe(b.fichier('courriers', 'C2')).etat, EtatIndexation.ocrEnAttente);
      final pendant = await b.ocr.traiterSuivant();
      expect(pendant.fait, isFalse, reason: 'un traitement est déjà en cours : jamais deux à la fois');
      attente.complete();
      await f1;
      await b.ocr.traiterSuivant();
      expect(m.maxParallele, 1);
      expect(m.appels, 2);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C2')).etat, EtatIndexation.ocrIndexe);
    });

    test('la saisie reste libre pendant une lecture : une écriture du magasin passe sans attendre le moteur', () async {
      final attente = Completer<void>();
      b.activer(MoteurOcrFactice(texteParDefaut: texteLu, attente: attente.future));
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      final lancement = Stopwatch()..start();
      final f = b.ocr.traiterSuivant();
      expect(lancement.elapsedMilliseconds, lessThan(500), reason: 'lancer une lecture rend la main aussitôt : la file ne monopolise jamais le fil de l’interface');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sw = Stopwatch()..start();
      b.magasin.collection('courriers').inserer({'id': 'LIBRE', 'statut': 'actif', 'reference': 'ARR-LIBRE', 'objet': 'Saisie pendant la lecture'});
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(b.magasin.collection('courriers').parId('LIBRE'), isNotNull);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.ocrEnCours);
      attente.complete();
      await f;
    });

    test('la couche texte NATIVE prime : un PDF à texte n’entre jamais en file, et une lecture arrivée d’ailleurs ne l’écrase pas', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      await b.courrier('C1', fx('courrier-texte.pdf'), 'courrier-texte.pdf');
      final sha = b.sha('courriers', 'C1');
      expect(b.magasin.collection(ocrFile).toutes, isEmpty);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.indexe);
      expect(b.ocr.demander(sha, famille: 'courrier').refus!.code, CodeOcr.texteNatif);
      // une lecture arrive par la synchronisation pour ce même fichier
      b.magasin.collection(ocrLectures).appliquerDistante({
        'id': 'OCR-${sha.substring(0, 16)}-intrus00000a',
        'sha256': sha,
        'texteBrut': 'intrus',
        'texte': 'ocrintrusxyz',
        'nbMots': 1,
        'moteur': 'factice',
        'moteurVersion': '0.1',
        'langue': 'fra',
        'ocrLe': '2026-11-13T10:00:00.000Z',
      });
      final t = b.fp.texteDe(sha);
      expect(t, contains('hyperglycemie'));
      expect(t, isNot(contains('ocrintrusxyz')));
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.indexe);
      expect(m.appels, 0);
    });

    test('un texte lu est cherché sans accents ; la recherche dit qu’il est lu par machine ; l’indice nomme les pièces lues', () async {
      b.activer(MoteurOcrFactice(texteParDefaut: texteLu));
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      await b.ocr.vider();
      final sha = b.sha('courriers', 'C1');
      expect(fichierCorrespond(b.fp.texteDe(sha), 'HYPERGLYCEMIE'), isTrue);
      final lignes = b.magasin.collection('courriers').toutes;
      expect(b.ocr.noteRecherche('hyperglycemie', lignes, famille: 'courrier', role: 'admin'), contains('1 résultat trouvé dans un texte lu par machine'));
      expect(b.ocr.noteRecherche('zzzz', lignes, famille: 'courrier', role: 'admin'), isNull);
      expect(b.ocr.noteRecherche('', lignes, famille: 'courrier', role: 'admin'), isNull);
      expect(b.fp.indiceNonIndexe(lignes), contains('1 pièce ne se cherche que par un texte lu par machine, à vérifier.'));
    });
  });

  group('idempotence : une file par empreinte, jamais deux lectures', () {
    test('le même scan sur deux courriers : une ligne de file, une version, un seul appel du moteur ; un redémarrage ne relit rien', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      final octets = variante('scan.png', 5);
      await b.courrier('C1', octets, 'scan.png');
      await b.courrier('C2', octets, 'scan.png');
      expect(b.magasin.collection(ocrFile).toutes, hasLength(1));
      await b.ocr.vider();
      expect(b.magasin.collection(ocrLectures).toutes, hasLength(1));
      expect(m.appels, 1);
      // REDÉMARRAGE : un nouveau service sur le même magasin
      final autre = b.nouveauService();
      autre.enregistrer(m);
      expect(autre.balayer(), 0);
      expect(await autre.vider(), 0);
      expect(m.appels, 1);
      expect(b.magasin.collection(ocrLectures).toutes, hasLength(1));
      expect(b.magasin.collection(ocrFile).toutes, hasLength(1));
    });
    test('deux postes qui lisent le même scan avec le même moteur ne font qu’UNE version (identifiant déterministe, la garde refuse le doublon)', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      await b.courrier('C1', variante('scan.png', 6), 'scan.png');
      await b.ocr.vider();
      final v = b.ocr.versionsDe(b.sha('courriers', 'C1')).single;
      // l'autre poste a écrit la MÊME lecture : la fiche distante est identique, rien ne change
      final change = b.magasin.collection(ocrLectures).appliquerDistante({...v});
      expect(change, isFalse);
      expect(b.magasin.collection(ocrLectures).toutes, hasLength(1));
      expect(() => b.magasin.collection(ocrLectures).inserer({...v}), throwsA(isA<EcritureRefusee>()));
    });
  });

  group('la borne de temps, les refus nommés, la reprise après arrêt', () {
    test('un moteur qui ne répond pas dans le délai : ocr_echec DELAI_DEPASSE nommé ; le suivant est lu (un échec ne bloque pas la file)', () async {
      final jamais = Completer<void>();
      final m = MoteurOcrFactice(texteParDefaut: texteLu, attente: jamais.future);
      b.activer(m, delaiMs: 300);
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      b.magasin.horloge = () => DateTime.utc(2026, 10, 30, 10, 0, 1); // la file prend le plus ancien d'abord
      await b.courrier('C2', variante('scan.png', 2), 'scan.png');
      final r1 = await b.ocr.traiterSuivant();
      expect(r1.fait, isTrue);
      final f = b.magasin.collection(ocrFile).parId('OCQ-${b.sha('courriers', 'C1').substring(0, 16)}')!;
      expect(f['etat'], 'echec');
      expect(f['code'], CodeOcr.delaiDepasse);
      expect(f['raison'], contains('n’a pas répondu'));
      expect((f['geste'] as String).length, greaterThan(10));
      final e = b.ocr.etatDe(b.fichier('courriers', 'C1'));
      expect(e.etat, EtatIndexation.ocrEchec);
      expect(e.libelle, startsWith('Lecture OCR en échec : le moteur n’a pas répondu'));
      jamais.complete();
      final r2 = await b.ocr.traiterSuivant();
      expect(r2.fait, isTrue);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C2')).etat, EtatIndexation.ocrIndexe);
    });

    test('image illisible, aucun texte, échec non nommé, PDF sans rendeur : chaque refus est NOMMÉ avec son geste', () async {
      final cas = <(String, MoteurOcrFactice, Uint8List, String, String)>[
        ('illisible', MoteurOcrFactice(refus: ocrRefus(CodeOcr.imageIllisible, 'l’image est illisible')), variante('scan.png', 1), 'scan.png', CodeOcr.imageIllisible),
        ('vide', MoteurOcrFactice(texteParDefaut: '   '), variante('scan.png', 2), 'scan.png', CodeOcr.aucunTexte),
        ('pdf', MoteurOcrFactice(texteParDefaut: 'x'), fx('scan-image.pdf'), 'scan-image.pdf', CodeOcr.rendu),
        ('format', MoteurOcrFactice(texteParDefaut: 'x', formats: const ['png', 'jpeg']), variante('scan.webp', 3), 'scan.webp', CodeOcr.formatNonLu),
      ];
      var i = 0;
      for (final c in cas) {
        i++;
        final b2 = Banc(Directory.systemTemp.createTempSync('sigh-ocr-$i-'));
        try {
          b2.activer(c.$2);
          final dep = await b2.doc('D2', c.$3, c.$4);
          expect(dep.ok, isTrue, reason: '${c.$1} ${dep.refus}');
          await b2.ocr.vider();
          final f = b2.magasin.collection(ocrFile).toutes.single;
          expect(f['etat'], 'echec', reason: c.$1);
          expect(f['code'], c.$5, reason: c.$1);
          expect(f['geste'], isNotEmpty, reason: c.$1);
          expect(b2.magasin.collection(ocrLectures).toutes, isEmpty, reason: c.$1);
          expect(b2.ocr.etatDe(b2.fichier('documentsPatient', 'D2')).etat, EtatIndexation.ocrEchec, reason: c.$1);
        } finally {
          b2.ocr.arreter();
          b2.tmp.deleteSync(recursive: true);
        }
      }
    });

    test('reprise après arrêt : un traitement récent reste en cours, passé deux délais il est remis en attente puis lu, après trois essais il est en échec ESSAIS_EPUISES', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      final id = 'OCQ-${b.sha('courriers', 'C1').substring(0, 16)}';
      final col = b.magasin.collection(ocrFile);
      col.mettreAJour(id, {'etat': 'en_cours', 'debutLe': '2026-10-30T09:59:00.000Z', 'essais': 1}, journaliser: false);
      expect(b.ocr.reprendre(), 0);
      expect(col.parId(id)!['etat'], 'en_cours');
      col.mettreAJour(id, {'debutLe': '2026-10-30T08:00:00.000Z'}, journaliser: false);
      expect(b.ocr.reprendre(), 1);
      expect(col.parId(id)!['etat'], 'en_attente');
      expect(await b.ocr.vider(), 1);
      expect(b.ocr.etatDe(b.fichier('courriers', 'C1')).etat, EtatIndexation.ocrIndexe);
      await b.courrier('C2', variante('scan.png', 2), 'scan.png');
      final id2 = 'OCQ-${b.sha('courriers', 'C2').substring(0, 16)}';
      col.mettreAJour(id2, {'etat': 'en_cours', 'debutLe': '2026-10-30T08:00:00.000Z', 'essais': 3}, journaliser: false);
      expect(b.ocr.reprendre(), 1);
      expect(col.parId(id2)!['etat'], 'echec');
      expect(col.parId(id2)!['code'], CodeOcr.essaisEpuises);
    });

    test('lecture désactivée au réglage : le scan n’entre pas en file, l’état dit pourquoi', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      b.ocr.definirReglage(role: 'admin', actif: false, moteur: 'factice', langue: 'fra', motif: 'désactivation');
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      expect(b.magasin.collection(ocrFile).toutes, isEmpty);
      final e = b.ocr.etatDe(b.fichier('courriers', 'C1'));
      expect(e.etat, EtatIndexation.nonIndexe);
      expect(e.raison, 'la lecture OCR est désactivée au réglage');
    });
  });

  group('zone et droits', () {
    test('le texte lu d’un scan de zone 2 est de zone 2 : l’accueil n’en reçoit rien, et la file ÉCARTE ce scan sous son rôle', () async {
      final m = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m);
      b.role = 'medecin';
      expect((await b.doc('D1', variante('scan.png', 1), 'scan.png')).ok, isTrue);
      // lu sous un profil clinique
      expect(await b.ocr.vider(), 1);
      final sha = b.sha('documentsPatient', 'D1');
      b.role = 'medecin';
      expect(b.fp.texteDe(sha, famille: 'patient', type: 'Compte rendu médical'), contains('hyperglycemie'));
      b.role = 'reception';
      expect(b.fp.texteDe(sha, famille: 'patient', type: 'Compte rendu médical'), '', reason: 'zone 2 : l’accueil ne lit pas ce texte');
      expect(b.fp.texteDe(sha, famille: 'patient', type: 'Pièce d’identité'), contains('hyperglycemie'), reason: 'la règle suit la ZONE du type, pas le fichier');
      // une seconde pièce de zone 2, en file : l'accueil ne la traite pas
      b.role = 'medecin';
      expect((await b.doc('D1', variante('scan.png', 9), 'scan.png')).ok, isTrue, reason: 'remplacement par un second scan');
      // (la file du second scan a été constituée sous le médecin) : on la vide sous l'accueil
      b.role = 'reception';
      final avant = m.appels;
      final r = await b.ocr.traiterSuivant();
      expect(r.fait, isFalse);
      expect(r.ecarte, anyOf('ZONE_REFUSEE', 'DROIT_REFUSE'));
      expect(m.appels, avant, reason: 'le moteur n’est pas appelé pour un scan que ce profil ne lit pas');
      expect(b.magasin.collection(ocrFile).toutes.where((f) => f['etat'] == 'en_attente'), hasLength(1));
      // changer de session ne laisse pas à l'agent suivant les écarts du précédent : le médecin traite ce scan
      b.role = 'medecin';
      expect(await b.ocr.vider(), 1);
      expect(b.ocr.etatDe(b.fichier('documentsPatient', 'D1')).etat, EtatIndexation.ocrIndexe);
      expect(m.appels, avant + 1);
    });

    test('la relance suit le droit d’ÉCRIRE de l’écran : offerte au médecin, absente pour l’anesthésiste qui lit la zone 2 sans y écrire ; le moteur refuse aussi (DROIT_REFUSE)', () async {
      b.activer(MoteurOcrFactice(texteParDefaut: texteLu));
      b.role = 'medecin';
      await b.doc('D1', variante('scan.png', 1), 'scan.png');
      await b.ocr.vider();
      final x = b.fichier('documentsPatient', 'D1');
      final peutMedecin = droit('medecin', 'm1-documents').editer;
      final peutAnesth = droit('anesthesiste', 'm1-documents').editer;
      expect(peutMedecin, isTrue);
      expect(peutAnesth, isFalse);
      expect(b.ocr.relancePossible(x, peutDeposer: peutMedecin), isTrue);
      expect(b.ocr.relancePossible(x, peutDeposer: peutAnesth), isFalse);
      final refus = b.ocr.relancer(x, peutDeposer: peutAnesth, famille: 'patient', type: 'Compte rendu médical');
      expect(refus.refus!.code, CodeOcr.droitRefuse);
    });
  });

  group('relance : une NOUVELLE version, l’ancienne reste lisible', () {
    test('un autre texte AJOUTE une version (la courante change, la première intacte) ; le même résultat ne crée rien ; une lecture ne se réécrit pas', () async {
      final m1 = MoteurOcrFactice(texteParDefaut: texteLu);
      b.activer(m1);
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      await b.ocr.vider();
      final sha = b.sha('courriers', 'C1');
      final x = b.fichier('courriers', 'C1');
      expect(b.ocr.relancePossible(x, peutDeposer: true), isTrue);
      // un nouveau moteur (autre texte), même identifiant de moteur : une nouvelle version datée
      b.ocr.enregistrer(MoteurOcrFactice(texteParDefaut: 'Seconde lecture : paludisme grave à Tanguiéta'));
      b.magasin.horloge = () => DateTime.utc(2026, 10, 31, 10);
      expect(b.ocr.relancer(x, peutDeposer: true, famille: 'courrier').ok, isTrue);
      expect(await b.ocr.vider(), 1);
      final vs = b.ocr.versionsDe(sha);
      expect(vs, hasLength(2));
      expect(vs[0]['texteBrut'], texteLu, reason: 'l’ancienne reste lisible, inchangée');
      expect(vs[1]['texteBrut'], 'Seconde lecture : paludisme grave à Tanguiéta');
      expect(vs[1]['declencheur'], 'relance');
      expect(b.ocr.versionCourante(sha)!['id'], vs[1]['id']);
      expect(fichierCorrespond(b.fp.texteDe(sha), 'paludisme'), isTrue);
      expect(fichierCorrespond(b.fp.texteDe(sha), 'hyperglycemie'), isFalse, reason: 'la recherche lit la version courante');
      // le MÊME résultat : aucune troisième version
      b.magasin.horloge = () => DateTime.utc(2026, 11, 1, 10);
      expect(b.ocr.relancer(x, peutDeposer: true, famille: 'courrier').ok, isTrue);
      expect(await b.ocr.vider(), 1);
      expect(b.ocr.versionsDe(sha), hasLength(2));
      // une lecture ne se réécrit ni ne s'archive
      final id = '${vs[0]['id']}';
      expect(() => b.magasin.collection(ocrLectures).mettreAJour(id, {'texteBrut': 'réécrit'}), throwsA(isA<EcritureRefusee>()));
      expect(() => b.magasin.collection(ocrLectures).archiver(id), throwsA(isA<EcritureRefusee>()));
      expect(b.magasin.collection(ocrLectures).parId(id)!['texteBrut'], texteLu);
    });
  });

  group('journal RG-12', () {
    test('chaque demande, chaque lecture, chaque relance et chaque réglage sont au journal', () async {
      b.activer(MoteurOcrFactice(texteParDefaut: texteLu));
      await b.courrier('C1', variante('scan.png', 1), 'scan.png');
      await b.ocr.vider();
      b.ocr.relancer(b.fichier('courriers', 'C1'), peutDeposer: true, famille: 'courrier');
      expect(b.audit('Réglage de la lecture OCR des scans'), hasLength(1));
      expect(b.audit('Lecture OCR demandée'), hasLength(1));
      expect(b.audit('Lecture OCR commencée'), hasLength(1));
      expect(b.audit('Lecture OCR d’un scan'), hasLength(1));
      expect(b.audit('Lecture OCR terminée'), hasLength(1));
      expect(b.audit('Relance de la lecture OCR'), hasLength(1));
      expect(b.audit('Lecture OCR d’un scan').single['utilisateur'], 'Agent Test');
    });
  });
}
