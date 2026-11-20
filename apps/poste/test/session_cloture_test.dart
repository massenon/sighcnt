import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_registre_sessions.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/shell/barre_superieure.dart';

import 'aide_polices.dart';

/// LA CLOTURE D'UNE SESSION, DE BOUT EN BOUT AU POSTE (retour de la Direction du 01/11/2026) : l'agent se connecte (une fiche de session naît), l'administrateur
/// clôture sa session au registre, et AU PROCHAIN GESTE le poste retombe sur la connexion, qui le DIT. Une session clôturée ne se rouvre pas : se reconnecter en
/// ouvre une AUTRE. Un compte bloqué n'ouvre pas de session. Les règles sont rejouées sur les vecteurs de la maquette par packages/domaine/test.
typedef M = Map<String, Object?>;
List<M> fl(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
List<M> jeu(String nom) => fl(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30, 10);
const secret = 'Clinique#Natitingou26';

Magasin poste() => Magasin({
      'audit': const <M>[],
      'utilisateurs': [for (final u in jeu('utilisateurs')) {...u}],
      'rbac': [for (final r in jeu('rbac')) {...r}],
      'tentativesConnexion': const <M>[],
      'personnel': jeu('personnel'),
      'soignants': jeu('soignants'),
      'rolesBase': jeu('rolesBase'),
      'support': const <M>[],
    }, 'POSTE');

Future<void> monter(WidgetTester t, Magasin m, SessionPoste s, {DateTime Function()? horloge}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'reception'),
      magasin: m,
      session: s,
      horloge: horloge ?? () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> calculer(WidgetTester t, {int ms = 500}) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(Duration(milliseconds: ms));
}

Future<void> saisir(WidgetTester t, String cle, String texte) async {
  await t.enterText(find.byKey(Key(cle)), texte);
  await t.pump();
}

Future<void> connecter(WidgetTester t, String identifiant) async {
  await saisir(t, 'acces:identifiant', identifiant);
  await saisir(t, 'acces:motdepasse', secret);
  await t.tap(find.widgetWithText(BoutonSigh, 'Se connecter').first);
  await t.pump(const Duration(milliseconds: 600));
  await calculer(t, ms: 600);
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
  });
  tearDown(ToastsSigh.viderPourTests);

  const admin = SecActeurSession(role: 'admin', identifiant: 'c.bassongui', nom: 'BASSONGUI Chabi Séko');

  testWidgets('connexion : une fiche de session naît ; l\'administrateur la clôture ; au PROCHAIN GESTE le poste retombe sur la connexion qui le dit ; se reconnecter ouvre une AUTRE session',
      (t) async {
    final m = poste();
    var maintenant = auj;
    final s = SessionPoste(exigeConnexion: true, horloge: () => maintenant);
    final compte = jeu('utilisateurs').firstWhere((u) => u['identifiant'] == 'e.orou');
    await t.runAsync(() => ServiceIdentifiants.de(m).definir('${compte['id']}', secret, par: 'test', doitChanger: false, maintenant: auj));
    await monter(t, m, s, horloge: () => maintenant);
    await connecter(t, 'e.orou');
    expect(s.etat, EtatSession.connectee);
    // À la connexion, le centre de notifications s'ouvre de lui-même : l'agent le referme (premier geste).
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 400));
    expect(s.etat, EtatSession.connectee);
    // Une fiche de session nominative, active, avec le poste de travail.
    final reg = RegistreSessions.de(m);
    final premiere = s.sessionId!;
    final f = reg.fiche(premiere)!;
    expect(f['etat'], 'active');
    expect(f['identifiant'], 'e.orou');
    expect(f['source'], 'poste');
    expect(f['role'], compte['role']);
    expect(find.byType(BarreSuperieure), findsOneWidget);

    // L'administrateur (de ce poste ou d'un autre) clôture la session au registre.
    final r = reg.cloturer(premiere, acteur: admin, droitEditer: true, maintenant: auj, motif: 'Poste laissé ouvert');
    expect(r.ok, isTrue);
    expect(reg.fiche(premiere)!['etat'], 'cloturee');
    // Tant que l'agent ne fait rien, rien ne change à l'écran ; au PROCHAIN GESTE, le poste se ferme.
    expect(s.etat, EtatSession.connectee);
    maintenant = auj.add(const Duration(seconds: 2));
    await t.tapAt(const Offset(800, 500));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.etat, EtatSession.deconnectee, reason: 'la session clôturée ferme le poste');
    expect(s.motifFermeture, 'cloturee');
    expect(s.sessionId, isNull);
    expect(find.byKey(const Key('acces:identifiant')), findsOneWidget, reason: 'la connexion reprend la main');
    expect(find.text(accMessageSessionCloturee), findsOneWidget, reason: 'et elle dit pourquoi');
    expect(find.byType(BarreSuperieure), findsNothing);
    // La fiche clôturée reste au registre : date, heure, auteur, motif (RG-12, RG-14).
    final cl = reg.fiche(premiere)!;
    expect(cl['clotureLe'], isNotNull);
    expect(cl['cloturePar'], 'BASSONGUI Chabi Séko');
    expect(cl['clotureMotif'], 'Poste laissé ouvert');
    expect(cl['statut'], isNot('archive'), reason: 'rien n\'est archivé ni supprimé (RG-14)');

    // Se reconnecter ouvre une AUTRE session ; l'ancienne ne rouvre pas.
    maintenant = auj.add(const Duration(seconds: 4));
    await connecter(t, 'e.orou');
    expect(s.etat, EtatSession.connectee);
    expect(s.sessionId, isNot(premiere));
    expect(reg.fiche(premiere)!['etat'], 'cloturee');
    expect(reg.fiche(s.sessionId!)!['etat'], 'active');
    expect(s.motifFermeture, isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  test('le verrou suspend la fiche de la session et la reprend ; une session clôturée pendant le verrouillage ne se reprend pas', () {
    final m = poste();
    var maintenant = auj;
    final s = SessionPoste(exigeConnexion: true, horloge: () => maintenant);
    final reg = RegistreSessions.de(m);
    s.connecter(const AccCompte(identifiant: 'e.orou', nom: 'OROU YO Edmond', role: 'reception'));
    s.sessionId = reg.ouvrir(identifiant: 'e.orou', nomComplet: 'OROU YO Edmond', role: 'reception', poste: 'POSTE-ACCUEIL', maintenant: auj);
    s.estCloturee = reg.estCloturee;
    s.surEtat = (i, e) => reg.changerEtat(i, e, maintenant);
    final id = s.sessionId!;
    maintenant = auj.add(const Duration(minutes: 16));
    expect(s.verifier('m2-agenda'), isTrue);
    expect(reg.fiche(id)!['etat'], 'suspendue', reason: 'le verrou suspend la fiche');
    expect(s.deverrouiller(), isNotNull);
    expect(reg.fiche(id)!['etat'], 'active', reason: 'le déverrouillage la reprend');
    // Verrouillée, puis clôturée par l'administrateur : le déverrouillage ne rouvre rien, la session se ferme.
    s.verrouillerMaintenant('m2-agenda');
    expect(reg.fiche(id)!['etat'], 'suspendue');
    expect(reg.cloturer(id, acteur: admin, droitEditer: true, maintenant: maintenant).ok, isTrue);
    expect(s.deverrouiller(), isNull);
    expect(s.etat, EtatSession.deconnectee);
    expect(s.motifFermeture, 'cloturee');
    expect(reg.fiche(id)!['etat'], 'cloturee', reason: 'le déverrouillage n\'a pas rouvert la fiche');
  });

  test('un geste qui ne se contrôle qu\'une fois par demi-seconde : le contrôle n\'écrase pas la boucle d\'événements', () {
    final m = poste();
    var maintenant = auj;
    var appels = 0;
    final s = SessionPoste(exigeConnexion: true, horloge: () => maintenant);
    s.connecter(const AccCompte(identifiant: 'e.orou', nom: 'OROU YO Edmond', role: 'reception'));
    s.sessionId = 'X';
    s.estCloturee = (_) {
      appels++;
      return false;
    };
    for (var i = 0; i < 50; i++) {
      s.activite();
    }
    expect(appels, 1, reason: 'cinquante gestes dans la même milliseconde ne relisent le registre qu\'une fois');
    maintenant = auj.add(const Duration(milliseconds: 600));
    s.activite();
    expect(appels, 2);
    expect(m.collection('sessionsUtilisateur').toutes, isEmpty);
  });

  test('un compte BLOQUÉ par l\'administrateur n\'ouvre pas de session, même avec le bon mot de passe ; débloqué, il l\'ouvre', () async {
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
    final m = poste();
    final compte = jeu('utilisateurs').firstWhere((u) => u['identifiant'] == 'e.orou');
    final id = '${compte['id']}';
    await ServiceIdentifiants.de(m).definir(id, secret, par: 'test', doitChanger: false, maintenant: auj);
    Future<ResultatConnexion> essayer() => ServiceIdentifiants.de(m).verifier(
        identifiant: 'e.orou', motDePasse: secret, rolesArchives: const {}, libelleRole: (r) => r, maintenant: auj);
    expect((await essayer()).decision.accepte, isTrue);

    final bloc = secBloquerCompte(m.collection('utilisateurs').parId(id),
        motif: 'Accès à retirer',
        acteur: const SecActeurCompte(identifiant: 'c.bassongui', nom: 'BASSONGUI Chabi Séko'),
        politique: secPolitique(null),
        maintenant: auj);
    expect(bloc.ok, isTrue);
    m.collection('utilisateurs').mettreAJour(id, bloc.patch);
    final refus = await essayer();
    expect(refus.decision.accepte, isFalse);
    expect(refus.decision.issue, AccIssue.compteBloque);
    expect(refus.decision.message, accMessageCompteBloque);
    expect(m.collection('tentativesConnexion').toutes.last['motif'], accMotifCompteBloque, reason: 'la tentative est écrite (RG-12)');

    final deb = secDebloquerCompte(m.collection('utilisateurs').parId(id),
        acteur: const SecActeurCompte(identifiant: 'c.bassongui', nom: 'BASSONGUI Chabi Séko'), politique: secPolitique(null), maintenant: auj);
    m.collection('utilisateurs').mettreAJour(id, deb.patch);
    expect((await essayer()).decision.accepte, isTrue);
  });
}
