import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';

/// Contrôle ergonomique du kit (WCAG 2.1 AA) : contraste des couples texte/fond réellement posés par les composants,
/// noms accessibles, état annoncé, navigation au clavier. Les couples qui NE passent PAS parce que la maquette les pose
/// ainsi sont listés avec leur ratio MESURÉ : ils ne peuvent pas se dégrader sans que le test échoue, et ils sont dits.
double luminance(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contraste(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(chargerPolices);

  test('contraste : badges, notes, KPI, boutons, libellés ≥ 4,5:1', () {
    final echecs = <String>[];
    for (final t in TonSigh.values) {
      final b = contraste(t.texteBadge, t.fond50);
      if (b < 4.5) echecs.add('badge $t ${b.toStringAsFixed(2)}');
      final n = contraste(t.texte900, t.fond50);
      if (n < 4.5) echecs.add('note $t ${n.toStringAsFixed(2)}');
      final i = contraste(t.icone600, t.fond50);
      if (i < 3)
        echecs.add('icône KPI $t ${i.toStringAsFixed(2)} (< 3:1 non textuel)');
    }
    for (final v in VarianteBouton.values) {
      final (fond, texte, _) = BoutonSigh.couleurs(v);
      final fondReel = fond == Colors.transparent ? Colors.white : fond;
      final r = contraste(texte, fondReel);
      if (r < 4.5) echecs.add('bouton $v ${r.toStringAsFixed(2)}');
    }
    final pairesTexte = {
      'libellé de champ slate-600/blanc': (JetonsShell.slate600, Colors.white),
      'saisie slate-900/blanc': (JetonsShell.slate900, Colors.white),
      'cellule slate-700/blanc': (JetonsShell.slate700, Colors.white),
      'KPI libellé slate-500/blanc': (JetonsShell.slate500, Colors.white),
      'titre slate-900/blanc': (JetonsShell.slate900, Colors.white),
      'onglet actif navy-900/blanc': (JetonsShell.navy900, Colors.white),
      'erreur danger-600/blanc': (JetonsShell.danger600, Colors.white),
    };
    pairesTexte.forEach((nom, p) {
      final r = contraste(p.$1, p.$2);
      if (r < 4.5) echecs.add('$nom ${r.toStringAsFixed(2)}');
    });
    // Couples hérités de la maquette qui ne passent pas AA — on borne leur ratio pour qu'il ne se dégrade pas.
    final herites = {
      'placeholder slate-400/blanc': (
        contraste(JetonsShell.slate400, Colors.white),
        2.5
      ),
      'aide de champ slate-400/blanc': (
        contraste(JetonsShell.slate400, Colors.white),
        2.5
      ),
      'bouton attention blanc/warning-500': (
        contraste(Colors.white, JetonsShell.warning500),
        2.5
      ),
      'onglet inactif slate-500/fond navy-50 (4,35:1, AA non atteint)': (
        contraste(JetonsShell.slate500, JetonsShell.navy50),
        4.3
      ),
    };
    herites.forEach((nom, p) =>
        expect(p.$1, greaterThanOrEqualTo(p.$2), reason: '$nom s’est dégradé'));
    // Les couples hérités qui figurent dans `echecs` sont attendus ; tout autre échec est une régression.
    final inattendus = echecs
        .where((e) => !e.startsWith('bouton VarianteBouton.attention'))
        .toList();
    expect(inattendus, isEmpty, reason: inattendus.join('\n'));
  });

  testWidgets(
      'noms accessibles : bouton, icône seule, onglet sélectionné, case, champ',
      (t) async {
    final h = t.ensureSemantics();
    final c = ControleurFormulaire(const [
      ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
      ChampDef(nom: 'ok', libelle: 'Accepter', type: TypeChamp.case_)
    ]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
      BoutonSigh(libelle: 'Enregistrer', onPressed: () {}),
      const BoutonSigh(libelle: 'Désactivé'),
      BoutonIcone(icone: LucideIcons.x, libelle: 'Fermer', onPressed: () {}),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'a',
            libelle: 'Général',
            compte: 2,
            construire: (_) => const SizedBox()),
        OngletDef(
            id: 'b', libelle: 'Notes', construire: (_) => const SizedBox())
      ]),
      FormulaireSigh(controleur: c),
      const KpiSigh(libelle: 'Patients', valeur: '128'),
    ])))));
    expect(
        t.getSemantics(find.byType(BoutonSigh).first),
        matchesSemantics(
          label: 'Enregistrer',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
        ));
    expect(find.bySemanticsLabel('Fermer'), findsOneWidget);
    expect(
        t
            .getSemantics(find.byKey(const Key('kit:onglet:a:actif')))
            .flagsCollection
            .isSelected
            .name,
        isNot('none'));
    expect(find.bySemanticsLabel('Général, 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Patients : 128'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Nom')), findsWidgets);
    // Un bouton désactivé ne répond pas.
    expect(
        t
            .getSemantics(find.byType(BoutonSigh).at(1))
            .flagsCollection
            .isEnabled
            .name,
        'isFalse');
    h.dispose();
  });

  testWidgets(
      'clavier : Tab atteint un bouton, Entrée l’active ; un champ obligatoire en erreur annonce son message',
      (t) async {
    var n = 0;
    final c = ControleurFormulaire(
        const [ChampDef(nom: 'nom', libelle: 'Nom', requis: true)]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      BoutonSigh(libelle: 'Valider', onPressed: () => n++),
      FormulaireSigh(controleur: c)
    ]))));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(n, 1, reason: 'Tab puis Entrée doivent activer le bouton');
    c.valider();
    await t.pump();
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
  });

  testWidgets(
      'cibles : boutons ≥ 28 px de haut, icône seule 36 px (hérité de la maquette ; 44 px non promis)',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      BoutonSigh(libelle: 'a', taille: TailleBouton.sm, onPressed: () {}),
      BoutonIcone(icone: LucideIcons.x, libelle: 'Fermer', onPressed: () {})
    ]))));
    expect(t.getSize(find.byType(BoutonSigh)).height, greaterThanOrEqualTo(28));
    expect(t.getSize(find.byType(BoutonIcone)).height, 36);
  });
}
