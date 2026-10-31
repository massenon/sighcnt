import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// m14-soignants : la fiche est DÉRIVÉE du personnel ; deux droits distincts (prescrit / exécute) ; rien ne se supprime.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  /// Ouvre le champ à choix multiple, coche [libelles] (le panneau reste ouvert d'un choix à l'autre), puis le referme en touchant le titre.
  Future<void> cocherPlusieurs(WidgetTester t, String champ, List<String> libelles) async {
    await toucherM14(
        t,
        find.descendant(
                of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell))
            .first);
    await t.pump(const Duration(milliseconds: 400));
    for (final l in libelles) {
      await t.tap(find.descendant(of: find.byType(InkWell), matching: find.text(l)).last);
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.tapAt(const Offset(5, 5));
    await t.pump(const Duration(milliseconds: 400));
  }

  casM14('ouverture : les 15 soignants du jeu, quatre indicateurs, trois onglets avec leur compte', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-soignants');
    expect(find.text('Soignants'), findsWidgets);
    for (final k in ['Prescripteurs', 'Exécutants de soins', 'Cumulent les deux']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(m.collection('soignants').actives.length, 15);
    // 6 prescripteurs, 10 exécutants, 3 qui cumulent : les effectifs de la Direction.
    final a = m.collection('soignants').actives;
    expect(a.where((x) => x['prescrit'] == true).length, 6);
    expect(a.where((x) => x['execute'] == true).length, 10);
    expect(a.where((x) => x['prescrit'] == true && x['execute'] == true).length, 3);
    for (final e in ['AGENT', 'POSTE', 'QUALITÉ', 'PRESCRIT', 'EXÉCUTE', 'SECTEURS']) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
    expect(find.text('Nouveau soignant'), findsOneWidget);
    expect(find.textContaining('3 médecins, 3 sages-femmes, 7 infirmiers'), findsOneWidget);
  });

  casM14('création : la fiche reprend le nom et le poste du dossier RH, les indicateurs se recalculent, l\'annulation ARCHIVE', (t) async {
    final m = magasinM14();
    final deja = m.collection('soignants').actives.map((s) => s['personnelId']).toSet();
    final agent = m.collection('personnel').actives.firstWhere((p) => !deja.contains(p['id']));
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau soignant'));
    await choisirM14(t, 'personnelId', '${agent['nomComplet']} — ${agent['poste'] ?? agent['fonction']}');
    await choisirM14(t, 'qualite', 'Infirmier');
    await cocherPlusieurs(t, 'secteurs', ['Salle de soins', 'Maternité']);
    await cocher(t, 'execute');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final s = m.collection('soignants').actives.first;
    expect(s['personnelId'], agent['id']);
    expect(s['nomComplet'], agent['nomComplet'], reason: 'dérivé du personnel, jamais ressaisi');
    expect(s['poste'], agent['poste']);
    expect(s['qualite'], 'infirmier');
    expect(s['execute'], true);
    expect(s['prescrit'], false);
    expect(s['secteurs'], ['salle_soins', 'maternite']);
    expect(s['source'], 'Habilitation saisie par l’administrateur');
    expect(find.text('Soignant créé.'), findsOneWidget);
    expect(m.collection('soignants').actives.length, 16);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Création' && a['reference'] == s['id']), isTrue);
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('soignants').actives.length, 15);
    expect(m.collection('soignants').archivees.single['id'], s['id'], reason: 'RG-14 : la fiche est archivée, jamais supprimée');
  });

  casM14('sans secteur d\'exercice : le formulaire est en erreur, rien n\'est écrit', (t) async {
    final m = magasinM14();
    final agent = m.collection('personnel').actives.first;
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau soignant'));
    await choisirM14(t, 'personnelId', '${agent['nomComplet']} — ${agent['poste'] ?? agent['fonction']}');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(find.text('Ce champ est obligatoire.'), findsWidgets);
    expect(m.collection('soignants').actives.length, 15);
  });

  casM14('onglets : « Prescripteurs » et « Exécutants » filtrent la même collection', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.textContaining('Prescripteurs').last);
    expect(find.text('Affichage de 1 à 6 sur 6 enregistrements'), findsOneWidget);
    await toucherM14(t, find.textContaining('Exécutants').last);
    expect(find.text('Affichage de 1 à 10 sur 10 enregistrements'), findsOneWidget);
  });

  casM14('modification : l'habilitation à exécuter change, le nom reste celui du dossier RH', (t) async {
    final m = magasinM14();
    // La première ligne du tableau (tri par nom) : sa commande « Modifier » est la première.
    final cible = ([...m.collection('soignants').actives]..sort((x, y) => '${x['nomComplet']}'.compareTo('${y['nomComplet']}'))).first;
    final avant = cible['execute'] == true;
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.byTooltip('Modifier').first);
    await cocher(t, 'execute');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final apres = m.collection('soignants').parId(cible['id'])!;
    expect(apres['execute'], !avant);
    expect(apres['nomComplet'], cible['nomComplet']);
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  casM14('archivage : le motif est exigé et journalisé ; la fiche reste au magasin', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.byTooltip('Archiver').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    expect(m.collection('soignants').archivees, isEmpty);
    await t.enterText(find.byType(TextField).last, 'Départ du service');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(m.collection('soignants').archivees.length, 1);
    expect(m.collection('soignants').toutes.length, 15);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Motif d’archivage' && '${a['apres']}'.contains('Départ du service')), isTrue);
  });

  casM14('la fiche en tiroir : la qualité et sa règle', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-soignants');
    await toucherM14(t, find.byTooltip('Consulter').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Réalise l’imagerie'), findsOneWidget);
    expect(find.text('Origine de la fiche'), findsOneWidget);
  });

  casM14('lecture seule : « Nouveau soignant », « Modifier » et « Archiver » sont ABSENTS', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm14-soignants',
        role: 'da', donnees: donneesLectureSeule('da', 'm14-soignants'));
    expect(find.text('Soignants'), findsWidgets);
    expect(find.text('Nouveau soignant'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.byTooltip('Consulter'), findsWidgets);
  });
}
