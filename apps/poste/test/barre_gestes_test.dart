// LES BOUTONS DE LA BARRE SUPÉRIEURE, AU GESTE (retour de terrain du 01/11/2026 : « les boutons de la barre supérieure ne fonctionnent pas »).
// Chaque test tape le vrai bouton (ou la vraie touche) et lit ce qui paraît : un bouton qui ne fait rien ne passe plus.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/modules/cfg/cfb_notifications.dart' show CfbAudio;
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_poste/shell/fenetre_poste.dart';
import 'package:sigh_poste/shell/logo_clinique.dart';
import 'package:sigh_poste/shell/page_standard.dart';

import 'aide_polices.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/barre.json').readAsStringSync()));
final auj = DateTime.parse(v['horloge'] as String);

/// Le jeu de la sonde de la maquette (collections de la barre) par-dessus les collections vides d'un poste neuf.
Magasin magasin({bool vide = false}) {
  final ref = obj(jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()));
  final jeu = obj(v['jeu']);
  return Magasin({
    'audit': const <M>[],
    'rbac': fl(jsonDecode(File('assets/donnees/jeu/rbac.json').readAsStringSync())),
    if (!vide) for (final e in jeu.entries) e.key: fl(e.value),
  }, 'POSTE', ref);
}

Future<void> monter(WidgetTester t,
    {String role = 'da', Magasin? m, SessionPoste? session, FenetrePoste? fenetre, String? ecran, Size taille = const Size(1600, 1000)}) async {
  t.view.physicalSize = taille;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m ?? magasin(),
      session: session,
      fenetre: fenetre,
      horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  if (session == null || session.etat == EtatSession.connectee) await fermerModales(t);
}

Future<void> fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10));
}

Future<void> toucher(WidgetTester t, Finder f, {int ms = 250}) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

String ecranCourant(WidgetTester t) => (find.byType(ContexteEcran).evaluate().first.widget as ContexteEcran).ecranId;
/// Le titre de la modale du DESSUS (le rappel quotidien du laboratoire peut en porter une dessous).
String titreModale(WidgetTester t) => (t.widgetList(find.byKey(const Key('kit:modale-titre'))).last as Text).data!;
List<String> titresModales() => [for (final e in find.byKey(const Key('kit:modale-titre')).evaluate()) (e.widget as Text).data!];
bool modaleOuverte() => find.byKey(const Key('kit:modale-panneau')).evaluate().isNotEmpty;

/// Ferme toutes les modales (Échap), comme l'agent qui prend connaissance : le rappel du laboratoire s'ouvre de lui-même à son tableau de bord.
Future<void> fermerModales(WidgetTester t) async {
  for (var i = 0; i < 4 && modaleOuverte(); i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> ctrlK(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyK);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  // Le canal sonore est réputé disponible : la notification système (« sonorisation indisponible ») ne fausse pas les comptes.
  setUp(() => CfbAudio.disponible = () => true);
  tearDown(ToastsSigh.viderPourTests);

  // ============================================================================================================================ RECHERCHE
  group('la recherche globale (champ et Ctrl K)', () {
    testWidgets('le champ de la barre ouvre le modal ; on saisit, un clic sur un résultat OUVRE l\'écran visé', (t) async {
      await monter(t, role: 'stock');
      expect(modaleOuverte(), isFalse);
      await toucher(t, find.byKey(const Key('recherche-globale')));
      expect(titreModale(t), 'Recherche globale');
      expect(find.byKey(const Key('recherche-vide')), findsOneWidget, reason: 'moins de deux caractères : le modal le dit');
      await t.enterText(find.byKey(const Key('recherche-champ')), 'amox');
      await t.pump();
      final resultat = find.byKey(const Key('resultat:m6-produits:AMOXICILLINE 500 MG'));
      expect(resultat, findsOneWidget);
      expect(find.textContaining('MED001'), findsOneWidget, reason: 'le détail du produit : code, stock, unité');
      await toucher(t, resultat);
      expect(modaleOuverte(), isFalse, reason: 'le clic referme le modal');
      expect(ecranCourant(t), 'm6-produits', reason: 'et ouvre l\'écran visé');
      await fin(t);
    });

    testWidgets('Ctrl K ouvre la recherche de n\'importe quel écran ; Échap la referme ; une rubrique ouvre sa page', (t) async {
      await monter(t, role: 'admin');
      await ctrlK(t);
      expect(titreModale(t), 'Recherche globale');
      await t.enterText(find.byKey(const Key('recherche-champ')), 'bilan');
      await t.pump();
      expect(find.textContaining('RUBRIQUES'), findsOneWidget);
      await toucher(t, find.byKey(const Key('resultat:m12-etats-financiers#bilan:Bilan')));
      expect(ecranCourant(t), 'm12-etats-financiers');
      await ctrlK(t);
      expect(modaleOuverte(), isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 300));
      expect(modaleOuverte(), isFalse, reason: 'Échap referme');
      await fin(t);
    });

    testWidgets('filtrée par les droits : un profil ne trouve pas ce qu\'il ne voit pas, et « aucun résultat » se DIT', (t) async {
      await monter(t, role: 'reception');
      await toucher(t, find.byKey(const Key('recherche-globale')));
      await t.enterText(find.byKey(const Key('recherche-champ')), 'amox');
      await t.pump();
      expect(find.byKey(const Key('resultat:m6-produits:AMOXICILLINE 500 MG')), findsNothing, reason: 'm6-produits est fermé à la réception');
      expect(find.byKey(const Key('recherche-aucun')), findsOneWidget);
      expect(find.text('Aucun résultat pour « amox ».'), findsOneWidget);
      await t.enterText(find.byKey(const Key('recherche-champ')), 'padonou');
      await t.pump();
      expect(find.textContaining('PADONOU Amina'), findsOneWidget, reason: 'la réception voit le répertoire des patients');
      await fin(t);
    });
  });

  // ============================================================================================================================ ACTIONS
  group('le menu Actions', () {
    testWidgets('liste les actions DE CE PROFIL (celles de la maquette, filtrées) ; un clic ouvre l\'écran', (t) async {
      await monter(t, role: 'reception');
      await toucher(t, find.byKey(const Key('barre-actions')));
      expect(titreModale(t), 'Actions rapides');
      final attendues = [for (final a in fl(obj(v['actions'])['reception'])) '${a['ecran']}'];
      expect(attendues.length, greaterThan(3));
      for (final e in attendues) {
        expect(find.byKey(Key('action:$e')), findsOneWidget, reason: e);
      }
      expect(find.byKey(const Key('action:m8-facturation')), findsNothing, reason: 'la facturation est fermée à la réception : jamais de porte fermée proposée');
      await toucher(t, find.byKey(const Key('action:m1-patients')));
      expect(modaleOuverte(), isFalse);
      expect(ecranCourant(t), 'm1-patients');
      await fin(t);
    });

    testWidgets('un profil sans action ouverte lit une phrase, jamais un modal vide', (t) async {
      await monter(t, role: 'ambulancier');
      await toucher(t, find.byKey(const Key('barre-actions')));
      final n = fl(obj(v['actions'])['ambulancier']).length;
      if (n == 0) {
        expect(find.byKey(const Key('actions-vide')), findsOneWidget);
        expect(find.text('Aucune action rapide ouverte à votre profil.'), findsOneWidget);
      } else {
        expect(find.byKey(const Key('actions-vide')), findsNothing);
      }
      await fin(t);
    });
  });

  // ============================================================================================================================ PLEIN ÉCRAN
  group('le plein écran', () {
    testWidgets('le bouton bascule l\'état réel de la fenêtre, et l\'info-bulle suit', (t) async {
      final f = FenetreMemoire();
      await monter(t, fenetre: f);
      expect(f.pleinEcran.value, isFalse);
      await toucher(t, find.byKey(const Key('barre-plein-ecran')));
      expect(f.bascules, 1);
      expect(f.pleinEcran.value, isTrue);
      expect(find.byTooltip('Quitter le plein écran (Échap)'), findsOneWidget);
      await toucher(t, find.byKey(const Key('barre-plein-ecran')));
      expect(f.pleinEcran.value, isFalse);
      expect(find.byTooltip('Plein écran (F11)'), findsOneWidget);
      await fin(t);
    });

    testWidgets('F11 fait la même chose ; une plateforme qui REFUSE est dite (jamais un bouton muet)', (t) async {
      final f = FenetreMemoire();
      await monter(t, fenetre: f);
      await t.sendKeyEvent(LogicalKeyboardKey.f11);
      await t.pump();
      expect(f.bascules, 1);
      await fin(t);
      final refus = FenetreMemoire(refuse: true);
      await monter(t, fenetre: refus);
      await toucher(t, find.byKey(const Key('barre-plein-ecran')));
      expect(find.text('Plein écran indisponible sur ce poste.'), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ CLOCHE
  group('la cloche et le centre de notifications', () {
    int attendu(String role) => fl(obj(v['notifications'])[role]).where((n) => n['domaine'] != 'Périphérique audio').length;

    testWidgets('le badge est le compte RÉEL des alertes non acquittées du rôle (celui de la maquette), jamais un chiffre écrit en dur', (t) async {
      for (final role in ['da', 'stock', 'laborantin', 'caissier']) {
        await monter(t, role: role);
        final n = attendu(role);
        expect(n, greaterThan(0));
        expect(t.widget<Text>(find.descendant(of: find.byKey(const Key('cloche-badge')), matching: find.byType(Text))).data, '$n', reason: role);
        await fin(t);
      }
      await monter(t, role: 'aide_soignant', m: magasin(vide: true));
      expect(find.byKey(const Key('cloche-badge')), findsNothing, reason: 'rien à signaler : pas de badge');
      await fin(t);
    });

    testWidgets('la cloche ouvre le centre ; acquitter sort du badge SANS retirer la ligne ; reprendre la remet ; voir ouvre la source', (t) async {
      await monter(t, role: 'stock');
      final avant = attendu('stock');
      await toucher(t, find.byKey(const Key('barre-cloche')));
      expect(titreModale(t), 'Notifications');
      // Regroupement au-delà de trois : les trois articles sous le seuil font UNE ligne.
      expect(find.text('3 article(s) sous leur seuil d’alerte'), findsOneWidget);
      expect(find.textContaining('AMOXICILLINE 500 MG : 0 en stock'), findsOneWidget, reason: 'un article seul reste nommé');
      final cle = 'groupe:stock_seuil|important';
      await toucher(t, find.byKey(Key('notif-acquitter:$cle')));
      expect(find.byKey(Key('notif-ligne:$cle')), findsOneWidget, reason: 'entendre n\'est pas traiter : la ligne reste au centre');
      expect(find.text('· acquittée'), findsOneWidget);
      expect(find.byKey(Key('notif-acquitter:$cle')), findsOneWidget);
      expect(find.text('Reprendre'), findsOneWidget);
      // Le badge (derrière la modale) a baissé du nombre de MEMBRES acquittés ? Non : d'UNE ligne groupée, comme la maquette.
      await toucher(t, find.byKey(Key('notif-acquitter:$cle')));
      expect(find.text('· acquittée'), findsNothing, reason: 'reprise');
      await toucher(t, find.byKey(const Key('notif-voir:groupe:stock_seuil|important')));
      expect(modaleOuverte(), isFalse);
      expect(ecranCourant(t), 'm6-alertes', reason: 'Voir ouvre l\'écran source');
      expect(avant, greaterThan(0));
      await fin(t);
    });

    testWidgets('acquitter fait baisser le badge, reprendre le fait remonter ; l\'acquittement est tracé au magasin', (t) async {
      final m = magasin();
      await monter(t, role: 'caissier', m: m);
      String badge() => t.widget<Text>(find.descendant(of: find.byKey(const Key('cloche-badge')), matching: find.byType(Text))).data!;
      final n0 = int.parse(badge());
      await toucher(t, find.byKey(const Key('barre-cloche')));
      final premiere = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('notif-acquitter:')).first;
      await toucher(t, premiere);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 300));
      expect(int.parse(badge()), n0 - 1);
      expect(m.collection('reglages').actives.any((f) => f['id'] == 'notificationsAcquittees'), isTrue);
      await fin(t);
    });

    testWidgets('jamais de donnée médicale dans le message : une alerte groupée ne nomme personne', (t) async {
      await monter(t, role: 'laborantin');
      await toucher(t, find.byKey(const Key('barre-cloche')));
      expect(titreModale(t), 'Notifications');
      expect(find.text('3 analyse(s) réglée(s), prélèvement à faire'), findsOneWidget);
      expect(find.textContaining('NFS'), findsNothing, reason: 'la ligne groupée ne détaille ni examen ni patient');
      await fin(t);
    });

    testWidgets('un profil sans alerte lit « Aucune alerte en cours », jamais un modal muet', (t) async {
      await monter(t, role: 'aide_soignant', m: magasin(vide: true));
      await toucher(t, find.byKey(const Key('barre-cloche')));
      expect(find.byKey(const Key('notif-vide')), findsOneWidget);
      expect(find.text('Aucune alerte en cours'), findsOneWidget);
      await fin(t);
    });

    testWidgets('une alerte ne mène jamais à un écran interdit : le caissier ne reçoit pas les échéances fiscales', (t) async {
      final centre = CentreNotifications(magasin: magasin(), donnees: () => donnees, role: () => 'caissier', horloge: () => auj, audioDisponible: () => true);
      expect(centre.collecter().where((n) => n.source == 'echeance_fiscale'), isEmpty);
      expect(centre.collecter().every((n) => n.lien == null || donnees.matrice.peutVoir('caissier', n.lien!)), isTrue);
    });
  });

  // ============================================================================================================================ PROFIL
  group('le menu du profil', () {
    testWidgets('nom, rôle, liens du compte, verrouiller, déconnexion', (t) async {
      final session = SessionPoste.ouverte('da', nom: 'GBEDJI Hervé', horloge: () => auj);
      await monter(t, role: 'da', session: session);
      expect(find.byKey(const Key('nom-courant')), findsOneWidget);
      await toucher(t, find.byKey(const Key('barre-profil')));
      expect(titreModale(t), 'Profil utilisateur');
      expect(t.widget<Text>(find.byKey(const Key('profil-nom'))).data, 'GBEDJI Hervé');
      expect(t.widget<Text>(find.byKey(const Key('profil-role'))).data, donnees.matrice.libelle('da'));
      expect(find.byKey(const Key('profil-lien:cfg-compte')), findsOneWidget);
      expect(find.byKey(const Key('profil-verrouiller')), findsOneWidget);
      expect(find.byKey(const Key('profil-deconnexion')), findsOneWidget);
      await toucher(t, find.byKey(const Key('profil-lien:cfg-compte')));
      expect(modaleOuverte(), isFalse);
      expect(ecranCourant(t), 'cfg-compte');
      await fin(t);
    });

    testWidgets('« Verrouiller l\'écran » suspend la session (jamais fermée) et pose l\'écran de verrouillage', (t) async {
      final session = SessionPoste.ouverte('da', nom: 'GBEDJI Hervé', horloge: () => auj);
      await monter(t, role: 'da', session: session);
      await toucher(t, find.byKey(const Key('barre-profil')));
      await toucher(t, find.byKey(const Key('profil-verrouiller')));
      expect(session.etat, EtatSession.verrouillee);
      expect(session.retour, isNotNull, reason: 'l\'écran à retrouver est retenu');
      await fin(t);
    });

    testWidgets('sans session, la commande « Verrouiller » est ABSENTE (non grisée)', (t) async {
      await monter(t, role: 'da');
      await toucher(t, find.byKey(const Key('barre-profil')));
      expect(find.byKey(const Key('profil-verrouiller')), findsNothing);
      expect(find.byKey(const Key('profil-deconnexion')), findsOneWidget);
      await fin(t);
    });

    testWidgets('« Se déconnecter » ferme la session et ouvre la connexion, sans chrome', (t) async {
      final session = SessionPoste(exigeConnexion: true, compte: const AccCompte(identifiant: 'da', nom: 'GBEDJI Hervé', role: 'da'), horloge: () => auj);
      await monter(t, role: 'da', session: session);
      await toucher(t, find.byKey(const Key('barre-profil')));
      await toucher(t, find.byKey(const Key('profil-deconnexion')));
      await t.pump(const Duration(milliseconds: 300));
      expect(session.etat, EtatSession.deconnectee);
      expect(find.byKey(const Key('barre-superieure')), findsNothing, reason: 'la connexion est servie sans barre');
      expect(find.byKey(const Key('acces:carte')), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ APRÈS LA CONNEXION
  group('après la connexion : le tableau de bord du poste ET le centre de notifications, d\'eux-mêmes', () {
    Future<void> seConnecter(WidgetTester t, SessionPoste s, String role) async {
      s.connecter(AccCompte(identifiant: role, nom: 'Agent $role', role: role));
      await t.pump();
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('chaque rôle qui a une page d\'accueil s\'ouvre dessus, et le centre s\'ouvre (À votre arrivée) avec ce qui l\'attend', (t) async {
      var verifies = 0;
      for (final role in ['da', 'direction', 'comptable', 'stock', 'caissier', 'laborantin', 'infirmier', 'echographiste', 'medecin', 'reception']) {
        final session = SessionPoste(exigeConnexion: true, horloge: () => auj);
        await monter(t, role: 'admin', session: session);
        expect(modaleOuverte(), isFalse, reason: 'rien ne s\'ouvre avant la connexion');
        await seConnecter(t, session, role);
        final home = donnees.matrice.accueil(role)!;
        expect(ecranCourant(t), home, reason: 'page d\'accueil de $role');
        expect(home, startsWith('dash-'), reason: 'c\'est un tableau de bord');
        expect(modaleOuverte(), isTrue, reason: 'le centre de notifications s\'ouvre à la connexion ($role)');
        expect(titresModales(), contains('À votre arrivée'), reason: role);
        final n = fl(obj(v['notifications'])[role]).where((x) => x['domaine'] != 'Périphérique audio').length;
        if (n == 0) {
          expect(find.byKey(const Key('notif-vide')), findsOneWidget, reason: role);
          expect(find.text('Rien ne vous attend'), findsOneWidget);
        } else {
          expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('notif-ligne:')), findsWidgets, reason: role);
        }
        await fermerModales(t);
        expect(modaleOuverte(), isFalse);
        verifies++;
        await fin(t);
      }
      expect(verifies, 10);
    });

    testWidgets('le modal est rangé par famille (stock, comptabilité, à valider…), chaque ligne a son lien vers la source', (t) async {
      final session = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, role: 'admin', session: session);
      await seConnecter(t, session, 'da');
      for (final famille in ['STOCK : ', 'COMPTABILITÉ : ', 'À VALIDER : ', 'FACTURATION : ', 'RECOUVREMENT : ']) {
        expect(find.textContaining(famille), findsOneWidget, reason: famille);
      }
      expect(find.text('2 pièce(s) comptable(s) en brouillon'), findsNothing, reason: 'deux pièces seulement : elles restent nommées');
      expect(find.text('Pièce comptable en brouillon : OD-2026-00001'), findsOneWidget);
      await toucher(t, find.byKey(const Key('notif-voir:fisc:E2')));
      expect(modaleOuverte(), isFalse);
      expect(ecranCourant(t), 'm12-echeances', reason: 'le lien mène à la source');
      await fin(t);
    });

    testWidgets('à l\'ouverture de session, une notification de poste ne nomme AUCUN patient (jamais de donnée médicale dans un message qui s\'ouvre seul)', (t) async {
      final m = magasin();
      // Une seule notification de poste pour l'imagerie : sous trois, elle reste une ligne nommée (donc à masquer à l'ouverture de session).
      m.collection('notifications').archiver('N1');
      m.collection('notifications').archiver('N3');
      m.collection('notifications').inserer({
        'id': 'NOTX',
        'statut': 'actif',
        'type': 'demande_imagerie',
        'poste': 'imagerie',
        'libelle': 'Nouvelle demande d’imagerie : BANI Zoukanéri',
        'detail': 'IRM pelvienne',
        'lue': false
      });
      final session = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, role: 'admin', session: session, m: m);
      await seConnecter(t, session, 'echographiste');
      expect(titreModale(t), 'À votre arrivée');
      expect(find.textContaining('BANI'), findsNothing);
      expect(find.text('Notification de poste'), findsOneWidget);
      await fermerModales(t);
      await toucher(t, find.byKey(const Key('barre-cloche')));
      expect(find.textContaining('BANI'), findsOneWidget, reason: 'le centre de la cloche, derrière les droits du poste, détaille');
      await fin(t);
    });

    testWidgets('un déverrouillage ne rouvre pas le centre (c\'est le même agent qui reprend son travail)', (t) async {
      final session = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, role: 'admin', session: session);
      await seConnecter(t, session, 'stock');
      await fermerModales(t);
      session.verrouillerMaintenant('dash-stock');
      await t.pump(const Duration(milliseconds: 300));
      session.deverrouiller();
      await t.pump(const Duration(milliseconds: 300));
      expect(modaleOuverte(), isFalse);
      await fin(t);
    });
  });

  // ============================================================================================================================ FIL D'ARIANE
  group('le fil d\'Ariane est celui de la maquette', () {
    testWidgets('sur chacune des pages lues dans la maquette : jamais « Accueil > Accueil », module cliquable, hub sans dernier maillon', (t) async {
      final pages = obj(v['fil']);
      for (final e in pages.entries) {
        await monter(t, role: 'admin', ecran: e.key);
        final maillons = [
          for (final w in t.widgetList<Text>(find.descendant(of: find.byKey(const Key('fil-ariane')), matching: find.byType(Text)))) w.data
        ];
        expect(maillons, [for (final x in (e.value as List)) '$x'], reason: e.key);
        await fin(t);
      }
    });

    testWidgets('« Accueil » ramène au tableau de bord du rôle, l\'intitulé du module à sa page d\'accueil', (t) async {
      await monter(t, role: 'admin', ecran: 'm6-lots');
      await toucher(t, find.byKey(const Key('fil-lien:2')));
      expect(find.byKey(const Key('titre-page')), findsOneWidget);
      await monter(t, role: 'admin', ecran: 'm6-lots');
      await toucher(t, find.byKey(const Key('fil-lien:0')));
      expect(ecranCourant(t), donnees.matrice.accueil('admin'));
      await fin(t);
    });
  });

  // ============================================================================================================================ LOGO
  group('le logo de la clinique', () {
    test('il est déclaré aux assets du poste, présent, et se décode (131 × 82 PNG, converti du JPEG)', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/img/'), reason: 'le dossier des images est déclaré');
      final f = File(LogoClinique.asset);
      expect(f.existsSync(), isTrue);
      final b = f.readAsBytesSync();
      expect(b.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'un PNG, non altéré (aucune conversion de fin de ligne)');
      expect(b.length, greaterThan(5000));
      expect(File('../../.gitattributes').readAsStringSync(), contains('*.png binary'), reason: 'un checkout Windows ne convertit jamais le logo');
    });

    testWidgets('la barre l\'AFFICHE réellement (image décodée, pas le monogramme de repli)', (t) async {
      await monter(t, role: 'da');
      await t.runAsync(() async {
        final ctx = t.element(find.byKey(const Key('barre-logo')));
        await precacheImage(const AssetImage(LogoClinique.asset), ctx);
      });
      await t.pump(const Duration(milliseconds: 200));
      expect(find.descendant(of: find.byKey(const Key('barre-logo')), matching: find.byKey(const Key('logo-clinique'))), findsOneWidget);
      expect(find.byKey(const Key('logo-clinique-repli')), findsNothing);
      final taille = t.getSize(find.byKey(const Key('logo-clinique')));
      expect(taille.width, greaterThan(40), reason: 'le logo est lisible (le carré de 28 px de la maquette le rendait minuscule)');
      await fin(t);
    });

    testWidgets('un asset illisible ne disparaît PAS en silence : le monogramme « CNT » prend la place', (t) async {
      await t.pumpWidget(MaterialApp(
          home: DefaultAssetBundle(bundle: _BundleVide(), child: const Scaffold(body: LogoClinique(largeur: 60, hauteur: 40)))));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('logo-clinique-repli')), findsOneWidget);
      expect(find.text(IdentiteClinique.sigle), findsOneWidget);
    });

    testWidgets('la connexion et le verrou le portent', (t) async {
      final session = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, role: 'admin', session: session);
      expect(find.byKey(const Key('logo-clinique')), findsWidgets, reason: 'écran de connexion');
      await fin(t);
      final ouverte = SessionPoste.ouverte('da', horloge: () => auj);
      await monter(t, role: 'da', session: ouverte);
      ouverte.verrouillerMaintenant('dash-da');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('logo-clinique')), findsWidgets, reason: 'écran verrouillé');
      await fin(t);
    });
  });

  test('la page standard est celle du kit : le fil expose ses liens', () {
    expect(const PageStandard(titre: 't', fil: ['A'], child: SizedBox()).surFil, isEmpty);
  });
}

/// Un paquet d'assets qui ne contient rien : charger quoi que ce soit échoue.
class _BundleVide extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('asset introuvable : $key'));
}
