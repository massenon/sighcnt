import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_caisse_poste.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT MECEF-M au poste : l'imprimante de caisse DATÉE (registre `parametres`, famille `mecef`, défaut semé), l'état de la caisse, le réglage du mode par geste
/// réservé. Les règles sont celles du domaine, rejouées sur les vecteurs de la maquette ; ici on éprouve la colle (lecture à la date, journal RG-12, refus, écran).
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 16);
String iso(DateTime d) => parametreDateIso(d);

/// Le magasin du jeu de démonstration (l'écran lit aussi les paramètres fiscaux), défauts du registre semés.
Magasin magasinJeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  serviceParametres(m, auteur: () => 'semis', horloge: () => auj).semerDefauts();
  return m;
}

Magasin magasin({List<Fiche> factures = const [], List<Fiche> avoirs = const []}) {
  final m = Magasin({'factures': factures, 'avoirs': avoirs, 'audit': const []});
  serviceParametres(m, auteur: () => 'semis', horloge: () => auj).semerDefauts();
  return m;
}

RefusMecef? regler(Magasin m,
        {String liaison = 'usb', String nom = 'Caisse 1', String? date, String? motif = 'liaison constatée', bool geste = true, bool fileul = false}) =>
    reglerImprimanteDuPoste(m,
        gesteAccorde: geste,
        fileul: fileul,
        libelleRole: 'Caissier',
        rolesQuiLeDetiennent: 'Administrateur, DAF',
        nom: nom,
        liaison: liaison,
        dateEffet: date ?? iso(auj),
        motif: motif,
        horloge: () => auj);

Fiche vente(String n, num? paye, String mecef, {String paiement = 'soldee', bool proforma = false}) =>
    {'id': n, 'numero': n, 'montantPaye': paye, 'statutPaiement': paiement, 'statutMecef': mecef, 'proforma': proforma, 'statut': 'actif'};

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.mere, role: role), ecranInitial: 'mecef-config', magasin: m, horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('imprimante de caisse', () {
    test('défaut SEMÉ lu en base ; une version datée s\'applique à sa date, la version à venir ne change rien aujourd\'hui, journal RG-12', () {
      final m = magasin();
      final v0 = imprimanteDuPoste(m, auj);
      expect([v0.source, v0.modele, v0.type, v0.largeurMm, v0.liaison], ['defaut', 'Xprinter XP-Q800', 'thermique', 80, 'a_verifier']);
      expect(m.collection(parCollectionParametres).toutes.where((v) => v['cle'] == mecefCleImprimante).length, 1, reason: 'version 0 semée');
      expect(regler(m), isNull);
      expect(imprimanteDuPoste(m, auj).liaison, 'usb');
      expect(imprimanteDuPoste(m, auj).nom, 'Caisse 1');
      expect(imprimanteDuPoste(m, auj.subtract(const Duration(days: 1))).source, 'defaut', reason: 'la veille, le défaut semé');
      expect(regler(m, liaison: 'ethernet', nom: 'Caisse réseau', date: iso(auj.add(const Duration(days: 5)))), isNull);
      expect(imprimanteDuPoste(m, auj).liaison, 'usb');
      expect(imprimanteDuPoste(m, auj.add(const Duration(days: 5))).liaison, 'ethernet');
      final j = m.collection('audit').toutes.where((a) => a['action'] == 'Imprimante de caisse : nouvelle version').toList();
      expect(j.length, 2);
      expect('${j.first['apres']}', contains('liaison constatée'));
    });

    test('les six refus NOMMÉS, le moteur refuse aussi ; rien n\'est écrit par un refus', () {
      final m = magasin();
      final n0 = m.collection(parCollectionParametres).toutes.length;
      expect(regler(m, geste: false)?.code, 'IMPRIMANTE_RESERVE');
      expect(regler(m, fileul: true)?.code, 'FILEUL_LECTURE_SEULE');
      expect(regler(m, motif: ' ')?.code, 'IMPRIMANTE_MOTIF_OBLIGATOIRE');
      expect(regler(m, date: '2026-11-01')?.code, 'IMPRIMANTE_DATE_PASSEE');
      expect(regler(m, nom: ' ')?.code, 'IMPRIMANTE_NOM_REQUIS');
      expect(regler(m, liaison: 'bluetooth')?.code, 'IMPRIMANTE_LIAISON_INCONNUE');
      expect(regler(m, liaison: 'a_verifier')?.code, 'IMPRIMANTE_LIAISON_INCONNUE');
      final r = regler(m, geste: false)!;
      expect(r.motif, isNotEmpty);
      expect(r.geste, contains('Administrateur, DAF'), reason: 'le refus dit qui détient le droit');
      expect(m.collection(parCollectionParametres).toutes.length, n0);
      expect(imprimanteDuPoste(m, auj).source, 'defaut');
    });

    test('RG-13 : le défaut semé de la définition est celui du domaine ; la famille mecef est fermée aux téléphones et hors du panneau générique', () {
      final d = definitionsParametres.firstWhere((x) => x.cle == mecefCleImprimante);
      expect(jsonDecode('${d.defaut}')['modele'], imprimanteSemee.modele);
      expect(parFamillesJamaisMobile, contains('mecef'));
      expect(parFamillesReglageDedie, contains('mecef'));
      final champs = {...Parametres.semer(d).toJson(), 'mobile': true};
      expect(Parametres.autoriseMobile(champs), isFalse);
    });
  });

  group('mode de facturation normalisée par geste réservé', () {
    test('réglé avec le droit (version datée, journal), refusé sans le droit, pour un fileul et pour un mode inconnu : le moteur refuse aussi', () {
      final m = magasin();
      RefusMecef? mode(Object? v, {bool geste = true, bool fileul = false}) => reglerModeMecefDuPoste(m,
          mode: v, gesteAccorde: geste, fileul: fileul, libelleRole: 'Caissier', rolesQuiLeDetiennent: 'Administrateur, DAF', horloge: () => auj);
      expect(modeMecefDuPoste(m, auj), 'boitier');
      expect(mode('emecef', geste: false)?.code, 'MODE_RESERVE');
      expect(mode('emecef', fileul: true)?.code, 'FILEUL_LECTURE_SEULE');
      expect(mode('inconnu')?.code, 'MODE_INCONNU');
      expect(modeMecefDuPoste(m, auj), 'boitier', reason: 'aucun refus n\'écrit');
      expect(mode('emecef'), isNull);
      expect(modeMecefDuPoste(m, auj), 'emecef');
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Mode de facturation normalisée'), isTrue);
    });
  });

  group('état de la caisse', () {
    test('ventes encaissées non normalisées (hors normalisées, non encaissées, pro-forma), avoirs en attente à part, montant inconnu = null', () {
      var m = magasin(factures: [
        vente('A', 5000, 'en_attente'),
        vente('B', 3000, 'a_verifier'),
        vente('C', 0, 'en_attente', paiement: 'impayee'),
        vente('D', 7000, 'valide'),
        vente('E', 9000, 'en_attente', proforma: true),
      ], avoirs: [
        {'id': 'V1', 'reference': 'AV1', 'montant': 2000, 'statutMecef': 'en_attente', 'statut': 'actif'},
        {'id': 'V2', 'reference': 'AV2', 'montant': 1500, 'statutMecef': 'valide', 'statut': 'actif'},
      ]);
      var e = etatCaissePoste(m);
      expect([e.ventes, e.ventesMontant, e.avoirs, e.avoirsMontant], [2, 8000, 1, 2000]);
      expect(e.parEtat, {'en_attente': 1, 'a_verifier': 1});
      m = magasin(factures: [vente('A', 5000, 'en_attente'), vente('F', null, 'en_attente')]);
      e = etatCaissePoste(m);
      expect(e.ventes, 2);
      expect(e.ventesMontant, isNull, reason: 'non calculable, jamais zéro');
      expect(etatCaissePoste(magasin()).ventesMontant, 0);
    });
  });

  group('écran « Configuration fiscale »', () {
    testWidgets('cartes État de la caisse et Imprimante de caisse ; commandes présentes avec le geste, ABSENTES sans', (t) async {
      final m = magasinJeu();
      m.collection('factures').ajouterSansJournal(vente('FN-2099-S1', null, 'en_attente'));
      await ouvrir(t, m);
      expect(find.text('État de la caisse'), findsOneWidget);
      expect(find.byKey(const Key('kit:carte-titre')).evaluate().any((e) => (e.widget as Text).data == 'Imprimante de caisse'), isTrue);
      expect(find.text('Non calculable'), findsWidgets);
      expect(find.text('Xprinter XP-Q800'), findsOneWidget);
      expect(find.text('À vérifier à l’arrière de l’appareil'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Voir la file'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler l’imprimante'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler le mode'), findsOneWidget);
      await ouvrir(t, m, role: 'comptable');
      expect(find.byKey(const Key('kit:carte-titre')).evaluate().any((e) => (e.widget as Text).data == 'Imprimante de caisse'), isTrue);
      expect(find.widgetWithText(BoutonSigh, 'Voir la file'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler l’imprimante'), findsNothing, reason: 'commande ABSENTE sans le geste');
      expect(find.widgetWithText(BoutonSigh, 'Régler le mode'), findsNothing);
      expect(find.textContaining('droit « Régler l’imprimante de caisse »'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('« Enregistrer l\'imprimante » sans motif refuse en nommant (IMPRIMANTE_MOTIF_OBLIGATOIRE) et n\'écrit rien', (t) async {
      final m = magasinJeu();
      await ouvrir(t, m);
      final bouton = find.widgetWithText(BoutonSigh, 'Régler l’imprimante');
      await t.ensureVisible(bouton);
      await t.tap(bouton);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer l’imprimante'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('IMPRIMANTE_MOTIF_OBLIGATOIRE'), findsWidgets);
      expect(imprimanteDuPoste(m, auj).source, 'defaut');
      await t.pump(const Duration(seconds: 10));
    });
  });
}
