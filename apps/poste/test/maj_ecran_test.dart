import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/liaison_maj.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT MAJ, écran « Mettre à jour le logiciel » (`m14-mise-a-jour`) : mère et fileul. Les commandes sont ABSENTES sans le geste `lancer_mise_a_jour` ; le moteur refuse aussi ; le refus se nomme ;
/// l'avertissement `IMPORT_PLUS_ANCIEN_QUE_SYNC` s'affiche avec les saisies listées, sans bloquer.
final cle = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);

/// Les opérations du service lancées par un bouton tournent dans la zone du test : chaque entrée-sortie demande un tour réel PUIS une image. On attend donc une CONDITION.
Future<void> attendre(WidgetTester t, {int tours = 8, bool Function()? jusqua}) async {
  if (jusqua == null) {
    for (var i = 0; i < tours; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 20));
    }
    return;
  }
  for (var i = 0; i < 700 && !jusqua(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 10));
  }
  if (!jusqua()) fail('condition jamais atteinte (${StackTrace.current.toString().split('\n')[1]})');
}

bool Function() texte(String morceau) => () => find.textContaining(morceau).evaluate().isNotEmpty;

DonneesNavigation sansGeste() {
  final brut = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final gestes = (brut['gestes'] as Map).cast<String, Object?>();
  final parRole = (gestes['parRole'] as Map).cast<String, Object?>();
  for (final r in parRole.keys) {
    (parRole[r] as Map)[majGeste] = 0;
  }
  return DonneesNavigation(manifeste: donneesNav.manifeste, matrice: MatriceDroits.depuisJson(brut), parite: const {});
}

void main() {
  setUpAll(chargerPolices);
  late Directory tmp;
  late String d;
  late ServiceMiseAJour svc;
  var redemarre = 0;
  var rejoue = 0;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('maj-ecran-');
    d = '${tmp.path}/donnees';
    final p = PersistanceFichiers(d, cle: cle);
    await p.ecrire('patients', [for (var i = 0; i < 5; i++) {'id': 'p$i', 'nom': 'P$i', 'tel': i == 0 ? null : '9$i'}]);
    svc = ServiceMiseAJour(dossier: d, cle: cle);
    LiaisonMaj.service = svc;
    redemarre = 0;
    rejoue = 0;
    LiaisonMaj.redemarrer = () async => redemarre++;
    LiaisonMaj.rejouerJournal = () => rejoue++;
  });
  tearDown(() {
    LiaisonMaj.reinitialiser();
    ToastsSigh.viderPourTests();
    tmp.deleteSync(recursive: true);
  });

  const commandes = ['Préparer la mise à jour', 'Essai à blanc', 'Migrer les données', 'Annuler la mise à jour', 'Exporter la base', 'Importer une base'];
  Finder bouton(String l) => find.widgetWithText(BoutonSigh, l);

  casM14('avec le geste : les six commandes, la migration refuse sans copie (nommé), préparer puis migrer donne « N avant, N après » et demande le redémarrage', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour');
    await attendre(t, jusqua: texte('migration(s) à passer'));
    for (final l in commandes) {
      expect(bouton(l), findsOneWidget, reason: l);
    }
    expect(find.textContaining('migration(s) à passer'), findsOneWidget);
    await toucherM14(t, bouton('Migrer les données'));
    await attendre(t, jusqua: texte('Geste :'));
    expect(find.textContaining('MAJ_SANS_SAUVEGARDE : Aucune copie vérifiée'), findsOneWidget);
    expect(find.textContaining('Geste :'), findsOneWidget);
    await toucherM14(t, bouton('Préparer la mise à jour'));
    await attendre(t, jusqua: texte('fiches relues'));
    expect(find.textContaining('fiches relues à l’identique'), findsOneWidget);
    await attendre(t, jusqua: () => find.text('Aucune').evaluate().isEmpty);
    expect(find.text('Aucune'), findsNothing, reason: 'une copie vérifiée existe');
    await toucherM14(t, bouton('Essai à blanc'));
    await attendre(t, jusqua: texte('Essai à blanc de la migration'));
    await attendre(t, jusqua: () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    expect(find.textContaining('1 champ(s) nul(s) retiré(s)'), findsOneWidget);
    await toucherM14(t, bouton('Migrer les données'));
    await attendre(t, jusqua: texte('redémarrez le poste'));
    expect(find.text('Migration des données'), findsOneWidget);
    expect(find.textContaining('5 fiches avant, 5 après'), findsWidgets);
    expect(find.textContaining('Geste :'), findsNothing, reason: 'le refus précédent est levé');
    expect(find.textContaining('redémarrez le poste'), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('maj:redemarrer')));
    expect(redemarre, 1);
    expect(await t.runAsync(() => svc.formatDonnees()), formatDonneesCourant);
  });

  casM14('SANS le geste : aucune commande (absentes, pas grisées), lecture seule dite ; le moteur refuse aussi', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour', donnees: sansGeste());
    await attendre(t, jusqua: texte('migration(s) à passer'));
    for (final l in commandes) {
      expect(bouton(l), findsNothing, reason: '$l doit être ABSENTE');
    }
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await t.runAsync(() async {
      await svc.preparer();
      try {
        await svc.migrer(geste: false);
        fail('refus attendu');
      } on RefusMajException catch (e) {
        expect(e.code, CodeMaj.geste);
      }
    });
  });

  casM14('fileul rattaché : importer une base plus ancienne que la dernière synchro affiche l’avertissement non bloquant et les saisies listées, puis rejoue le journal', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour');
    LiaisonMaj.fileulRattache = () => true;
    LiaisonMaj.derniereSynchro = () => DateTime.now().add(const Duration(hours: 1));
    late String export;
    await t.runAsync(() async {
      export = await svc.exporter('${tmp.path}/e.sighexp');
      final p = PersistanceFichiers(d, cle: cle);
      final pat = (await p.lireTout())['patients']!;
      await p.ecrire('patients', [...pat, {'id': 'hors-ligne', 'nom': 'Saisie de ce fileul'}]);
      await svc.preparer();
    });
    LiaisonMaj.choisirExport = () async => export;
    await attendre(t, tours: 3);
    await toucherM14(t, bouton('Importer une base'));
    await attendre(t, jusqua: texte('patients / hors-ligne : créée'));
    expect(find.textContaining('IMPORT_PLUS_ANCIEN_QUE_SYNC : cette base date'), findsOneWidget, reason: 'l’avertissement de la modale (la carte du parcours le nomme aussi)');
    expect(find.textContaining('patients / hors-ligne : créée'), findsOneWidget);
    expect(find.textContaining('gardées dans la copie d’avant l’import'), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('maj:import-confirmer')));
    await attendre(t, jusqua: texte('redémarrez le poste'));
    expect(rejoue, 1);
    expect(find.textContaining('redémarrez le poste'), findsOneWidget);
    final apres = await t.runAsync(() => PersistanceFichiers(d, cle: cle).lireTout());
    expect(apres!['patients']!.any((f) => f['id'] == 'hors-ligne'), isFalse);
  });

  casM14('import refusé : le motif est nommé à l’écran, rien n’est remplacé (autre clinique)', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour');
    final autre = List<int>.generate(32, (i) => (i * 5 + 1) & 0xff);
    late String export;
    await t.runAsync(() async {
      final d2 = '${tmp.path}/autre/donnees';
      await PersistanceFichiers(d2, cle: autre).ecrire('patients', [{'id': 'x'}]);
      export = await ServiceMiseAJour(dossier: d2, cle: autre).exporter('${tmp.path}/autre.sighexp');
    });
    LiaisonMaj.choisirExport = () async => export;
    await toucherM14(t, bouton('Importer une base'));
    await attendre(t, jusqua: texte('Geste :'));
    expect(find.textContaining('IMPORT_AUTRE_CLINIQUE : L’export vient d’une autre clinique'), findsOneWidget);
    expect(find.byKey(const Key('maj:import-confirmer')), findsNothing);
  });

  casM14('retour arrière : la liste des saisies postérieures est montrée avant, la saisie reste dans la copie rangée', (t) async {
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour');
    await t.runAsync(() async {
      await svc.preparer();
      final p = PersistanceFichiers(d, cle: cle);
      final pat = (await p.lireTout())['patients']!;
      await p.ecrire('patients', [...pat, {'id': 'tardif', 'nom': 'Après la copie'}]);
    });
    await toucherM14(t, bouton('Annuler la mise à jour'));
    await attendre(t, jusqua: texte('patients / tardif : créée'));
    expect(find.textContaining('patients / tardif : créée'), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('maj:retour-confirmer')));
    await attendre(t, jusqua: texte('redémarrez le poste'));
    expect(find.textContaining('redémarrez le poste'), findsOneWidget);
    final apres = await t.runAsync(() => PersistanceFichiers(d, cle: cle).lireTout());
    expect(apres!['patients']!.any((f) => f['id'] == 'tardif'), isFalse);
  });

  casM14('poste sans chiffrement : l’écran le dit, aucune commande', (t) async {
    LiaisonMaj.service = null;
    await ouvrirM14(t, magasinM14(), 'm14-mise-a-jour');
    expect(find.textContaining('Mise à jour indisponible'), findsOneWidget);
    for (final l in commandes) {
      expect(bouton(l), findsNothing, reason: l);
    }
  });
}
