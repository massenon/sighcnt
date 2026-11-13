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
import 'package:sigh_poste/kit/fichiers_ui.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_sync/sigh_sync.dart';


/// LES ÉCRANS DES FICHIERS NUMÉRISÉS (lot D5, étape 4) : dépôt sur la fiche d'un courrier (M13) et d'un document du patient (M1) par le sélecteur INJECTABLE, carte de la pièce, aperçu
/// (visionneuse d'images, lecteur de PDF injecté), téléchargement sous le nom normalisé, retrait annulable, remplacement, recherche dans le texte indexé, refus nommés, commandes interdites
/// ABSENTES, zones RG-13, réglage de la taille maximale. Le disque est réel (dossier temporaire) ; le rendu natif d'un PDF n'est PAS vérifié ici (lecteur factice).
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

void main() {
  late Directory tmp;
  late LecteurFactice lecteur;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-ecr-');
    lecteur = LecteurFactice();
    SelecteursFichiers.lecteurPdf = lecteur;
  });
  tearDown(() {
    SelecteursFichiers.reinitialiser();
    tmp.deleteSync(recursive: true);
  });

  FichiersPoste brancher(Magasin m) => FichiersPoste(m, StockageFichiers('${tmp.path}/fichiers'))..installer();
  void choisit(String nom, [Uint8List? octets]) => SelecteursFichiers.choisir = () async => FichierChoisi(nom, octets ?? fx(nom));

  group('courriers (M13)', () {
    cas('dépôt par le sélecteur injectable : carte de la pièce, « Numérisé » DÉRIVÉ, recherche dans le texte du PDF, journal', (t) async {
      final m = poste({'courriers': courriers()});
      final fp = brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      // Avant tout dépôt : « À scanner » partout, jamais « Oui » (la case saisie est retirée).
      expect(find.text('À scanner'), findsNWidgets(2));
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      expect(find.text('Aucune pièce numérisée rattachée à cette fiche.'), findsOneWidget);
      choisit('courrier-texte.pdf');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('fichiers:nom')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('fichiers:nom'))).data, '2026-08-20_ARR_0001.pdf');
      expect(t.widget<Text>(find.byKey(const Key('fichiers:empreinte'))).data, '${docAbrege(sha256Octets(fx('courrier-texte.pdf')))}…');
      expect(find.text('Texte indexé'), findsOneWidget);
      expect(fichierDe(m.collection('courriers').parId('C1')), isNotNull);
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Dépôt d’un fichier numérisé'), hasLength(1));
      // le tableau : « Oui » avec la mention « texte indexé »
      await fermerTiroir(t);
      expect(find.text('texte indexé'), findsOneWidget);
      // la RECHERCHE lit le texte du PDF (sans accent ni casse) ; le courrier voisin n'y répond pas
      await chercher(t, 'HYPERGLYCEMIE');
      expect(find.text('ARR-2026-0001'), findsOneWidget);
      await chercher(t, 'amoxicilline');
      expect(find.text('ARR-2026-0001'), findsOneWidget);
      await chercher(t, 'zzzintrouvable');
      expect(find.text('Aucun résultat pour cette recherche.'), findsOneWidget);
      fp.dispose();
    });

    cas('une image sans couche texte : « texte non indexé » dit sous « Aucun résultat » ; le filtre « Texte non indexé » la retrouve', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'DEP-2026-0002');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.text('Texte non indexé'), findsOneWidget);
      await fermerTiroir(t);
      await chercher(t, 'zzzintrouvable');
      expect(find.textContaining('1 pièce numérisée n’a pas de texte indexé'), findsOneWidget);
    });

    cas('aperçu : une image s’ouvre dans la visionneuse (zoom, rotation, ajustement), un PDF dans le lecteur injecté ; téléchargement sous le nom normalisé', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m);
      String? nomEnregistre;
      Uint8List? octetsEnregistres;
      SelecteursFichiers.enregistrer = (nom, octets) async {
        nomEnregistre = nom;
        octetsEnregistres = octets;
        return '/tmp/choisi/$nom';
      };
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      await toucher(t, find.byKey(const Key('fichiers:apercu')));
      await attendreIo(t, tours: 8);
      final v = t.state<VisionneuseImageState>(find.byType(VisionneuseImage));
      expect(v.zoom, 1);
      expect(v.ajuste, isTrue);
      await toucher(t, find.byTooltip('Agrandir'));
      expect(v.zoom, closeTo(1.25, 1e-9));
      expect(v.ajuste, isFalse);
      expect(find.text('125 %'), findsOneWidget);
      await toucher(t, find.byTooltip('Tourner à droite'));
      await toucher(t, find.byTooltip('Tourner à droite'));
      expect(v.rotation, 180);
      await toucher(t, find.byTooltip('Tourner à gauche'));
      expect(v.rotation, 90);
      await toucher(t, find.byTooltip('Réduire'));
      expect(v.zoom, closeTo(1.0, 1e-9));
      await toucher(t, find.byTooltip('Agrandir'));
      await toucher(t, find.byTooltip('Ajuster à la fenêtre'));
      expect(v.zoom, 1);
      expect(v.ajuste, isTrue);
      await toucher(t, find.byTooltip('Taille réelle'));
      await attendreIo(t, tours: 3);
      expect(v.zoom, closeTo(600 / (420 * 600 / 400 < 1500 ? 420 * 600 / 400 : 1500), 0.05), reason: 'image de 600 px de large : zoom = taille naturelle / taille ajustée');
      expect(find.bySemanticsLabel(RegExp('zoom .* %, rotation 90 degrés')), findsOneWidget);
      // fermer la visionneuse, puis télécharger
      await fermerModale(t);
      await toucher(t, find.byKey(const Key('fichiers:telecharger')));
      await attendreIo(t, tours: 8);
      expect(nomEnregistre, '2026-08-20_ARR_0001.png');
      expect(octetsEnregistres, fx('scan.png'));
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Téléchargement d’un document numérisé'), hasLength(1));
      expect(find.textContaining('Pièce enregistrée sous 2026-08-20_ARR_0001.png'), findsOneWidget);
    });

    cas('un PDF s’ouvre dans le composant de lecture (rendu factice : le rendu natif n’est pas vérifié ici) avec les octets VÉRIFIÉS', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('courrier-texte.pdf');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      await toucher(t, find.byKey(const Key('fichiers:apercu')));
      await attendreIo(t, tours: 8);
      expect(find.byKey(const Key('lecteur-factice')), findsOneWidget);
      expect(lecteur.recu, fx('courrier-texte.pdf'));
      expect(lecteur.nom, '2026-08-20_ARR_0001.pdf');
    });

    cas('REFUS NOMMÉS : format lu sur les octets (extension mensongère), fichier vide, doublon sur la même fiche ; rien n’est rangé', (t) async {
      final m = poste({'courriers': courriers()});
      final fp = brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('camoufle.pdf', fx('scan.png'));
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('fichiers:refus')), findsOneWidget);
      expect(find.textContaining('FORMAT_REFUSE : le contenu de « camoufle.pdf » n’est pas un PDF (l’extension ne suffit pas)'), findsOneWidget);
      choisit('vide.pdf', Uint8List(0));
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.textContaining('FICHIER_VIDE'), findsOneWidget);
      expect(await t.runAsync(() => fp.stockage.empreintes().toList()), isEmpty);
      expect(fichierDe(m.collection('courriers').parId('C1')), isNull);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      // le même fichier sur la même fiche : on passe par « Remplacer »
      await toucher(t, find.byKey(const Key('fichiers:remplacer')));
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir-remplacer')));
      await attendreIo(t);
      expect(find.textContaining('DOUBLON_MEME_FICHE : ce fichier est déjà rattaché à cette fiche : pièce ARR-2026-0001'), findsOneWidget);
    });

    cas('RETRAIT annulable avec motif obligatoire : le fichier reste au disque (RG-14), l’historique garde l’empreinte, l’annulation remet la pièce', (t) async {
      final m = poste({'courriers': courriers()});
      final fp = brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.jpg');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      final sha = sha256Octets(fx('scan.jpg'));
      await toucher(t, find.byKey(const Key('fichiers:retirer')));
      expect(find.text('Retirer la pièce de la fiche ?'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Mauvais scan, à refaire');
      await toucher(t, find.text('Retirer').last);
      await attendreIo(t, tours: 4);
      expect(fichierDe(m.collection('courriers').parId('C1')), isNull);
      expect((m.collection('courriers').parId('C1')!['fichiersRetires'] as List).single['motif'], 'Mauvais scan, à refaire');
      expect(await t.runAsync(() => fp.stockage.existe(sha)), isTrue);
      expect(find.textContaining('empreinte ${docAbrege(sha)} · retirée par '), findsOneWidget);
      expect(find.textContaining('motif : Mauvais scan, à refaire'), findsOneWidget);
      // annuler : la pièce revient
      await toucher(t, find.text('Annuler').first);
      await attendreIo(t, tours: 4);
      expect(fichierDe(m.collection('courriers').parId('C1')), isNotNull);
      expect(find.byKey(const Key('fichiers:retirer')), findsOneWidget);
    });

    cas('REMPLACER : l’ancienne pièce est retirée (historique), jamais supprimée du disque', (t) async {
      final m = poste({'courriers': courriers()});
      final fp = brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      await toucher(t, find.byKey(const Key('fichiers:remplacer')));
      choisit('scan.jpg');
      await toucher(t, find.byKey(const Key('fichiers:choisir-remplacer')));
      await attendreIo(t);
      final fiche = m.collection('courriers').parId('C1')!;
      expect(fichierDe(fiche)!['sha256'], sha256Octets(fx('scan.jpg')));
      expect((fiche['fichiersRetires'] as List).single['sha256'], sha256Octets(fx('scan.png')));
      expect(await t.runAsync(() => fp.stockage.existe(sha256Octets(fx('scan.png')))), isTrue);
    });

    cas('COMMANDES INTERDITES ABSENTES : l’accueil dépose sans pouvoir retirer la pièce (pas de droit d’annuler) ; le bouton de la taille maximale n’est pas à l’accueil', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m);
      await ouvrir(t, m, 'm13-courriers', role: 'reception');
      expect(find.byKey(const Key('fichiers:bouton-taille')), findsNothing);
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('scan.png');
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.byKey(const Key('fichiers:apercu')), findsOneWidget);
      expect(find.byKey(const Key('fichiers:telecharger')), findsOneWidget);
      expect(find.byKey(const Key('fichiers:retirer')), findsNothing, reason: 'absent, jamais grisé');
      expect(find.byTooltip('Archiver'), findsNothing);
    });

    cas('un profil qui ne fait que consulter voit la fiche sans pouvoir y déposer de pièce', (t) async {
      final m = poste({'courriers': courriers()});
      brancher(m);
      await t.pumpWidget(MaterialApp(
          home: ContexteEcran(
              ecranId: 'm13-courriers',
              role: 'lecteur',
              droit: const Droit(voir: true, editer: false, annuler: false),
              magasin: m,
              aller: (_) {},
              child: const Scaffold(body: SingleChildScrollView(child: CartePieceNumerisee(famille: 'courrier', ficheId: 'C1', titre: 'Courrier', role: 'lecteur', droit: Droit(voir: true, editer: false, annuler: false)))))));
      await t.pump();
      expect(find.text('Votre profil consulte cette fiche sans pouvoir y déposer de pièce.'), findsOneWidget);
      expect(find.byKey(const Key('fichiers:choisir')), findsNothing);
    });

    cas('sans stockage branché (poste non préparé) : la carte le dit, jamais un plantage', (t) async {
      final m = poste({'courriers': courriers()});
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      expect(find.text('Le stockage des fichiers numérisés n’est pas disponible sur ce poste.'), findsOneWidget);
    });

    cas('état d’un fichier dont la fiche est arrivée avant lui : « non disponible hors ligne », jamais un écran vide', (t) async {
      final c = courriers();
      c[0]['fichier'] = {'sha256': 'ab' * 32, 'nom': 'x.pdf', 'nomNormalise': '2026-08-20_ARR_0001.pdf', 'mime': 'application/pdf', 'taille': 5000, 'texteIndexe': true, 'deposePar': 'Autre poste', 'deposeLe': '2026-08-20T09:00:00.000Z'};
      final m = poste({'courriers': c});
      brancher(m);
      await ouvrir(t, m, 'm13-courriers');
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      await attendreIo(t, tours: 30);
      expect(find.byKey(const Key('fichiers:etat-nonDisponibleHorsLigne')), findsOneWidget);
      expect(find.textContaining('Fichier non disponible hors ligne'), findsOneWidget);
      await toucher(t, find.byKey(const Key('fichiers:apercu')));
      await attendreIo(t, tours: 10);
      expect(find.textContaining('FICHIER_ABSENT'), findsOneWidget);
    });
  });

  group('documents du patient (M1) et zones RG-13', () {
    cas('l’ACCUEIL ne voit que les pièces administratives et le DIT ; le médecin les voit toutes', (t) async {
      final m = poste({'documentsPatient': documents()});
      brancher(m);
      await ouvrir(t, m, 'm1-documents', role: 'reception');
      expect(find.text('GED-00002'), findsOneWidget);
      expect(find.text('GED-00001'), findsNothing);
      expect(find.textContaining('Votre profil ne voit que les pièces administratives'), findsOneWidget);
      expect(find.textContaining('1 pièce médicale n’est pas affichée (RG-13)'), findsOneWidget);
      await ouvrir(t, m, 'm1-documents', role: 'medecin');
      expect(find.text('GED-00001'), findsOneWidget);
      expect(find.text('GED-00002'), findsOneWidget);
      expect(find.textContaining('Votre profil ne voit que'), findsNothing);
    });

    cas('création d’un document AVEC son fichier : la fiche n’existe que si le fichier est rangé ; un refus nommé ne laisse aucune fiche vide ; annulable', (t) async {
      final p = [
        {'id': 'P1', 'statut': 'actif', 'code': 'CNT/1/26', 'nom': 'ADJOVI', 'prenom': 'Paul'}
      ];
      final m = poste({'documentsPatient': const [], 'patients': p});
      final fp = brancher(m);
      await ouvrir(t, m, 'm1-documents', role: 'medecin');
      await toucher(t, find.text('Ajouter un document'));
      final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl.poser('patientId', 'P1');
      ctl.poser('type', 'Compte rendu médical');
      // un fichier refusé : pas de fiche
      choisit('faux.exe');
      await toucher(t, find.byKey(const Key('doc:choisir')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('FORMAT_REFUSE'), findsOneWidget);
      choisit('scan.webp');
      await toucher(t, find.byKey(const Key('doc:choisir')));
      expect(find.textContaining('Fichier choisi : scan.webp'), findsOneWidget);
      await toucher(t, find.byKey(const Key('doc:rattacher')));
      await attendreIo(t);
      final docs = m.collection('documentsPatient').toutes;
      expect(docs, hasLength(1));
      expect(docs.single['reference'], 'GED-00001');
      expect(docs.single['code'], 'CNT/1/26');
      expect(fichierDe(docs.single)!['nomNormalise'], '${docs.single['date']}_CNT-1-26_compte-rendu-medical_001.webp');
      expect(fichierDe(docs.single)!['mime'], 'image/webp');
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Création d’un document numérisé'), hasLength(1));
      // le même fichier dans le même dossier : refusé, aucune seconde fiche
      await toucher(t, find.text('Ajouter un document'));
      final ctl2 = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl2.poser('patientId', 'P1');
      ctl2.poser('type', 'Compte rendu médical');
      choisit('scan.webp');
      await toucher(t, find.byKey(const Key('doc:choisir')));
      await toucher(t, find.byKey(const Key('doc:rattacher')));
      await attendreIo(t);
      expect(find.textContaining('DOUBLON_MEME_FICHE'), findsOneWidget);
      expect(m.collection('documentsPatient').toutes, hasLength(1));
      expect(await t.runAsync(() => fp.stockage.empreintes().toList()), hasLength(1), reason: 'une seule copie sur le disque');
    });

    cas('l’accueil ne peut pas déposer un compte rendu : le type n’est même pas proposé (zone 2)', (t) async {
      final m = poste({'documentsPatient': const [], 'patients': const []});
      brancher(m);
      await ouvrir(t, m, 'm1-documents', role: 'reception');
      await toucher(t, find.text('Ajouter un document'));
      final defs = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur.champs;
      final types = defs.firstWhere((c) => c.nom == 'type').options.map((o) => o.valeur).toList();
      expect(types, ['Pièce d’identité', 'Carte d’assurance']);
    });

    cas('l’aperçu d’un document sans fichier dit « fichier non encore déposé » ; la fiche en tiroir porte la carte de la pièce', (t) async {
      final m = poste({'documentsPatient': documents()});
      brancher(m);
      await ouvrir(t, m, 'm1-documents', role: 'medecin');
      await toucher(t, find.byTooltip('Prévisualiser').first);
      expect(find.textContaining('fichier non encore déposé'), findsOneWidget);
      await fermerModale(t);
      await chercher(t, 'GED-00002');
      await toucher(t, find.byTooltip('Consulter').first);
      expect(find.byKey(const Key('fichiers:carte-patient')), findsOneWidget);
    });
  });

  group('taille maximale', () {
    cas('le bouton n’est offert qu’à l’administrateur et à la DAF ; le réglage est motivé, borné, journalisé et appliqué au dépôt suivant', (t) async {
      final m = poste({'courriers': courriers()});
      final fp = brancher(m);
      await ouvrir(t, m, 'm13-courriers', role: 'admin');
      expect(find.byKey(const Key('fichiers:bouton-taille')), findsOneWidget);
      await toucher(t, find.byKey(const Key('fichiers:bouton-taille')));
      expect(find.textContaining('Valeur de départ de 10 Mo : à valider par la Direction'), findsOneWidget);
      // trop petit : refus nommé dans la modale
      await t.enterText(find.byKey(const Key('fichiers:taille-mo')), '0.05');
      await t.enterText(find.byKey(const Key('fichiers:taille-motif')), 'essai');
      await toucher(t, find.byKey(const Key('fichiers:taille-enregistrer')));
      expect(find.textContaining('TAILLE_INVALIDE'), findsOneWidget);
      // sans motif : refus nommé
      await t.enterText(find.byKey(const Key('fichiers:taille-mo')), '0.2');
      await t.enterText(find.byKey(const Key('fichiers:taille-motif')), '');
      await toucher(t, find.byKey(const Key('fichiers:taille-enregistrer')));
      expect(find.textContaining('MOTIF_REQUIS'), findsOneWidget);
      await t.enterText(find.byKey(const Key('fichiers:taille-motif')), 'Scans plus légers');
      await toucher(t, find.byKey(const Key('fichiers:taille-enregistrer')));
      expect(fp.tailleMax(), (0.2 * 1048576).round());
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Taille maximale d’un fichier numérisé'), hasLength(1));
      // le dépôt suivant le subit
      await chercher(t, 'ARR-2026-0001');
      await toucher(t, find.byTooltip('Consulter').first);
      choisit('gros.pdf', Uint8List.fromList([...fx('courrier-texte.pdf'), ...List.filled(250 * 1024, 32)]));
      await toucher(t, find.byKey(const Key('fichiers:choisir')));
      await attendreIo(t);
      expect(find.textContaining('TAILLE_DEPASSEE'), findsOneWidget);
    });
  });

  group('visionneuse d’images', () {
    cas('zoom borné, rotation par quarts de tour, ajustement ; l’état se lit à l’écran et aux lecteurs d’écran', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VisionneuseImage(octets: fx('scan.png'), libelle: 'Scan test')))));
      await t.pump();
      final v = t.state<VisionneuseImageState>(find.byType(VisionneuseImage));
      for (var i = 0; i < 20; i++) {
        await t.tap(find.byTooltip('Agrandir'));
        await t.pump();
      }
      expect(v.zoom, 8.0, reason: 'le zoom est borné à 800 %');
      for (var i = 0; i < 60; i++) {
        await t.tap(find.byTooltip('Réduire'));
        await t.pump();
      }
      expect(v.zoom, closeTo(0.1, 1e-9), reason: 'et à 10 %');
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byTooltip('Tourner à droite'));
        await t.pump();
      }
      expect(v.rotation, 90);
      await t.tap(find.byTooltip('Tourner à gauche'));
      await t.tap(find.byTooltip('Tourner à gauche'));
      await t.pump();
      expect(v.rotation, 270);
      // le déplacement à la souris : un glissement sort l'image de l'ajustement
      await t.tap(find.byTooltip('Ajuster à la fenêtre'));
      await t.pump();
      expect(v.ajuste, isTrue);
      await t.drag(find.byKey(const Key('visionneuse:cadre')), const Offset(30, 10), warnIfMissed: true);
      await t.pump();
      expect(v.ajuste, isFalse);
      expect(find.bySemanticsLabel(RegExp('Scan test : zoom 100 %')), findsOneWidget);
    });
  });

  test('règle de rédaction : aucun tiret cadratin ni demi-cadratin employé comme ponctuation dans les fichiers du lot (le « — » seul est la valeur absente, syntaxe)', () {
    for (final f in ['lib/kit/fichiers_ui.dart', 'lib/donnees/fichiers_poste.dart', 'lib/sync/service_fichiers.dart']) {
      final texte = File(f).readAsStringSync();
      expect(RegExp(r'\S [—–] \S').hasMatch(texte), isFalse, reason: f);
      expect(texte.contains('–'), isFalse, reason: f);
    }
  });
}
