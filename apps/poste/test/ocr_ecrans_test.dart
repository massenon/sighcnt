import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/fichiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart' show FichierChoisi;
import 'package:sigh_poste/donnees/ocr_poste.dart';
import 'package:sigh_poste/kit/fichiers_ui.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_sync/sigh_sync.dart';


/// LA LECTURE OCR AUX ÉCRANS (lot OCR-prep) : l'état d'indexation de la pièce (badge de la carte, petit mot de la ligne), le marquage « lu par machine, à vérifier », la commande « Relancer la lecture »
/// ABSENTE sans le droit et sans moteur prêt, le message sous « Aucun résultat », la note de recherche, le réglage réservé à l'administrateur et à la DAF. AUCUN moteur réel : un moteur FACTICE.
const fixtures = 'test/fixtures/fichiers';
Uint8List fx(String n) => File('$fixtures/$n').readAsBytesSync();
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30, 10);

class LecteurFactice implements LecteurPdf {
  Uint8List? recu;
  String? nom;
  @override
  Widget construire(BuildContext context, {required Uint8List octets, required String nom, required String titre}) {
    recu = octets;
    this.nom = nom;
    return Text('LECTEUR PDF FACTICE : $nom (${octets.length} octets)', key: const Key('lecteur-factice'));
  }
}

Magasin poste(Map<String, List<Map<String, Object?>>> collections) => Magasin({
      'audit': const [],
      'personnel': const [],
      'patients': const [],
      for (final e in collections.entries) e.key: [for (final x in e.value) {...x}],
    }, 'POSTE')
      ..utilisateur = 'Agent Test'
      ..horloge = () => DateTime.utc(2026, 10, 30, 10);

List<Map<String, Object?>> courriers() => [
      {'id': 'C1', 'statut': 'actif', 'reference': 'ARR-2026-0001', 'sens': 'arrivee', 'date': '2026-08-20', 'correspondant': 'Préfecture', 'objet': 'Convocation', 'nature': 'Lettre', 'affecteA': 'Direction Médicale', 'traitement': 'en_attente'},
      {'id': 'C2', 'statut': 'actif', 'reference': 'DEP-2026-0002', 'sens': 'depart', 'date': '2026-09-01', 'correspondant': 'ARS', 'objet': 'Rapport', 'nature': 'Rapport', 'affecteA': 'Direction Administrative', 'traitement': 'traite'},
    ];

List<Map<String, Object?>> documents() => [
      {'id': 'D1', 'statut': 'actif', 'reference': 'GED-00001', 'patientId': 'P1', 'code': 'CNT/1/26', 'patient': 'ADJOVI Paul', 'type': 'Compte rendu médical', 'date': '2026-08-12', 'etat': 'valide', 'depose': 'X'},
      {'id': 'D2', 'statut': 'actif', 'reference': 'GED-00002', 'patientId': 'P1', 'code': 'CNT/1/26', 'patient': 'ADJOVI Paul', 'type': 'Pièce d’identité', 'date': '2026-08-12', 'etat': 'valide', 'depose': 'X'},
    ];

Future<void> attendreIo(WidgetTester t, {int tours = 25}) async {
  for (var i = 0; i < tours; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> chercher(WidgetTester t, String q) async {
  await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, q);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> toucher(WidgetTester t, Finder f) async {
  // Au milieu de la zone visible : le pied de page de la coque masque le bas de l'écran.
  final el = f.evaluate().first;
  if (Scrollable.maybeOf(el) != null) await Scrollable.ensureVisible(el, alignment: 0.4);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 200));
  await t.pump(const Duration(milliseconds: 600));
}

/// Un cas de widget : à la fin, l'arbre est démonté et le temps avance au-delà des toasts (aucun minuteur ne reste en attente).
void cas(String description, Future<void> Function(WidgetTester) corps) => testWidgets(description, (t) async {
      await corps(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
    });

Future<void> fermerTiroir(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byKey(const Key('kit:tiroir-panneau')), matching: find.byTooltip('Fermer')).last);
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> fermerModale(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.byTooltip('Fermer')).last);
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 600));
}


const texteLu = 'Hyperglycémie sévère : père déjà traité à Natitingou, œuf de ç';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-ocr-ecr-');
  });
  tearDown(() {
    SelecteursFichiers.reinitialiser();
    tmp.deleteSync(recursive: true);
  });

  (FichiersPoste, OcrPoste) brancher(Magasin m, String Function() role, {bool fileul = false}) {
    final fp = FichiersPoste(m, StockageFichiers('${tmp.path}/fichiers'))..installer();
    final o = OcrPoste(fp, roleCourant: role, droitDe: (r, e) => donnees.matrice.droit(r, e), gesteDe: (r, g) => donnees.matrice.droitGeste(r, g), estFileul: () => fileul)
      ..automatique = false
      ..installer();
    return (fp, o);
  }

  void choisit(String nom, [Uint8List? octets]) => SelecteursFichiers.choisir = () async => FichierChoisi(nom, octets ?? fx(nom));

  group('réglage de clinique sur un fileul : il se lit, il ne se pose pas', () {
    cas('un fileul dont la mère n’a rien publié : « pas encore reçu » est DIT, la commande Enregistrer est ABSENTE ;', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m, () => 'admin', fileul: true);
      await ouvrir(t, m, 'm13-courriers');
      await toucher(t, find.byKey(const Key('ocr:bouton-reglage')));
      expect(find.byKey(const Key('ocr:reglage-recu')), findsOneWidget);
      expect(find.textContaining('pas encore reçu de le poste mère'), findsOneWidget);
      expect(find.byKey(const Key('ocr:enregistrer')), findsNothing, reason: 'commande ABSENTE sur un fileul, jamais grisée');
      expect(find.byKey(const Key('ocr:actif')), findsNothing);
    });
  });

  group('sans moteur : l’écran le dit', () {
    cas('un scan : badge « Texte non indexé », raison « aucun moteur d’OCR installé sur ce poste », AUCUNE commande de relance, message sous « Aucun résultat » avec le bon nombre', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m, () => 'admin');
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('ocr:etat-non_indexe')), findsOneWidget);
      expect(find.textContaining('Texte non indexé : aucun moteur d’OCR installé sur ce poste.'), findsOneWidget);
      expect(find.byKey(const Key('ocr:relancer')), findsNothing, reason: 'commande ABSENTE sans moteur, pas grisée');
      expect(m.collection(ocrFile).toutes, isEmpty);
      expect(m.collection(ocrLectures).toutes, isEmpty);
      await fermerTiroir(t);
      expect(find.byKey(const Key('ocr:ligne-non_indexe')), findsOneWidget);
      expect(find.text('texte non indexé'), findsOneWidget);
      await chercher(t, 'zzzintrouvable');
      expect(find.textContaining('1 pièce sans texte lu : aucun moteur d’OCR installé sur ce poste.'), findsOneWidget);
      expect(find.textContaining('image sans couche texte'), findsOneWidget);
    });

    cas('le réglage : le bouton est PRÉSENT pour l’administrateur, activer sans moteur est refusé en le nommant (MOTEUR_ABSENT)', (t) async {
      final m = poste({'courriers': courriers()});
      final (_, o) = brancher(m, () => 'admin');
      await ouvrir(t, m, 'm13-courriers');
      expect(find.byKey(const Key('ocr:bouton-reglage')), findsOneWidget);
      await toucher(t, find.byKey(const Key('ocr:bouton-reglage')));
      expect(find.byKey(const Key('ocr:reglage-note')), findsOneWidget);
      expect(find.textContaining('Aucun moteur d’OCR installé sur ce poste.'), findsWidgets);
      await toucher(t, find.byKey(const Key('ocr:actif')));
      await t.enterText(find.byKey(const Key('ocr:motif')), 'essai de sonde');
      await toucher(t, find.byKey(const Key('ocr:enregistrer')));
      expect(find.byKey(const Key('ocr:reglage-refus')), findsOneWidget);
      expect(find.textContaining('MOTEUR_ABSENT'), findsOneWidget);
      expect(o.reglage.actif, isFalse);
    });

    cas('le bouton de réglage est ABSENT pour un profil qui ne règle pas (agent administratif)', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m, () => 'agentadmin');
      await ouvrir(t, m, 'm13-courriers', role: 'agentadmin');
      expect(find.byKey(const Key('ocr:bouton-reglage')), findsNothing);
    });
  });

  group('moteur factice : lu par machine, à vérifier', () {
    cas('le scan est lu : badge, marquage, historique, petit mot de la ligne, recherche sans accent avec la note « trouvé dans un texte lu par machine », relance offerte', (t) async {
      final m = poste({'courriers': courriers()});
      final (_, o) = brancher(m, () => 'admin');
      final moteur = MoteurOcrFactice(texteParDefaut: texteLu);
      o.enregistrer(moteur);
      expect(o.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: 'sonde').ok, isTrue);
      o.arreter();
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('ocr:etat-ocr_en_attente')), findsOneWidget, reason: 'déposé : en attente (la file tourne un fichier à la fois)');
      o.arreter();
      await t.runAsync(() => o.vider());
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ocr:etat-ocr_indexe')), findsOneWidget);
      expect(find.byKey(const Key('ocr:marque')), findsOneWidget);
      expect(find.textContaining('La reconnaissance de caractères peut se tromper'), findsOneWidget);
      expect(find.byKey(const Key('ocr:historique-1')), findsOneWidget);
      expect(find.byKey(const Key('ocr:relancer')), findsOneWidget, reason: 'moteur prêt, droit d’écrire, texte lu : la relance est offerte');
      await fermerTiroir(t);
      expect(find.text('texte lu par machine, à vérifier'), findsOneWidget);
      await chercher(t, 'HYPERGLYCEMIE');
      expect(find.text('ARR-2026-0001'), findsOneWidget);
      expect(find.byKey(const Key('kit:note-recherche')), findsOneWidget);
      expect(find.textContaining('1 résultat trouvé dans un texte lu par machine'), findsOneWidget);
      await chercher(t, 'ARR-2026-0001');
      expect(find.byKey(const Key('kit:note-recherche')), findsNothing, reason: 'une recherche qui ne passe pas par le texte lu n’affiche aucun bandeau');
      expect(moteur.appels, 1);
    });

    cas('un PDF à couche texte n’est pas lu par machine : état « Texte indexé », aucun bloc OCR, aucune relance', (t) async {
      final m = poste({'courriers': courriers()});
      final (_, o) = brancher(m, () => 'admin');
      final moteur = MoteurOcrFactice(texteParDefaut: texteLu);
      o.enregistrer(moteur);
      o.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: 'sonde');
      o.arreter();
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('courrier-texte.pdf');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('ocr:etat-indexe')), findsOneWidget);
      expect(find.byKey(const Key('ocr:marque')), findsNothing);
      expect(find.byKey(const Key('ocr:relancer')), findsNothing);
      expect(moteur.appels, 0);
    });

    cas('la correction signée : commande ABSENTE pour qui n’écrit pas (anesthésiste), PRÉSENTE pour le médecin ; il signe, la carte dit « corrigé et signé », la lecture machine reste lisible, un texte vide est refusé en le nommant', (t) async {
      for (final role in ['anesthesiste', 'medecin']) {
        final m = poste({'documentsPatient': documents()});
        final (_, o) = brancher(m, () => 'medecin');
        o.enregistrer(MoteurOcrFactice(texteParDefaut: texteLu));
        expect(o.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: 'sonde').ok, isTrue);
        o.arreter();
        final r = await t.runAsync(() => FichiersPoste.de(m)!.deposer(
            famille: 'patient', ficheId: 'D1', nom: 'scan.png', octets: fx('scan.png'), role: 'medecin', droit: donnees.matrice.droit('medecin', 'm1-documents')));
        expect(r!.ok, isTrue, reason: '${r.refus}');
        o.arreter();
        await t.runAsync(() => o.vider());
        await ouvrir(t, m, 'm1-documents', role: role);
        await chercher(t, 'GED-00001');
        await toucher(t, find.byTooltip('Consulter').first);
        await attendreIo(t, tours: 6);
        expect(find.byKey(const Key('ocr:corriger')), role == 'medecin' ? findsOneWidget : findsNothing, reason: role);
        if (role == 'medecin') {
          await toucher(t, find.byKey(const Key('ocr:corriger')));
          await t.enterText(find.byKey(const Key('ocr:texte-corrige')), '   ');
          await toucher(t, find.byKey(const Key('ocr:signer')));
          expect(find.textContaining('CORRECTION_TEXTE_VIDE'), findsOneWidget);
          await t.enterText(find.byKey(const Key('ocr:texte-corrige')), 'Compte rendu corrigé par le médecin');
          await toucher(t, find.byKey(const Key('ocr:signer')));
          await attendreIo(t, tours: 6);
          expect(find.byKey(const Key('ocr:etat-ocr_corrige')), findsOneWidget);
          expect(find.byKey(const Key('ocr:corrige')), findsOneWidget);
          expect(find.byKey(const Key('ocr:marque')), findsNothing, reason: 'le texte courant est signé : plus « lu par machine, à vérifier »');
          expect(find.byKey(const Key('ocr:historique-2')), findsOneWidget, reason: 'la lecture machine reste au registre des versions, à côté de la correction');
          expect(m.collection(ocrLectures).toutes.where((x) => x['texteSource'] == 'ocr'), hasLength(1));
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 20));
      }
    });

    cas('la relance est ABSENTE pour un profil qui ne peut pas écrire sur l’écran (anesthésiste : lit la zone 2, n’écrit pas), et PRÉSENTE pour le médecin', (t) async {
      for (final role in ['anesthesiste', 'medecin']) {
        final m = poste({'documentsPatient': documents()});
        final (_, o) = brancher(m, () => 'medecin');
        o.enregistrer(MoteurOcrFactice(texteParDefaut: texteLu));
        expect(o.definirReglage(role: 'admin', actif: true, moteur: 'factice', langue: 'fra', motif: 'sonde').ok, isTrue);
        o.arreter();
        final r = await t.runAsync(() => FichiersPoste.de(m)!.deposer(
            famille: 'patient', ficheId: 'D1', nom: 'scan.png', octets: fx('scan.png'), role: 'medecin', droit: donnees.matrice.droit('medecin', 'm1-documents')));
        expect(r!.ok, isTrue, reason: '${r.refus}');
        o.arreter();
        await t.runAsync(() => o.vider());
        await ouvrir(t, m, 'm1-documents', role: role);
        await chercher(t, 'GED-00001');
        await toucher(t, find.byTooltip('Consulter').first);
        await attendreIo(t, tours: 6);
        expect(find.byKey(const Key('ocr:etat-ocr_indexe')), findsOneWidget, reason: role);
        expect(find.byKey(const Key('ocr:marque')), findsOneWidget, reason: role);
        expect(find.byKey(const Key('ocr:relancer')), role == 'medecin' ? findsOneWidget : findsNothing, reason: role);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 20));
      }
    });
  });
}
