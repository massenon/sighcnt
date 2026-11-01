// La suite du mobile : visite prénatale, visite post-natale, surveillance mère-bébé, orientation de la réception, lot de tournée, réglages, code PIN.
// Le moteur est faux mais le SERVICE est le vrai : ce que l'écran affiche et refuse vient des règles de packages/domaine, rejouées sur les vecteurs
// de la maquette (packages/domaine/test/mob_suite_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/core/coffre_pin_securise.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

Future<FauxMoteurSuite> ouvrir(WidgetTester t, {String fonction = 'sage_femme', String agent = 'Sage-femme de garde', SourceMemoire? source, CoffrePin? coffre, DateTime Function()? horloge}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final m = FauxMoteurSuite(fonction: fonction, agent: agent, source: source ?? lotSageFemme())..profil = ProfilMobile.soignant;
  await t.pumpWidget(SighMobile(moteur: m, coffre: coffre, horlogeVerrou: horloge));
  await t.pumpAndSettle();
  return m;
}

Future<FauxMoteurSuite> ouvrirReception(WidgetTester t, {SourceMemoire? source}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final m = FauxMoteurSuite(source: source ?? accueilDeSecours())..profil = ProfilMobile.receptionSecours;
  await t.pumpWidget(SighMobile(moteur: m));
  await t.pumpAndSettle();
  return m;
}

Future<void> dossierDe(WidgetTester t, String id) async {
  await t.tap(find.byKey(const Key('onglet-dossiers')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key('patient-$id')));
  await t.pumpAndSettle();
}

Future<void> saisir(WidgetTester t, Map<String, String> champs) async {
  for (final e in champs.entries) {
    await t.enterText(find.byKey(Key('champ-${e.key}')), e.value);
  }
}

Future<void> toucher(WidgetTester t, String cle) async {
  await t.ensureVisible(find.byKey(Key(cle)));
  await t.tap(find.byKey(Key(cle)));
  await t.pumpAndSettle();
}

void main() {
  group('profil sage-femme : les trois écrans partent du dossier', () {
    testWidgets('les commandes n\'existent que pour la sage-femme : le médecin et l\'infirmier ne les voient pas', (t) async {
      await ouvrir(t);
      await dossierDe(t, 'p4');
      for (final c in ['ouvrir-cpn', 'ouvrir-cpon', 'ouvrir-surveillance']) {
        expect(find.byKey(Key(c)), findsOneWidget, reason: c);
      }
      expect(find.text('Visite prénatale (CPN)'), findsOneWidget);
      expect(find.text('Visite post-natale (CPoN)'), findsOneWidget);
      expect(find.text('Surveillance mère-bébé'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      for (final f in ['medecin', 'infirmier']) {
        await ouvrir(t, fonction: f);
        await dossierDe(t, 'p4');
        for (final c in ['ouvrir-cpn', 'ouvrir-cpon', 'ouvrir-surveillance']) {
          expect(find.byKey(Key(c)), findsNothing, reason: '$f : une commande interdite est ABSENTE');
        }
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('CPN : champs obligatoires, bornes nommées, et rien n\'est écrit tant que la saisie est refusée', (t) async {
      final m = await ouvrir(t);
      await dossierDe(t, 'p4');
      await toucher(t, 'ouvrir-cpn');
      expect(find.text('Visite prénatale (CPN)'), findsWidgets);
      expect(find.textContaining('Âge à risque'), findsNothing, reason: '31 ans : dans la fenêtre');
      await toucher(t, 'enregistrer');
      for (final e in ['Le terme est obligatoire.', 'Le poids est obligatoire.', 'La systolique est obligatoire.', 'La diastolique est obligatoire.']) {
        expect(find.text(e), findsOneWidget, reason: e);
      }
      await saisir(t, {'sa': '46', 'poids': '29', 'sys': '261', 'dia': '29', 'bcf': '221'});
      await toucher(t, 'enregistrer');
      expect(find.text('Le terme : valeur improbable (4 à 45).'), findsOneWidget);
      expect(find.text('Le poids : valeur improbable (30 à 200).'), findsOneWidget);
      expect(find.text('La systolique : valeur improbable (60 à 260).'), findsOneWidget);
      expect(find.text('La diastolique : valeur improbable (30 à 160).'), findsOneWidget);
      expect(find.text('Le BCF : valeur improbable (60 à 220).'), findsOneWidget);
      expect(m.source.de('cpn'), isEmpty);
    });

    testWidgets('CPN : une visite enregistrée = UNE ligne de journal nommée, la grossesse à risque est signalée, l\'écran se referme', (t) async {
      final m = await ouvrir(t);
      await dossierDe(t, 'p4');
      await toucher(t, 'ouvrir-cpn');
      await saisir(t, {'sa': '28', 'poids': '62,5', 'sys': '140', 'dia': '80', 'bcf': '140', 'hu': '27'});
      await t.tap(find.byKey(const Key('champ-proteinurie')));
      await t.pumpAndSettle();
      await t.tap(find.text('++').last);
      await t.pumpAndSettle();
      await toucher(t, 'enregistrer');
      expect(m.source.de('cpn'), hasLength(1));
      final f = m.source.de('cpn').single;
      expect(f['patientId'], 'p4');
      expect(f['termeSA'], 28);
      expect(f['tension'], '140/80');
      expect(f['proteinurie'], '++');
      expect(f['aRisque'], isTrue);
      expect(f['redigePar'], 'Sage-femme de garde');
      expect(f['fonction'], 'sage_femme');
      expect(f['detail'], '28 SA · TA 140/80 · À RISQUE');
      expect(find.byKey(const Key('enregistrer')), findsNothing, reason: 'revenu au dossier');
      expect(find.textContaining('signalée comme grossesse à risque'), findsOneWidget);
    });

    testWidgets('CPN : l\'âge à risque se signale en tête (67 ans) sans bloquer', (t) async {
      await ouvrir(t);
      await dossierDe(t, 'p1');
      await toucher(t, 'ouvrir-cpn');
      expect(find.text('Âge à risque (hors 18–35 ans).'), findsOneWidget);
    });

    testWidgets('CPoN : mère et nouveau-né, TA obligatoire (texte libre), température 34 à 43, poids du bébé 1000 à 6000', (t) async {
      final m = await ouvrir(t);
      await dossierDe(t, 'p2');
      await toucher(t, 'ouvrir-cpon');
      await toucher(t, 'enregistrer');
      expect(find.text('La TA est obligatoire.'), findsOneWidget);
      expect(find.text('La température est obligatoire.'), findsOneWidget);
      expect(find.text('Le poids du bébé est obligatoire.'), findsOneWidget);
      await saisir(t, {'ta': '12/8', 't': '43,1', 'pb': '999'});
      await toucher(t, 'enregistrer');
      expect(find.text('La température : valeur improbable (34 à 43).'), findsOneWidget);
      expect(find.text('Le poids du bébé : valeur improbable (1000 à 6000).'), findsOneWidget);
      await saisir(t, {'t': '37', 'pb': '3200'});
      await toucher(t, 'enregistrer');
      final f = m.source.de('cpon').single;
      expect(f['jourPostNatal'], 'J1');
      expect(f['libelle'], 'CPoN J1 — KPOGNON Rose');
      expect(f['detail'], 'T° 37 · cordon propre et sec');
      expect(f['redigePar'], 'Sage-femme de garde');
    });

    testWidgets('surveillance : tout est facultatif, trois bornes, une note explique la grille unique, la ligne désigne la patiente', (t) async {
      final m = await ouvrir(t);
      await dossierDe(t, 'p4');
      await toucher(t, 'ouvrir-surveillance');
      expect(find.textContaining('Une seule grille de temps'), findsOneWidget);
      await saisir(t, {'mpouls': '221', 'bfr': '9', 'bt': '41,1'});
      await toucher(t, 'enregistrer');
      expect(find.text('Le pouls : valeur improbable (30 à 220).'), findsOneWidget);
      expect(find.text('La FR du bébé : valeur improbable (10 à 100).'), findsOneWidget);
      expect(find.text('La T° du bébé : valeur improbable (34 à 41).'), findsOneWidget);
      await saisir(t, {'mta': '12/8', 'mpouls': '80', 'bfr': '40', 'bt': '36,8'});
      await toucher(t, 'enregistrer');
      final f = m.source.de('surveillances').single;
      expect(f['patientId'], 'p4');
      expect(f['temps'], 'H4');
      expect(f['libelle'], 'Surveillance H4');
      expect(f['detail'], 'mère 12/8 · bébé FR 40');
    });

    testWidgets('le contrôle est REFAIT au moteur : un médecin qui contourne le bouton est refusé en le nommant, rien n\'est écrit', (t) async {
      final m = FauxMoteurSuite(fonction: 'medecin', agent: 'Dr YENI', source: lotSageFemme())..profil = ProfilMobile.soignant;
      final suite = ServiceSuite.depuisSoignant(m.soignant!);
      expect(suite.peut('cpn'), isFalse);
      await expectLater(
          suite.enregistrerCpn('p4', {'sa': '28', 'poids': '60', 'sys': '120', 'dia': '80'}),
          throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'ECRAN_FERME_AU_PROFIL').having((e) => e.motif, 'motif', contains('Écran fermé au profil « Médecin »'))));
      expect(m.source.ecritures, isEmpty);
    });

    testWidgets('lot expiré : la visite est refusée en le disant, avec la date et le geste', (t) async {
      final s = lotSageFemme()..fin = DateTime(2026, 10, 31, 9).millisecondsSinceEpoch;
      final m = await ouvrir(t, source: s);
      await dossierDe(t, 'p4');
      await toucher(t, 'ouvrir-cpn');
      await saisir(t, {'sa': '28', 'poids': '60', 'sys': '120', 'dia': '80'});
      await toucher(t, 'enregistrer');
      expect(find.textContaining('Le lot de la tournée a expiré le 31/10/2026 à 09h00'), findsOneWidget);
      expect(find.textContaining('Se connecter pour recevoir le lot du jour'), findsOneWidget);
      expect(m.source.ecritures, isEmpty);
    });

    testWidgets('sans agent nommé, rien ne s\'écrit (RG-12)', (t) async {
      final m = FauxMoteurSuite(fonction: 'sage_femme', agent: '', source: lotSageFemme())..profil = ProfilMobile.soignant;
      await expectLater(ServiceSuite.depuisSoignant(m.soignant!).enregistrerCpon('p2', {'ta': '12/8', 't': '37', 'pb': '3200'}),
          throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'ACTEUR_INCONNU')));
      expect(m.source.ecritures, isEmpty);
    });
  });

  group('réception de secours : l\'orientation', () {
    testWidgets('la commande existe pour la réception seule ; le lot et la CPN lui sont fermés', (t) async {
      await ouvrirReception(t);
      expect(find.byKey(const Key('orienter')), findsOneWidget);
      expect(find.byKey(const Key('ouvrir-lot')), findsNothing, reason: 'le simulateur ferme le lot à la réception');
      expect(find.byKey(const Key('ouvrir-reglages')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await ouvrir(t, fonction: 'medecin');
      expect(find.byKey(const Key('orienter')), findsNothing);
      expect(find.byKey(const Key('ouvrir-lot')), findsOneWidget);
    });

    testWidgets('sans dossier ouvert, l\'écran ne propose que le texte « Ouvrez d’abord un dossier. »', (t) async {
      await ouvrirReception(t, source: SourceMemoire({'patients': []}));
      await toucher(t, 'orienter');
      expect(find.text('Ouvrez d’abord un dossier.'), findsOneWidget);
      expect(find.byKey(const Key('envoyer-orientation')), findsNothing);
    });

    testWidgets('orienter : six destinations, trois degrés, UNE ligne de journal au nom de l\'agent ; seuls les dossiers de l\'accueil de secours sont proposés', (t) async {
      final m = await ouvrirReception(t);
      await toucher(t, 'orienter');
      expect(find.text('Orienter un patient'), findsWidgets);
      for (final o in ['Médecin de garde', 'Laboratoire', 'Salle de soins', 'Maternité', 'Caisse (dès retour du courant)', 'Référence vers un autre établissement']) {
        expect(find.text(o, skipOffstage: false), findsWidgets, reason: o);
      }
      expect(find.text('HOUNKPATIN Ida — PROV-1', skipOffstage: false), findsWidgets);
      expect(find.text('DOSSOU Aline — CNT/12/26', skipOffstage: false), findsNothing, reason: 'un patient du poste n\'est pas un dossier de secours');
      await t.tap(find.byKey(const Key('champ-dest')));
      await t.pumpAndSettle();
      await t.tap(find.text('Maternité').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('champ-urg')));
      await t.pumpAndSettle();
      await t.tap(find.text('Très urgent').last);
      await t.pumpAndSettle();
      await toucher(t, 'envoyer-orientation');
      final f = m.source.de('orientations').single;
      expect(f['libelle'], 'Orientation — HOUNKPATIN Ida');
      expect(f['detail'], 'Maternité · Très urgent');
      expect(f['orientePar'], 'OROU YO Edmond');
      expect(f['origine'], 'reception_secours');
    });

    testWidgets('un soignant qui contourne l\'écran est refusé en le nommant', (t) async {
      final m = FauxMoteurSuite(fonction: 'sage_femme', source: accueilDeSecours())..profil = ProfilMobile.soignant;
      final suite = ServiceSuite(m.source, profil: 'sagefemme', agent: 'x');
      await expectLater(suite.orienter('d1', destination: 'Laboratoire', degre: 'Normal'), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'ECRAN_FERME_AU_PROFIL')));
      final rec = ServiceSuite(m.source, profil: 'reception', agent: 'x');
      await expectLater(rec.orienter('inconnu', destination: 'Laboratoire', degre: 'Normal'), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'DOSSIER_INCONNU')));
    });
  });

  group('lot de tournée', () {
    testWidgets('valide : dossiers, validité restante, date d\'expiration, note, dossiers du lot ; Rafraîchir relit le moteur', (t) async {
      final m = await ouvrir(t);
      await toucher(t, 'ouvrir-lot');
      expect(find.text('Lot du jour'), findsOneWidget);
      expect(find.text('Dossiers'), findsOneWidget);
      expect(find.text('Validité restante'), findsOneWidget);
      expect(find.byKey(const Key('lot-dossiers')), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.text('10 h'), findsOneWidget);
      expect(find.text('Lot valide'), findsOneWidget);
      expect(find.text('Expire le 31/10/2026 à 20h00'), findsOneWidget);
      expect(find.textContaining('Date de dépôt : non communiquée'), findsOneWidget);
      expect(find.textContaining('Le lot est chiffré et expire'), findsOneWidget);
      expect(find.text('SOUROU Mariam'), findsOneWidget);
      await toucher(t, 'rafraichir-lot');
      expect(m.rafraichissements, 1);
    });

    testWidgets('expiré : l\'état le dit, la validité vaut 0 h', (t) async {
      await ouvrir(t, source: lotSageFemme()..fin = DateTime(2026, 10, 31, 9, 30).millisecondsSinceEpoch);
      await toucher(t, 'ouvrir-lot');
      expect(find.byKey(const Key('lot-etat')), findsOneWidget);
      expect(find.textContaining('Lot expiré'), findsOneWidget);
      expect(find.text('0 h'), findsOneWidget);
      expect(find.text('A expiré le 31/10/2026 à 09h30'), findsOneWidget);
    });

    testWidgets('aucun lot reçu : l\'écran le dit au lieu d\'afficher un faux compteur', (t) async {
      await ouvrir(t, source: lotSageFemme()..fin = null);
      await toucher(t, 'ouvrir-lot');
      expect(find.textContaining('Aucun lot reçu'), findsOneWidget);
      expect(find.byKey(const Key('lot-expiration')), findsNothing);
    });
  });

  group('réglages', () {
    testWidgets('profil, agent, appareil, garanties vraies : le verrouillage dépend du coffre, les notifications ne sont pas branchées', (t) async {
      await ouvrir(t);
      await toucher(t, 'ouvrir-reglages');
      expect(find.text('Ce téléphone'), findsOneWidget);
      expect(find.text('Sage-femme'), findsOneWidget);
      expect(find.text('Sage-femme de garde'), findsOneWidget);
      expect(find.text('Appareil u-test-01 · version 0.1.0+1'), findsOneWidget);
      expect(find.text('après 5 minutes d’inactivité'), findsOneWidget);
      expect(find.text('Désactivé'), findsOneWidget, reason: 'sans coffre de code PIN, le verrouillage n\'est pas actif et l\'écran ne dit pas « Activé »');
      expect(find.text('Actif'), findsOneWidget);
      expect(find.text('Non branchées'), findsOneWidget);
      expect(find.text('Activées'), findsNothing);
    });

    testWidgets('réinitialiser : la confirmation se refuse sans effet, s\'accepte sans saisie en attente, ramène à l\'appairage', (t) async {
      final m = await ouvrir(t);
      await toucher(t, 'ouvrir-reglages');
      await toucher(t, 'reinitialiser-appairage');
      expect(find.text('Les saisies non envoyées seront EXPORTÉES avant effacement. Continuer ?'), findsOneWidget);
      await toucher(t, 'reinit-annuler');
      expect(m.reinitialise, isFalse);
      await toucher(t, 'reinitialiser-appairage');
      await toucher(t, 'reinit-ok');
      expect(m.reinitialise, isTrue);
      await t.pumpAndSettle();
    });

    testWidgets('réinitialiser avec des saisies non parties est REFUSÉ en le disant : l\'export n\'est pas branché (E1655)', (t) async {
      final m = await ouvrir(t);
      m.etat.value = const EtatMobile(horsLigne: true, enAttente: 2);
      await toucher(t, 'ouvrir-reglages');
      await toucher(t, 'reinitialiser-appairage');
      await toucher(t, 'reinit-ok');
      expect(m.reinitialise, isFalse);
      expect(find.textContaining('2 saisies ne sont pas encore parties'), findsOneWidget);
    });
  });

  group('code PIN', () {
    testWidgets('l\'application démarre VERROUILLÉE ; un mauvais code compte les essais, trois essais bloquent, le bon code ouvre', (t) async {
      final coffre = CoffrePinMemoire('1234');
      var maintenant = DateTime(2026, 10, 31, 10);
      await ouvrir(t, coffre: coffre, horloge: () => maintenant);
      expect(find.text('Code PIN'), findsOneWidget);
      expect(find.text('Saisissez votre code à 4 chiffres.'), findsOneWidget);
      expect(find.textContaining('Démonstration'), findsNothing, reason: 'le code 1234 de la page est une démonstration, jamais affiché sur un vrai téléphone');
      expect(find.text('Ma tournée'), findsNothing, reason: 'l\'accueil est caché tant que le code n\'est pas saisi');
      Future<void> frappe(String s) async {
        for (final k in s.split('')) {
          await t.tap(find.byKey(Key('touche-$k')));
          await t.pump();
        }
        await t.pump();
      }

      await frappe('12');
      expect(find.byKey(const Key('point-plein-1')), findsOneWidget);
      await t.tap(find.byKey(const Key('touche-effacer')));
      await t.pump();
      expect(find.byKey(const Key('point-plein-1')), findsNothing);
      expect(find.byKey(const Key('point-plein-0')), findsOneWidget);
      await t.tap(find.byKey(const Key('touche-effacer')));
      await t.pump();
      expect(find.byKey(const Key('point-plein-0')), findsNothing);
      await frappe('0000');
      expect(find.text('Code incorrect (1/3).'), findsOneWidget);
      await frappe('0000');
      expect(find.text('Code incorrect (2/3).'), findsOneWidget);
      await frappe('0000');
      expect(find.text('Trop d’essais — réessayez dans 30 s.'), findsOneWidget);
      await frappe('1234');
      expect(find.text('Ma tournée'), findsNothing, reason: 'bloqué, même le bon code est ignoré');
      maintenant = maintenant.add(const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(find.text('Trop d’essais — réessayez dans 30 s.'), findsNothing);
      await frappe('1234');
      await t.pumpAndSettle();
      expect(find.text('Ma tournée'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('premier lancement : le code se choisit deux fois ; une seconde saisie différente recommence', (t) async {
      final coffre = CoffrePinMemoire();
      await ouvrir(t, coffre: coffre);
      expect(find.text('Choisissez un code à 4 chiffres.'), findsOneWidget);
      Future<void> frappe(String s) async {
        for (final k in s.split('')) {
          await t.tap(find.byKey(Key('touche-$k')));
          await t.pump();
        }
        await t.pump();
      }

      await frappe('4321');
      expect(find.text('Saisissez le même code une seconde fois.'), findsOneWidget);
      await frappe('4322');
      expect(find.textContaining('ne sont pas identiques'), findsOneWidget);
      expect(await coffre.aUnCode(), isFalse);
      await frappe('4321');
      await frappe('4321');
      await t.pumpAndSettle();
      expect(await coffre.verifier('4321'), isTrue);
      expect(find.text('Ma tournée'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('l\'inactivité reverrouille après 5 minutes ; l\'écran en dessous garde son état', (t) async {
      final coffre = CoffrePinMemoire('1234');
      await ouvrir(t, coffre: coffre);
      for (final k in '1234'.split('')) {
        await t.tap(find.byKey(Key('touche-$k')));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.text('Ma tournée'), findsOneWidget);
      await t.tap(find.byKey(const Key('onglet-dossiers')));
      await t.pumpAndSettle();
      await t.pump(const Duration(minutes: 4, seconds: 59));
      expect(find.text('Code PIN'), findsNothing);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(find.text('Code PIN'), findsOneWidget);
      for (final k in '1234'.split('')) {
        await t.tap(find.byKey(Key('touche-$k')));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.byKey(const Key('patient-p4')), findsOneWidget, reason: 'l\'onglet choisi est resté');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('coffre du code PIN : un haché salé, jamais le code', () {
    test('définir, vérifier, retenir les essais ; le stockage ne contient pas le code', () async {
      final stockage = StockageMemoire();
      final coffre = CoffrePinSecurise(stockage, iterations: 1000);
      expect(await coffre.aUnCode(), isFalse);
      await coffre.definir('4321');
      expect(await coffre.aUnCode(), isTrue);
      expect(await coffre.verifier('4321'), isTrue);
      expect(await coffre.verifier('1234'), isFalse);
      expect(stockage.valeurs.values.any((v) => v.contains('4321')), isFalse, reason: 'le code n\'est jamais écrit');
      expect(stockage.valeurs['pin.hache'], isNot('4321'));
      await coffre.poserCompteur(const MobPinCompteur(essais: 3, bloqueJusquaMs: 1234567));
      final relu = CoffrePinSecurise(stockage, iterations: 1000);
      final c = await relu.compteur();
      expect(c.essais, 3);
      expect(c.bloqueJusquaMs, 1234567);
      await expectLater(coffre.definir('12'), throwsA(isA<RefusMobile>().having((e) => e.code, 'code', 'PIN_FORMAT')));
      // Redéfinir change le sel : deux coffres du même code n'ont pas le même haché.
      final autre = StockageMemoire();
      await CoffrePinSecurise(autre, iterations: 1000).definir('4321');
      expect(autre.valeurs['pin.hache'], isNot(stockage.valeurs['pin.hache']));
    });
  });
}

class StockageMemoire implements StockageSecret {
  final Map<String, String> valeurs = {};
  @override
  Future<String?> lire(String cle) async => valeurs[cle];
  @override
  Future<void> ecrire(String cle, String valeur) async => valeurs[cle] = valeur;
}
