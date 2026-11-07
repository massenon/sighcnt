import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-natures-facture : les règles (code, rang, indicateurs) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfa_regles_test.dart) ;
/// ici, l'ÉCRAN — ce qui s'affiche, ce qui est refusé, écrit, archivé, et ce qui est ABSENT sans le droit.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Future<void> chercher(WidgetTester t, String q) async {
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, q);
    await t.pump(const Duration(milliseconds: 500));
  }

  casM14('ouverture : 14 natures, trois indicateurs, en-têtes de la maquette, Nouveau présent', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture');
    expect(m.collection('naturesFacture').actives.length, 14);
    expect(find.text('Natures disponibles'), findsOneWidget);
    expect(find.text('Secteurs couverts'), findsOneWidget);
    expect(find.text('Natures archivées'), findsOneWidget);
    for (final h in ['Code', 'Nature', 'Secteur émetteur', 'Origine', 'Actions']) {
      expect(find.text(h.toUpperCase()), findsWidgets, reason: h);
    }
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsOneWidget);
    expect(find.text('Restaurables depuis la corbeille'), findsOneWidget);
  });

  casM14('création sans code : quatre lettres du libellé en majuscules, rang 15, toast nommé, annulation = archivage', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'libelle', 'Soins externes test');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('naturesFacture').toutes.first;
    expect(f['libelle'], 'Soins externes test');
    expect(f['code'], 'SOIN');
    expect(f['ordre'], 15);
    expect(f['source'], 'Décision de la Direction');
    expect(find.text('Nature créé.'), findsOneWidget);
    // Annuler la création archive la fiche (RG-14) : rien n'est supprimé.
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('naturesFacture').toutes.first['statut'], 'archive');
    expect(m.collection('naturesFacture').toutes.length, 15);
  });

  casM14('champ obligatoire vide : refus nommé, rien n’est écrit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
    expect(m.collection('naturesFacture').toutes.length, 14);
  });

  casM14('modification : la fiche est corrigée, le code déjà attribué ne change pas', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture');
    await chercher(t, 'Ambulance');
    await toucherM14(t, find.byTooltip('Modifier').first);
    await saisir(t, 'libelle', 'Ambulance et transfert');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection('naturesFacture').toutes.firstWhere((x) => x['code'] == 'AMBU');
    expect(f['libelle'], 'Ambulance et transfert');
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
  });

  casM14('archivage : le motif est exigé, la nature passe aux archivées (jamais supprimée), l’indicateur le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture');
    await chercher(t, 'Ambulance');
    await toucherM14(t, find.byTooltip('Archiver').first);
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('naturesFacture').archivees, isEmpty, reason: 'sans motif, rien n’est archivé');
    await t.enterText(find.byType(TextField).last, 'Doublon');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('naturesFacture').archivees.length, 1);
    expect(m.collection('naturesFacture').toutes.length, 14);
  });

  casM14('droits : en lecture seule, Nouveau, Modifier et Archiver sont ABSENTS (jamais grisés) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-natures-facture', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-natures-facture'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
