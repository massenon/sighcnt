import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));

/// cfg-rappels : les règles (aperçu, anniversaires) sont rejouées sur les vecteurs de la maquette (packages/domaine/test/cfa_regles_test.dart) ; ici,
/// l'ÉCRAN — le logiciel PRÉPARE, il n'envoie pas ; un rappel n'est jamais doublé ; le refus nommé sans modèle actif ; les droits.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final r = obj(v['rappels']);

  Future<void> onglet(WidgetTester t, String id) => toucherM14(t, find.byKey(Key('kit:onglet:$id')));

  casM14('ouverture : quatre indicateurs, la note « il n’envoie pas », trois onglets, les six modèles proposés', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-rappels');
    for (final k in (r['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsWidgets, reason: '${k[0]}');
    }
    expect(find.text('le logiciel prépare, il n’envoie pas'), findsOneWidget);
    expect(find.textContaining('Prétendre l’envoi serait mentir sur ce qui se passe'), findsOneWidget);
    for (final o in ['Modèles de message', 'Rappels préparés', 'Variables']) {
      expect(find.text(o), findsWidgets, reason: o);
    }
    for (final h in obj(r['modeles'])['entetes'] as List) {
      expect(find.text('$h'.toUpperCase()), findsWidgets, reason: '$h');
    }
    for (final l in (obj(r['modeles'])['lignes'] as List).cast<List>()) {
      expect(find.text('${l[0]}'), findsWidgets, reason: '${l[0]}');
    }
  });

  casM14('amorçage : sans modèle au magasin, les six modèles proposés naissent (à valider par la Direction)', (t) async {
    final m = Magasin.depuisDossier([for (final n in Magasin.collectionsDuJeu) if (n != 'modelesMessage') n], 'test/fixtures/jeu_sobre');
    await ouvrirM14(t, m, 'cfg-rappels');
    expect(m.collection('modelesMessage').actives.length, 6);
    expect(m.collection('modelesMessage').actives.every((x) => x['source'] == 'Modèle proposé — à valider par la Direction'), isTrue);
  });

  casM14('onglet Variables : cinq jetons, un jeton inconnu reste visible', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-rappels');
    await onglet(t, 'variables');
    for (final l in (obj(liste(r['variables']).first)['lignes'] as List).cast<List>()) {
      expect(find.text('${l[0]}'), findsOneWidget, reason: '${l[0]}');
      expect(find.text('${l[1]}'), findsOneWidget, reason: '${l[1]}');
    }
    expect(find.textContaining('Un jeton inconnu reste tel quel dans le texte'), findsOneWidget);
  });

  casM14('création d’un modèle : la source est « Rédigé par l’administrateur » ; le détail remplace les variables et GARDE un jeton inconnu', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-rappels');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau modèle'));
    await choisirM14(t, 'occasion', 'Fête ou jour férié');
    await saisir(t, 'libelle', 'Modèle test');
    await saisir(t, 'texte', 'Bonjour {{nom}} — {{inconnu}} à {{clinique}}');
    await toucherM14(t, find.text('Modèle actif'));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('modelesMessage').toutes.first;
    expect([f['occasion'], f['libelle'], f['actif'], f['source']], ['fete', 'Modèle test', true, 'Rédigé par l’administrateur']);
    expect(find.text('Modèle créé.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.byTooltip('Consulter').first);
    expect(find.textContaining('OROU YO Marguerite — {{inconnu}} à CLINIQUE NASSIERA TOO SARL'), findsOneWidget);
  });

  casM14('anniversaires du jour : un rappel EN FILE par patient (références RPL-…), jamais deux fois le même ; le logiciel ne les envoie pas', (t) async {
    final m = magasinM14();
    final auj = DateTime(2026, 10, 30, 10);
    final p = m.collection('patients').actives;
    m.collection('patients').mettreAJour(p[0]['id'], {'dateNaissance': '1990-10-30'});
    m.collection('patients').mettreAJour(p[1]['id'], {'dateNaissance': '2001-10-30'});
    await ouvrirM14(t, m, 'cfg-rappels', horloge: auj);
    await onglet(t, 'rappels');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Préparer les anniversaires du jour'));
    final col = m.collection('rappels');
    expect(col.actives.length, 2);
    expect(col.actives.map((x) => x['reference']).toSet(), {'RPL-00001', 'RPL-00002'});
    for (final x in col.actives) {
      expect([x['occasion'], x['etat'], x['dateEcheance']], ['Anniversaire', 'en_file', '2026-10-30']);
      expect('${x['message']}', contains('${x['destinataire']}'));
      expect('${x['message']}', isNot(contains('OROU YO')));
    }
    expect(find.text('2 rappel(s) préparé(s) — 2 anniversaire(s) aujourd’hui.'), findsOneWidget);
    expect(find.text('Les messages sont EN FILE : le logiciel ne les envoie pas.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    // Une seconde fois : le patient ne reçoit pas deux fois le même message.
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Préparer les anniversaires du jour'));
    expect(col.actives.length, 2);
    expect(find.text('0 rappel(s) préparé(s) — 2 anniversaire(s) aujourd’hui.'), findsOneWidget);
  });

  casM14('sans modèle d’anniversaire ACTIF : refus nommé, aucun rappel ; sans anniversaire : on le dit', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-rappels');
    await onglet(t, 'rappels');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Préparer les anniversaires du jour'));
    expect(find.text('Aucun patient ne fête son anniversaire aujourd’hui.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    final mod = m.collection('modelesMessage').actives.firstWhere((x) => x['occasion'] == 'anniversaire');
    m.collection('modelesMessage').mettreAJour(mod['id'], {'actif': false});
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Préparer les anniversaires du jour'));
    expect(find.text('Aucun modèle d’anniversaire actif.'), findsOneWidget);
    expect(m.collection('rappels').toutes, isEmpty);
  });

  casM14('un rappel se consulte et s’archive, il ne se modifie pas (le message est composé)', (t) async {
    final m = magasinM14();
    m.collection('rappels').inserer({'statut': 'actif', 'reference': 'RPL-00001', 'occasion': 'Anniversaire', 'destinataire': 'TEST Un', 'telephone': '0100000000', 'dateEcheance': '2026-10-30', 'etat': 'en_file', 'message': 'Bonjour TEST Un'}, prefixe: 'RPL');
    await ouvrirM14(t, m, 'cfg-rappels');
    await onglet(t, 'rappels');
    expect(find.text('En file'), findsWidgets);
    expect(find.byTooltip('Modifier'), findsNothing);
    await toucherM14(t, find.byTooltip('Consulter').first);
    expect(find.text('Bonjour TEST Un'), findsOneWidget);
    expect(find.text('MESSAGE COMPOSÉ'), findsOneWidget);
  });

  casM14('droits : en lecture seule, aucune commande d’écriture (absentes, jamais grisées)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-rappels', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-rappels'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau modèle'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.byTooltip('Consulter'), findsWidgets);
    await onglet(t, 'rappels');
    expect(find.widgetWithText(BoutonSigh, 'Préparer les anniversaires du jour'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
