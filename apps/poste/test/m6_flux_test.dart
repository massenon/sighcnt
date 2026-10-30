import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show money;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Les écrans de FLUX de M6 (pharmacies, dispensation, étiquetage, reprise SAGE) : le moteur est rejoué sur les vecteurs de la maquette (packages/domaine) ; ici,
/// l'ÉCRAN — ce qui est écrit, refusé, annulable, et ce que chaque rôle voit.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Fiche prod(String id, String designation, num stock, {num? detail, num seuil = 3, String? emplacement}) => {
      'id': id,
      'code': id,
      'designation': designation,
      'unite': 'Unité',
      'categorie': 'medicament',
      'stock': stock,
      'stockDetail': detail ?? stock,
      'prixAchat': 100,
      'prixVente': 100,
      'cump': 100,
      'seuilAlerte': seuil,
      if (emplacement != null) 'emplacement': emplacement,
    };

Fiche ordo(String num, String statut, List<Fiche> lignes, {String dispensation = 'en_attente', String date = '2026-10-10'}) => {
      'id': 'O-$num',
      'numero': num,
      'date': date,
      'patient': 'TEST $num',
      'patientCode': 'CNT/1/26',
      'medecin': 'Dr TEST',
      'statutPaiement': statut,
      'statutDispensation': dispensation,
      'medicaments': lignes,
    };

Fiche ligne(Fiche p, num q) => {'produitId': p['id'], 'produit': p['designation'], 'quantite': q, 'posologie': '1/j'};

Magasin magasin({
  List<Fiche> produits = const [],
  List<Fiche> ordonnances = const [],
  List<Fiche> taches = const [],
  List<Fiche> dispensations = const [],
  List<Fiche> emplacements = const [],
  List<Fiche> lots = const [],
  List<Fiche> valorisations = const [],
}) =>
    Magasin({
      'produits': produits,
      'ordonnances': ordonnances,
      'taches': taches,
      'dispensations': dispensations,
      'emplacements': emplacements,
      'lots': lots,
      'valorisationsSage': valorisations,
      'mouvements': const [],
      'audit': const [],
    });

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
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

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  await t.enterText(
      find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField)), valeur);
  await t.pump();
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('pharmacie externe — la voie orale que le patient emporte', () {
    final cp = prod('CP', 'PARACETAMOL 500 MG CP', 40);
    final inj = prod('INJ', 'ADRENALINE 1 MG INJ', 10);

    cas('une ordonnance réglée : « Délivrer » décompte le stock, écrit le mouvement justifié par le n° d\'ordonnance et marque l\'ordonnance servie', (t) async {
      final m = magasin(produits: [cp, inj], ordonnances: [
        ordo('ORD-1', 'soldee', [ligne(cp, 10), ligne(inj, 2)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-externe');
      // La ligne injectable relève de la pharmacie INTERNE (« inj » = injectable) : seule la voie orale s'affiche ici.
      expect(find.text('PARACETAMOL 500 MG CP'), findsOneWidget);
      expect(find.text('ADRENALINE 1 MG INJ'), findsNothing);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer'));
      expect(find.text('Délivrer PARACETAMOL 500 MG CP ?'), findsOneWidget);
      expect(find.textContaining('10 unité(s) sortiront du stock au titre de l’ordonnance ORD-1, remises au patient au comptoir.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer').last);
      expect(m.collection('produits').parId('CP')!['stock'], 30);
      final mv = m.collection('mouvements').actives.single;
      expect(mv['justificatif'], 'Ordonnance ORD-1', reason: 'RG-03 : le justificatif est le numéro d\'ordonnance');
      expect(mv['type'], 'delivrance_externe');
      expect(mv['destination'], 'Patient');
      expect(mv['reference'], 'MVT-00001');
      expect(m.collection('ordonnances').parId('O-ORD-1')!['statutDispensation'], 'servie');
      expect(find.text('Délivré — stock ramené à 30.'), findsOneWidget);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Modification' && e['entite'] == 'ordonnances'), isTrue, reason: 'RG-12');
    });

    cas('une ordonnance non réglée : la ligne est visible, la délivrance bloquée et dite', (t) async {
      final m = magasin(produits: [cp], ordonnances: [
        ordo('ORD-2', 'impayee', [ligne(cp, 5)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-externe');
      expect(find.text('Non réglée'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Délivrer'), findsNothing);
      await toucher(t, find.byTooltip('Bloquée : l’ordonnance n’est pas réglée'));
      expect(find.text('Délivrance bloquée — l’ordonnance ORD-2 n’est pas réglée.'), findsOneWidget);
      expect(m.collection('mouvements').actives, isEmpty);
      expect(m.collection('produits').parId('CP')!['stock'], 40);
    });

    cas('stock insuffisant : refus NOMMÉ (RG-03), aucun mouvement, aucune modale', (t) async {
      final rare = prod('RARE', 'AMOXICILLINE 500 MG', 1);
      final m = magasin(produits: [rare], ordonnances: [
        ordo('ORD-3', 'soldee', [ligne(rare, 4)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-externe');
      expect(find.text('Stock insuffisant'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer'));
      expect(find.text('Délivrance refusée — stock insuffisant sur « AMOXICILLINE 500 MG » : 1 en rayon pour 4 demandé(s).'), findsOneWidget);
      expect(find.text('Délivrer AMOXICILLINE 500 MG ?'), findsNothing);
      expect(m.collection('mouvements').actives, isEmpty);
      expect(m.collection('produits').parId('RARE')!['stock'], 1, reason: 'le stock ne devient JAMAIS négatif');
    });

    cas('annuler la confirmation : rien n\'est écrit', (t) async {
      final m = magasin(produits: [cp], ordonnances: [
        ordo('ORD-4', 'soldee', [ligne(cp, 5)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-externe');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler'));
      expect(m.collection('mouvements').actives, isEmpty);
      expect(m.collection('ordonnances').parId('O-ORD-4')!['statutDispensation'], 'en_attente');
    });

    cas('l’alerte de stock lit le stock de DÉTAIL après la sortie : sous le seuil, une tâche de réapprovisionnement naît (une seule)', (t) async {
      // E45 : la pharmacie décompte le stock TOTAL (6 → 3) et laisse le stock de détail (4) tel quel ; c'est lui que lit l'alerte.
      final bas = prod('BAS', 'ARTESUNATE 60 MG', 6, detail: 4, seuil: 5);
      final m = magasin(produits: [bas], ordonnances: [
        ordo('ORD-5', 'soldee', [ligne(bas, 3)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-externe');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer').last);
      final tache = m.collection('taches').actives.single;
      expect(tache['type'], 'reapprovisionnement');
      expect(tache['libelle'], 'Sous le seuil — ARTESUNATE 60 MG');
      expect(tache['justificatif'], 'ORD-5');
    });
  });

  group('pharmacie interne — les produits remis à la salle de soins', () {
    final inj = prod('INJ', 'ADRENALINE 1 MG INJ', 10);
    final cp = prod('CP', 'PARACETAMOL 500 MG CP', 40);

    cas('un injectable (« inj ») relève de la pharmacie interne : la sortie va à la salle de soins', (t) async {
      final m = magasin(produits: [inj, cp], ordonnances: [
        ordo('ORD-6', 'soldee', [ligne(inj, 2), ligne(cp, 10)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-interne');
      expect(find.text('ADRENALINE 1 MG INJ'), findsOneWidget);
      expect(find.text('PARACETAMOL 500 MG CP'), findsNothing);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer'));
      expect(find.textContaining('à destination de la salle de soins qui les administrera.'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Délivrer').last);
      final mv = m.collection('mouvements').actives.single;
      expect(mv['type'], 'delivrance_interne');
      expect(mv['destination'], 'Salle de soins');
      expect(mv['justificatif'], 'Ordonnance ORD-6');
    });

    cas('la voie portée par la ligne prime sur la désignation', (t) async {
      final m = magasin(produits: [cp], ordonnances: [
        ordo('ORD-7', 'soldee', [
          {...ligne(cp, 1), 'voie': 'parenterale'}
        ])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-interne');
      expect(find.text('PARACETAMOL 500 MG CP'), findsOneWidget);
    });

    cas('un profil qui consulte sans écrire (médecin) voit les lignes, aucune commande : « Délivrer » est ABSENT, pas grisé', (t) async {
      final m = magasin(produits: [inj], ordonnances: [
        ordo('ORD-8', 'soldee', [ligne(inj, 2)])
      ]);
      await ouvrir(t, m, 'm6-pharmacie-interne', role: 'medecin');
      expect(find.text('ADRENALINE 1 MG INJ'), findsOneWidget);
      expect(find.text('Délivrable'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Délivrer'), findsNothing);
      expect(find.byTooltip('Bloquée : l’ordonnance n’est pas réglée'), findsNothing);
    });
  });

  group('dispensation — le registre, la file des ordonnances encaissées', () {
    final a = prod('A', 'ARTESUNATE 60 MG INJ', 12);
    final b = prod('B', 'GANT STERILE', 5);
    final rare = prod('R', 'SERUM SALE 500 ML INJ', 2);

    Fiche tache(Fiche o, String statut) => {
          'id': 'T-${o['numero']}',
          'type': 'dispensation',
          'poste': 'pharmacie',
          'statut': statut,
          'ordonnanceId': o['id'],
          'reference': o['numero'],
          'patient': o['patient'],
          'patientCode': o['patientCode'],
          'detail': 'Délivrer',
          'montant': 1000,
          'date': o['date'],
        };

    cas('AUCUNE création manuelle : la commande de nouvelle dispensation est absente', (t) async {
      await ouvrir(t, magasin(produits: [a]), 'm6-dispensation');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle dispensation'), findsNothing);
      expect(find.text('File des délivrances (ordonnances encaissées)'), findsOneWidget);
      expect(find.text('Aucune dispensation enregistrée.'), findsOneWidget);
      expect(find.text('Aucune ordonnance en attente de délivrance.'), findsOneWidget);
    });

    cas('délivrer une ordonnance encaissée : une sortie par ligne, justificatif = n° d\'ordonnance, tâche refermée', (t) async {
      final o = ordo('ORD-D1', 'soldee', [ligne(a, 2), ligne(b, 1)]);
      final m = magasin(produits: [a, b], ordonnances: [o], taches: [tache(o, 'en_attente')]);
      await ouvrir(t, m, 'm6-dispensation');
      await toucher(t, find.byTooltip('Délivrer'));
      expect(find.text('Délivrer ORD-D1'), findsOneWidget);
      expect(find.text('La sortie portera le numéro d’ordonnance comme justificatif (RG-03) et sera valorisée au prix d’achat (RG-02).'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Confirmer la délivrance'));
      final mvs = m.collection('mouvements').actives;
      expect(mvs.length, 2);
      expect(mvs.every((x) => x['justificatif'] == 'Ordonnance ORD-D1'), isTrue);
      expect(m.collection('produits').parId('A')!['stockDetail'], 10);
      expect(m.collection('produits').parId('A')!['stock'], 10);
      expect(m.collection('ordonnances').parId('O-ORD-D1')!['statutDispensation'], 'servie');
      expect(m.collection('taches').parId('T-ORD-D1')!['statut'], 'fait');
      expect(find.text('Médicaments délivrés — 2 sortie(s) de stock.'), findsOneWidget);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Dispensation' && e['reference'] == 'ORD-D1'), isTrue);
    });

    cas('une ligne non couverte : la modale refuse de confirmer et renvoie aux transferts (RG-03)', (t) async {
      final o = ordo('ORD-D2', 'soldee', [ligne(b, 4), ligne(rare, 6)]);
      final m = magasin(produits: [b, rare], ordonnances: [o], taches: [tache(o, 'en_attente')]);
      await ouvrir(t, m, 'm6-dispensation');
      await toucher(t, find.byTooltip('Délivrer'));
      expect(find.text('Stock insuffisant'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Confirmer la délivrance'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Aller aux transferts'), findsOneWidget);
      expect(find.textContaining('RG-03 — le stock ne peut pas devenir négatif.'), findsOneWidget);
      expect(m.collection('mouvements').actives, isEmpty);
    });

    cas('deux lignes du même produit dont le cumul dépasse le stock : refusé (le stock ne devient jamais négatif)', (t) async {
      final o = ordo('ORD-D3', 'soldee', [ligne(b, 3), ligne(b, 3)]);
      final m = magasin(produits: [b], ordonnances: [o], taches: [tache(o, 'en_attente')]);
      await ouvrir(t, m, 'm6-dispensation');
      await toucher(t, find.byTooltip('Délivrer'));
      expect(find.widgetWithText(BoutonSigh, 'Confirmer la délivrance'), findsNothing);
      expect(m.collection('produits').parId('B')!['stockDetail'], 5);
    });

    cas('un profil qui consulte la file sans l\'exécuter (médecin) : le bouton est verrouillé et le dit', (t) async {
      final o = ordo('ORD-D5', 'soldee', [ligne(a, 1)]);
      final m = magasin(produits: [a], ordonnances: [o], taches: [tache(o, 'en_attente')]);
      await ouvrir(t, m, 'm6-dispensation', role: 'medecin');
      expect(find.byTooltip('Délivrer'), findsNothing);
      await toucher(t, find.byTooltip('Votre profil consulte cette file sans l’exécuter'));
      expect(find.text('Votre profil consulte cette file sans pouvoir la traiter.'), findsOneWidget);
    });

    cas('une tâche bloquée par la caisse : visible, verrouillée', (t) async {
      final o = ordo('ORD-D4', 'impayee', [ligne(a, 1)]);
      final m = magasin(produits: [a], ordonnances: [o], taches: [tache(o, 'bloque')]);
      await ouvrir(t, m, 'm6-dispensation');
      expect(find.text('Attente encaissement'), findsOneWidget);
      await toucher(t, find.byTooltip('Bloquée jusqu’à l’encaissement'));
      expect(find.text('Cette opération attend le passage en caisse.'), findsOneWidget);
    });

    cas('l\'historique : indicateurs, tiroir de détail et bon de sortie imprimable', (t) async {
      final m = magasin(produits: [a, prod('Z', 'COTON', 0)], dispensations: [
        {
          'id': 'D1',
          'reference': 'DISP-00001',
          'date': '2026-09-20',
          'patient': 'TEST Dupont',
          'patientCode': 'CNT/1/26',
          'dispensePar': 'DIEYABIDI Aïssatou',
          'montant': 3750,
          'lignes': [
            {'produit': 'ARTESUNATE 60 MG INJ', 'quantite': 2, 'unite': 'Unité', 'prix': 1500},
            {'produit': 'GANT STERILE', 'quantite': 1, 'unite': 'Boîte', 'prix': 750},
          ],
        }
      ]);
      await ouvrir(t, m, 'm6-dispensation');
      expect(find.text(money(3750)), findsOneWidget);
      await toucher(t, find.text('DISP-00001'));
      expect(find.text('Dispensation DISP-00001'), findsOneWidget);
      expect(find.text('Produits délivrés'), findsOneWidget);
      await t.pump(const Duration(seconds: 1)); // le tiroir finit de glisser
      await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer le bon'));
      expect(find.text('Bon de sortie de stock — dispensation'), findsWidgets);
    });
  });

  group('étiquetage & emplacements', () {
    Fiche casier(String id, String code, {num? capacite}) => {
          'id': id,
          'code': code,
          'libelle': 'Casier $code',
          'zone': 'Rayonnage sec',
          'temperature': 'Ambiante',
          if (capacite != null) 'capacite': capacite,
        };
    final produits = [
      prod('P1', 'ARTESUNATE 60 MG INJ', 12, emplacement: 'A1'),
      prod('P2', 'GANT STERILE', 3, seuil: 5, emplacement: 'A1'),
      prod('P3', 'SPARADRAP', 7),
    ];

    cas('le plan des rayons : les articles sans emplacement ne s\'appellent pas « undefined »', (t) async {
      await ouvrir(t, magasin(produits: produits, emplacements: [casier('E1', 'A1', capacite: 2)]), 'm6-etiquetage');
      expect(find.text('Sans emplacement'), findsOneWidget);
      expect(find.text('undefined'), findsNothing);
      expect(find.text('2 / 2'), findsOneWidget, reason: 'casier à sa capacité');
    });

    cas('lecture seule (médecin) : ni création, ni modification, ni archivage — les commandes sont absentes', (t) async {
      await ouvrir(t, magasin(produits: produits, emplacements: [casier('E1', 'A1')]), 'm6-etiquetage', role: 'medecin');
      expect(find.text('Casier A1'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouvel emplacement'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Éditer toutes les étiquettes'), findsOneWidget, reason: 'imprimer est une lecture');
    });

    cas('créer un emplacement : source datée, annulable (la fiche est archivée), formulaire vide refusé', (t) async {
      final m = magasin(produits: produits, emplacements: [casier('E1', 'A1')]);
      await ouvrir(t, m, 'm6-etiquetage');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Nouvel emplacement'));
      expect(find.text('Nouvel emplacement de rangement'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('emplacements').actives.length, 1);
      await saisir(t, 'code', 'B2');
      await saisir(t, 'libelle', 'Armoire sécurisée 2');
      await saisir(t, 'capacite', '4');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final e = m.collection('emplacements').actives.first;
      expect(e['code'], 'B2');
      expect(e['capacite'], 4);
      expect(e['zone'], 'Rayonnage sec');
      expect(e['source'], 'Créé dans l’application le 30/10/2026');
      expect(find.text('Emplacement créé.'), findsOneWidget);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('emplacements').actives.length, 1, reason: 'annuler archive la fiche (RG-14), ne la supprime pas');
      expect(m.collection('emplacements').toutes.length, 2);
    });

    cas('archiver un emplacement : confirmation, annulable', (t) async {
      final m = magasin(produits: produits, emplacements: [casier('E1', 'A1'), casier('E2', 'Z9')]);
      await ouvrir(t, m, 'm6-etiquetage');
      await toucher(t, find.byTooltip('Archiver').first);
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('emplacements').actives.length, 1);
      expect(m.collection('emplacements').archivees.length, 1);
      expect(find.text('Enregistrement archivé.'), findsOneWidget);
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('emplacements').actives.length, 2);
    });

    cas('les étiquettes d\'un casier portent le lot qui périme le premier (FEFO)', (t) async {
      final m = magasin(produits: produits, emplacements: [casier('E1', 'A1')], lots: [
        {'id': 'L1', 'produitId': 'P1', 'numeroLot': 'LOT-B', 'datePeremption': '2027-03-01'},
        {'id': 'L2', 'produitId': 'P1', 'numeroLot': 'LOT-A', 'datePeremption': '2026-12-15'},
      ]);
      await ouvrir(t, m, 'm6-etiquetage');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Étiquettes').first);
      expect(find.text('Étiquettes produits'), findsWidgets);
      expect(find.textContaining('Lot : LOT-A'), findsWidgets);
      expect(find.textContaining('LOT-B'), findsNothing);
    });

    cas('modifier un article depuis « Articles par emplacement » : seule la modification est offerte (pas d\'archivage)', (t) async {
      final m = magasin(produits: [prod('P1', 'ARTESUNATE 60 MG INJ', 12, emplacement: 'A1')], emplacements: [casier('E1', 'A1')]);
      await ouvrir(t, m, 'm6-etiquetage');
      expect(find.byTooltip('Modifier'), findsWidgets);
      await toucher(t, find.byTooltip('Modifier').last);
      expect(find.text('Modifier l’enregistrement'), findsOneWidget);
      await saisir(t, 'seuilAlerte', '9');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(m.collection('produits').actives.any((p) => p['seuilAlerte'] == 9), isTrue);
    });
  });

  group('reprise SAGE 100', () {
    cas('sans surcouche : 32 références restent à valoriser ; la saisie exige une SOURCE', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-reprise');
      expect(find.text('184'), findsWidgets);
      await toucher(t, find.textContaining('Points à traiter'));
      expect(find.textContaining('32 article(s) figurent à l’inventaire SAGE sans prix de revient unitaire'), findsOneWidget);
      await toucher(t, find.byTooltip('Valoriser').first);
      expect(find.textContaining('Valoriser — '), findsWidgets);
      await saisir(t, 'prixRevient', '850');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valoriser'));
      expect(m.collection('valorisationsSage').actives, isEmpty, reason: 'sans origine, la valeur ne se vérifie pas : rien n\'est écrit');
      await saisir(t, 'source', 'Facture UBIPHARM n° 4471');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valoriser'));
      final v = m.collection('valorisationsSage').actives.single;
      expect(v['prixRevient'], 850);
      expect(v['source'], 'Facture UBIPHARM n° 4471');
      expect(v['date'], '2026-10-30');
      expect(find.text('Référence valorisée.'), findsOneWidget);
      // Le compteur suit : la référence vient d'être tarifée.
      await toucher(t, find.text('Articles repris').last);
      expect(find.text('31'), findsWidgets);
    });

    cas('lecture seule (comptable) : « Valider la reprise » et « Valoriser » sont absents ; le bordereau reste imprimable', (t) async {
      await ouvrir(t, magasin(), 'm6-reprise', role: 'comptable');
      expect(find.widgetWithText(BoutonSigh, 'Valider la reprise'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Éditer le bordereau'), findsOneWidget);
      await toucher(t, find.textContaining('Points à traiter').first);
      expect(find.byTooltip('Valoriser'), findsNothing);
    });

    cas('valider la reprise : confirmée, journalisée (RG-12), le document n\'est pas modifié', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm6-reprise');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider la reprise'));
      expect(find.text('Valider la reprise du stock initial ?'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Valider la reprise').last);
      expect(find.text('Reprise validée.'), findsOneWidget);
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Validation' && e['reference'] == 'IMPORT-SAGE-20260715'), isTrue);
    });

    cas('le bordereau : les totaux sont refaits depuis les lignes (TOTAL GRAND STOCK)', (t) async {
      await ouvrir(t, magasin(), 'm6-reprise');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Éditer le bordereau'));
      expect(find.text('Bordereau de reprise du stock initial'), findsWidgets);
      expect(find.textContaining('TOTAL GRAND STOCK'), findsWidgets);
    });
  });
}
