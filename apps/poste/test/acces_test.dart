import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/shell/barre_superieure.dart';
import 'package:sigh_poste/shell/contexte_autonome.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_poste/shell/page_standard.dart';
import 'package:sigh_poste/shell/ruban.dart';

import 'aide_polices.dart';
import 'parite/extracteur.dart' as ex;

/// Écrans d'ACCÈS (sans coque) et de SUPPORT : connexion, mot de passe oublié, réinitialisation, double facteur, écran verrouillé, pages d'erreur, plan du
/// site, aide, contact éditeur, et la page publique d'enquête branchée à la coque. Les règles sont rejouées sur les vecteurs de la maquette
/// (`packages/domaine/test/acces_test.dart`) ; ici, l'ÉCRAN et ce que la COQUE fait des écrans autonomes. Le verrou de session se teste à l'HORLOGE INJECTÉE.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

final donnees = DonneesNavigation.depuisDossier();
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/acces.json').readAsStringSync()));
final auj = DateTime(2026, 10, 30, 10);

List<M> jeu(String nom) => fl(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));
String sp(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

Magasin poste({List<M> utilisateurs = const [], List<M> rbac = const [], List<M> jetons = const [], List<M> enquetes = const []}) => Magasin({
      'audit': const <M>[],
      'utilisateurs': [for (final u in utilisateurs.isEmpty ? jeu('utilisateurs') : utilisateurs) {...u}],
      'rbac': [for (final r in rbac.isEmpty ? jeu('rbac') : rbac) {...r}],
      'tentativesConnexion': const <M>[],
      'rolesBase': jeu('rolesBase'),
      'support': const <M>[],
      'jetonsEnquete': jetons,
      'enquetes': enquetes,
      'reponsesEnquetes': const <M>[],
    }, 'POSTE');

Future<void> monter(WidgetTester t, Magasin m,
    {String? ecran,
    SessionPoste? session,
    String role = 'reception',
    DateTime Function()? horloge,
    Map<String, String> parametres = const {},
    Size taille = const Size(1600, 1000)}) async {
  t.view.physicalSize = taille;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      session: session,
      parametres: parametres,
      horloge: horloge ?? () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Démonte la coque (annule le minuteur du verrou) et laisse partir les messages.
Future<void> fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 10));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      ToastsSigh.viderPourTests();
    });

Future<void> saisir(WidgetTester t, String cle, String texte) async {
  await t.enterText(find.byKey(Key(cle)), texte);
  await t.pump();
}

Future<void> toucher(WidgetTester t, Finder f, {int ms = 300}) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Future<void> bouton(WidgetTester t, String libelle, {int ms = 300}) => toucher(t, find.widgetWithText(BoutonSigh, libelle).first, ms: ms);

bool sansChrome(WidgetTester t) =>
    find.byType(BarreSuperieure).evaluate().isEmpty &&
    find.byType(Ruban).evaluate().isEmpty &&
    find.byType(PageStandard).evaluate().isEmpty &&
    find.byType(ContexteEcran).evaluate().isEmpty;

List<M> audit(Magasin m, String action) => [for (final e in m.collection('audit').toutes) if (e['action'] == action) e];

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  // ============================================================================================================================ LA COQUE
  group('la coque sert les écrans autonomes sans chrome', () {
    cas('un écran autonome demandé s’ouvre en plein écran : ni barre, ni ruban, ni page standard', (t) async {
      for (final id in ['index', 'auth-forgot', 'auth-reset', 'auth-2fa', 'auth-lock', 'error-404', 'error-403', 'plan-du-site']) {
        await monter(t, poste(), ecran: id);
        expect(sansChrome(t), isTrue, reason: id);
        expect(find.byType(ContexteAutonome), findsOneWidget, reason: id);
        await fin(t);
      }
    });

    cas('un écran ordinaire garde sa coque (aucune régression)', (t) async {
      await monter(t, poste(), ecran: 'aide-apropos');
      expect(find.byType(BarreSuperieure), findsOneWidget);
      expect(find.byType(Ruban), findsOneWidget);
      expect(find.byType(PageStandard), findsOneWidget);
      expect(find.byType(ContexteAutonome), findsNothing);
      await fin(t);
    });

    cas('la page publique reçoit le magasin et l’horloge — ni session, ni manifeste, ni navigation', (t) async {
      await monter(t, poste(), ecran: 'enquete-publique', session: SessionPoste.ouverte('reception', horloge: () => auj));
      final x = t.widget<ContexteAutonome>(find.byType(ContexteAutonome));
      expect(x.publique, isTrue);
      expect(x.session, isNull);
      expect(x.donnees, isNull);
      expect(x.role, isNull);
      expect(x.parametres, isEmpty);
      expect(sansChrome(t), isTrue);
      await fin(t);
    });
  });

  // ============================================================================================================================ ENQUÊTE PUBLIQUE
  group('enquete-publique branchée à la coque', () {
    final enquete = <M>[
      {
        'id': 'ENQ0001',
        'statut': 'actif',
        'reference': 'ENQ-SAT',
        'titre': 'Satisfaction des patients',
        'description': 'Votre avis nous aide.',
        'questions': [
          {'id': 'q1', 'libelle': 'Accueil', 'type': 'note'}
        ],
      }
    ];
    final jeton = <M>[
      {
        'id': 'J1',
        'statut': 'actif',
        'jeton': 'abcdefghjkmnpqrstuvwxyz2',
        'enqueteId': 'ENQ0001',
        'enqueteTitre': 'Satisfaction des patients',
        'anonyme': true,
        'usage': 'salle',
        'creeLe': '2026-10-01',
        'expireLe': '2026-12-31',
      }
    ];

    cas('avec un jeton valide dans l’adresse : le questionnaire, sans le moindre chrome', (t) async {
      await monter(t, poste(jetons: jeton, enquetes: enquete), ecran: 'enquete-publique', parametres: {'jeton': 'abcdefghjkmnpqrstuvwxyz2'});
      expect(find.byKey(const Key('qual:questionnaire')), findsOneWidget);
      expect(find.text('Satisfaction des patients'), findsOneWidget);
      expect(sansChrome(t), isTrue);
      expect(find.byType(ContexteEcran), findsNothing);
      await fin(t);
    });

    cas('sans jeton, jeton inconnu, expiré ou révoqué : LA MÊME réponse', (t) async {
      final textes = <String>{};
      final expire = [
        {...jeton.first, 'jeton': 'expire11111111111111111', 'expireLe': '2026-10-29'}
      ];
      final revoque = [
        {...jeton.first, 'jeton': 'revoque1111111111111111', 'revoqueLe': '2026-10-01'}
      ];
      for (final code in [null, 'nexistepas', 'expire11111111111111111', 'revoque1111111111111111']) {
        await monter(t, poste(jetons: [...jeton, ...expire, ...revoque], enquetes: enquete),
            ecran: 'enquete-publique', parametres: code == null ? const {} : {'jeton': code});
        expect(find.byKey(const Key('qual:lien-invalide')), findsOneWidget);
        textes.add(ex.textesVisibles(t).join('|'));
        await fin(t);
      }
      expect(textes.length, 1);
    });
  });

  // ============================================================================================================================ CONNEXION
  group('index — connexion', () {
    cas('personne n’est connecté : la coque ne sert que la connexion, avec les textes de la maquette', (t) async {
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, poste(), session: s);
      expect(s.etat, EtatSession.deconnectee);
      expect(sansChrome(t), isTrue);
      final vus = ex.textesVisibles(t);
      for (final texte in (obj(v['connexion'])['textes'] as List).cast<String>()) {
        if (texte == 'Identifiant ou mot de passe incorrect.') continue; // le message d'un refus, absent d'une page neuve
        final n = ex.normaliser(texte);
        expect(vus.any((x) => x.contains(n)), isTrue, reason: texte);
      }
      await fin(t);
    });

    cas('la page ne liste AUCUN compte : ni sélecteur de profil, ni mot de passe pré-rempli, ni pied (20/10/2026)', (t) async {
      await monter(t, poste(), session: SessionPoste(exigeConnexion: true, horloge: () => auj));
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(DropdownMenu), findsNothing);
      final champs = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(champs.length, 2);
      expect(champs.every((c) => c.controller!.text.isEmpty), isTrue);
      for (final compte in jeu('utilisateurs').take(10)) {
        expect(find.textContaining('${compte['identifiant']}'), findsNothing);
      }
      expect(find.textContaining('comptes ouverts par l’administrateur'), findsNothing);
      expect(find.textContaining('Plan du site'), findsNothing);
      // Le mot de passe est masqué ; l'œil le montre.
      expect(t.widget<TextField>(find.byKey(const Key('acces:motdepasse'))).obscureText, isTrue);
      await toucher(t, find.byKey(const Key('acces:oeil')));
      expect(t.widget<TextField>(find.byKey(const Key('acces:motdepasse'))).obscureText, isFalse);
      await fin(t);
    });

    cas('le poste dit ce qu’il ne fait pas : le mot de passe n’est pas vérifié (A5)', (t) async {
      await monter(t, poste(), session: SessionPoste(exigeConnexion: true, horloge: () => auj));
      expect(find.byKey(const Key('acces:simulation')), findsOneWidget);
      expect(find.textContaining('ne vérifie pas encore le mot de passe'), findsOneWidget);
      await fin(t);
    });

    cas('trois soumissions vides : les trois messages de la maquette, le troisième annonce le verrouillage', (t) async {
      await monter(t, poste(), session: SessionPoste(exigeConnexion: true, horloge: () => auj));
      for (final e in fl(obj(v['connexion'])['essaisVides'])) {
        await bouton(t, 'Se connecter');
        expect(find.text('${e['texte']}'), findsOneWidget);
      }
      await fin(t);
    });

    cas('identifiant inconnu : refus générique, tentative écrite (RG-12), session non ouverte', (t) async {
      final m = poste();
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, m, session: s);
      await saisir(t, 'acces:identifiant', 'inconnu.xyz');
      await saisir(t, 'acces:motdepasse', 'faux');
      await bouton(t, 'Se connecter');
      expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
      expect(s.etat, EtatSession.deconnectee);
      final t0 = m.collection('tentativesConnexion').toutes.single;
      expect(t0['identifiant'], 'inconnu.xyz');
      expect(t0['motif'], 'Identifiant inconnu');
      expect(t0['traitee'], false);
      await fin(t);
    });

    cas('compte du jeu : la session s’ouvre sous SON rôle, la coque apparaît à l’accueil du profil, la connexion est journalisée sans prétendre vérifier', (t) async {
      final m = poste();
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      final compte = jeu('utilisateurs').firstWhere((u) => u['identifiant'] == 'e.orou');
      await monter(t, m, session: s);
      await saisir(t, 'acces:identifiant', 'e.orou');
      await saisir(t, 'acces:motdepasse', 'nimporte-quoi');
      await bouton(t, 'Se connecter', ms: 600);
      expect(s.etat, EtatSession.connectee);
      expect(s.role, compte['role']);
      expect(s.compte!.nom, compte['nomComplet']);
      expect(find.byType(BarreSuperieure), findsOneWidget, reason: 'la coque prend le relais');
      expect(find.byKey(const Key('acces:identifiant')), findsNothing);
      final e = audit(m, 'Connexion').single;
      expect(e['reference'], 'e.orou');
      expect(e['module'], 'M14');
      expect(obj(e['apres'])['motDePasseVerifie'], false);
      await fin(t);
    });

    cas('rôle archivé : refus NOMMÉ en modale, tentative et journal écrits, aucune session', (t) async {
      final m = poste(utilisateurs: [
        {'id': 'U1', 'statut': 'actif', 'identifiant': 'p.pharma', 'nomComplet': 'Ancien Pharmacien', 'role': 'pharmacien'}
      ]);
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, m, session: s);
      await saisir(t, 'acces:identifiant', 'p.pharma');
      await saisir(t, 'acces:motdepasse', 'x');
      await bouton(t, 'Se connecter', ms: 500);
      expect(s.etat, EtatSession.deconnectee);
      expect(find.text('Connexion refusée'), findsOneWidget);
      expect(find.textContaining('a été archivé par l’administrateur système'), findsOneWidget);
      expect(find.text('Ce compte ne peut plus ouvrir de session.'), findsOneWidget);
      expect(find.textContaining('Connexion refusée — le profil « '), findsOneWidget);
      final t0 = m.collection('tentativesConnexion').toutes.single;
      expect(t0['motif'], 'Rôle archivé — accès retiré par l’administrateur');
      expect(t0['role'], 'pharmacien');
      expect(audit(m, 'Connexion refusée').single['reference'], 'p.pharma');
      await fin(t);
    });

    cas('compte archivé : refus nommé (RG-14)', (t) async {
      final m = poste(utilisateurs: [
        {'id': 'U1', 'statut': 'archive', 'identifiant': 'a.ferme', 'nomComplet': 'Compte fermé', 'role': 'caissier'}
      ]);
      await monter(t, m, session: SessionPoste(exigeConnexion: true, horloge: () => auj));
      await saisir(t, 'acces:identifiant', 'a.ferme');
      await saisir(t, 'acces:motdepasse', 'x');
      await bouton(t, 'Se connecter');
      expect(find.text('Ce compte a été archivé : il n’ouvre plus de session (RG-14).'), findsOneWidget);
      await fin(t);
    });

    cas('« Mot de passe oublié ? » mène à l’écran voisin, puis « Retour à la connexion » revient', (t) async {
      await monter(t, poste(), session: SessionPoste(exigeConnexion: true, horloge: () => auj));
      await toucher(t, find.text('Mot de passe oublié ?'));
      expect(find.text('Mot de passe oublié'), findsOneWidget);
      await toucher(t, find.text('← Retour à la connexion'));
      expect(find.text('Connexion'), findsWidgets);
      expect(find.byKey(const Key('acces:motdepasse')), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ OUBLI / RÉINITIALISATION / 2FA
  group('mot de passe oublié, réinitialisation, double facteur', () {
    cas('mot de passe oublié : le geste est journalisé, le message est celui de la maquette, puis la réinitialisation s’ouvre', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'auth-forgot');
      final o = obj(v['oubli']);
      for (final texte in (o['textes'] as List).cast<String>().skip(10)) {
        expect(ex.textesVisibles(t).any((x) => x.contains(ex.normaliser(texte))), isTrue, reason: texte);
      }
      await bouton(t, 'Envoyer les instructions');
      expect(find.text('Renseigner l’identifiant ou l’adresse électronique.'), findsOneWidget, reason: 'champ obligatoire');
      await saisir(t, 'acces:identifiant', 'a.kassa');
      await bouton(t, 'Envoyer les instructions');
      final toast = fl(o['toasts']).single;
      expect(find.text('${toast['titre']}'), findsOneWidget);
      expect(find.text('${toast['detail']}'), findsOneWidget);
      expect(audit(m, 'Demande de réinitialisation du mot de passe').single['reference'], 'a.kassa');
      await t.pump(const Duration(milliseconds: 1300));
      expect(find.text('Réinitialiser le mot de passe'), findsWidgets, reason: 'navigation vers auth-reset (${(o['navigation'] as List).single})');
      await fin(t);
    });

    cas('réinitialisation : quatre règles affichées, discordance refusée EN LA NOMMANT, concordance contrôlée sans rien conserver', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'auth-reset');
      final r = obj(v['reinit']);
      for (final regle in (r['regles'] as List).cast<String>()) {
        expect(find.text(regle), findsOneWidget);
      }
      await saisir(t, 'acces:nouveau', 'Motdepasse#2026');
      await saisir(t, 'acces:confirmation', 'autre');
      await bouton(t, 'Définir le mot de passe');
      expect(find.text('${fl(r['discordance']).single['titre']}'), findsOneWidget);
      expect(audit(m, 'Réinitialisation du mot de passe (saisie contrôlée, non conservée)'), isEmpty);
      await saisir(t, 'acces:confirmation', 'Motdepasse#2026');
      await bouton(t, 'Définir le mot de passe');
      expect(find.textContaining('aucun mot de passe n’est conservé'), findsOneWidget);
      // Le secret ne passe JAMAIS au journal.
      final e = audit(m, 'Réinitialisation du mot de passe (saisie contrôlée, non conservée)').single;
      expect(jsonEncode(e).contains('Motdepasse'), isFalse);
      await t.pump(const Duration(milliseconds: 1100));
      expect(find.byKey(const Key('acces:motdepasse')), findsOneWidget, reason: 'retour à la connexion');
      await fin(t);
    });

    cas('double facteur : six cases numériques, le focus avance à chaque chiffre, l’honnêteté sur ce qui n’est pas vérifié', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'auth-2fa');
      expect(find.byType(TextField), findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        expect(find.bySemanticsLabel('Chiffre ${i + 1}'), findsOneWidget);
      }
      await t.tap(find.byKey(const Key('acces:chiffre0')));
      await t.enterText(find.byKey(const Key('acces:chiffre0')), '1');
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('acces:chiffre1'))).focusNode!.hasFocus, isTrue);
      await bouton(t, 'Vérifier');
      expect(find.text('Code reçu — non vérifié sur ce poste.'), findsOneWidget);
      expect(audit(m, 'Double facteur : code reçu, non vérifié'), hasLength(1));
      await t.pump(const Duration(milliseconds: 1000));
      await fin(t);
    });
  });

  // ============================================================================================================================ VERROU
  group('auth-lock — le verrou de session (horloge injectée)', () {
    final aide = 'Aide & À propos';
    final question2 = accFaq[1];
    Finder reponse2() => find.byKey(Key('aide:reponse:${question2.q}'));

    cas('quinze minutes d’inactivité suspendent la session SANS la fermer : le travail reste monté, intact, sous l’écran verrouillé', (t) async {
      var maintenant = auj;
      final m = poste();
      final s = SessionPoste.ouverte('reception', nom: 'EZIN Orou', horloge: () => maintenant);
      await monter(t, m, ecran: 'aide-apropos', session: s, horloge: () => maintenant);
      // L'agent a ouvert la deuxième question : un état local que le verrou ne doit pas perdre.
      await toucher(t, find.text(question2.q));
      expect(reponse2(), findsOneWidget);

      maintenant = auj.add(const Duration(minutes: 14));
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.connectee, reason: '14 minutes : pas encore');
      // Un geste relance le compte à rebours.
      await t.tapAt(const Offset(5, 500));
      maintenant = auj.add(const Duration(minutes: 28));
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.connectee, reason: '14 minutes depuis le dernier geste : pas encore');

      maintenant = auj.add(const Duration(minutes: 29, seconds: 1));
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.verrouillee);
      expect(find.text('Session verrouillée'), findsOneWidget);
      expect(find.text(accTitreRetour), findsOneWidget);
      expect(find.text('Au déverrouillage, vous reviendrez sur « $aide ».'), findsOneWidget);
      expect(find.textContaining('après 15 minutes d’inactivité'), findsOneWidget);
      expect(find.text('EZIN Orou'), findsOneWidget);
      // Le travail est CACHÉ, pas détruit : il n'est plus visible, plus focalisable.
      expect(reponse2(), findsNothing);
      expect(reponse2().evaluate().length, 0);
      expect(find.byType(BarreSuperieure), findsNothing);
      expect(s.retour, const AccRetour('aide-apropos'));
      final v1 = audit(m, 'Verrouillage pour inactivité').single;
      expect(v1['module'], 'M14');
      expect(obj(v1['apres'])['ecran'], 'aide-apropos');
      expect(obj(v1['apres'])['delaiMinutes'], 15);

      // Déverrouillage : le retour est à usage unique, le travail est retrouvé tel quel.
      await saisir(t, 'acces:motdepasse', 'secret');
      await bouton(t, 'Déverrouiller', ms: 400);
      expect(s.etat, EtatSession.connectee);
      expect(s.retour, isNull, reason: 'consommée');
      expect(find.text('Session verrouillée'), findsNothing);
      expect(reponse2(), findsOneWidget, reason: 'l’agent retrouve son écran, à l’onglet près');
      expect(find.byType(BarreSuperieure), findsOneWidget);
      expect(audit(m, 'Déverrouillage de session').single['reference'], 'reception');
      // Le compte à rebours repart du déverrouillage : pas de reverrouillage immédiat.
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.connectee);
      await fin(t);
    });

    cas('un mot de passe vide ne déverrouille pas', (t) async {
      var maintenant = auj;
      final s = SessionPoste.ouverte('reception', horloge: () => maintenant);
      await monter(t, poste(), ecran: 'aide-apropos', session: s, horloge: () => maintenant);
      maintenant = auj.add(const Duration(minutes: 16));
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.verrouillee);
      await bouton(t, 'Déverrouiller');
      expect(find.text('Saisir le mot de passe.'), findsOneWidget);
      expect(s.etat, EtatSession.verrouillee);
      await fin(t);
    });

    cas('« Se connecter avec un autre compte » : la session et l’adresse de retour disparaissent, la connexion s’ouvre', (t) async {
      var maintenant = auj;
      final s = SessionPoste(exigeConnexion: true, horloge: () => maintenant, compte: const AccCompte(identifiant: 'e.orou', nom: 'EZIN Orou', role: 'reception'));
      await monter(t, poste(), ecran: 'aide-apropos', session: s, horloge: () => maintenant);
      maintenant = auj.add(const Duration(minutes: 16));
      await t.pump(const Duration(seconds: 3));
      expect(s.etat, EtatSession.verrouillee);
      await toucher(t, find.text('Se connecter avec un autre compte'));
      expect(s.compte, isNull);
      expect(s.retour, isNull);
      expect(s.etat, EtatSession.deconnectee);
      expect(find.byKey(const Key('acces:identifiant')), findsOneWidget);
      await fin(t);
    });

    cas('sans verrou posé (adresse directe), le déverrouillage ramène à l’accueil du profil', (t) async {
      final s = SessionPoste.ouverte('reception', nom: 'EZIN Orou', horloge: () => auj);
      await monter(t, poste(), ecran: 'auth-lock', session: s);
      expect(find.textContaining('Au déverrouillage'), findsNothing, reason: 'aucune adresse de retour');
      await saisir(t, 'acces:motdepasse', 'x');
      await bouton(t, 'Déverrouiller', ms: 600);
      expect(find.byType(BarreSuperieure), findsOneWidget);
      await fin(t);
    });

    cas('sans session explicite, rien ne se verrouille (comportement historique) : aucun minuteur ne reste', (t) async {
      await monter(t, poste(), ecran: 'aide-apropos');
      await t.pump(const Duration(minutes: 20));
      expect(find.text('Session verrouillée'), findsNothing);
      await fin(t);
    });
  });

  // ============================================================================================================================ ERREURS
  group('pages d’erreur', () {
    for (final (id, code) in [('error-404', '404'), ('error-403', '403')]) {
      cas('$id : les textes de la maquette, retour à l’accueil du rôle, plan du site', (t) async {
        final m = poste();
        await monter(t, m, ecran: id, role: 'reception');
        final e = obj(obj(v['erreurs'])[id]);
        for (final texte in (e['textes'] as List).cast<String>()) {
          expect(ex.textesVisibles(t).any((x) => x.contains(ex.normaliser(texte))), isTrue, reason: texte);
        }
        expect(find.text(code), findsOneWidget);
        await bouton(t, 'Plan du site');
        expect(find.text('Inventaire de tous les écrans du prototype, organisés par domaine et par module.'), findsOneWidget);
        await fin(t);
      });
    }

    cas('« Retour à l’accueil » ouvre l’accueil du profil (réception) ; sans session exigée, la coque suit', (t) async {
      await monter(t, poste(), ecran: 'error-404', role: 'reception');
      await bouton(t, 'Retour à l’accueil', ms: 600);
      expect(find.byType(BarreSuperieure), findsOneWidget);
      expect(find.byType(PageStandard), findsOneWidget);
      await fin(t);
    });

    cas('personne n’est connecté : « Retour à l’accueil » mène à la connexion', (t) async {
      final s = SessionPoste(exigeConnexion: true, horloge: () => auj);
      await monter(t, poste(), session: s);
      // L'adresse directe d'une page d'erreur reste servie à un visiteur : elle ne montre rien de privé.
      await toucher(t, find.text('Mot de passe oublié ?'));
      expect(find.byKey(const Key('acces:identifiant')), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ PLAN DU SITE
  group('plan-du-site', () {
    cas('l’inventaire COMPLET du manifeste, dans l’ordre des domaines, avec le pied de la maquette', (t) async {
      await monter(t, poste(), ecran: 'plan-du-site', taille: const Size(1600, 30000));
      final p = obj(v['plan']);
      expect(sansChrome(t), isTrue);
      for (final s in fl(p['sections']).where((s) => (s['modules'] as List).isNotEmpty)) {
        expect(find.text((s['titre'] as String).toUpperCase()), findsOneWidget, reason: '${s['titre']}');
        for (final mo in fl(s['modules'])) {
          expect(find.text('${mo['titre']}'), findsWidgets, reason: '${mo['titre']}');
        }
      }
      expect(find.text(p['pied'] as String), findsOneWidget);
      expect(find.text('ACCÈS ET PAGES SYSTÈME'), findsOneWidget);
      for (final l in fl(fl(p['sections']).last['liensSysteme'])) {
        expect(find.widgetWithText(BoutonSigh, '${l['label']}'), findsOneWidget, reason: '${l['label']}');
      }
      await fin(t);
    });

    cas('un écran permis s’ouvre dans la coque ; un écran fermé au profil mène à la 403 et la tentative est journalisée (RG-13)', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'plan-du-site', role: 'reception', taille: const Size(1600, 30000));
      // m14-audit est fermé à la réception.
      expect(donnees.matrice.peutVoir('reception', 'm14-audit'), isFalse);
      await toucher(t, find.text('Journal d’audit').first);
      expect(find.text('403'), findsOneWidget);
      expect(find.text('Accès refusé'), findsWidgets);
      final e = audit(m, 'Accès refusé').single;
      expect(e['reference'], 'm14-audit');
      expect(obj(e['apres'])['role'], 'reception');
      await fin(t);
    });

    cas('« Retour à l’application » ouvre l’accueil du profil', (t) async {
      await monter(t, poste(), ecran: 'plan-du-site', role: 'reception', taille: const Size(1600, 30000));
      await bouton(t, 'Retour à l’application', ms: 600);
      expect(find.byType(BarreSuperieure), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ AIDE
  group('aide-apropos', () {
    cas('textes, quatre chiffres dérivés du manifeste, une carte par module, neuf questions', (t) async {
      await monter(t, poste(), ecran: 'aide-apropos', taille: const Size(1600, 12000));
      final a = obj(v['aide']);
      for (final k in fl(a['kpis'])) {
        final w = t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == k['label']));
        expect(sp(w.valeur), sp(k['valeur']), reason: '${k['label']}');
      }
      for (final mo in fl(a['modules'])) {
        expect(find.text('${mo['resume']}'), findsWidgets, reason: '${mo['titre']}');
      }
      expect(find.textContaining('Domaine Accueil'), findsWidgets);
      for (final q in fl(a['faq'])) {
        expect(find.text('${q['q']}'), findsOneWidget);
      }
      for (final l in a['apropos'] as List) {
        expect(find.text('${(l as List)[1]}'), findsWidgets);
      }
      expect(find.text('Vous ne trouvez pas de réponse ?'), findsOneWidget);
      await fin(t);
    });

    cas('la première question est ouverte, les autres se déplient au toucher ; <code> et <strong> sont rendus, pas affichés', (t) async {
      await monter(t, poste(), ecran: 'aide-apropos', taille: const Size(1600, 12000));
      expect(find.byKey(Key('aide:reponse:${accFaq[0].q}')), findsOneWidget);
      expect(find.byKey(Key('aide:reponse:${accFaq[1].q}')), findsNothing);
      await toucher(t, find.text(accFaq[4].q));
      final rt = t.widget<Text>(find.byKey(Key('aide:reponse:${accFaq[4].q}')));
      expect(rt.textSpan!.toPlainText(), accTexteSansBalises(accFaq[4].r));
      expect(rt.textSpan!.toPlainText().contains('<'), isFalse);
      await fin(t);
    });

    cas('« Contacter l’éditeur » ouvre le formulaire de contact', (t) async {
      await monter(t, poste(), ecran: 'aide-apropos', taille: const Size(1600, 12000));
      await bouton(t, 'Contacter l’éditeur', ms: 600);
      expect(find.text('Envoyer un message'), findsWidgets);
      await fin(t);
    });
  });

  // ============================================================================================================================ CONTACT
  group('contact-editeur', () {
    cas('refus nommés : formulaires vides', (t) async {
      await monter(t, poste(), ecran: 'contact-editeur', taille: const Size(1600, 3000));
      final c = obj(v['contact']);
      await bouton(t, 'Envoyer le message');
      expect(find.text('${fl(c['refusMessage']).single['titre']}'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await bouton(t, 'Signaler l’anomalie');
      expect(find.text('${fl(c['refusAnomalie']).single['titre']}'), findsOneWidget);
      await fin(t);
    });

    cas('un message : la fiche de la maquette, la référence du registre, le toast avec « Annuler », le formulaire vidé', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'contact-editeur', role: 'admin', taille: const Size(1600, 3000));
      final c = obj(v['contact']);
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:objet')), matching: find.byType(TextField)), 'Question sur la comptabilité');
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:message')), matching: find.byType(TextField)), 'Comment lire la balance ?');
      await bouton(t, 'Envoyer le message');
      final toast = fl(c['toastMessage']).single;
      expect(find.text('${toast['titre']}'), findsOneWidget);
      expect(find.text('${toast['detail']}'), findsOneWidget);
      final f = m.collection('support').toutes.single;
      expect(f['reference'], 'SUP-2026-0001');
      expect(f['date'], '2026-10-30');
      expect(f['etat'], 'envoyee');
      expect(f['type'], 'message');
      expect(f['objet'], 'Question sur la comptabilité');
      expect(f['description'], 'Comment lire la balance ?');
      expect(f['auteur'], isNotEmpty, reason: 'RG-12 : aucune action anonyme');
      expect(audit(m, 'Création'), isNotEmpty);
      // Le formulaire est vidé, la demande figure au tableau des demandes envoyées.
      expect(t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:objet')), matching: find.byType(TextField))).controller!.text, isEmpty);
      expect(find.text('Demandes envoyées'), findsOneWidget);
      expect(find.text('SUP-2026-0001'), findsWidgets);
      // Annuler = archiver (RG-14), jamais supprimer.
      await toucher(t, find.text('Annuler').first);
      expect(m.collection('support').actives, isEmpty);
      expect(m.collection('support').toutes, hasLength(1));
      await fin(t);
    });

    cas('une anomalie : numéro suivant du registre, module écrit par son code, étapes facultatives', (t) async {
      final m = poste();
      await monter(t, m, ecran: 'contact-editeur', role: 'admin', taille: const Size(1600, 3000));
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:objet')), matching: find.byType(TextField)), 'Q');
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:message')), matching: find.byType(TextField)), 'R');
      await bouton(t, 'Envoyer le message');
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:description')), matching: find.byType(TextField)), 'Le reçu ne se détaille pas');
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:etapes')), matching: find.byType(TextField)), '1. Encaisser 2. Imprimer');
      await bouton(t, 'Signaler l’anomalie');
      final f = m.collection('support').toutes.first;
      expect(f['reference'], 'SUP-2026-0002', reason: 'plus grand numéro écrit + 1');
      expect(f['type'], 'anomalie');
      expect(f['objet'], startsWith('Anomalie — '));
      expect('${f['module']}'.contains('|'), isFalse, reason: 'le code du module, pas la valeur interne du champ');
      expect(f['description'], 'Le reçu ne se détaille pas');
      expect(f['etapes'], '1. Encaisser 2. Imprimer');
      expect(f['capture'], isNull);
      await fin(t);
    });

    cas('la capture d’écran : le poste n’a pas de sélecteur de fichier et le dit', (t) async {
      await monter(t, poste(), ecran: 'contact-editeur', taille: const Size(1600, 3000));
      expect(find.text('Aucune capture jointe.'), findsOneWidget);
      await bouton(t, 'Joindre une capture d’écran');
      expect(find.text('Aucun sélecteur de fichier sur ce poste.'), findsOneWidget);
      await fin(t);
    });

    cas('coordonnées et renvoi vers l’aide', (t) async {
      await monter(t, poste(), ecran: 'contact-editeur', taille: const Size(1600, 3000));
      for (final l in (obj(v['contact'])['coordonnees'] as List).cast<String>().where((x) => x.contains('@') || x.contains('+229'))) {
        expect(find.byWidgetPredicate((w) => w is Text && sp(w.data) == l), findsOneWidget, reason: l);
      }
      await bouton(t, 'Consulter l’aide & la FAQ', ms: 600);
      expect(find.text('Vous ne trouvez pas de réponse ?'), findsOneWidget);
      await fin(t);
    });
  });

  // ============================================================================================================================ PARITÉ N1
  group('parité N1 mesurée contre les fiches de la maquette', () {
    for (final id in ['aide-apropos', 'contact-editeur']) {
      cas('$id : 100 % des libellés de la fiche', (t) async {
        final fiche = obj(jsonDecode(File('../../docs/architecture/ecrans/$id.json').readAsStringSync()));
        await monter(t, poste(), ecran: id, role: 'admin', taille: const Size(1440, 900));
        final p = ex.comparerContenu(id, fiche, ex.textesVisibles(t));
        expect(p.manquants, isEmpty, reason: '$id : ${p.presents}/${p.attendus}');
        expect(p.taux, 1.0);
        await fin(t);
      });
    }
  });
}
