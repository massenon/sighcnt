import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show nombre, trierPar, ciblesInventaire;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// Mouvements de stock (M6) : transferts multi-lignes, mouvements, inventaires et leur feuille, pertes. Les règles sont rejouées sur des vecteurs
/// dans `packages/domaine` ; ici, l'ÉCRAN — ce qui est écrit, refusé, annulable, et la parité de contenu N1 contre les fiches de la maquette.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');

/// Un article du magasin central, assez fourni pour qu'un transfert partiel soit possible, et au libellé unique.
Fiche article(Magasin m, {int rang = 0}) => trierPar(
        m.collection('produits').actives.where((p) => n(p['stockGros']) >= 6 && n(p['stockGros']) < 900).toList(),
        (p) => p['designation'])[rang];

String libelleArticle(Fiche p) => '${p['designation']} (disponible : ${nombre(p['stockGros'])} ${p['unite']})';

/// Un bon posé directement au registre (le jeu de la maquette n'en porte pas dans `transferts.json`).
Fiche poserBon(Magasin m, Fiche p, {String reference = 'TR-00001', num quantite = 3}) => m.collection('transferts').inserer({
      'id': 'TRF-T1',
      'reference': reference,
      'date': '2026-10-29',
      'demandeur': 'Maternité',
      'motif': 'Dotation',
      'lignes': [
        {
          'produitId': p['id'],
          'code': p['code'],
          'produit': p['designation'],
          'categorie': p['categorie'],
          'unite': p['unite'],
          'cump': p['cump'],
          'quantite': quantite,
          'lot': null,
          'peremption': null
        }
      ],
      'nbLignes': 1,
      'quantiteTotale': quantite,
      'valeur': quantite * n(p['cump']),
      'operateur': 'Testeur',
      'receptionnaire': 'Major',
      'etat': 'receptionne',
      'dateReception': '2026-10-29',
      'produit': p['designation'],
      'unite': p['unite'],
      'quantite': quantite,
    }).fiche;

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

/// Ouvre la liste du champ [champ] et y choisit [cible] (en la cherchant : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible, {String? recherche}) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, recherche ?? cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> saisir(WidgetTester t, String champ, String texte) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), texte);
  await t.pump(const Duration(milliseconds: 100));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Map<String, Object?> fiche(String id) =>
    (jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()) as Map).cast<String, Object?>();

/// Parité N1 mesurée sur l'écran ouvert, contre la fiche extraite de la maquette.
Parite mesurer(WidgetTester t, String id) => comparerContenu(id, fiche(id), textesVisibles(t));

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('parité de contenu N1 (fiches de la maquette)', () {
    for (final id in ['m6-mouvements', 'm6-inventaire', 'm6-inventaire-feuille', 'm6-pertes']) {
      cas('$id : 100 % des libellés de la maquette', (t) async {
        final m = magasin();
        // Un inventaire au registre : sans lui l'écran montre son état vide, et la maquette (extraite avec ses données) ses en-têtes.
        if (id == 'm6-inventaire') {
          m.collection('inventaires').inserer({'id': 'INV-T', 'reference': 'INV-0001', 'date': '2026-10-01', 'type': 'Mensuel', 'perimetre': 'Tous les articles', 'nbArticles': 10, 'nbEcarts': 0, 'valeurEcart': 0, 'operateur': 'X', 'statutInv': 'valide', 'lignes': []});
        }
        await ouvrir(t, m, id);
        final p = mesurer(t, id);
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
      });
    }

    cas('m6-transferts : 100 % des libellés, le registre portant des bons (le jeu livré n\'en contient pas)', (t) async {
      final m = magasin();
      poserBon(m, article(m));
      await ouvrir(t, m, 'm6-transferts');
      final p = mesurer(t, 'm6-transferts');
      expect(p.manquants, isEmpty, reason: 'm6-transferts : ${p.presents}/${p.attendus}');
    });
  });

  group('transferts gros → détail', () {
    cas('le jeu livré ne porte aucun bon : l\'état vide le dit', (t) async {
      await ouvrir(t, magasin(), 'm6-transferts');
      expect(find.text('Aucun transfert enregistré.'), findsOneWidget);
      expect(find.text('Nouveau transfert'), findsOneWidget);
    });

    cas('un bon de deux lignes : le magasin est débité, la pharmacie créditée, deux mouvements symétriques par ligne, numéro TR-00001', (t) async {
      final m = magasin();
      final a = article(m), b = article(m, rang: 1);
      final avantA = (n(a['stockGros']), n(a['stockDetail'])), avantB = (n(b['stockGros']), n(b['stockDetail']));
      final mvtAvant = m.collection('mouvements').actives.length;
      await ouvrir(t, m, 'm6-transferts');
      await toucher(t, find.text('Nouveau transfert'));
      await choisir(t, 'demandeur', 'Laboratoire');
      await choisir(t, 'article', libelleArticle(a), recherche: '${a['designation']}');
      await saisir(t, 'quantite', '2');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      await choisir(t, 'article', libelleArticle(b), recherche: '${b['designation']}');
      await saisir(t, 'quantite', '4');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      expect(find.textContaining('2 ligne(s) — valeur totale'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider le transfert'));
      final bon = m.collection('transferts').actives.single;
      expect(bon['reference'], 'TR-00001');
      expect(bon['demandeur'], 'Laboratoire');
      expect((bon['lignes'] as List).length, 2);
      expect(bon['nbLignes'], 2);
      expect(bon['quantiteTotale'], 6);
      expect(m.collection('produits').parId(a['id'])!['stockGros'], avantA.$1 - 2);
      expect(m.collection('produits').parId(a['id'])!['stockDetail'], avantA.$2 + 2);
      expect(m.collection('produits').parId(b['id'])!['stockGros'], avantB.$1 - 4);
      final mv = m.collection('mouvements').actives.where((x) => x['reference'] == 'TR-00001').toList();
      expect(mv.length, 4);
      expect(mv.where((x) => x['stockType'] == 'gros').length, 2);
      expect(mv.every((x) => x['justificatif'] == 'Bon de transfert TR-00001'), isTrue);
      expect(m.collection('mouvements').actives.length, mvtAvant + 4);
      expect(m.collection('audit').toutes.any((e) => e['entite'] == 'transferts' || e['reference'] == 'TR-00001'), isTrue, reason: 'RG-12 : journalisé');

      // L'annulation restitue TOUTES les lignes.
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('transferts').actives, isEmpty);
      expect(m.collection('produits').parId(a['id'])!['stockGros'], avantA.$1);
      expect(m.collection('produits').parId(a['id'])!['stockDetail'], avantA.$2);
      expect(m.collection('produits').parId(b['id'])!['stockGros'], avantB.$1);
      expect(m.collection('mouvements').actives.length, mvtAvant);
    });

    cas('RG-03 : une ligne qui dépasse le stock est refusée en NOMMANT l\'article ; « déjà N sur ce bon » ; le même article se cumule', (t) async {
      final m = magasin();
      final a = article(m);
      final gros = n(a['stockGros']).toInt();
      await ouvrir(t, m, 'm6-transferts');
      await toucher(t, find.text('Nouveau transfert'));
      await choisir(t, 'article', libelleArticle(a), recherche: '${a['designation']}');
      await saisir(t, 'quantite', '${gros + 1}');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      expect(find.textContaining('RG-03 — « ${a['designation']} » : ${nombre(gros)} ${a['unite']} encore disponible(s) au magasin.'), findsOneWidget);
      expect(find.textContaining('Aucune ligne sur ce bon'), findsOneWidget);
      await toucher(t, find.text('Annuler').last); // ferme le message ? non : ferme la modale
      ToastsSigh.viderPourTests();
      await t.pump();
      // Deux ajouts de l'article sur le même bon se cumulent ; le second, trop gros, nomme ce qui est déjà posé.
      await toucher(t, find.text('Nouveau transfert'));
      await choisir(t, 'article', libelleArticle(a), recherche: '${a['designation']}');
      await saisir(t, 'quantite', '${gros - 1}');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      await choisir(t, 'article', libelleArticle(a), recherche: '${a['designation']}');
      await saisir(t, 'quantite', '2');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      expect(find.textContaining('(déjà ${nombre(gros - 1)} sur ce bon)'), findsOneWidget);
      await choisir(t, 'article', libelleArticle(a), recherche: '${a['designation']}');
      await saisir(t, 'quantite', '1');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider le transfert'));
      final bon = m.collection('transferts').actives.single;
      expect((bon['lignes'] as List).length, 1, reason: 'le même article se cumule sur une seule ligne');
      expect(((bon['lignes'] as List).single as Map)['quantite'], gros);
      expect(m.collection('produits').parId(a['id'])!['stockGros'], 0, reason: 'le cumul exact du stock est accepté, jamais au-delà');
    });

    cas('un bon vide est refusé, rien n\'est écrit', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-transferts');
      await toucher(t, find.text('Nouveau transfert'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider le transfert'));
      expect(find.text('Ajouter au moins un article au bon.'), findsOneWidget);
      expect(m.collection('transferts').actives, isEmpty);
    });

    cas('« Modifier » REFUSE en expliquant : archiver puis réémettre ; le bon archivé, annulable', (t) async {
      final m = magasin();
      final a = article(m);
      final bon = poserBon(m, a);
      await ouvrir(t, m, 'm6-transferts');
      await toucher(t, find.byTooltip('Modifier le bon').first);
      expect(find.text('Un bon de transfert ne se modifie pas'), findsOneWidget);
      expect(find.textContaining('archiver ce bon, puis en émettre un nouveau'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver ce bon'));
      expect(m.collection('transferts').parId(bon['id'])!['statut'], 'archive');
      expect(m.collection('transferts').actives, isEmpty);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('transferts').actives.length, 1);
    });

    cas('le tiroir porte le bon ENTIER avec son total calculé ; les deux vues lisent les mêmes lignes', (t) async {
      final m = magasin();
      final a = article(m);
      poserBon(m, a, quantite: 5);
      await ouvrir(t, m, 'm6-transferts');
      await toucher(t, find.byTooltip('Voir les articles du bon').first);
      await t.pumpAndSettle();
      expect(find.text('Bon de transfert TR-00001'), findsOneWidget);
      expect(find.textContaining('TOTAL — 1 article(s)'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer le bon'));
      await t.pumpAndSettle();
      expect(find.text('TOTAL DU BON'), findsOneWidget);
    });

    cas('sans le droit d\'écrire (Direction : lecture), « Nouveau transfert », « Modifier le bon » et « Archiver » sont ABSENTS (jamais grisés)', (t) async {
      final m = magasin();
      poserBon(m, article(m));
      await ouvrir(t, m, 'm6-transferts', role: 'direction');
      expect(find.text('Bons de transfert'), findsWidgets, reason: 'la Direction LIT les transferts');
      expect(find.text('Nouveau transfert'), findsNothing);
      expect(find.byTooltip('Modifier le bon'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Voir les articles du bon'), findsWidgets);
    });
  });

  group('mouvements de stock', () {
    cas('RG-03 : une sortie supérieure au stock concerné est refusée, le disponible est dit ; une entrée s\'enregistre SANS toucher au stock', (t) async {
      final m = magasin();
      final p = article(m);
      final gros = n(p['stockGros']);
      final avant = m.collection('mouvements').actives.length;
      await ouvrir(t, m, 'm6-mouvements');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
      await choisir(t, 'produitId', '${p['designation']} (stock : ${p['stock']})', recherche: '${p['designation']}');
      await choisir(t, 'type', 'Sortie');
      await saisir(t, 'quantite', '${gros + 1}');
      await saisir(t, 'justificatif', 'FAC-TEST');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('RG-03 — sortie de ${gros.toInt() + 1} impossible : stock disponible de ${gros.toInt()} seulement.'), findsOneWidget);
      expect(m.collection('mouvements').actives.length, avant);
      // Même formulaire : une ENTRÉE passe, elle porte le rang suivant de la série M et n'écrit rien dans le stock.
      await choisir(t, 'type', 'Entrée');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final nouveau = m.collection('mouvements').actives.first;
      expect(m.collection('mouvements').actives.length, avant + 1);
      expect(nouveau['type'], 'entree');
      expect(nouveau['typeLabel'], 'Entrée');
      expect(nouveau['utilisateur'], isNotEmpty);
      expect(nouveau['produit'], p['designation']);
      final rangs = m.collection('mouvements').toutes.map((x) => RegExp(r'^M(\d{6})$').firstMatch('${x['reference']}')).whereType<RegExpMatch>().map((x) => int.parse(x.group(1)!)).toList();
      expect('${nouveau['reference']}', 'M${(rangs.reduce((a, b) => a > b ? a : b)).toString().padLeft(6, '0')}', reason: 'le nouveau numéro est le plus grand de la série');
      expect(rangs.where((r) => r == int.parse('${nouveau['reference']}'.substring(1))).length, 1, reason: 'aucun doublon de numéro (E17)');
      expect(m.collection('produits').parId(p['id'])!['stockGros'], gros, reason: 'écart E20 : un mouvement saisi ne modifie pas le stock');
    });

    cas('l\'onglet « Archivés » : un mouvement archivé y passe, restaurable', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-mouvements');
      final premier = m.collection('mouvements').actives.first;
      m.collection('mouvements').archiver(premier['id']);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Archivés'), findsWidgets);
      await toucher(t, find.textContaining('Archivés').first);
      expect(find.byTooltip('Restaurer'), findsWidgets);
    });
  });

  group('feuille d\'inventaire', () {
    cas('un inventaire du magasin DÉTAIL régularise le détail seul : un mouvement par écart, annulable en bloc', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-inventaire');
      expect(find.text('Aucun inventaire enregistré.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Lancer un inventaire'));
      await choisir(t, 'magasin', 'Stock détail (pharmacie d’urgence)');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir la feuille de saisie'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Feuille d’inventaire'), findsWidgets);
      expect(find.text('Stock détail (pharmacie d’urgence)'), findsWidgets);
      final cible = ciblesInventaire(m.collection('produits').actives, 'Tous les articles');
      final p = cible.first;
      final theo = n(p['stockDetail']);
      final gros = n(p['stockGros']), stock = n(p['stock']);
      final regulAvant = m.collection('mouvements').actives.where((x) => x['type'] == 'inventaire').length;
      await t.enterText(find.byKey(Key('inv:${p['code']}')), '${theo.toInt() + 5}');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('+5'), findsWidgets);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider l’inventaire').last);
      final inv = m.collection('inventaires').actives.single;
      expect(inv['reference'], 'INV-0001');
      expect(inv['magasin'], 'detail');
      expect(inv['nbEcarts'], 1);
      expect(inv['nbArticles'], cible.length);
      final apres = m.collection('produits').parId(p['id'])!;
      expect(apres['stockDetail'], theo + 5);
      expect(apres['stockGros'], gros, reason: 'le magasin non compté n\'est jamais touché');
      expect(apres['stock'], stock + 5);
      final mv = m.collection('mouvements').actives.first;
      expect(mv['type'], 'inventaire');
      expect(mv['stockType'], 'detail');
      expect(mv['justificatif'], 'Inventaire INV-0001');
      expect(mv['quantite'], 5);
      // La feuille se referme sur son résultat ; l'annulation revient sur l'opération ENTIÈRE.
      expect(find.text('Inventaire INV-0001 — validé'), findsOneWidget);
      expect(find.text('Revenir au registre des inventaires'), findsOneWidget);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('inventaires').actives, isEmpty);
      final restitue = m.collection('produits').parId(p['id'])!;
      expect(restitue['stockDetail'], theo);
      expect(restitue['stock'], stock);
      expect(m.collection('mouvements').actives.where((x) => x['type'] == 'inventaire').length, regulAvant);
    });

    cas('ouverte à froid, la feuille prend les valeurs de la maquette (magasin gros, tous les articles) ; sans le droit, elle n\'écrit pas', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-inventaire-feuille');
      expect(find.text('Stock gros (magasin central)'), findsWidgets);
      expect(find.text('Comptage — Tous les articles'), findsOneWidget);
      expect(find.text('Valider l’inventaire'), findsWidgets);
    });
  });

  group('pertes, casses & rebuts', () {
    cas('une perte supérieure au stock est refusée en NOMMANT l\'article ; une perte valide est un mouvement valorisé au CUMP, annulable', (t) async {
      final m = magasin();
      final p = article(m);
      final stock = n(p['stock']);
      final cump = n(p['cump']);
      final avant = m.collection('mouvements').actives.length;
      await ouvrir(t, m, 'm6-pertes');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Déclarer une perte'));
      await choisir(t, 'produitId', '${p['designation']} (Stock ${nombre(stock)} ${p['unite']} — CUMP ${nombre(cump)})', recherche: '${p['designation']}');
      await saisir(t, 'quantite', '${stock.toInt() + 1}');
      await saisir(t, 'justificatif', 'PV-TEST');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Déclarer la perte').last);
      expect(find.text('Perte supérieure au stock.'), findsOneWidget);
      expect(find.textContaining('${p['designation']} — ${nombre(stock)} en stock, ${nombre(stock.toInt() + 1)} déclaré(s). RG-03'), findsOneWidget);
      expect(m.collection('mouvements').actives.length, avant);
      expect(m.collection('produits').parId(p['id'])!['stock'], stock);

      await saisir(t, 'quantite', '2');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Déclarer la perte').last);
      expect(m.collection('mouvements').actives.length, avant + 1);
      final mv = m.collection('mouvements').actives.first;
      expect(mv['type'], 'casse');
      expect(mv['typeLabel'], 'Casse / bris', reason: 'E18 : la colonne Nature du registre ne reste pas vide');
      expect(mv['valeur'], 2 * cump);
      expect(mv['justificatif'], 'PV-TEST');
      expect(mv['reference'], startsWith('MVT-'));
      expect(m.collection('produits').parId(p['id'])!['stock'], stock - 2);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Déclaration de perte'), isTrue);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('mouvements').actives.length, avant);
      expect(m.collection('produits').parId(p['id'])!['stock'], stock, reason: 'le stock est rétabli');
    });

    cas('le registre des pertes ne lit que les pertes, casses et péremptions des mouvements', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-pertes');
      final attendu = m.collection('mouvements').actives.where((x) => const ['perte', 'casse', 'peremption'].contains(x['type'])).length;
      expect(find.text('Événements enregistrés'), findsOneWidget);
      expect(find.text(nombre(attendu)), findsWidgets);
    });
  });

  group('droits : une commande interdite est ABSENTE', () {
    cas('mouvements, pertes et inventaires en lecture : aucune commande d\'écriture, le bandeau dit pourquoi', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-mouvements', role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      await ouvrir(t, m, 'm6-pertes', role: 'direction');
      expect(find.text('Déclarer une perte'), findsNothing);
      expect(find.text('Éditer le constat'), findsOneWidget, reason: 'imprimer le constat reste ouvert à la lecture');
      await ouvrir(t, m, 'm6-inventaire', role: 'direction');
      expect(find.text('Lancer un inventaire'), findsNothing);
    });

    cas('la feuille d\'inventaire sans le droit d\'écrire : elle le dit et n\'offre aucun comptage', (t) async {
      await ouvrir(t, magasin(), 'm6-inventaire-feuille', role: 'direction');
      expect(find.textContaining('consulte les inventaires sans les saisir'), findsOneWidget);
      expect(find.text('Revenir au registre'), findsOneWidget);
      expect(find.text('Valider l’inventaire'), findsNothing);
    });
  });
}
