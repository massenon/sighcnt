import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show money;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Achats (M7) : les règles sont rejouées sur des vecteurs de la maquette (`packages/domaine/test/achats_test.dart`) ; ici, l'ÉCRAN — ce que l'agent
/// voit, ce qui est écrit, refusé, annulable, et ce qui est ABSENT faute de droit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
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

/// L'onglet [id] — la clé de l'onglet actif porte le suffixe « :actif ».
Finder ong(String id) => find.byWidgetPredicate(
    (w) => w.key != null && RegExp("'kit:onglet:$id(:actif)?'").hasMatch('${w.key}'));

Future<void> onglet(WidgetTester t, String id) => toucher(t, ong(id));

/// Ouvre la liste du champ [champ] et y choisit [cible] (le panneau ne construit que les lignes visibles : on tape dans la recherche).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find.descendant(
              of: find.byKey(Key('kit:champ:$champ')),
              matching: find.byType(InkWell))
          .first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> ecrire(WidgetTester t, String champ, String texte) async {
  await t.enterText(
      find.descendant(
          of: find.byKey(Key('kit:champ:$champ')),
          matching: find.byType(TextField)),
      texte);
  await t.pump(const Duration(milliseconds: 200));
}

Finder bouton(String libelle) => find.widgetWithText(BoutonSigh, libelle);

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

/// Un bon posé au sommet du registre (date lointaine : la table trie par date décroissante).
Fiche poserBon(Magasin m, String ref, String etape,
        {String demandeur = 'GARBA Yahouza', String date = '2099-01-01'}) =>
    m.collection('besoins').inserer({
      'reference': ref,
      'date': date,
      'service': 'Maternité',
      'demandeur': demandeur,
      'etape': etape,
      'motif': 'Dotation',
      'statut': 'actif',
      'lignes': [
        {
          'produitId': 'PRD0001',
          'produit': 'ABAISSE LANGUE',
          'unite': 'Unité',
          'quantiteDemandee': 10,
          'quantiteAccordee': 8,
          'quantiteLivree': null,
          'prixAchat': 650
        }
      ],
      'montantEstime': 6500,
    }, prefixe: 'BES').fiche;

/// La livraison que le registre montre en tête (tri par date décroissante).
Fiche enTete(Iterable<Fiche> l) =>
    l.reduce((a, b) => '${a['date']}'.compareTo('${b['date']}') >= 0 ? a : b);

Fiche bon(Magasin m, String ref) => m
    .collection('besoins')
    .toutes
    .firstWhere((b) => b['reference'] == ref);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('besoins : quatre vues, chacune gardée par ce qu\'elle permet', () {
    cas('la DAF voit les quatre vues, avec leur compte', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      for (final id in ['miennes', 'arbitrage', 'achats', 'tous']) {
        expect(ong(id), findsOneWidget,
            reason: id);
      }
      final actifs = m.collection('besoins').actives;
      final aArbitrer = actifs
          .where((b) => ['soumis', 'controle_stock', 'validation_da'].contains(b['etape']))
          .length;
      expect(
          find.descendant(
              of: ong('arbitrage'),
              matching: find.text('$aArbitrer')),
          findsOneWidget);
      expect(find.text('Circuit de traitement'), findsOneWidget);
    });

    cas('un médecin n\'arbitre pas, n\'achète pas : il ne voit que ses demandes — et peut exprimer un besoin',
        (t) async {
      await ouvrir(t, magasin(), 'm7-besoins', role: 'medecin');
      expect(ong('miennes'), findsOneWidget);
      expect(ong('arbitrage'), findsNothing);
      expect(ong('achats'), findsNothing);
      expect(ong('tous'), findsNothing);
      expect(bouton('Nouveau bon'), findsOneWidget);
    });

    cas('le comptable lit les besoins validés et le registre, sans arbitrer',
        (t) async {
      await ouvrir(t, magasin(), 'm7-besoins', role: 'comptable');
      expect(ong('achats'), findsOneWidget);
      expect(ong('tous'), findsOneWidget);
      expect(ong('arbitrage'), findsNothing);
    });

    cas('« Mes demandes » ne montre que les bons de l\'agent connecté', (t) async {
      final m = magasin();
      // L'agent du poste est identifié par son profil : un bon à son nom apparaît, un bon au nom d'un autre non.
      poserBon(m, 'BEB-TEST-MIEN', 'soumis', demandeur: 'Directeur Médical');
      poserBon(m, 'BEB-TEST-AUTRE', 'soumis', demandeur: 'Quelqu\'un d\'autre');
      await ouvrir(t, m, 'm7-besoins', role: 'dm');
      expect(find.text('BEB-TEST-MIEN'), findsOneWidget);
      expect(find.text('BEB-TEST-AUTRE'), findsNothing);
    });
  });

  group('besoins : l\'arbitrage de la DAF', () {
    cas('valider accorde, nomme l\'arbitre et informe DEUX postes par une notification',
        (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-1', 'validation_da');
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      await onglet(t, 'arbitrage');
      await toucher(t, find.byTooltip('Valider le besoin').first);
      expect(find.text('Valider ce besoin ?'), findsOneWidget);
      expect(find.text('Observation (facultative)'), findsOneWidget);
      await toucher(t, bouton('Valider et informer'));
      final b = bon(m, 'BEB-TEST-1');
      expect(b['etape'], 'accorde');
      expect(b['valideePar'], isNotNull);
      expect(b['arbitrePar'], b['valideePar']);
      final notifs = m.collection('notifications').actives;
      expect({for (final x in notifs) x['poste']}, {'comptable', 'stock'});
      expect(notifs.every((x) => x['type'] == 'besoin_accorde' && x['reference'] == 'BEB-TEST-1'), isTrue);
      expect(notifs.every((x) => x['lue'] == false), isTrue);
      expect(find.textContaining('le comptable et le gestionnaire de stock sont informés'),
          findsOneWidget);
    });

    cas('rejeter SANS motif est refusé : rien n\'est écrit, la fenêtre reste ouverte',
        (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-2', 'soumis');
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      await onglet(t, 'arbitrage');
      await toucher(t, find.byTooltip('Rejeter avec motif').first);
      expect(find.text('Motif — obligatoire *'), findsOneWidget);
      await toucher(t, bouton('Rejeter'));
      expect(find.text('Le motif est obligatoire.'), findsWidgets);
      expect(bon(m, 'BEB-TEST-2')['etape'], 'soumis');
      expect(find.text('Rejeter ce besoin ?'), findsOneWidget);
      expect(m.collection('notifications').actives, isEmpty);
    });

    cas('rejeter AVEC motif : issue du circuit, bon conservé (non archivé) avec son motif, personne n\'est notifié',
        (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-3', 'validation_da');
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      await onglet(t, 'arbitrage');
      await toucher(t, find.byTooltip('Rejeter avec motif').first);
      await ecrire(t, 'motif', 'Déjà en stock');
      await toucher(t, bouton('Rejeter'));
      final b = bon(m, 'BEB-TEST-3');
      expect(b['etape'], 'rejete');
      expect(b['motifArbitrage'], 'Déjà en stock');
      expect(b['statut'], 'actif', reason: 'un bon rejeté n\'est pas archivé');
      expect(m.collection('notifications').actives, isEmpty);
      // Il disparaît de la file d'arbitrage (ce n'est plus une étape du circuit) mais reste au registre.
      expect(find.text('BEB-TEST-3'), findsNothing);
      await onglet(t, 'tous');
      expect(find.text('BEB-TEST-3'), findsOneWidget);
      expect(find.text('Rejeté'), findsWidgets);
    });

    cas('demander un complément exige aussi son motif', (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-4', 'controle_stock');
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      await onglet(t, 'arbitrage');
      await toucher(t, find.byTooltip('Demander un complément').first);
      await toucher(t, bouton('Demander'));
      expect(bon(m, 'BEB-TEST-4')['etape'], 'controle_stock');
      await ecrire(t, 'motif', 'Préciser la marque');
      await toucher(t, bouton('Demander'));
      expect(bon(m, 'BEB-TEST-4')['etape'], 'complement');
      expect(bon(m, 'BEB-TEST-4')['motifArbitrage'], 'Préciser la marque');
    });

    cas('les gestes d\'arbitrage n\'existent QUE dans la vue d\'arbitrage', (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-5', 'validation_da');
      await ouvrir(t, m, 'm7-besoins', role: 'da');
      await onglet(t, 'tous');
      expect(find.byTooltip('Valider le besoin'), findsNothing);
      expect(find.byTooltip('Modifier'), findsWidgets);
      await onglet(t, 'achats');
      expect(find.byTooltip('Valider le besoin'), findsNothing);
      expect(find.byTooltip('Transformer en bon de commande'), findsWidgets);
    });
  });

  group('besoins : les gestes de l\'achat', () {
    cas('transformer en commande passe le bon en préparation et ouvre les commandes', (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-6', 'accorde');
      await ouvrir(t, m, 'm7-besoins', role: 'stock');
      await onglet(t, 'achats');
      await toucher(t, find.byTooltip('Transformer en bon de commande').first);
      expect(find.textContaining('RG-04'), findsWidgets);
      await toucher(t, bouton('Ouvrir les commandes'));
      expect(bon(m, 'BEB-TEST-6')['etape'], 'prepare');
      expect(bon(m, 'BEB-TEST-6')['preparePar'], isNotNull);
    });

    cas('distribuer sort le bon du circuit d\'achat (issue « distribué »)', (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-7', 'accorde');
      await ouvrir(t, m, 'm7-besoins', role: 'stock');
      await onglet(t, 'achats');
      await toucher(t, find.byTooltip('Marquer distribué au service').first);
      await toucher(t, bouton('Distribuer'));
      expect(bon(m, 'BEB-TEST-7')['etape'], 'distribue');
      expect(find.text('Besoin BEB-TEST-7 distribué à Maternité.'), findsOneWidget);
    });
  });

  group('besoins : la saisie s\'adapte à qui l\'ouvre', () {
    Future<void> remplir(WidgetTester t) async {
      // Un article (le premier est proposé d'office), 10 demandés : on ajoute la ligne puis on crée le bon.
      await toucher(t, bouton('Ajouter'));
      await toucher(t, bouton('Créer le bon'));
    }

    cas('un médecin n\'a pas à choisir l\'étape : son bon part SOUMIS, numéroté à la suite de la série',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-besoins', role: 'medecin');
      await toucher(t, bouton('Nouveau bon'));
      expect(find.text('Étape du circuit *'), findsNothing);
      await remplir(t);
      final cree = m.collection('besoins').actives.first;
      expect(cree['etape'], 'soumis');
      expect(cree['reference'], 'BEB-2026-0021', reason: 'la série se lit sur les 20 bons existants');
      expect(cree['valideePar'], isNull);
      expect((cree['lignes'] as List).length, 1);
      expect(find.text('Bon créé — BEB-2026-0021'), findsOneWidget);
    });

    cas('le gestionnaire de stock tient le circuit : il choisit l\'étape (brouillon par défaut)',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-besoins', role: 'stock');
      await toucher(t, bouton('Nouveau bon'));
      expect(find.text('Étape du circuit *'), findsOneWidget);
      await remplir(t);
      expect(m.collection('besoins').actives.first['etape'], 'brouillon');
    });

    cas('sans article, le bon est refusé et dit pourquoi', (t) async {
      final m = magasin();
      final avant = m.collection('besoins').actives.length;
      await ouvrir(t, m, 'm7-besoins', role: 'medecin');
      await toucher(t, bouton('Nouveau bon'));
      await toucher(t, bouton('Créer le bon'));
      expect(find.text('Ajouter au moins un article.'), findsOneWidget);
      expect(m.collection('besoins').actives.length, avant);
    });

    cas('modifier un bon ne le renumérote pas et conserve son validateur', (t) async {
      final m = magasin();
      final b = poserBon(m, 'BEB-TEST-8', 'accorde');
      m.collection('besoins').mettreAJour(b['id'], {'valideePar': 'AUTRE Personne'});
      await ouvrir(t, m, 'm7-besoins', role: 'stock');
      await onglet(t, 'tous');
      await toucher(t, find.byTooltip('Modifier').first);
      await ecrire(t, 'motif', 'Revu');
      await toucher(t, bouton('Enregistrer'));
      final apres = bon(m, 'BEB-TEST-8');
      expect(apres['motif'], 'Revu');
      expect(apres['valideePar'], 'AUTRE Personne');
      expect(apres['reference'], 'BEB-TEST-8');
    });

    cas('archiver est annulable, et réservé à qui a le droit d\'annuler', (t) async {
      final m = magasin();
      poserBon(m, 'BEB-TEST-9', 'soumis', demandeur: 'Directeur Médical');
      await ouvrir(t, m, 'm7-besoins', role: 'dm');
      expect(find.byTooltip('Archiver'), findsNothing,
          reason: 'le directeur médical lit et écrit, il n\'annule pas');
    });
  });

  group('commandes : RG-04', () {
    Fiche commande(Magasin m, String ref, String statut,
            {String? valideePar}) =>
        m.collection('commandes').inserer({
          'reference': ref,
          'date': '2099-01-01',
          'fournisseur': 'CAME',
          'fournisseurNom': 'CAME — Centrale d’Achat des Médicaments Essentiels',
          'delaiLivraison': 7,
          'statutCommande': statut,
          if (valideePar != null) 'valideePar': valideePar,
          'statut': 'actif',
          'lignes': [
            {
              'produitId': 'PRD0001',
              'produit': 'ABAISSE LANGUE',
              'unite': 'Unité',
              'quantite': 10,
              'prixUnitaire': 650,
              'montant': 6500
            },
            {
              'produitId': 'PRD0002',
              'produit': 'ACCUZON',
              'unite': 'Unité',
              'quantite': 4,
              'prixUnitaire': 1000,
              'montant': 4000
            },
          ],
          'montant': 10500,
        }, prefixe: 'COM').fiche;

    cas('la DAF valide : « Validée », nommée et datée — annulable', (t) async {
      final m = magasin();
      commande(m, 'BC-TEST-1', 'attente_validation');
      await ouvrir(t, m, 'm7-commandes', role: 'da');
      expect(find.textContaining('en attente de validation par la Directrice Administrative'), findsOneWidget);
      await toucher(t, find.byTooltip('Valider (DA)').first);
      expect(find.text('Valider la commande BC-TEST-1 ?'), findsOneWidget);
      await toucher(t, bouton('Valider la commande'));
      final c = m.collection('commandes').toutes.firstWhere((x) => x['reference'] == 'BC-TEST-1');
      expect(c['statutCommande'], 'validee');
      expect(c['valideePar'], 'TAKI Alimatou');
      expect(c['dateValidation'], '2026-10-30');
      await toucher(t, find.text('Annuler').last);
      final apres = m.collection('commandes').toutes.firstWhere((x) => x['reference'] == 'BC-TEST-1');
      expect(apres['statutCommande'], 'attente_validation', reason: 'une annulation restitue l\'état d\'avant');
      expect(find.text('Action annulée.'), findsOneWidget);
    });

    cas('un profil qui lit les commandes (comptable) ne peut ni valider ni créer ni modifier : les gestes sont ABSENTS',
        (t) async {
      final m = magasin();
      commande(m, 'BC-TEST-2', 'attente_validation');
      await ouvrir(t, m, 'm7-commandes', role: 'comptable');
      expect(find.text('BC-TEST-2'), findsOneWidget);
      expect(find.byTooltip('Valider (DA)'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(bouton('Nouvelle commande'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
    });

    cas('une commande créée porte la série BC-2026 à la suite de l\'existante et son montant est la somme de ses lignes',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-commandes', role: 'da');
      await toucher(t, bouton('Nouvelle commande'));
      await toucher(t, bouton('Ajouter'));
      await toucher(t, bouton('Créer la commande'));
      final c = m.collection('commandes').actives.first;
      expect(c['reference'], 'BC-2026-0016');
      expect(c['statutCommande'], 'brouillon');
      expect(c['valideePar'], isNull, reason: 'un brouillon n\'est validé par personne');
      final lignes = (c['lignes'] as List).cast<Map>();
      expect(lignes.length, 1);
      expect(c['montant'], lignes.fold<num>(0, (a, l) => a + n(l['montant'])));
    });

    cas('sans article, la commande est refusée', (t) async {
      final m = magasin();
      final avant = m.collection('commandes').actives.length;
      await ouvrir(t, m, 'm7-commandes', role: 'da');
      await toucher(t, bouton('Nouvelle commande'));
      await toucher(t, bouton('Créer la commande'));
      expect(find.text('Ajouter au moins un article.'), findsOneWidget);
      expect(m.collection('commandes').actives.length, avant);
    });

    cas('rien ne se réceptionne avant la validation : une commande en attente n\'est pas dans la file de réception',
        (t) async {
      final m = magasin();
      commande(m, 'BC-TEST-ATTENTE', 'attente_validation');
      commande(m, 'BC-TEST-VALIDEE', 'validee', valideePar: 'TAKI Alimatou');
      await ouvrir(t, m, 'm7-receptions', role: 'stock');
      expect(find.text('BC-TEST-VALIDEE'), findsOneWidget);
      expect(find.text('BC-TEST-ATTENTE'), findsNothing);
    });
  });

  group('réception d\'une commande', () {
    Fiche cmd(Magasin m) => m.collection('commandes').inserer({
          'reference': 'BC-TEST-REC',
          'date': '2099-01-01',
          'fournisseur': 'CAME',
          'fournisseurNom': 'CAME — Centrale d’Achat des Médicaments Essentiels',
          'delaiLivraison': 7,
          'statutCommande': 'validee',
          'valideePar': 'TAKI Alimatou',
          'statut': 'actif',
          'lignes': [
            {
              'produitId': 'PRD0001',
              'produit': 'ABAISSE LANGUE',
              'unite': 'Unité',
              'quantite': 20,
              'prixUnitaire': 650,
              'montant': 13000
            },
            {
              'produitId': 'PRD0002',
              'produit': 'ACCUZON',
              'unite': 'Unité',
              'quantite': 7,
              'prixUnitaire': 1000,
              'montant': 7000
            },
          ],
          'montant': 20000,
        }, prefixe: 'COM').fiche;

    Future<void> ouvrirReception(WidgetTester t, Magasin m) async {
      await ouvrir(t, m, 'm7-receptions', role: 'stock');
      await toucher(t, bouton('Réceptionner').first);
    }

    cas('un manquant s\'affiche en rouge, le bordereau porte l\'écart, le stock gros et le CUMP bougent, un mouvement est écrit',
        (t) async {
      final m = magasin();
      cmd(m);
      final p1 = m.collection('produits').parId('PRD0001')!;
      final p2 = m.collection('produits').parId('PRD0002')!;
      final gros1 = n(p1['stockGros']), gros2 = n(p2['stockGros']);
      final mouvementsAvant = m.collection('mouvements').actives.length;
      await ouvrirReception(t, m);
      expect(find.text('Réception de la commande BC-TEST-REC'), findsOneWidget);
      await ecrire(t, 'referenceBL', '26LNA00099');
      await t.enterText(find.byKey(const Key('recu:0')), '15');
      await t.pump();
      expect(find.byKey(const Key('ecart:0')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('ecart:0'))) as Text).data, contains('5'));
      expect((t.widget(find.byKey(const Key('ecart:1'))) as Text).data, '0');
      await toucher(t, bouton('Valider la réception'));
      final bl = m.collection('livraisons').actives.first;
      expect(bl['reference'], '26LNA00099');
      expect(bl['commandeRef'], 'BC-TEST-REC');
      expect(bl['statutReception'], 'ecart');
      expect(bl['controlePar'], ['MAMAN Zoukanéri', 'DIEYABIDI Aïssatou']);
      final ls = (bl['lignes'] as List).cast<Map>();
      expect([ls[0]['quantiteLivree'], ls[0]['ecart']], [15, -5]);
      expect([ls[1]['quantiteLivree'], ls[1]['ecart']], [7, 0]);
      expect(bl['montant'], 15 * 650 + 7 * 1000);
      expect(m.collection('produits').parId('PRD0001')!['stockGros'], gros1 + 15);
      expect(m.collection('produits').parId('PRD0002')!['stockGros'], gros2 + 7);
      // CUMP = (valeur du stock + valeur de l'entrée) / quantité totale, arrondi.
      final s1 = n(p1['stock']), c1 = n(p1['cump']);
      expect(m.collection('produits').parId('PRD0001')!['cump'],
          ((s1 * c1 + 15 * 650) / (s1 + 15)).round());
      expect(m.collection('mouvements').actives.length, mouvementsAvant + 2);
      final mv = m.collection('mouvements').actives.first;
      expect(mv['type'], 'entree');
      expect(mv['justificatif'], 'Bon de livraison 26LNA00099');
      expect(m.collection('commandes').toutes.firstWhere((x) => x['reference'] == 'BC-TEST-REC')['statutCommande'], 'livree');
      expect(find.text('Réception enregistrée — 1 écart(s) constaté(s).'), findsOneWidget);
      // La commande a quitté la file de réception.
      expect(find.text('BC-TEST-REC'), findsNothing);
    });

    cas('annuler la réception restitue les stocks, retire le bordereau et les mouvements, rend la commande réceptionnable',
        (t) async {
      final m = magasin();
      cmd(m);
      final avant = {
        for (final id in ['PRD0001', 'PRD0002'])
          id: {...m.collection('produits').parId(id)!}
      };
      final mvAvant = m.collection('mouvements').actives.length;
      final blAvant = m.collection('livraisons').actives.length;
      await ouvrirReception(t, m);
      await ecrire(t, 'referenceBL', '26LNA00100');
      await toucher(t, bouton('Valider la réception'));
      expect(m.collection('livraisons').actives.length, blAvant + 1);
      await toucher(t, find.text('Annuler').last);
      for (final id in ['PRD0001', 'PRD0002']) {
        final p = m.collection('produits').parId(id)!;
        for (final k in ['stockGros', 'stock', 'cump']) {
          expect(p[k], avant[id]![k], reason: '$id.$k');
        }
      }
      expect(m.collection('mouvements').actives.length, mvAvant);
      expect(m.collection('livraisons').actives.length, blAvant);
      expect(m.collection('commandes').toutes.firstWhere((x) => x['reference'] == 'BC-TEST-REC')['statutCommande'], 'validee');
      expect(find.text('BC-TEST-REC'), findsOneWidget);
    });

    cas('sans numéro de bordereau la réception est refusée : rien n\'est écrit', (t) async {
      final m = magasin();
      cmd(m);
      final blAvant = m.collection('livraisons').actives.length;
      final stock = m.collection('produits').parId('PRD0001')!['stockGros'];
      await ouvrirReception(t, m);
      await toucher(t, bouton('Valider la réception'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('livraisons').actives.length, blAvant);
      expect(m.collection('produits').parId('PRD0001')!['stockGros'], stock);
    });

    cas('réceptionner ÉCRIT : la commande est absente pour un profil qui lit l\'écran (E79)', (t) async {
      final m = magasin();
      cmd(m);
      await ouvrir(t, m, 'm7-receptions', role: 'comptable');
      expect(find.text('BC-TEST-REC'), findsOneWidget);
      expect(bouton('Réceptionner'), findsNothing);
    });
  });

  group('bons de livraison et écarts', () {
    cas('le jeu : un bordereau avec écart apparaît au registre des écarts, valeur = |écart| × prix', (t) async {
      final m = magasin();
      final l = m.collection('livraisons').actives.firstWhere((x) => x['statutReception'] == 'ecart');
      final ligne = (l['lignes'] as List).cast<Map>().firstWhere((x) => n(x['ecart']) != 0);
      await ouvrir(t, m, 'm7-ecarts');
      expect(find.text('${ligne['produit']}'), findsOneWidget);
      expect(find.text('${l['reference']}'), findsOneWidget);
      final valeur = n(ligne['ecart']).abs() * n(ligne['prixUnitaire']);
      expect(find.text(money(valeur, avecDevise: false)), findsOneWidget);
      expect(find.text(money(valeur)), findsOneWidget, reason: 'le KPI « valeur des manquants »');
      expect(find.text('Éditer l’état des manquants'), findsOneWidget);
    });

    cas('un bordereau conforme n\'a aucun écart au registre ; sans écart l\'état vide le dit', (t) async {
      final m = magasin();
      for (final l in m.collection('livraisons').actives) {
        m.collection('livraisons').mettreAJour(l['id'], {'statutReception': 'conforme'});
      }
      await ouvrir(t, m, 'm7-ecarts');
      expect(find.text('Aucun écart de livraison constaté.'), findsOneWidget);
    });

    cas('modifier un bordereau garde les contrôleurs en LISTE : son détail s\'ouvre sans casser (E78)', (t) async {
      final m = magasin();
      final l0 = enTete(m.collection('livraisons').actives);
      await ouvrir(t, m, 'm7-livraisons');
      await toucher(t, find.byTooltip('Modifier').first);
      await ecrire(t, 'controlePar', ' A ,B,, C ');
      await toucher(t, bouton('Enregistrer'));
      final apres = m.collection('livraisons').parId(l0['id'])!;
      expect(apres['controlePar'], ['A', 'B', 'C']);
      await toucher(t, find.text('${apres['reference']}').first);
      expect(find.text('A, B, C'), findsOneWidget);
      expect(find.text('Bon de livraison ${apres['reference']}'), findsOneWidget);
    });

    cas('un nouveau bordereau est numéroté BL-00001, sans lignes ; sans commande rattachée il est refusé', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm7-livraisons');
      await toucher(t, bouton('Nouveau'));
      await toucher(t, bouton('Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      await ecrire(t, 'commandeRef', 'BC-2026-0001');
      await toucher(t, bouton('Créer'));
      final bl = m.collection('livraisons').actives.first;
      expect(bl['reference'], 'BL-00001');
      expect(bl['lignes'], isEmpty);
      expect(bl['montant'], 0);
      expect(bl['controlePar'], isEmpty);
      expect(find.text('Bon de livraison créé.'), findsOneWidget);
    });

    cas('archiver un bordereau demande un motif, ne supprime rien (RG-14) et s\'annule', (t) async {
      final m = magasin();
      final l0 = enTete(m.collection('livraisons').actives);
      final avant = m.collection('livraisons').actives.length;
      await ouvrir(t, m, 'm7-livraisons');
      await toucher(t, find.byTooltip('Archiver').first);
      await toucher(t, bouton('Archiver'));
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      expect(m.collection('livraisons').actives.length, avant);
      await t.enterText(find.byType(TextField).last, 'Doublon de saisie');
      await t.pump();
      await toucher(t, bouton('Archiver'));
      expect(m.collection('livraisons').actives.length, avant - 1);
      expect(m.collection('livraisons').parId(l0['id'])!['statut'], 'archive');
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('livraisons').actives.length, avant);
    });

    cas('un profil en lecture (direction) n\'a ni création, ni modification, ni archivage', (t) async {
      await ouvrir(t, magasin(), 'm7-livraisons', role: 'direction');
      expect(bouton('Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Imprimer'), findsWidgets);
    });
  });
}
