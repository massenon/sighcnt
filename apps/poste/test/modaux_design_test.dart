import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/core/theme.dart';
import 'package:sigh_poste/kit/kit.dart';

/// LES MODAUX RESPECTENT LE DESIGN SYSTEM (Direction, 01/11/2026, point 4).
///
/// Trois gardes :
///  1. SOURCE : aucun dialogue, menu, feuille basse, sélecteur ou bandeau natif de Material hors de `lib/kit/` (le kit les habille ; le reste du poste passe
///     par `afficherModale`, `afficherTiroir`, `confirmerSigh`, `SelecteurSigh`, `ToastsSigh`). Un écran qui ouvre `showDialog` ou `AlertDialog` hérite des
///     couleurs par défaut de Material : fond teinté, aucun voile `scrim`, aucune ombre `pop`.
///  2. THÈME : le thème du poste porte le fond blanc, la teinte nulle et le rayon 12 sur chaque surface flottante de Material (filet de sécurité).
///  3. RENDU : la modale, le tiroir, la confirmation, la liste déroulante et le message du kit portent le fond de carte blanc, le voile `scrim`, le rayon 12 et
///     l'ombre `pop`.
const _interdits = <String>[
  'showDialog(',
  'showGeneralDialog(',
  'showModalBottomSheet(',
  'showBottomSheet(',
  'showMenu(',
  'showDatePicker(',
  'showTimePicker(',
  'showDateRangePicker(',
  'showSnackBar(',
  'showCupertino',
  'AlertDialog(',
  'SimpleDialog(',
  'Dialog(',
  'Dialog.fullscreen(',
  'SnackBar(',
  'BottomSheet(',
  'PopupMenuButton',
  'DropdownButton',
  'DropdownMenu(',
  'DropdownButtonFormField',
  'MenuAnchor(',
  'Drawer(',
  'endDrawer',
];

/// Les fichiers du kit sont les SEULS à toucher les composants natifs : ils les habillent.
bool _dansLeKit(String chemin) => chemin.replaceAll('\\', '/').contains('/lib/kit/');

bool _commentaire(String ligne) {
  final t = ligne.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

void main() {
  test('SOURCE : aucun dialogue, menu ou sélecteur natif hors du kit', () {
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (_dansLeKit(f.absolute.path)) continue;
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        if (_commentaire(lignes[i])) continue;
        // Les tokens ne sont cherchés que HORS d'un mot plus long (`ConfirmDialog(` ne contient pas `Dialog(` isolé).
        for (final m in _interdits) {
          final k = lignes[i].indexOf(m);
          if (k < 0) continue;
          if (k > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(lignes[i][k - 1])) continue;
          fautes.add('${f.path}:${i + 1} : $m');
        }
      }
    }
    expect(fautes, isEmpty, reason: 'Passer par le kit (afficherModale, afficherTiroir, confirmerSigh, SelecteurSigh, ToastsSigh) :\n${fautes.join('\n')}');
  });

  test('SOURCE : tout dialogue ou sélecteur ouvert par le kit déclare son voile (`scrim`)', () {
    final fautes = <String>[];
    for (final f in Directory('lib/kit').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'(showGeneralDialog|showDatePicker|showTimePicker)<?[A-Za-z]*>?\(').allMatches(s)) {
        // Le bloc d'arguments : jusqu'à la parenthèse fermante de l'appel (les arguments tiennent sur quelques dizaines de lignes).
        final bloc = s.substring(m.start, (m.start + 700).clamp(0, s.length));
        if (!bloc.contains('barrierColor')) fautes.add('${f.path} : ${m.group(0)} sans barrierColor');
      }
    }
    expect(fautes, isEmpty);
  });

  test('THÈME : chaque surface flottante de Material est blanche, sans teinte, au rayon 12', () {
    final th = ThemeSigh.clair();
    RoundedRectangleBorder? r(ShapeBorder? s) => s is RoundedRectangleBorder ? s : null;
    for (final (nom, fond, teinte, forme) in <(String, Color?, Color?, ShapeBorder?)>[
      ('dialogTheme', th.dialogTheme.backgroundColor, th.dialogTheme.surfaceTintColor, th.dialogTheme.shape),
      ('popupMenuTheme', th.popupMenuTheme.color, th.popupMenuTheme.surfaceTintColor, th.popupMenuTheme.shape),
      ('datePickerTheme', th.datePickerTheme.backgroundColor, th.datePickerTheme.surfaceTintColor, th.datePickerTheme.shape),
      ('timePickerTheme', th.timePickerTheme.backgroundColor, Colors.transparent, th.timePickerTheme.shape),
      ('bottomSheetTheme', th.bottomSheetTheme.backgroundColor, th.bottomSheetTheme.surfaceTintColor, null),
      ('snackBarTheme', th.snackBarTheme.backgroundColor, Colors.transparent, th.snackBarTheme.shape),
    ]) {
      expect(fond, Colors.white, reason: '$nom : fond de carte blanc');
      expect(teinte, Colors.transparent, reason: '$nom : aucune teinte de surface');
      if (forme != null) {
        expect(r(forme)?.borderRadius, BorderRadius.circular(12), reason: '$nom : rayon 12');
      }
    }
    expect(th.bottomSheetTheme.modalBarrierColor, JetonsShell.scrim);
    expect(th.dialogTheme.shadowColor, JetonsShell.navy950, reason: 'ombre de la famille navy, pas le noir par défaut');
  });

  testWidgets('RENDU : la modale du kit (fond blanc, rayon 12, ombre pop, voile scrim, entête, pied)', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Builder(
            builder: (c) => TextButton(
                onPressed: () => afficherModale<void>(c,
                    titre: 'Titre', corps: const Text('Corps'), pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]),
                child: const Text('ouvrir')))));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    final panneau = t.widget<Material>(find.byKey(const Key('kit:modale-panneau')));
    expect(panneau.color, Colors.white);
    expect((panneau.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(12));
    expect(find.byKey(const Key('kit:modale-entete')), findsOneWidget);
    expect(find.byKey(const Key('kit:modale-pied')), findsOneWidget);
    final ombre = t.widgetList<DecoratedBox>(find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.byType(DecoratedBox)));
    expect(ombre.any((d) => (d.decoration as BoxDecoration).boxShadow == JetonsShell.ombrePop), isTrue, reason: 'ombre pop');
    final voile = t.widget<ModalBarrier>(find.byType(ModalBarrier).last);
    expect(voile.color, JetonsShell.scrim, reason: 'voile navy-950 à 40 %');
    expect(JetonsShell.scrim.a, closeTo(0.4, 0.01));
  });

  testWidgets('RENDU : le tiroir et la confirmation du kit portent le même voile et le même fond', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Builder(
            builder: (c) => Column(children: [
                  TextButton(onPressed: () => afficherTiroir<void>(c, titre: 'Tiroir', corps: const Text('Corps')), child: const Text('tiroir')),
                  TextButton(onPressed: () => confirmerSigh(c, titre: 'Sûr ?', message: 'Message'), child: const Text('confirmer')),
                ]))));
    await t.tap(find.text('tiroir'));
    await t.pumpAndSettle();
    expect(t.widget<Material>(find.byKey(const Key('kit:tiroir-panneau'))).color, Colors.white);
    expect(t.widget<ModalBarrier>(find.byType(ModalBarrier).last).color, JetonsShell.scrim);
    await t.tapAt(const Offset(10, 300));
    await t.pumpAndSettle();
    await t.tap(find.text('confirmer'));
    await t.pumpAndSettle();
    expect(t.widget<Material>(find.byKey(const Key('kit:modale-panneau'))).color, Colors.white);
    expect(t.widget<ModalBarrier>(find.byType(ModalBarrier).last).color, JetonsShell.scrim);
  });

  testWidgets('RENDU : la liste déroulante du kit (SelecteurSigh) ouvre le panneau blanc au rayon 12, pas le menu natif', (t) async {
    var choisi = 'a';
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (c, maj) => SelecteurSigh(
                    libelle: 'Choix',
                    valeur: choisi,
                    options: const [OptionChamp('a', 'Alpha'), OptionChamp('b', 'Bravo')],
                    surChange: (v) => maj(() => choisi = v))))));
    expect(find.byType(DropdownButton<String>), findsNothing);
    await t.tap(find.text('Alpha'));
    await t.pumpAndSettle();
    expect(find.text('Bravo'), findsOneWidget);
    final panneau = t.widgetList<Material>(find.ancestor(of: find.text('Bravo'), matching: find.byType(Material))).first;
    expect(panneau.color, Colors.white);
    expect((panneau.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(12));
    await t.tap(find.text('Bravo'));
    await t.pumpAndSettle();
    expect(choisi, 'b', reason: 'le choix remonte');
    expect(find.text('Bravo'), findsOneWidget, reason: 'le panneau est refermé, la valeur est affichée');
  });

  testWidgets('RENDU : le message (toast) du kit est une carte blanche au rayon 12 et à l\'ombre pop', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Builder(builder: (c) => TextButton(onPressed: () => ToastsSigh.afficher(c, 'Fait.'), child: const Text('msg')))));
    await t.tap(find.text('msg'));
    await t.pump();
    final carte = t.widget<Container>(find.ancestor(of: find.text('Fait.'), matching: find.byType(Container)).first);
    final deco = carte.decoration as BoxDecoration;
    expect(deco.color, Colors.white);
    expect(deco.borderRadius, BorderRadius.circular(12));
    expect(deco.boxShadow, JetonsShell.ombrePop);
    ToastsSigh.viderPourTests();
    await t.pumpAndSettle();
  });
}
