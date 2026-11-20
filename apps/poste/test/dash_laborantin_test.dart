import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-laborantin` : comparé au relevé de l'écran réel (dont les deux séries tirées au hasard par la maquette et les deux compteurs écrits en dur) ;
/// le rappel du matin s'ouvre une fois par jour et par poste, et seulement s'il y a quelque chose à dire.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-laborantin']);

  testWidgets('relevé de la maquette : premier regard (validation biologique), indicateurs, classement, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-laborantin', role: 'laborantin');
    comparer(t, v);
    await finir(t);
  });

  testWidgets('le rappel du matin dit ce qui attend le poste, une fois par jour', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'dash-laborantin', role: 'laborantin');
    final modale = sp('${(v['dialogue'] as List).first}');
    expect(find.text('Rappel du laboratoire'), findsOneWidget);
    // Les deux comptes du rappel sont ceux que la maquette a affichés sur le même jeu et la même horloge.
    final comptes = RegExp(r'(\d+) analyse\(s\) réglée\(s\)').firstMatch(modale)!.group(1)!;
    final recus = RegExp(r'(\d+) échantillon\(s\) reçu\(s\)').firstMatch(modale)!.group(1)!;
    expect(find.textContaining('$comptes analyse(s) réglée(s) à la caisse, prélèvement à faire'), findsOneWidget);
    expect(find.textContaining('$recus échantillon(s) reçu(s), résultat à renseigner'), findsOneWidget);
    expect(find.text('Salle de prélèvement'), findsWidgets);
    await t.tap(find.text('J’ai pris connaissance'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Rappel du laboratoire'), findsNothing);
    // Second passage le même jour, sur le même poste : la modale ne se rouvre pas.
    await ouvrir(t, m, 'dash-laborantin', role: 'laborantin');
    expect(find.text('Rappel du laboratoire'), findsNothing);
    expect(obj(vecteurs()['dash-laborantin#secondPassage'])['dialogue'], isEmpty);
    await finir(t);
  });

  testWidgets('rien à dire : aucune modale (elle coûterait un clic pour aucune information)', (t) async {
    final m = magasin();
    for (final d in m.collection('demandesAnalyses').actives.toList()) {
      m.collection('demandesAnalyses').archiver(d['id']);
    }
    await ouvrir(t, m, 'dash-laborantin', role: 'laborantin');
    expect(find.text('Rappel du laboratoire'), findsNothing);
    expect(find.text('Aucun résultat en attente de validation biologique.'), findsOneWidget);
    await finir(t);
  });

  testWidgets('le bouton du rappel ouvre l\'écran visé, et la modale se referme', (t) async {
    await ouvrir(t, magasin(), 'dash-laborantin', role: 'laborantin');
    final dansModale = find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.text('Salle de prélèvement'));
    expect(dansModale, findsOneWidget);
    await t.tap(dansModale);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Rappel du laboratoire'), findsNothing);
    await finir(t);
  });
}
