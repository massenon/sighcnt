import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/demarrage_cle.dart';
import 'package:sigh_poste/donnees/persistance.dart';

/// LOT MAJ, exigence 10 : l'écran de restauration de la clé sur un poste neuf (la fonction `CleLocale.importer` existait, l'écran manquait). Refus nommés ; rien n'est écrit sur un refus.
Future<void> attendre(WidgetTester t, bool Function() jusqua) async {
  for (var i = 0; i < 1500 && !jusqua(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 10));
  }
  if (!jusqua()) fail('condition jamais atteinte');
}

bool Function() present(Finder f) => () => f.evaluate().isNotEmpty;

void main() {
  late Directory tmp;
  late String sauvegarde;
  late List<int> cleA;
  const phrase = 'phrase-de-passe-longue';

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('cle-');
    final a = CleLocale('${tmp.path}/a/cle-poste.bin');
    await a.obtenir(); // première clé de la clinique (poste d'origine)
    cleA = await a.obtenir();
    sauvegarde = await a.exporter('${tmp.path}/sigh-cle.cle', phrase);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<bool> monter(WidgetTester t, CleLocale neuve, {String? fichier}) async {
    var fini = false;
    await t.pumpWidget(MaterialApp(home: EcranDemarrageCle(cle: neuve, choisirFichier: () async => fichier, termine: () => fini = true)));
    await t.tap(find.byKey(const Key('cle:restaurer')));
    await t.pump();
    return fini;
  }

  testWidgets('poste neuf : la clé de la clinique est restaurée (même clé, aucune clé neuve fabriquée), le démarrage reprend', (t) async {
    final b = CleLocale('${tmp.path}/b/cle-poste.bin');
    var termine = false;
    await t.pumpWidget(MaterialApp(home: EcranDemarrageCle(cle: b, choisirFichier: () async => sauvegarde, termine: () => termine = true)));
    expect(cleAbsente(b.chemin), isTrue);
    await t.tap(find.byKey(const Key('cle:restaurer')));
    await t.pump();
    await t.tap(find.byKey(const Key('cle:choisir')));
    await attendre(t, present(find.textContaining('sigh-cle.cle')));
    await t.enterText(find.byKey(const Key('cle:phrase')), phrase);
    await t.tap(find.byKey(const Key('cle:confirmer')));
    await attendre(t, () => termine);
    expect(cleAbsente(b.chemin), isFalse);
    expect(await t.runAsync(() => b.obtenir()), cleA, reason: 'la clé restaurée est celle de la clinique');
  });

  testWidgets('mauvaise phrase de passe : CLE_PHRASE_INCORRECTE nommé avec son geste, aucune clé écrite', (t) async {
    final b = CleLocale('${tmp.path}/b/cle-poste.bin');
    await monter(t, b, fichier: sauvegarde);
    await t.tap(find.byKey(const Key('cle:choisir')));
    await attendre(t, present(find.textContaining('sigh-cle.cle')));
    await t.enterText(find.byKey(const Key('cle:phrase')), 'une-autre-phrase-12');
    await t.tap(find.byKey(const Key('cle:confirmer')));
    await attendre(t, present(find.byKey(const Key('cle:refus'))));
    final texte = (t.widget(find.byKey(const Key('cle:refus'))) as Text).data!;
    expect(texte, contains('CLE_PHRASE_INCORRECTE'));
    expect(texte, contains('Geste :'));
    expect(cleAbsente(b.chemin), isTrue, reason: 'rien n’est écrit sur un refus');
  });

  testWidgets('fichier qui n’est pas une sauvegarde de clé : CLE_FICHIER_INVALIDE ; aucun fichier choisi : IMPORT_SANS_CLE', (t) async {
    File('${tmp.path}/autre.txt').writeAsStringSync('ceci n’est pas une clé SIGH, assez long pour passer la longueur minimale du contrôle');
    final b = CleLocale('${tmp.path}/b/cle-poste.bin');
    await monter(t, b, fichier: '${tmp.path}/autre.txt');
    await t.tap(find.byKey(const Key('cle:confirmer')));
    await t.pump();
    expect((t.widget(find.byKey(const Key('cle:refus'))) as Text).data, contains('IMPORT_SANS_CLE'));
    await t.tap(find.byKey(const Key('cle:choisir')));
    await attendre(t, present(find.textContaining('autre.txt')));
    await t.enterText(find.byKey(const Key('cle:phrase')), phrase);
    await t.tap(find.byKey(const Key('cle:confirmer')));
    await attendre(t, present(find.textContaining('CLE_FICHIER_INVALIDE')));
    expect(cleAbsente(b.chemin), isTrue);
  });

  testWidgets('premier poste de la clinique : « créer la clé » fabrique la clé seulement sur ce geste', (t) async {
    final b = CleLocale('${tmp.path}/b/cle-poste.bin');
    var termine = false;
    await t.pumpWidget(MaterialApp(home: EcranDemarrageCle(cle: b, choisirFichier: () async => null, termine: () => termine = true)));
    expect(cleAbsente(b.chemin), isTrue, reason: 'rien n’est créé tant que personne n’a choisi');
    await t.tap(find.byKey(const Key('cle:creer')));
    await attendre(t, () => termine);
    expect(cleAbsente(b.chemin), isFalse);
    expect(await t.runAsync(() => b.obtenir()), isNot(cleA));
  });
}
