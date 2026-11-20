import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));
String s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

/// cfg-types-piece et cfg-certificats : les règles (numérotation, trames, KPI) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfa_regles_test.dart) ; ici, l'ÉCRAN — les collisions de sigles CONSERVÉES et signalées, la composition du texte au fil de la
/// saisie, la délivrance (numéro, archivage au dossier, journal RG-12, impression), l'annulation motivée (RG-14) et les droits.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final tp = obj(v['typesPiece']);
  final ce = obj(v['certificats']);

  Future<void> chercher(WidgetTester t, String q) async {
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, q);
    await t.pump(const Duration(milliseconds: 500));
  }

  group('cfg-types-piece', () {
    casM14('ouverture : indicateurs, les collisions de sigles sont CONSERVÉES et nommées, en-têtes de la maquette', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-types-piece');
      for (final k in (tp['kpis'] as List).cast<List>().take(3)) {
        expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
        expect(find.text('${k[1]}'), findsWidgets, reason: '${k[0]} = ${k[1]}');
      }
      expect(find.text('Pièces délivrées'), findsOneWidget);
      expect(find.textContaining('CMA pour l’accouchement et pour l’aptitude'), findsOneWidget);
      expect(find.textContaining('Trancher appartient à la Direction.'), findsOneWidget);
      for (final h in obj(tp['tableau'])['entetes'] as List) {
        expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
      }
      expect(find.text('collision'), findsNWidgets(4));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau type de pièce'), findsOneWidget);
    });

    casM14('détail d’un sigle en collision : la numérotation et la raison de la conservation', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-types-piece');
      await chercher(t, 'Certificat médical d’aptitude');
      await toucherM14(t, find.byTooltip('Consulter').first);
      expect(find.text('CMA n°/n°/CNT/DG/DE/2026'), findsOneWidget);
      expect(find.text('SOS seule'), findsOneWidget);
      expect(find.textContaining('Le sigle est conservé tel quel'), findsOneWidget);
    });

    casM14('création : un type sans tarif est « non tarifé » ; champs obligatoires refusés, rien n’est écrit ; archivage motivé', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-types-piece');
      final avant = m.collection('typesPiece').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau type de pièce'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('typesPiece').toutes.length, avant);
      await t.pump(const Duration(seconds: 10));
      await saisir(t, 'sigle', 'TST');
      await saisir(t, 'libelle', 'Pièce test');
      await saisir(t, 'direction', 'DM');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = m.collection('typesPiece').toutes.first;
      expect([f['sigle'], f['libelle'], f['direction']], ['TST', 'Pièce test', 'DM']);
      expect(f['tarifCode'], '');
      expect(find.text('Type de pièce créé.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await chercher(t, 'Pièce test');
      await toucherM14(t, find.byTooltip('Archiver').first);
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(m.collection('typesPiece').archivees.length, 1);
      expect(m.collection('typesPiece').toutes.length, avant + 1);
    });

    casM14('droits : en lecture seule, aucune commande d’écriture', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-types-piece', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-types-piece'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau type de pièce'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
    });
  });

  group('cfg-certificats', () {
    casM14('ouverture : quatre indicateurs, huit types, registre vide qui le dit', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-certificats');
      for (final k in (ce['kpis'] as List).cast<List>()) {
        expect(find.text('${k[0]}'), findsOneWidget, reason: '${k[0]}');
      }
      expect(find.text('Types de certificats — cliquer pour rédiger'), findsOneWidget);
      expect(find.text('Registre des certificats délivrés'), findsOneWidget);
      for (final t0 in cfaTypesCertificat) {
        expect(find.text(t0.libelle), findsOneWidget, reason: t0.libelle);
      }
      expect(find.text('Aucun délivré'), findsNWidgets(8));
      expect(find.text('Aucun certificat délivré.'), findsOneWidget);
    });

    casM14('la rédaction compose le texte au fil de la saisie : points de suspension tant que le champ est vide', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-certificats');
      await toucherM14(t, find.byKey(const Key('cfa:type:initial')));
      expect(find.text('Certificat médical initial'), findsWidgets);
      String apercu() => t.widget<Text>(find.descendant(of: find.byKey(const Key('cfa:apercu-certificat')), matching: find.byType(Text))).data!;
      expect(apercu(), contains('……………'));
      expect(apercu(), contains('avoir constaté : ……………. Incapacité totale de travail estimée à …………… jour(s)'));
      await saisir(t, 'constatations', 'une plaie superficielle du bras');
      await saisir(t, 'itt', '5');
      expect(apercu(), contains('avoir constaté : une plaie superficielle du bras. Incapacité totale de travail estimée à 5 jour(s)'));
    });

    casM14('délivrance : numérotée, archivée au dossier, journalisée (RG-12), imprimée ; puis annulation MOTIVÉE (RG-14)', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-certificats');
      final patient = m.collection('patients').actives.first;
      await toucherM14(t, find.byKey(const Key('cfa:type:aptitude')));
      await choisirM14(t, 'patientCode', '${patient['code']} — ${patient['nom']} ${patient['prenom']}');
      await saisir(t, 'activite', 'la natation');
      final journalAvant = m.collection('audit').toutes.length;
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Délivrer le certificat'));
      final col = m.collection('certificats');
      expect(col.actives.length, 1);
      final f = col.actives.first;
      expect(f['numero'], 'CERT-2026-0001');
      expect(f['type'], 'aptitude');
      expect(f['patientId'], patient['id']);
      expect(f['patient'], '${patient['nom']} ${patient['prenom']}');
      expect('${f['texte']}', contains('n’avoir constaté aucune contre-indication à la pratique de : la natation.'));
      expect(find.text('Certificat CERT-2026-0001 délivré.'), findsOneWidget);
      // Le journal porte la délivrance (en plus de la création de la fiche).
      final journal = m.collection('audit').toutes.take(m.collection('audit').toutes.length - journalAvant).toList();
      expect(journal.where((j) => j['action'] == 'Délivrance de certificat' && j['reference'] == 'CERT-2026-0001'), hasLength(1));
      // La pièce s'ouvre à l'impression.
      expect(find.text('CERTIFICAT D’APTITUDE PHYSIQUE'), findsWidgets);
      expect(find.textContaining('Signature et cachet'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
      Navigator.of(t.element(find.byType(Scaffold).first), rootNavigator: true).maybePop();
      await t.pump(const Duration(milliseconds: 400));
      // Annulation : le motif est exigé, la fiche reste au registre.
      await toucherM14(t, find.byTooltip('Annuler le certificat').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler le certificat').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(col.archivees, isEmpty, reason: 'sans motif, rien n’est annulé');
      await t.enterText(find.byType(TextField).last, 'Erreur de patient');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler le certificat').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(col.archivees.length, 1);
      expect(col.toutes.length, 1);
    });

    casM14('un champ obligatoire vide est REFUSÉ en le nommant : aucun numéro n’est consommé', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-certificats');
      await toucherM14(t, find.byKey(const Key('cfa:type:aptitude')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Délivrer le certificat'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('certificats').toutes, isEmpty);
    });

    casM14('droits : sans le droit d’écrire, les types ne s’ouvrent pas ; sans le droit d’annuler, « Annuler le certificat » est ABSENT', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-certificats', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-certificats'));
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await t.tap(find.byKey(const Key('cfa:type:aptitude')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(BoutonSigh, 'Délivrer le certificat'), findsNothing);
      expect(find.byTooltip('Annuler le certificat'), findsNothing);
    });
  });
}
