import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Émission de facture : le moteur (`emettreFacture`) est rejoué sur 24 vecteurs de l'écran réel de la maquette ; ici, l'ÉCRAN — ce que l'agent voit,
/// ce qu'il peut faire, et ce qui est écrit au magasin.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

Magasin magasin() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  // Une convention saisie pour le souscripteur du patient assuré : consultation couverte à 80 %, plafonnée.
  m.collection('garanties').inserer({
    'id': 'GAR-T',
    'souscripteurId': 'SOU003',
    'assureur': 'OLEA',
    'categorie': 'consultation',
    'libelle': 'Consultation',
    'taux': 80,
    'plafond': 5000,
    'unitePlafond': 'acte',
    'statut': 'actif'
  });
  m.collection('patients').mettreAJour('PAT0008', {'carteExpiration': '2099-12-31'});
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: 'm8-facturation',
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

/// Ouvre la liste dont le résumé affiche [courant] et y choisit [cible].
Future<void> choisir(WidgetTester t, String courant, String cible) async {
  await toucher(t, find.text(courant).first);
  if (find.text(cible).evaluate().isEmpty) {
    // Longue liste : le panneau ne construit que les lignes visibles, on cherche.
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  final f = find.descendant(
      of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, valeur);
  await t.pump();
}

Future<void> ajouterLibre(WidgetTester t, String libelle, String prix,
    {String quantite = '1'}) async {
  await choisir(t, 'Acte / consultation', 'Ligne libre');
  await saisir(t, 'designation', libelle);
  await saisir(t, 'prix', prix);
  await saisir(t, 'quantite', quantite);
  await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
}

/// Un geste affiche un message qui vit quelques secondes : on laisse le temps filer avant de rendre la main au banc.
void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('l\'écran s\'ouvre sur le premier patient (par code) et la première nature',
      (t) async {
    await ouvrir(t, magasin());
    expect(find.text('TCHANE Bertine'), findsWidgets);
    expect(find.text('Consultation généraliste'), findsWidgets);
    expect(find.text('Aucune prestation ajoutée.'), findsOneWidget);
    expect(find.textContaining('Patient non assuré'), findsWidgets);
  });

  cas('patient non assuré : UNE pièce, soldée, et l\'annulation est visible',
      (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500', quantite: '2');
    expect(find.text('Carnet de santé'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final apres = m.collection('factures').actives;
    expect(apres.length, avant + 1);
    final f = apres.last;
    expect(f['numero'], 'FN-2026-${(avant + 1).toString().padLeft(5, '0')}');
    expect(f['statutPaiement'], 'soldee');
    expect(f['montantPaye'], 1000);
    expect(f['baseMecef'], 1000);
    expect(f['volet'], isNull);
    expect(f['numeroMecef'], isNotNull);
    expect(find.textContaining('encaissé'), findsWidgets);
    // Annuler retire la pièce (archivage, RG-14) — visible dans le compte des actives.
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('factures').actives.length, avant);
    // Le journal d'audit (RG-12) a vu la création.
    expect(
        m.collection('audit').toutes.any((e) =>
            e['action'] == 'Création' && e['entite'] == 'factures'),
        isTrue);
  });

  cas('RG-03 : un médicament au-delà du stock est refusé, nommément, et rien n\'est ajouté',
      (t) async {
    await ouvrir(t, magasin());
    await choisir(t, 'Acte / consultation', 'Médicament');
    await saisir(t, 'quantite', '100000');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
    expect(find.textContaining('RG-03 — stock insuffisant en pharmacie'), findsWidgets);
    expect(find.text('Aucune prestation ajoutée.'), findsOneWidget);
  });

  cas('sans prestation : refus nommé, aucune pièce', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.text('Ajouter au moins une prestation.'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
  });

  cas('assuré : lignes couvertes ET non couvertes → deux pièces jumelles -A / -B',
      (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await choisir(t, 'TCHANE Bertine', 'DOSSOU Salifou');
    expect(find.textContaining('Couverture OLEA ASSURANCE'), findsWidgets);
    // Une consultation du catalogue (couverte) puis une ligne libre (aucune garantie).
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
    await ajouterLibre(t, 'Certificat hors convention', '2000');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final nouvelles = m.collection('factures').actives.sublist(avant);
    expect(nouvelles.length, 2);
    expect(nouvelles[0]['numero'], endsWith('-A'));
    expect(nouvelles[1]['numero'], endsWith('-B'));
    expect(nouvelles[0]['volet'], 'couvert');
    expect(nouvelles[1]['volet'], 'non_couvert');
    expect(n(nouvelles[0]['partAssurance']), greaterThan(0));
    expect(n(nouvelles[1]['partAssurance']), 0);
    // Numéros consécutifs (E6b), numéro de police porté.
    final a = int.parse(RegExp(r'(\d{5})-A').firstMatch('${nouvelles[0]['numero']}')!.group(1)!);
    final b = int.parse(RegExp(r'(\d{5})-B').firstMatch('${nouvelles[1]['numero']}')!.group(1)!);
    expect(b, a + 1);
    expect(nouvelles[0]['numeroPolice'], isNotNull);
    // La base MECeF ne porte que ce que le patient a réglé.
    expect(nouvelles[0]['baseMecef'], nouvelles[0]['montantPaye']);
  });

  cas('pro-forma : rien d\'encaissé, pas de numéro MECeF', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Soin', '1000');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Facture pro-forma'));
    final f = m.collection('factures').actives.last;
    expect(m.collection('factures').actives.length, avant + 1);
    expect(f['numero'], startsWith('PRO-2026-'));
    expect(f['montantPaye'], 0);
    expect(f['baseMecef'], 0);
    expect(f['numeroMecef'], isNull);
    expect(f['proforma'], true);
  });

  cas('médicament : la sortie de stock est écrite avec son justificatif, et l\'annulation la restitue',
      (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await choisir(t, 'Acte / consultation', 'Médicament');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
    final ligne = m.collection('factures').actives.length;
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives[ligne];
    final mv = m.collection('mouvements').toutes.last;
    expect(mv['type'], 'sortie');
    expect(mv['justificatif'], 'Facture ${f['numero']}');
    final prod = m.collection('produits').parId(mv['produitId'])!;
    final avant = n(prod['stockDetail']) + n(mv['quantite']);
    await toucher(t, find.text('Annuler').last);
    expect(n(m.collection('produits').parId(mv['produitId'])!['stockDetail']), avant);
  });

  cas('ticket de caisse : aperçu du rouleau 80 mm, base MECeF = part patient',
      (t) async {
    await ouvrir(t, magasin());
    await ajouterLibre(t, 'Soin', '1000');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ticket de caisse'));
    expect(find.byKey(const Key('impression:ticket')), findsOneWidget);
    expect(find.textContaining('BASE MECeF'), findsWidgets);
  });

  cas('RBAC : un profil qui ne fait que lire voit l\'écran sans pouvoir émettre',
      (t) async {
    await ouvrir(t, magasin(), role: 'direction');
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Facture pro-forma'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle nature'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Ticket de caisse'), findsOneWidget);
  });
}
