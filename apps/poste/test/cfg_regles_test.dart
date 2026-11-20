import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-regles : les règles (effet mesuré, familles, statut des sources) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfb_regles_test.dart) ;
/// ici, l'ÉCRAN — la bascule de valorisation (confirmée, journalisée, écrite aux réglages), ce qui est inerte sans le droit d'écrire, l'état imprimé.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouverture : quatre indicateurs, sept familles rangées par groupe, 15 documents sources et 14 règles de gestion', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles');
    for (final k in ['Documents sources', 'Intégrés au système', 'À importer', 'Règles de gestion', 'RG-01 à RG-14']) {
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(find.text('Pharmacie et consommables de soins'), findsWidgets);
    expect(find.text('Médicaments'), findsWidgets);
    expect(find.text('Réactifs de laboratoire'), findsWidgets);
    expect(find.text('Ouvrir'), findsNWidgets(15));
    expect(find.text('RG-14'), findsWidgets);
    expect(find.text('Consulter les notes'), findsOneWidget);
  });

  casM14('le prix de vente est en vigueur par défaut ; l’effet mesuré est CALCULÉ sur le stock du jeu (246 F, 49 articles sur 184)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles');
    expect(find.text('En vigueur'), findsOneWidget);
    expect(find.textContaining('246'), findsWidgets);
    expect(find.textContaining('un effet d’arrondi, non une différence de méthode'), findsOneWidget);
    expect(find.textContaining('49 article(s) sur 184'), findsOneWidget);
  });

  casM14('passer au CUMP : la confirmation nomme la méthode ; refusée, rien ne change ; confirmée, le réglage est écrit, journalisé, annoncé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles');
    await toucherM14(t, find.byKey(const Key('cfb:valo:cump')));
    expect(find.textContaining('Valoriser les sorties au coût unitaire moyen pondéré (cump) ?'), findsOneWidget);
    await toucherM14(t, find.text('Annuler').last);
    expect(m.collection('reglages').actives, isEmpty, reason: 'refusée : rien d’écrit');
    await toucherM14(t, find.byKey(const Key('cfb:valo:cump')));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
    final f = m.collection('reglages').actives.single;
    expect([f['id'], f['valeur']], ['valorisationSortie', 'cump']);
    final j = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Paramétrage');
    expect([j['module'], j['entite'], j['reference']], ['M6', 'Valorisation des sorties', 'cump']);
    expect(j['avant'], {'methode': 'prixVente'});
    expect(j['apres'], {'methode': 'cump'});
    expect(find.text('Sorties valorisées au coût unitaire moyen pondéré (cump).'), findsOneWidget);
    expect(find.text('Applicable aux prochaines sorties de stock.'), findsOneWidget);
    expect(find.text('En vigueur'), findsOneWidget);
    // retour au prix de vente : le même réglage est mis à jour, jamais dupliqué
    await toucherM14(t, find.byKey(const Key('cfb:valo:prixVente')));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
    expect(m.collection('reglages').actives.single['valeur'], 'prixVente');
    expect(find.text('Sorties valorisées au prix de vente.'), findsOneWidget);
  });

  casM14('cliquer la méthode déjà en vigueur : aucune confirmation, aucune écriture', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles');
    await toucherM14(t, find.byKey(const Key('cfb:valo:prixVente')));
    expect(find.widgetWithText(BoutonSigh, 'Appliquer'), findsNothing);
    expect(m.collection('reglages').toutes, isEmpty);
  });

  casM14('droits : en lecture seule, la bascule est INERTE (la maquette la laisse à tout profil) et le bandeau le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-regles'));
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('cfb:valo:cump')));
    expect(find.widgetWithText(BoutonSigh, 'Appliquer'), findsNothing);
    expect(m.collection('reglages').toutes, isEmpty);
  });

  casM14('« Imprimer la matrice » ouvre l’aperçu de la pièce, signée de la Directrice Administrative et du Directeur Médical', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-regles');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la matrice'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Matrice de traçabilité des règles métier'), findsWidgets);
    expect(find.textContaining('Directrice Administrative'), findsWidgets);
    expect(find.textContaining('Directeur Médical'), findsWidgets);
  });
}
