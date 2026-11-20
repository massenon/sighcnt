import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m14/sauvegardes.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-sauvegardes : l'historique est CALCULÉ (graine 3517, rejoué sur les vecteurs par le domaine), « Restaurer » est SIMULÉ ; générer, lancer, télécharger et
/// tester travaillent sur le magasin RÉEL du poste. Les écritures de fichier sont interceptées : aucun test n'écrit sur le disque.
void main() {
  setUpAll(chargerPolices);
  final ecrits = <(String, String)>[];
  setUp(() {
    ecrits.clear();
    ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf';
    enregistrerSauvegarde = (nom, contenu) async {
      ecrits.add((nom, contenu));
      return '/faux/$nom';
    };
  });
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouverture : indicateurs et historique de 34 jours calculés, six fichiers du jeu, deux tableaux', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    final rows = secHistoriqueSauvegardes(aujourdhui);
    expect(rows.length, 34);
    for (final k in ['Sauvegardes conservées', 'Dernière sauvegarde', 'Échecs constatés', 'Volume moyen']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('${secVolumeMoyen(rows)} Mo'), findsOneWidget);
    expect(find.text('BK-20261030'), findsOneWidget);
    expect(find.text('Fichiers de sauvegarde disponibles'), findsOneWidget);
    expect(find.text('Historique des sauvegardes'), findsOneWidget);
    for (final e in ['FICHIER', 'TABLES', 'PORTÉE', 'RÉFÉRENCE', 'HEURE', 'TYPE', 'SUPPORT', 'VOLUME', 'DURÉE', 'RÉSULTAT', 'MESSAGE']) {
      expect(find.text(e), findsWidgets, reason: e);
    }
    final echecs = rows.where((r) => !r.succes).length;
    expect(find.textContaining('$echecs sauvegarde(s) en échec.'), findsOneWidget);
    expect(m.collection('fichiersSauvegarde').actives.length, 6);
    // La note dit ce qui est simulé.
    expect(find.textContaining('l’historique ci-dessus est calculé'), findsOneWidget);
    // Seules les sauvegardes réussies se restaurent (première page de 15 lignes).
    expect(find.widgetWithText(BoutonSigh, 'Restaurer'), findsNWidgets(rows.take(15).where((r) => r.succes).length));
  });

  casM14('collection vide : les six fichiers hebdomadaires sont amorcés (graine 88), une fois', (t) async {
    final m = Magasin({...{for (final n in Magasin.collectionsDuJeu) n: <Fiche>[]}}, 'POSTE', const {});
    await ouvrirM14(t, m, 'm14-sauvegardes');
    expect(m.collection('fichiersSauvegarde').actives.length, 6);
    expect(m.collection('fichiersSauvegarde').actives.first['fichier'], 'sigh-cnt-20261030.json');
    expect(m.collection('fichiersSauvegarde').actives.last['fichier'], 'sigh-cnt-20260925.json');
  });

  casM14('« Générer une sauvegarde » : une fiche de fichier (nom, tables, poids), annulable par archivage — RG-14', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Générer une sauvegarde'));
    final f = m.collection('fichiersSauvegarde').actives.first;
    expect(f['fichier'], 'sigh-cnt-20261030-07.json');
    expect(f['date'], '2026-10-30');
    expect(f['portee'], 'Base complète');
    expect(f['tables'], Magasin.collectionsDuJeu.length);
    expect(f['taille'], greaterThan(1000));
    expect(f['genereePar'], 'Administrateur système');
    expect(find.text('Sauvegarde sigh-cnt-20261030-07.json générée.'), findsOneWidget);
    expect(m.collection('fichiersSauvegarde').actives.length, 7);
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('fichiersSauvegarde').actives.length, 6);
    expect(m.collection('fichiersSauvegarde').archivees.length, 1);
  });

  casM14('« Télécharger » écrit l\'état COURANT du magasin sous le nom de la ligne, et le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    await toucherM14(t, find.byTooltip('Télécharger').first);
    expect(ecrits.length, 1);
    expect(ecrits.single.$1, m.collection('fichiersSauvegarde').actives.first['fichier']);
    final lu = jsonDecode(ecrits.single.$2) as Map;
    expect(lu.containsKey('utilisateurs'), isTrue);
    expect((lu['utilisateurs'] as List).length, m.collection('utilisateurs').toutes.length);
    expect(find.text('Sauvegarde téléchargée.'), findsOneWidget);
    expect(find.textContaining('état courant du poste, non celui du'), findsOneWidget);
  });

  casM14('« Lancer une sauvegarde manuelle » : confirmation, fichier réellement écrit, journal (RG-12) — volume et durée MESURÉS', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lancer une sauvegarde manuelle'));
    expect(find.text('Lancer une sauvegarde immédiate ?'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Annuler'));
    expect(ecrits, isEmpty, reason: 'annuler la confirmation n\'écrit rien');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lancer une sauvegarde manuelle'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lancer la sauvegarde'));
    await t.pump(const Duration(milliseconds: 300));
    expect(ecrits.length, 1);
    expect(ecrits.single.$1, 'BK-MANUELLE-20261030.json');
    expect(find.text('Sauvegarde effectuée avec succès.'), findsOneWidget);
    expect(find.textContaining('Volume : '), findsOneWidget);
    expect(find.textContaining('412 Mo'), findsNothing, reason: 'le volume n\'est pas inventé');
    final e = m.collection('audit').toutes.first;
    expect([e['action'], e['module'], e['entite'], e['reference']], ['Création', 'M14', 'Sauvegarde', 'BK-MANUELLE']);
    expect(e['apres'], {'type': 'manuelle'});
  });

  casM14('« Tester une restauration » relit réellement le magasin sérialisé, table par table', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Tester une restauration'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Lancer le test'));
    expect(find.text('Test de restauration réussi.'), findsOneWidget);
    expect(find.textContaining('Relecture vérifiée : ${Magasin.collectionsDuJeu.length} tables'), findsOneWidget);
    expect(find.textContaining('rien n’a été restauré'), findsOneWidget);
    expect(ecrits, isEmpty);
  });

  casM14('« Restaurer » : motif exigé et journalisé, simulation DITE, aucune donnée remplacée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    final avant = jsonEncode(etatDuMagasin(m));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Restaurer').first);
    expect(find.text('Restaurer la sauvegarde du 30/10/2026 ?'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Restaurer').last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Test de restauration');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Restaurer').last);
    expect(find.text('Restauration simulée avec succès.'), findsOneWidget);
    expect(find.textContaining('aucune donnée n’est effectivement remplacée'), findsOneWidget);
    final e = m.collection('audit').toutes.first;
    expect([e['action'], e['entite'], e['reference']], ['Restauration', 'Sauvegarde', 'BK-20261030']);
    expect(e['apres'], {'motif': 'Test de restauration'});
    // Seule l'entrée de journal a bougé : les autres tables sont identiques.
    final apres = etatDuMagasin(m)..remove('audit');
    final ref = (jsonDecode(avant) as Map)..remove('audit');
    expect(jsonEncode(apres), jsonEncode(ref));
  });

  casM14('« Importer par module » n\'est pas porté : refus nommé, rien n\'est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-sauvegardes');
    final avant = m.collection('audit').toutes.length;
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Importer par module'));
    expect(find.text('Import par module non porté sur le poste.'), findsOneWidget);
    expect(find.textContaining('RG-14 : rien ne se supprime'), findsOneWidget);
    expect(m.collection('audit').toutes.length, avant);
  });

  casM14('« Exporter le journal des sauvegardes » : l\'état porte le cartouche et les deux signatures', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-sauvegardes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Exporter le journal des sauvegardes'));
    expect(find.text('Historique glissant — situation au 30/10/2026'), findsOneWidget);
    expect(find.text('La Directrice Administrative'), findsOneWidget);
    expect(find.text('TAKI Alimatou'), findsOneWidget);
  });

  casM14('lecture seule : générer, importer, lancer et restaurer sont ABSENTS ; télécharger et tester restent offerts', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-sauvegardes',
        role: 'da', donnees: donneesLectureSeule('da', 'm14-sauvegardes'));
    expect(find.text('Sauvegardes conservées'), findsOneWidget);
    for (final c in ['Générer une sauvegarde', 'Importer par module', 'Lancer une sauvegarde manuelle', 'Restaurer']) {
      expect(find.widgetWithText(BoutonSigh, c), findsNothing, reason: c);
    }
    expect(find.byTooltip('Télécharger'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Tester une restauration'), findsOneWidget);
  });
}
