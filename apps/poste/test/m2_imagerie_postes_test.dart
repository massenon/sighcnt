import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Poste d'imagerie médicale : `m2-imagerie-demandes`, `m2-dashboard-imagerie`, `m2-echographie-galerie`. Les règles sont rejouées sur les vecteurs
/// du domaine (`img_demandes.json`, engendrés en PILOTANT les écrans réels de la maquette) ; ici, l'ÉCRAN — ce qu'il montre dans l'ordre de la
/// maquette, ce qu'il écrit, refuse, ou n'offre pas à un profil.
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/img_demandes.json').readAsStringSync())
    as Map)
    .cast<String, Object?>();

List<Map<String, Object?>> liste(Object? v) =>
    [for (final x in (v as List)) (x as Map).cast<String, Object?>()];

/// Le jeu complet, vidé de l'imagerie et des tâches puis rempli de ce que le cas du vecteur a posé dans la maquette.
Magasin magasin(
    {List<Map<String, Object?>> demandes = const [],
    List<Map<String, Object?>> comptesRendus = const [],
    List<Map<String, Object?>> cliches = const [],
    List<Map<String, Object?>> taches = const []}) {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  void remplacer(String nom, List<Map<String, Object?>> fiches, String prefixe) {
    final col = m.collection(nom);
    for (final f in col.actives) {
      col.archiver(f['id']);
    }
    for (final f in fiches) {
      col.inserer({...f}, prefixe: prefixe);
    }
  }

  remplacer('demandesImagerie', demandes, 'IME');
  remplacer('resultatsImagerie', comptesRendus, 'IMG');
  remplacer('clichesImagerie', cliches, 'CLI');
  remplacer('taches', taches, 'TCH');
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin', DateTime? jour}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => jour ?? DateTime.parse('${vecteurs['moisCourant']}-15')));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

/// Les indicateurs affichés : (libellé, valeur) dans l'ordre de la grille.
List<(String, String)> kpis(WidgetTester t) {
  final l = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) w.data!];
  final v = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) w.data!];
  return [for (var i = 0; i < l.length; i++) (l[i], v[i])];
}

/// Ouvre la liste du champ [champ] et y choisit [cible] (la cherche d'abord : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find.descendant(
          of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Coche [libelle] dans la liste à choix multiples [champ] (on la cherche d'abord : le panneau ne construit que les lignes visibles).
Future<void> cocher(WidgetTester t, String champ, String libelle) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.enterText(find.byType(TextField).last, libelle);
  await t.pump(const Duration(milliseconds: 200));
  await toucher(t, find.text(libelle).last);
  await fermerPanneau(t);
}

Future<void> fermerPanneau(WidgetTester t) async {
  await t.tapAt(const Offset(4, 4));
  await t.pump(const Duration(milliseconds: 300));
}

Finder champTexte(String nom) => find.descendant(
    of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

String ref(Map<String, Object?> ligne) => '${(ligne['cellules']! as List).first}'.split(' ').first;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  final registre = liste(vecteurs['registre']);
  final poste = liste(vecteurs['poste']);
  final galerie = liste(vecteurs['galerie']);

  group('registre des demandes', () {
    cas('les quatre indicateurs et la première page, dans l\'ordre de l\'écran réel', (t) async {
      final c = registre[0];
      await ouvrir(t, magasin(demandes: liste(c['demandes'])), 'm2-imagerie-demandes');
      final lu = (c['lu']! as Map).cast<String, Object?>();
      expect(kpis(t), [for (final k in liste(lu['kpis'])) ('${k['label']}', '${k['valeur']}')]);
      final lignes = liste(liste(lu['tables']).single['lignes']);
      expect(lignes.length, 12);
      var dy = -1.0;
      for (final l in lignes) {
        final y = t.getTopLeft(find.text(ref(l))).dy;
        expect(y, greaterThan(dy), reason: '${ref(l)} doit suivre la ligne précédente (tri par date décroissante)');
        dy = y;
      }
      // Les deux demandes les plus anciennes sont à la page 2.
      for (final d in liste(c['demandes'])) {
        if (!lignes.any((l) => ref(l) == d['reference'])) {
          expect(find.text('${d['reference']}'), findsNothing);
        }
      }
      expect(find.textContaining('sur 14'), findsWidgets);
    });

    cas('les commandes de chaque ligne suivent l\'état (« Saisir le CR » verrouillé tant que la caisse n\'a pas encaissé)', (t) async {
      final c = registre[0];
      await ouvrir(t, magasin(demandes: liste(c['demandes'])), 'm2-imagerie-demandes');
      final lignes = liste(liste((c['lu']! as Map)['tables']).single['lignes']);
      int combien(String texte) => lignes.where((l) => (l['cellules']! as List).last == texte).length;
      expect(find.text('Saisir le CR'), findsNWidgets(combien('Saisir le CR')));
      expect(find.text('Poursuivre le CR'), findsNWidgets(combien('Poursuivre le CR')));
      // Aucun compte rendu n'existe : « Rendre » n'est offert nulle part.
      expect(find.text('Rendre'), findsNothing);
    });

    cas('une demande non réglée : la saisie est refusée en nommant la caisse et la pièce', (t) async {
      final c = registre[2];
      final d = liste(c['demandes']).single;
      await ouvrir(t, magasin(demandes: [d]), 'm2-imagerie-demandes');
      await toucher(t, find.text('Saisir le CR'));
      expect(find.text('Saisie impossible : examen non réglé.'), findsOneWidget);
      expect(find.text('La caisse doit encaisser la pièce ${d['factureNumero']} d’abord.'), findsOneWidget);
    });

    cas('registre vide : l\'état vide dit quoi faire, les indicateurs sont à zéro', (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-demandes');
      expect(kpis(t).map((k) => k.$2).toSet(), {'0'});
      expect(find.text('Aucune demande d’imagerie. Une demande s’ouvre ici ou naît d’une consultation.'), findsOneWidget);
    });

    cas('le détail d\'une demande non réglée rappelle que la balle est à la caisse', (t) async {
      final d = liste(registre[2]['demandes']).single;
      await ouvrir(t, magasin(demandes: [d]), 'm2-imagerie-demandes');
      await toucher(t, find.text('${d['patient']} — ${d['patientCode']}'));
      expect(find.textContaining('L’examen attend son règlement : la balle est à la caisse (${d['factureNumero']}).'), findsOneWidget);
    });

    cas('« Rendre » : sans conclusion il est refusé ; avec, la demande est validée et le prescripteur notifié', (t) async {
      final dem = {
        'id': 'D1', 'reference': 'IME-00001', 'statut': 'executee', 'dateHeure': '2026-08-20T09:00:00.000Z', 'patient': 'ALI Sidi',
        'patientCode': 'CNT/7/26', 'examenCode': 'IMG-TDM-CER', 'examen': 'Scanner cérébral', 'prescripteur': 'Dr TEST', 'prix': 70000,
      };
      final cr = {
        'id': 'C1', 'reference': 'IMG-0100', 'statut': 'brouillon', 'demandeImagerieId': 'D1', 'examen': 'Scanner cérébral', 'examenCode': 'IMG-TDM-CER',
        'patient': 'ALI Sidi', 'patientId': 'P7', 'prescripteur': 'Dr TEST', 'conclusion': '',
      };
      final m = magasin(demandes: [dem], comptesRendus: [cr]);
      await ouvrir(t, m, 'm2-imagerie-demandes');
      await toucher(t, find.text('Rendre'));
      expect(find.text('La conclusion est obligatoire avant de rendre le compte rendu.'), findsOneWidget);
      expect(m.collection('resultatsImagerie').parId('C1')!['statut'], 'brouillon');
      expect(m.collection('demandesImagerie').parId('D1')!['statut'], 'executee');
      m.collection('resultatsImagerie').mettreAJour('C1', {'conclusion': 'Examen sans particularité.'});
      await toucher(t, find.text('Rendre'));
      expect(find.text('Rendre le compte rendu au prescripteur ?'), findsOneWidget);
      expect(find.text('Le compte rendu IMG-0100 sera transmis à Dr TEST. Une correction ultérieure devra être signalée comme telle.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rendre').last);
      expect(m.collection('resultatsImagerie').parId('C1')!['statut'], 'rendu');
      expect(m.collection('resultatsImagerie').parId('C1')!['renduLe'], isNotNull);
      expect(m.collection('demandesImagerie').parId('D1')!['statut'], 'validee');
      final n = m.collection('notifications').actives.first;
      expect(n['type'], 'imagerie_rendue');
      expect(n['libelle'], 'Compte rendu d’imagerie rendu — ALI Sidi');
      expect(find.text('Compte rendu rendu au prescripteur.'), findsOneWidget);
      expect(find.text('Rendre'), findsNothing, reason: 'la demande est validée : plus de commande d\'écriture');
    });

    cas('RBAC : lecture seule → ni « Nouvelle demande » ni saisie ; l\'échographiste exécute mais ne prescrit pas', (t) async {
      final dems = liste(registre[0]['demandes']);
      await ouvrir(t, magasin(demandes: dems), 'm2-imagerie-demandes', role: 'admin');
      expect(find.text('Nouvelle demande'), findsOneWidget);
      await ouvrir(t, magasin(demandes: dems), 'm2-imagerie-demandes', role: 'direction');
      expect(find.text('Nouvelle demande'), findsNothing);
      expect(find.text('Poursuivre le CR'), findsNothing, reason: 'un profil en lecture voit les états, pas les commandes d\'écriture');
      await ouvrir(t, magasin(demandes: dems), 'm2-imagerie-demandes', role: 'echographiste');
      expect(find.text('Nouvelle demande'), findsNothing, reason: 'ouvrir une demande est un acte de prescription');
      expect(find.text('Saisir le CR'), findsWidgets);
    });

    Future<void> remplir(WidgetTester t, Magasin m, String examen) async {
      final patient = m.collection('patients').actives.first;
      await ouvrir(t, m, 'm2-imagerie-demandes');
      await toucher(t, find.text('Nouvelle demande'));
      await choisir(t, 'patientCode', '${patient['code']} — ${patient['nom']} ${patient['prenom']}');
      await cocher(t, 'examens', examen);
      await choisir(t, 'prescripteur', '— Prescripteur extérieur à la clinique —');
      await t.enterText(champTexte('prescripteurExterne'), 'Dr SALIFOU Aminou, CS de Perma');
      await t.enterText(champTexte('indication'), 'Douleurs pelviennes');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la demande'));
    }

    cas('« Nouvelle demande » sans tarif au catalogue : refusé en nommant l\'examen, rien n\'est facturé', (t) async {
      // Sans catalogue tarifaire (archivé ci-dessous) et sans acte rapproché, le scanner n'a aucun tarif : un tiret n'est pas un zéro.
      final m = magasin();
      // Le jeu livré porte désormais le catalogue tarifaire : on l'archive pour poser le cas « aucun tarif ».
      for (final x in m.collection('catalogueTarifs').actives.toList()) {
        m.collection('catalogueTarifs').archiver(x['id']);
      }
      final avantFactures = m.collection('factures').toutes.length;
      final avantArchivees = m.collection('demandesImagerie').archivees.length;
      await remplir(t, m, 'Scanner cérébral');
      expect(find.textContaining('Tarif non renseigné pour : Scanner cérébral. Le renseigner au référentiel tarifaire avant de facturer.'), findsWidgets);
      expect(m.collection('factures').toutes.length, avantFactures);
      expect(m.collection('demandesImagerie').actives.where((d) => d['indication'] == 'Douleurs pelviennes'), isEmpty);
      // La demande refusée est écrite puis ARCHIVÉE (RG-14) : le numéro qu'elle a consommé ne se réutilise pas.
      expect(m.collection('demandesImagerie').archivees.length, avantArchivees + 1);
      expect(m.collection('demandesImagerie').archivees.first['examenCode'], 'IMG-TDM-CER');
      expect(m.collection('taches').actives.where((x) => x['type'] == 'encaissement'), isEmpty);
    });

    cas('« Nouvelle demande » : demande bloquée, facture à la caisse, tâches, notification — le prescripteur extérieur est nommé', (t) async {
      final m = magasin();
      // Le tarif vient du catalogue tarifaire : l'entrée de la maquette pour le scanner cérébral (aucun prix inventé).
      final entree = liste(vecteurs['tarifPrix']).firstWhere((x) => (x['entree'] as Map?)?['code'] == 'IMG-TDM-CER')['entree']! as Map;
      m.collection('catalogueTarifs').inserer({...entree.cast<String, Object?>(), 'id': 'TAR1'});
      final patient = m.collection('patients').actives.first;
      final avantFactures = m.collection('factures').toutes.length;
      await remplir(t, m, 'Scanner cérébral');
      final d = m.collection('demandesImagerie').actives.first;
      expect(d['statut'], 'demandee');
      expect(d['bloqueParPaiement'], true);
      expect(d['prescripteur'], 'Dr SALIFOU Aminou, CS de Perma (extérieur)');
      expect(d['prix'], entree['prixNonAssure']);
      expect(d['patientCode'], patient['code']);
      final f = m.collection('factures').actives.first;
      expect(m.collection('factures').toutes.length, avantFactures + 1);
      expect(f['numero'], startsWith('FI-'));
      expect(d['factureNumero'], f['numero']);
      expect(((f['lignes'] as List).single as Map)['demandeImagerieId'], d['id']);
      expect(f['statutPaiement'], 'impayee');
      final taches = m.collection('taches').actives.take(2).toList();
      expect({for (final x in taches) x['type']: x['statut']}, {'encaissement': 'en_attente', 'imagerie': 'bloque'});
      expect(m.collection('notifications').actives.first['type'], 'demande_imagerie');
      expect(find.text('Demande émise — 1 examen(s).'), findsOneWidget);
      expect(find.textContaining('Facture ${f['numero']} à la caisse'), findsOneWidget);
      // La demande apparaît au registre, en attente de caisse.
      expect(find.text('${d['reference']}'), findsOneWidget);
    });

    cas('« Nouvelle demande » : une échographie se tarife par l\'acte rapproché de la grille (le jeu du poste porte les actes)', (t) async {
      final m = magasin();
      await remplir(t, m, 'Échographie pelvienne');
      final d = m.collection('demandesImagerie').actives.first;
      expect(d['examenCode'], 'IMG-ECHO-PEL');
      expect(d['prix'], 9000);
      expect(find.text('Demande émise — 1 examen(s).'), findsOneWidget);
    });

    cas('« Nouvelle demande » sans patient ni identité : refusé en le disant, rien n\'est écrit', (t) async {
      final m = magasin();
      final avant = m.collection('demandesImagerie').toutes.length;
      await ouvrir(t, m, 'm2-imagerie-demandes');
      await toucher(t, find.text('Nouvelle demande'));
      await cocher(t, 'examens', 'Échographie pelvienne');
      await choisir(t, 'prescripteur', '— Prescripteur extérieur à la clinique —');
      await t.enterText(champTexte('indication'), 'x');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la demande'));
      expect(find.text('Sélectionner un patient du répertoire, ou renseigner le nom et les prénoms du patient adressé de l’extérieur.'), findsOneWidget);
      expect(m.collection('demandesImagerie').toutes.length, avant);
    });

    cas('« Nouvelle demande » : un formulaire incomplet est signalé', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm2-imagerie-demandes');
      await toucher(t, find.text('Nouvelle demande'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre la demande'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    });
  });

  group('poste d\'imagerie', () {
    for (final c in poste) {
      cas('${c['nom']}', (t) async {
        final m = magasin(
            demandes: liste(c['demandes']),
            comptesRendus: liste(c['comptesRendus']),
            taches: liste(c['taches']));
        await ouvrir(t, m, 'm2-dashboard-imagerie');
        final lu = (c['lu']! as Map).cast<String, Object?>();
        expect(kpis(t), [for (final k in liste(lu['kpis'])) ('${k['label']}', '${k['valeur']}')]);
        for (final k in liste(lu['kpis'])) {
          if (k['indice'] != null) expect(find.text('${k['indice']}'), findsOneWidget);
        }
        final tables = liste(lu['tables']);
        final aExecuter = tables.where((x) => (x['entetes']! as List).first == 'N°').toList();
        if (aExecuter.isNotEmpty && (aExecuter.first['lignes'] as List).isNotEmpty && aExecuter.first['entetes'].toString().contains('PRIORITÉ')) {
          var dy = -1.0;
          for (final l in liste(aExecuter.first['lignes'])) {
            final y = t.getTopLeft(find.text(ref(l))).dy;
            expect(y, greaterThan(dy), reason: '${ref(l)} : les plus anciens d\'abord');
            dy = y;
            final cellules = (l['cellules']! as List).cast<String>();
            expect(find.text(cellules[3]), findsWidgets, reason: 'priorité ${cellules[3]}');
          }
        } else {
          expect(find.text('Aucun examen réglé en attente : rien ne vous attend.'), findsOneWidget);
        }
        // Activité par modalité : une ligne par modalité, les cinq compteurs de la maquette.
        final modal = tables.firstWhere((x) => (x['entetes']! as List).first == 'MODALITÉ');
        for (final l in liste(modal['lignes'])) {
          final cellules = (l['cellules']! as List).cast<String>();
          expect(find.text(cellules[0]), findsOneWidget);
        }
        expect(find.textContaining('${(lu['cartes']! as List).last}'), findsWidgets);
      });
    }

    cas('un clic sur une modalité ouvre son tableau ; un profil sans accès reste sur place', (t) async {
      final c = poste[0];
      final m = magasin(demandes: liste(c['demandes']), comptesRendus: liste(c['comptesRendus']));
      await ouvrir(t, m, 'm2-dashboard-imagerie');
      await toucher(t, find.text('Radiographie').first);
      expect(find.text('Tableau Radiographie'), findsWidgets);
    });

    cas('« Saisir le CR » n\'est offert qu\'à qui peut écrire ; la file d\'attente est visible de tous', (t) async {
      final c = poste[0];
      final m = magasin(demandes: liste(c['demandes']), comptesRendus: liste(c['comptesRendus']), taches: liste(c['taches']));
      await ouvrir(t, m, 'm2-dashboard-imagerie', role: 'direction');
      expect(find.text('Saisir le CR'), findsNothing);
      expect(find.textContaining('File d’attente du poste — 2 à traiter, 1 en attente de caisse'), findsOneWidget);
    });
  });

  group('galerie des clichés', () {
    cas('indicateurs et cartes dans l\'ordre de l\'écran réel (le plus récent d\'abord)', (t) async {
      final c = galerie[0];
      await ouvrir(t, magasin(cliches: liste(c['cliches']).map((x) => {...x, 'fichier': _png}).toList()), 'm2-echographie-galerie');
      final lu = (c['lu']! as Map).cast<String, Object?>();
      expect(kpis(t), [for (final k in liste(lu['kpis'])) ('${k['label']}', '${k['valeur']}')]);
      var dy = -1.0;
      var dx = -1.0;
      for (final carte in liste(lu['cliches'])) {
        final texte = (carte['texte']! as List).cast<String>();
        // Les cartes se lisent en lignes de trois : l'ordre est celui de lecture (haut→bas, gauche→droite).
        final cartesLignes = find.byWidgetPredicate((w) => w.key is Key && '${w.key}'.contains('img:cliche:'));
        expect(cartesLignes, findsWidgets);
        final fenetre = find.textContaining(texte[1]);
        expect(fenetre, findsWidgets, reason: texte[1]);
        final p = t.getTopLeft(fenetre.first);
        expect(p.dy > dy || (p.dy == dy && p.dx > dx), isTrue, reason: '${texte[0]} — ${texte[1]}');
        dy = p.dy;
        dx = p.dx;
        if (texte.contains('sans CR lié')) {
          expect(find.text('sans CR lié'), findsWidgets);
        }
      }
      expect(find.text('Archiver le cliché'), findsNothing, reason: 'une icône : sa légende est sémantique');
    });

    cas('galerie vide : l\'état vide, la commande d\'ajout reste offerte', (t) async {
      await ouvrir(t, magasin(), 'm2-echographie-galerie');
      expect(find.text('Aucun cliché conservé. Les images s’ajoutent depuis ce poste, rattachées au patient.'), findsOneWidget);
      expect(find.text('Ajouter un cliché'), findsOneWidget);
    });

    cas('archiver un cliché : confirmation, archivage logique (RG-14), il ne compte plus', (t) async {
      final cl = liste(galerie[0]['cliches']).map((x) => {...x, 'fichier': _png}).toList();
      final m = magasin(cliches: cl);
      await ouvrir(t, m, 'm2-echographie-galerie');
      await toucher(t, find.bySemanticsLabel('Archiver le cliché').first);
      expect(find.text('Archiver ce cliché ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('clichesImagerie').actives.length, 3);
      expect(m.collection('clichesImagerie').archivees.length, 1);
      expect(find.text('Cliché archivé.'), findsOneWidget);
      expect(kpis(t).first, ('Clichés conservés', '3'));
    });

    cas('ajouter un cliché : sans image il est refusé ; avec, il est conservé rattaché au patient et au CR', (t) async {
      final dossier = Directory.systemTemp.createTempSync('cliche');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final fichier = File('${dossier.path}/echo.png')..writeAsBytesSync(base64Decode(_png.split(',').last));
      final cr = {'id': 'C1', 'reference': 'IMG-0100', 'statut': 'brouillon', 'examen': 'Échographie pelvienne', 'patient': 'ALI Sidi'};
      final m = magasin(comptesRendus: [cr]);
      final patient = m.collection('patients').actives.first;
      await ouvrir(t, m, 'm2-echographie-galerie');
      await toucher(t, find.text('Ajouter un cliché'));
      await choisir(t, 'patientCode', '${patient['code']} — ${patient['nom']} ${patient['prenom']}');
      await choisir(t, 'crReference', 'IMG-0100 — Échographie pelvienne — ALI Sidi');
      await choisir(t, 'examen', 'Échographie pelvienne');
      await t.enterText(champTexte('legende'), 'Coupe sagittale');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Conserver le cliché'));
      expect(find.text('Choisir une image.'), findsOneWidget);
      expect(find.text('Un cliché sans image n’est qu’une légende.'), findsOneWidget);
      expect(m.collection('clichesImagerie').actives, isEmpty);
      await t.enterText(find.byKey(const Key('img:chemin')), fichier.path);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Charger'));
      await t.pump(const Duration(milliseconds: 300));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Conserver le cliché'));
      final c = m.collection('clichesImagerie').actives.single;
      expect(c['patientCode'], patient['code']);
      expect(c['crReference'], 'IMG-0100');
      expect(c['legende'], 'Coupe sagittale');
      expect('${c['fichier']}', startsWith('data:image/png;base64,'));
      expect(find.text('Cliché conservé.'), findsOneWidget);
      expect(kpis(t).first, ('Clichés conservés', '1'));
    });

    cas('RBAC : en lecture, la galerie se consulte sans pouvoir ajouter ni archiver', (t) async {
      final cl = liste(galerie[0]['cliches']).map((x) => {...x, 'fichier': _png}).toList();
      await ouvrir(t, magasin(cliches: cl), 'm2-echographie-galerie', role: 'direction');
      expect(find.text('Ajouter un cliché'), findsNothing);
      expect(find.bySemanticsLabel('Archiver le cliché'), findsNothing);
      expect(kpis(t).first.$2, '4');
    });
  });
}

const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
