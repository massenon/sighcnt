import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LES FICHIERS NUMÉRISÉS AU POSTE (lot D5, étape 3) : dépôt, refus nommés, retrait annulable, lecture avec empreinte vérifiée, taille maximale, recherche dans le texte indexé,
/// état d'un fichier absent. Le disque est réel (dossier temporaire), la matrice des droits est celle de `rbac.json`.
const fixtures = 'test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();
final donnees = DonneesNavigation.depuisDossier();
Droit droit(String role, String ecran) => donnees.matrice.droit(role, ecran);

class Banc {
  Banc(this.tmp, {List<int>? cle}) {
    magasin = Magasin({
      'courriers': [
        {'id': 'C1', 'statut': 'actif', 'reference': 'ARR-2026-0042', 'sens': 'arrivee', 'date': '2026-08-20', 'correspondant': 'Préfecture', 'objet': 'Convocation', 'observations': 'Urgent'},
        {'id': 'C2', 'statut': 'actif', 'reference': 'DEP-2026-0003', 'sens': 'depart', 'date': '2026-09-01', 'correspondant': 'ARS', 'objet': 'Rapport'},
        {'id': 'C3', 'statut': 'archive', 'reference': 'ARR-2026-0043', 'sens': 'arrivee', 'date': '2026-08-21'},
      ],
      'documentsPatient': [
        {'id': 'D1', 'statut': 'actif', 'reference': 'GED-00007', 'patientId': 'P1', 'code': 'CNT/12/26', 'type': 'Compte rendu médical', 'date': '2026-08-12'},
        {'id': 'D2', 'statut': 'actif', 'reference': 'GED-00008', 'patientId': 'P1', 'code': 'CNT/12/26', 'type': 'Pièce d’identité', 'date': '2026-08-12'},
        {'id': 'D3', 'statut': 'actif', 'reference': 'GED-00009', 'patientId': 'P2', 'code': 'CNT/13/26', 'type': 'Facture', 'date': '2026-08-13'},
      ],
      'audit': const [],
    }, 'POSTE')
      ..utilisateur = 'Agent Test';
    magasin.horloge = () => DateTime.utc(2026, 10, 30, 10);
    stockage = StockageFichiers('${tmp.path}/fichiers', cle: cle);
    fp = FichiersPoste(magasin, stockage)..installer();
  }
  final Directory tmp;
  late final Magasin magasin;
  late final StockageFichiers stockage;
  late final FichiersPoste fp;

  Future<ResultatFichier> deposerCourrier(String id, String nom, {String role = 'admin', Uint8List? octets, bool remplacer = false, Future<bool> Function(FicheDoc)? confirmer}) =>
      fp.deposer(famille: 'courrier', ficheId: id, nom: nom, octets: octets ?? fx(nom), role: role, droit: droit(role, 'm13-courriers'), remplacer: remplacer, confirmerAutre: confirmer);
  Future<ResultatFichier> deposerDoc(String id, String nom, {String role = 'admin', Uint8List? octets, String? patient, Future<bool> Function(FicheDoc)? confirmer}) => fp.deposer(
      famille: 'patient', ficheId: id, nom: nom, octets: octets ?? fx(nom), role: role, droit: droit(role, 'm1-documents'), portee: patient == null ? null : (f) => f['patientId'] == patient, confirmerAutre: confirmer);
  List<Map<String, Object?>> audit(String action) => [for (final f in magasin.collection('audit').toutes) if (f['action'] == action) f];
}

void main() {
  late Directory tmp;
  late Banc b;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-fp-');
    b = Banc(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('dépôt', () {
    test('un PDF à couche texte : rangé sous son empreinte, fiche mise à jour, nom normalisé recalculé, texte indexé, journal RG-12, annulable', () async {
      final r = await b.deposerCourrier('C1', 'courrier-texte.pdf');
      expect(r.ok, isTrue, reason: '${r.refus}');
      final f = fichierDe(b.magasin.collection('courriers').parId('C1'))!;
      expect(f['sha256'], sha256Octets(fx('courrier-texte.pdf')));
      expect(f['nomNormalise'], '2026-08-20_ARR_0042.pdf');
      expect(f['nom'], 'courrier-texte.pdf');
      expect(f['mime'], 'application/pdf');
      expect(f['pages'], 1);
      expect(f['texteIndexe'], isTrue);
      expect(f['deposePar'], 'Agent Test');
      expect(courrierNumerise(b.magasin.collection('courriers').parId('C1')), isTrue);
      expect(await b.stockage.lire('${f['sha256']}'), fx('courrier-texte.pdf'));
      // le registre par empreinte : une fiche, avec le texte normalisé, sans compteur
      final reg = b.magasin.collection('fichiers').parId(fichierIdRegistre('${f['sha256']}'))!;
      expect(reg['texte'], contains('hyperglycemie'));
      expect(reg.containsKey('nbReferences'), isFalse);
      // le journal
      final j = b.audit('Dépôt d’un fichier numérisé').single;
      expect(j['utilisateur'], 'Agent Test');
      expect(j['reference'], 'ARR-2026-0042');
      expect(j['module'], 'M13');
      // l'annulation remet la fiche « sans pièce » (la clé ajoutée est retirée)
      r.annuler!();
      expect(b.magasin.collection('courriers').parId('C1')!['fichier'], isNull, reason: '`fichier: null` explicite : une clé retirée ne se propage pas à la synchronisation');
      expect(courrierNumerise(b.magasin.collection('courriers').parId('C1')), isFalse);
    });

    test('une image : pas de couche texte, dit « texte non indexé » ; WEBP admis au dossier patient seulement', () async {
      expect((await b.deposerCourrier('C1', 'scan.png')).ok, isTrue);
      expect(fichierDe(b.magasin.collection('courriers').parId('C1'))!['texteIndexe'], isFalse);
      final w = await b.deposerCourrier('C2', 'scan.webp');
      expect(w.refus!.code, 'FORMAT_REFUSE');
      expect((await b.deposerDoc('D3', 'scan.webp')).ok, isTrue);
    });

    test('refus NOMMÉS : format lu sur les octets, extension mensongère, vide, taille, fiche archivée, fiche inconnue', () async {
      expect((await b.deposerCourrier('C1', 'faux.exe')).refus!.code, 'FORMAT_REFUSE');
      final m = await b.deposerCourrier('C1', 'camoufle.pdf', octets: fx('scan.png'));
      expect(m.refus!.code, 'FORMAT_REFUSE');
      expect(m.refus!.motif, contains('l’extension ne suffit pas'));
      expect((await b.deposerCourrier('C1', 'vide.pdf', octets: Uint8List(0))).refus!.code, 'FICHIER_VIDE');
      expect((await b.deposerCourrier('C3', 'scan.png')).refus!.code, 'FICHE_ARCHIVEE');
      expect((await b.deposerCourrier('ABSENT', 'scan.png')).refus!.code, 'FICHE_INTROUVABLE');
      // rien n'a été écrit
      expect(await b.stockage.empreintes().toList(), isEmpty);
      expect(b.magasin.collection('fichiers').toutes, isEmpty);
    });

    test('taille maximale RÉGLÉE EN BASE : réservée à l’administrateur et à la DAF, motivée, bornée, appliquée au dépôt suivant', () async {
      expect(b.fp.tailleMax(), fichierTailleDefaut);
      expect(b.fp.tailleMaxReglee, isFalse);
      expect(b.fp.definirTailleMax(role: 'caissier', octets: 200 * 1024, motif: 'x').refus!.code, 'REGLAGE_RESERVE');
      expect(b.fp.definirTailleMax(role: 'admin', octets: 200 * 1024, motif: '').refus!.code, 'MOTIF_REQUIS');
      expect(b.fp.definirTailleMax(role: 'admin', octets: 10, motif: 'x').refus!.code, 'TAILLE_INVALIDE');
      expect(b.fp.definirTailleMax(role: 'da', octets: 100 * 1024, motif: 'Scans plus légers').ok, isTrue);
      expect(b.fp.tailleMax(), 100 * 1024);
      expect(b.fp.tailleMaxReglee, isTrue);
      final r = await b.deposerCourrier('C1', 'scan.png');
      expect(r.ok, isTrue, reason: 'scan.png (20 Ko) passe sous 100 Ko');
      final gros = Uint8List.fromList([...fx('courrier-texte.pdf'), ...List.filled(150 * 1024, 32)]);
      final g = await b.deposerCourrier('C2', 'gros.pdf', octets: gros);
      expect(g.refus!.code, 'TAILLE_DEPASSEE');
      expect(g.refus!.motif, contains('100 Ko'));
      expect(b.audit('Taille maximale d’un fichier numérisé').length, 1);
      // retirer le réglage : le défaut de 10 Mo admet le fichier de 150 Ko
      b.magasin.collection('reglages').mettreAJour('documentsBornes', {'valeur': null}, journaliser: false);
      expect(b.fp.tailleMax(), fichierTailleDefaut);
      expect((await b.deposerCourrier('C2', 'gros.pdf', octets: gros)).ok, isTrue);
    });

    test('DROITS : le caissier ne dépose pas de courrier, l’accueil dépose un courrier et une pièce d’identité mais pas un compte rendu (RG-13)', () async {
      expect((await b.deposerCourrier('C1', 'scan.png', role: 'caissier')).refus!.code, 'DROIT_REFUSE');
      expect((await b.deposerCourrier('C1', 'scan.png', role: 'reception')).ok, isTrue);
      expect((await b.deposerDoc('D2', 'scan.png', role: 'reception')).ok, isTrue);
      final r = await b.deposerDoc('D1', 'scan.jpg', role: 'reception');
      expect(r.refus!.code, 'ZONE_REFUSEE');
      expect(r.refus!.motif, contains('RG-13'));
      expect(fichierDe(b.magasin.collection('documentsPatient').parId('D1')), isNull);
      expect((await b.deposerDoc('D1', 'scan.jpg', role: 'medecin')).ok, isTrue);
    });

    test('DOUBLON : le même fichier sur la même fiche ou dans le même dossier est refusé en nommant la pièce ; sur une autre fiche, l’agent confirme', () async {
      expect((await b.deposerCourrier('C1', 'scan.png')).ok, isTrue);
      final d = await b.deposerCourrier('C1', 'scan.png');
      expect(d.refus!.code, 'DOUBLON_MEME_FICHE');
      expect(d.refus!.motif, contains('ARR-2026-0042 (2026-08-20_ARR_0042.png)'));
      // autre fiche : sans confirmation, annulé ; avec, rattaché et le registre garde UNE fiche pour l'empreinte
      expect((await b.deposerCourrier('C2', 'scan.png')).refus!.code, 'DEPOT_ANNULE');
      FicheDoc? vu;
      final c = await b.deposerCourrier('C2', 'scan.png', confirmer: (a) async {
        vu = a;
        return true;
      });
      expect(c.ok, isTrue);
      expect(vu!['reference'], 'ARR-2026-0042');
      expect(c.avertissementDoublon, isNotNull);
      expect(b.magasin.collection('fichiers').toutes.length, 1, reason: 'une fiche par empreinte, jamais deux');
      expect((await b.stockage.empreintes().toList()).length, 1, reason: 'une seule copie sur le disque');
      expect(fichierNbReferences(b.magasin.collection('courriers').toutes, sha256Octets(fx('scan.png'))), 2);
      // dossier patient : même fichier dans le même dossier
      expect((await b.deposerDoc('D1', 'scan.jpg', patient: 'P1')).ok, isTrue);
      final dd = await b.deposerDoc('D2', 'scan.jpg', patient: 'P1');
      expect(dd.refus!.code, 'DOUBLON_MEME_FICHE');
      expect(dd.refus!.motif, contains('ce dossier'));
    });

    test('REMPLACER : l’ancienne pièce est RETIRÉE de la fiche (historique), jamais supprimée du disque ; le même fichier est refusé', () async {
      expect((await b.deposerCourrier('C1', 'scan.png')).ok, isTrue);
      expect((await b.deposerCourrier('C1', 'scan.png', remplacer: true)).refus!.code, 'DOUBLON_MEME_FICHE');
      final r = await b.deposerCourrier('C1', 'scan.jpg', remplacer: true);
      expect(r.ok, isTrue);
      final fiche = b.magasin.collection('courriers').parId('C1')!;
      expect(fichierDe(fiche)!['sha256'], sha256Octets(fx('scan.jpg')));
      final hist = fiche['fichiersRetires'] as List;
      expect(hist.length, 1);
      expect((hist.single as Map)['sha256'], sha256Octets(fx('scan.png')));
      expect((hist.single as Map)['motif'], 'Remplacée par un autre fichier');
      expect(await b.stockage.existe(sha256Octets(fx('scan.png'))), isTrue, reason: 'RG-14 : l’ancien fichier reste sur le disque');
      // annuler le remplacement remet la première pièce
      r.annuler!();
      final apres = b.magasin.collection('courriers').parId('C1')!;
      expect(fichierDe(apres)!['sha256'], sha256Octets(fx('scan.png')));
    });
  });

  group('retrait (RG-14)', () {
    test('le retrait n’efface RIEN : fichier au disque, empreinte à l’historique de la fiche et au journal, droit d’ANNULER requis, annulable', () async {
      await b.deposerCourrier('C1', 'scan.png');
      final sha = sha256Octets(fx('scan.png'));
      // l'accueil a le droit d'écrire le registre des courriers mais pas d'annuler
      final refus = b.fp.retirer(famille: 'courrier', ficheId: 'C1', motif: 'x', role: 'reception', droit: droit('reception', 'm13-courriers'));
      expect(refus.refus!.code, 'DROIT_REFUSE');
      expect(fichierDe(b.magasin.collection('courriers').parId('C1')), isNotNull);
      final r = b.fp.retirer(famille: 'courrier', ficheId: 'C1', motif: 'Mauvais scan, à refaire', role: 'admin', droit: droit('admin', 'm13-courriers'));
      expect(r.ok, isTrue);
      final fiche = b.magasin.collection('courriers').parId('C1')!;
      expect(fichierDe(fiche), isNull);
      expect(courrierNumerise(fiche), isFalse);
      expect((fiche['fichiersRetires'] as List).single['sha256'], sha);
      expect(await b.stockage.existe(sha), isTrue);
      expect(await b.stockage.lire(sha), fx('scan.png'));
      final j = b.audit('Pièce numérisée retirée de la fiche').single;
      expect((j['avant'] as Map)['empreinte'], docAbrege(sha));
      r.annuler!();
      expect(fichierDe(b.magasin.collection('courriers').parId('C1'))!['sha256'], sha);
      expect(b.magasin.collection('courriers').parId('C1')!['fichiersRetires'], isEmpty);
      // une fiche sans pièce ne se retire pas
      expect(b.fp.retirer(famille: 'courrier', ficheId: 'C2', motif: 'x', role: 'admin', droit: droit('admin', 'm13-courriers')).refus!.code, 'SANS_PIECE');
    });
  });

  group('lecture', () {
    test('un fichier lu a son empreinte vérifiée ; un fichier altéré n’est JAMAIS servi et le refus nomme l’empreinte ; la lecture est journalisée', () async {
      await b.deposerCourrier('C1', 'scan.png');
      final fiche = b.magasin.collection('courriers').parId('C1')!;
      final ok = await b.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'));
      expect(ok.ok, isTrue);
      expect(ok.octets, fx('scan.png'));
      expect(ok.nom, '2026-08-20_ARR_0042.png');
      expect(b.audit('Consultation d’un document numérisé').length, 1);
      await b.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'), usage: 'telechargement');
      expect(b.audit('Téléchargement d’un document numérisé').length, 1);
      // altération sur le disque
      final sha = sha256Octets(fx('scan.png'));
      final f = File((await b.stockage.cheminDe(sha))!);
      final x = f.readAsBytesSync()..[100] ^= 0xff;
      f.writeAsBytesSync(x);
      final fraiche = Banc(tmp)..magasin.collection('courriers');
      final r = await fraiche.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'));
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'FICHIER_ALTERE');
      expect(r.refus!.motif, contains(docAbrege(sha)));
      expect(r.octets, isNull);
      expect(await fraiche.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.altere);
    });

    test('RG-13 : l’accueil ne LIT pas un compte rendu ; le caissier ne lit pas le registre des courriers', () async {
      await b.deposerDoc('D1', 'scan.png', role: 'medecin');
      final d1 = b.magasin.collection('documentsPatient').parId('D1')!;
      final r = await b.fp.lire(famille: 'patient', fiche: d1, role: 'reception', droit: droit('reception', 'm1-documents'));
      expect(r.refus!.code, 'ZONE_REFUSEE');
      expect(r.octets, isNull);
      expect((await b.fp.lire(famille: 'patient', fiche: d1, role: 'medecin', droit: droit('medecin', 'm1-documents'))).ok, isTrue);
      await b.deposerCourrier('C1', 'scan.png');
      final c1 = b.magasin.collection('courriers').parId('C1')!;
      expect((await b.fp.lire(famille: 'courrier', fiche: c1, role: 'caissier', droit: droit('caissier', 'm13-courriers'))).refus!.code, 'DROIT_REFUSE');
      expect(await b.fp.etat(famille: 'patient', fiche: d1, role: 'reception'), EtatFichierPoste.zoneRefusee);
    });

    test('état d’un fichier dont la fiche est arrivée avant lui : en cours de transfert (mère joignable) ou non disponible hors ligne, jamais une erreur', () async {
      final fiche = {
        'id': 'C9', 'statut': 'actif', 'reference': 'ARR-2026-0099', 'date': '2026-08-20',
        'fichier': {'sha256': 'ab' * 32, 'nom': 'x.pdf', 'nomNormalise': '2026-08-20_ARR_0099.pdf', 'mime': 'application/pdf'},
      };
      expect(await b.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.nonDisponibleHorsLigne, reason: 'poste autonome : pas de mère, le fichier n’est pas disponible hors ligne');
      final lu = await b.fp.lire(famille: 'courrier', fiche: fiche, role: 'admin', droit: droit('admin', 'm13-courriers'));
      expect(lu.refus!.code, 'FICHIER_ABSENT');
      b.fp.transfert = _Mere(joignable: true, enCours: {'ab' * 32});
      expect(await b.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.enCoursDeTransfert);
      b.fp.transfert = _Mere(joignable: false, enCours: {});
      expect(await b.fp.etat(famille: 'courrier', fiche: fiche, role: 'admin'), EtatFichierPoste.nonDisponibleHorsLigne);
      expect(await b.fp.etat(famille: 'courrier', fiche: {'id': 'C8'}, role: 'admin'), EtatFichierPoste.sansFichier);
    });
  });

  group('recherche dans le texte indexé', () {
    test('un mot du corps d’un PDF retrouve la pièce (sans accent ni casse) ; une image est dite « non indexée »', () async {
      await b.deposerCourrier('C1', 'courrier-texte.pdf');
      await b.deposerCourrier('C2', 'scan.png');
      final c1 = b.magasin.collection('courriers').parId('C1')!, c2 = b.magasin.collection('courriers').parId('C2')!;
      expect(fichierCorrespond(b.fp.texteRecherche(c1), 'HYPERGLYCEMIE'), isTrue);
      expect(fichierCorrespond(b.fp.texteRecherche(c1), 'amoxicilline'), isTrue);
      expect(fichierCorrespond(b.fp.texteRecherche(c2), 'amoxicilline'), isFalse);
      expect(fichierCorrespond(b.fp.texteRecherche(c1), 'urgent'), isTrue, reason: 'les observations sont lues aussi');
      expect(fichierCorrespond(b.fp.texteRecherche(c1), '20/08/2026'), isTrue);
      expect(b.fp.indiceNonIndexe(b.magasin.collection('courriers').toutes), startsWith('1 pièce numérisée n’a pas de texte indexé'));
      expect(b.fp.indiceNonIndexe([c1]), isNull);
    });
  });

  group('au repos', () {
    test('avec la clé du poste, le fichier rangé n’est pas en clair sur le disque', () async {
      final c = Banc(tmp, cle: List<int>.generate(32, (i) => i));
      await c.deposerCourrier('C1', 'scan.png');
      final sha = sha256Octets(fx('scan.png'));
      final brut = File((await c.stockage.cheminDe(sha))!).readAsBytesSync();
      expect(brut, isNot(fx('scan.png')));
      expect(c.stockage.chiffre, isTrue);
      expect(await c.stockage.lire(sha), fx('scan.png'));
    });
  });
}

class _Mere implements EtatTransfertFichiers {
  _Mere({required this.joignable, required Set<String> enCours}) : encours = enCours;
  final bool joignable;
  final Set<String> encours;
  @override
  bool enCours(String sha) => encours.contains(sha);
  @override
  bool get mereJoignable => joignable;
}
