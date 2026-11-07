import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-centres-couts : les règles (code attribué, indicateurs) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfb_regles_test.dart) ;
/// ici, l'ÉCRAN — ce qui s'affiche, ce qui est refusé, écrit, archivé, et ce qui est ABSENT sans le droit.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouverture : sept centres, quatre indicateurs, en-têtes de la maquette, Nouveau présent', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts');
    expect(m.collection('centresCouts').actives.length, 7);
    for (final k in ['Centres de coûts', 'Centres d’exploitation', 'Centres de support', 'Sans responsable']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    for (final h in ['Code', 'Centre', 'Type', 'Responsable', 'Actions']) {
      expect(find.text(h.toUpperCase()), findsWidgets, reason: h);
    }
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsOneWidget);
    expect(find.text('non désigné'), findsWidgets);
  });

  casM14('création sans code : CC + rang (huitième) ; le toast nomme le centre ; annuler la création l’ARCHIVE (RG-14)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Centre Test Alpha');
    await choisirM14(t, 'type', 'Centre de support');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('centresCouts').toutes.first;
    expect(f['code'], 'CC08');
    expect(f['type'], 'support');
    expect(f['source'], 'Décision de la Direction');
    expect(find.text('Centre créé.'), findsOneWidget);
    expect(find.text('Centre Test Alpha'), findsWidgets);
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('centresCouts').toutes.first['statut'], 'archive');
    expect(m.collection('centresCouts').toutes.length, 8, reason: 'rien n’est supprimé');
  });

  casM14('un code saisi est gardé tel quel, le responsable désigné sort du compte « Sans responsable »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Centre Test Beta');
    await saisir(t, 'code', 'XYZ');
    await saisir(t, 'responsable', 'TEST Resp');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('centresCouts').toutes.first;
    expect([f['code'], f['responsable']], ['XYZ', 'TEST Resp']);
    expect(find.text('TEST Resp'), findsWidgets);
    expect(find.text('7'), findsWidgets, reason: 'sept centres sans responsable sur huit');
  });

  casM14('champ obligatoire vide : refus nommé, rien n’est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
    expect(m.collection('centresCouts').toutes.length, 7);
  });

  casM14('archivage : le motif est exigé, le centre quitte la liste de travail, jamais supprimé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts');
    await toucherM14(t, find.byTooltip('Archiver').first);
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('centresCouts').archivees, isEmpty, reason: 'sans motif, rien n’est archivé');
    await t.enterText(find.byType(TextField).last, 'Service fermé');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('centresCouts').archivees.length, 1);
    expect(m.collection('centresCouts').toutes.length, 7);
  });

  casM14('droits : en lecture seule, Nouveau, Modifier et Archiver sont ABSENTS (jamais grisés) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-centres-couts', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-centres-couts'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
