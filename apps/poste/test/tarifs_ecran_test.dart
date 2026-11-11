import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// L'ÉCRAN UNIQUE « Tarifs et prix » (lot T6, étape 4). Les règles (résolution, proposition, décision, refus nommés) sont rejouées sur les vecteurs de la maquette par
/// `packages/domaine/test/tarifs_test.dart` ; la parité N1 est mesurée par `cfg_parite_test.dart` et `parite_ecrans_test.dart`. Ici, l'ÉCRAN : ce qu'il montre, les deux droits
/// (proposer, décider), le geste de chaque onglet, et ce qui est ABSENT sans le droit (jamais grisé).
String _prix(Magasin m, String code, {int jours = 0}) {
  final r = TarifsPoste.prix(m, code, tarIso(aujourdhui.add(Duration(days: jours))), false, aujourdhui: aujourdhui);
  return '${r.montant}';
}

Future<void> onglet(WidgetTester t, String id) async {
  final f = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:$id'));
  await toucherM14(t, f.first);
}

Future<void> chercher(WidgetTester t, String texte) async {
  await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, texte);
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouverture : quatre indicateurs, six onglets avec leur compte, la grille imprimée des analyses attend sa décision', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs');
    expect(find.text('Tarifs et prix'), findsWidgets);
    for (final k in ['Prestations tarifées', 'Prix en vigueur', 'Propositions en attente', 'Sans prix en vigueur']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('201'), findsWidgets, reason: 'les 201 prestations du référentiel');
    expect(find.text('39'), findsWidgets, reason: 'les 39 prix de la grille imprimée des analyses sont des PROPOSITIONS à décider');
    for (final o in ['Prestations', 'Analyses', 'Imagerie', 'Produits', 'Alertes', 'Historique']) {
      expect(find.text(o), findsWidgets, reason: o);
    }
    for (final h in ['Libellé de facturation', 'Prix non assuré', 'Prix assuré', 'Couverture', 'En vigueur depuis', 'Version']) {
      expect(find.text(h.toUpperCase()), findsWidgets, reason: h);
    }
    expect(find.text('Imprimer la grille'), findsOneWidget);
    expect(find.text('Nouvelle prestation'), findsOneWidget);
  });

  casM14('PROPOSER ne change RIEN ; le Oui (onglet Alertes) met le prix en vigueur à sa date ; le retour part à l\'auteur', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await chercher(t, 'MG01');
    await toucherM14(t, find.byTooltip('Proposer un changement').first);
    await saisir(t, 'prixNonAssure', '5200');
    await saisir(t, 'prixAssure', '3100');
    await saisir(t, 'motif', 'Test : réajustement');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final v = TarifsPoste.lire(m).versionsDe('MG01').last;
    expect([v['statut'], v['prixNonAssure'], v['proposeRole']], ['propose', 5200, 'da']);
    expect(_prix(m, 'MG01'), '5000', reason: 'une proposition ne change RIEN');
    expect(find.text('Proposition enregistrée : elle attend la décision (Oui ou Non).'), findsOneWidget);
    // L'enregistrement mène aux alertes : la ligne attend un Oui ou un Non.
    expect(find.text('Non assuré proposé'.toUpperCase()), findsWidgets);
    await chercher(t, 'MG01');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui, valider'));
    expect(_prix(m, 'MG01'), '5200', reason: 'le Oui met le prix en vigueur à sa date d\'effet');
    final apres = TarifsPoste.lire(m).versionsDe('MG01').last;
    expect([apres['statut'], apres['roleDecision']], ['valide', 'da']);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Changement de prix : validation').length, 1, reason: 'UNE ligne de journal par transition (RG-12)');
  });

  casM14('un NON exige son motif, le prix ne change pas, la proposition reste lisible à l\'historique', (t) async {
    final m = magasinM14();
    TarifsPoste(m, role: 'da', auteur: () => 'DAF', peutEditerEcran: true, horloge: () => aujourdhui)
        .proposer(DemandeProposition(code: 'MG02', prixNonAssure: 8400, etatAssure: 'unique', dateEffet: tarIso(aujourdhui), motif: 'Test'));
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await onglet(t, 'alertes');
    await chercher(t, 'MG02');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Non').first);
    // Sans motif : refusé.
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Non, refuser'));
    expect(TarifsPoste.lire(m).versionsDe('MG02').last['statut'], 'propose');
    await t.enterText(find.byType(TextField).last, 'Prix hors grille');
    await t.pump();
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Non, refuser'));
    final v = TarifsPoste.lire(m).versionsDe('MG02').last;
    expect([v['statut'], v['motifDecision'], v['roleDecision']], ['refuse', 'Prix hors grille', 'direction']);
    expect(_prix(m, 'MG02'), '8000');
    // Le retour part au poste de l'auteur (la DAF), avec le motif.
    final n = m.collection('notifications').toutes.where((x) => x['type'] == 'prix_decide').single;
    expect([n['poste'], n['libelle']], ['da', 'Votre changement de prix MG02 a été refusé']);
  });

  casM14('« Valider » à la modale met en vigueur en un geste, avec le rôle tracé ; le profil qui édite sans décider n\'a pas la commande', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await chercher(t, 'MG01');
    await toucherM14(t, find.byTooltip('Proposer un changement').first);
    await saisir(t, 'prixNonAssure', '15500');
    await saisir(t, 'motif', 'Test : validé en un geste');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
    final v = TarifsPoste.lire(m).versionsDe('MG01').last;
    expect([v['statut'], v['roleDecision'], v['motifDecision']], ['valide', 'da', 'Validée en un geste à la saisie']);
    expect(_prix(m, 'MG01'), '15500');
    expect(find.textContaining('Changement de prix validé : il prend effet le'), findsOneWidget);
  });

  casM14('ABSENT, jamais grisé, sans le droit : « Nouvelle prestation », « Proposer un changement », Oui, Non, Oui à tout', (t) async {
    final m = magasinM14();
    // La réception LIT les prix (fiche RBAC : lecture) ; elle ne propose ni ne décide.
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'reception');
    expect(find.text('Nouvelle prestation'), findsNothing);
    expect(find.byTooltip('Proposer un changement'), findsNothing);
    expect(find.byTooltip('Consulter'), findsWidgets, reason: 'elle consulte');
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await onglet(t, 'alertes');
    expect(find.widgetWithText(BoutonSigh, 'Oui'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Non'), findsNothing);
    expect(find.text('Oui à tout'), findsNothing);
    expect(find.textContaining('vous lisez les propositions sans les trancher'), findsOneWidget);
    // Un droit d'ÉDITER accordé sans la liste de décision ne donne pas la décision : le moteur refuse (VALIDATION_RESERVEE).
    final r = TarifsPoste(m, role: 'comptable', auteur: () => 'Comptable', peutEditerEcran: true, horloge: () => aujourdhui)
        .decider('${TarifsPoste.lire(m).versions.firstWhere((v) => v['statut'] == 'propose')['id']}', 'oui');
    expect(r.refus!.code, 'VALIDATION_RESERVEE');
  });

  casM14('« Oui à tout » : la comparaison ligne à ligne s\'affiche AVANT, puis chaque ligne passe par la décision ordinaire', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await onglet(t, 'alertes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui à tout'));
    expect(find.text('Oui à tout : comparaison ligne à ligne'), findsOneWidget);
    expect(find.byKey(const Key('tarifs:comparaison-oui-a-tout')), findsOneWidget);
    expect(find.text('Non assuré en vigueur'.toUpperCase()), findsWidgets);
    expect(find.text('Pièces (30 jours)'.toUpperCase()), findsWidgets);
    final avant = TarifsPoste.lire(m).versions.where((v) => v['statut'] == 'propose').length;
    expect(avant, 39);
    await toucherM14(t, find.textContaining('Oui à tout (').last);
    expect(TarifsPoste.lire(m).versions.where((v) => v['statut'] == 'propose').length, lessThan(avant), reason: 'les lignes acceptées ont pris effet');
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Changement de prix : Oui à tout'), isTrue, reason: 'un geste journalisé');
  });

  casM14('Historique : toutes les versions d\'un prix, la comparaison de deux versions', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await onglet(t, 'historique');
    await choisirM14(t, 'code', 'L01 : AKOP');
    expect(find.text('Version'.toUpperCase()), findsWidgets);
    expect(find.text('Proposée'), findsWidgets, reason: 'la version 2 de la grille imprimée attend sa décision');
    expect(find.text('Comparer deux versions'), findsOneWidget);
    expect(find.text('Variation du non assuré'), findsOneWidget);
  });

  casM14('Produits : LECTURE SEULE (RG-02), sans commande d\'écriture', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await onglet(t, 'produits');
    expect(find.textContaining('Lecture seule. RG-02'), findsOneWidget);
    expect(find.text('Prix d’achat'.toUpperCase()), findsWidgets);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
  });

  casM14('« Catalogue tarifaire (deux prix) » est une page de renvoi vers « Tarifs et prix »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-catalogue', role: 'da');
    expect(find.text('Catalogue tarifaire (deux prix)'), findsWidgets);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ouvrir « Tarifs et prix »'));
    expect(find.text('Prestations tarifées'), findsOneWidget);
  });
}
