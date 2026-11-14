import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/sync/service_propositions_tarif.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LA DIRECTION SUR UN FILEUL RATTACHÉ PROPOSE ET DÉCIDE UN PRIX (lot TFIN-2, étape 3). Le lot TFIN avait constaté que la coque mettait « Tarifs et prix » en LECTURE SEULE sur tout fileul rattaché
/// (`coque.dart`, `_surLaMere` : tout écran du module CFG) : la décision T11 (la Direction est fileul ; PRD-TARIFS 6.2, tableau des droits : `direction` oui, oui, oui) n'était atteignable que par l'API.
/// Ici, le GESTE D'ÉCRAN : le fileul DÉPOSE (rien d'écrit chez lui hors la demande, famille R), la mère applique (service branché) sous le nom et le rôle de l'auteur, le verdict revient. « Valider » reste
/// réservé à la liste de rôles de la famille (admin, da, direction) et revérifié par le moteur de la mère ; les autres rôles d'un fileul restent en LECTURE ; rien ne part vers un téléphone.
Future<Magasin> _fileul(WidgetTester t) async {
  final m = magasinM14();
  await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
  expect(ServiceInstallation.de(m).rattache, isTrue);
  return m;
}

/// Les mêmes données de navigation, mais [role] détient l'ÉDITION de [ecran] (la matrice la lui donne : seule la coque, sur un fileul, la lui retire).
DonneesNavigation _donneesAvecEdition(String role, String ecran) {
  final brut = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final parRole = (brut['parRole'] as Map).cast<String, Object?>();
  final r = ((parRole[role] as Map?)?.cast<String, Object?>() ?? <String, Object?>{})..[ecran] = [1, 1, 0];
  parRole[role] = r;
  return DonneesNavigation(manifeste: donneesNav.manifeste, matrice: MatriceDroits.depuisJson(brut), parite: const {});
}

Future<void> _chercher(WidgetTester t, String texte) async {
  await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, texte);
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('la Direction sur un fileul rattaché a « Proposer un changement » et « Valider » : sa proposition est DÉPOSÉE (rien d\'écrit chez lui) et la mère l\'applique sous son nom et son rôle', (t) async {
    final m = await _fileul(t);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await _chercher(t, 'MG01');
    expect(find.byTooltip('Proposer un changement'), findsWidgets, reason: 'la Direction (fileul) propose : PRD-TARIFS 6.2');
    final n0 = m.collection('versionsTarif').toutes.length;
    await toucherM14(t, find.byTooltip('Proposer un changement').first);
    expect(find.widgetWithText(BoutonSigh, 'Valider'), findsOneWidget, reason: 'la Direction est dans la liste de rôles de la famille');
    await saisir(t, 'prixNonAssure', '5400');
    await saisir(t, 'prixAssure', '3200');
    await saisir(t, 'motif', 'Test : proposition de la Direction depuis un fileul');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(m.collection('versionsTarif').toutes.length, n0, reason: 'un fileul n\'écrit JAMAIS une version (famille R) : seule la demande est écrite');
    final d = m.collection('propositionsTarif').toutes.where((x) => x['genre'] == 'proposition');
    expect(d.length, 1);
    expect([d.first['code'], '${d.first['prixNonAssure']}', d.first['etat'], d.first['demandeRole']], ['MG01', '5400', 'deposee', 'direction']);
    expect(find.textContaining('Demande déposée à la mère'), findsOneWidget);

    // La MÈRE (le service branché dans `main.dart`) applique la demande déposée, sous le nom et le rôle de l'auteur, et nomme son verdict.
    final mere = magasinM14();
    mere.collection('propositionsTarif').inserer({...d.first});
    final service = ServicePropositionsTarif(mere, donnees: () async => donneesNav, horloge: () => aujourdhui);
    expect(await t.runAsync(service.traiter), 1);
    final v = TarifsPoste.lire(mere).versionsDe('MG01').last;
    expect([v['statut'], v['prixNonAssure'], v['proposeRole']], ['propose', 5400, 'direction'], reason: 'appliquée sous le RÔLE de l\'auteur (RG-12)');
    expect(mere.collection('propositionsTarif').toutes.single['etat'], 'appliquee');
    expect(await t.runAsync(service.traiter), 0, reason: 'rejeu sans effet : une demande appliquée n\'est jamais reprise');
  });

  casM14('la Direction sur un fileul DÉCIDE (Oui) : une demande de décision est déposée, la mère la valide sous le rôle `direction`', (t) async {
    final mere = magasinM14();
    final daf = TarifsPoste(mere, role: 'da', auteur: () => 'DAF', peutEditerEcran: true, horloge: () => aujourdhui, etiquette: 'D');
    final prop = daf.proposer(DemandeProposition(code: 'MG01', prixNonAssure: 5500, etatAssure: 'unique', dateEffet: tarIso(aujourdhui.add(const Duration(days: 2))), motif: 'Test'));
    expect(prop.ok, isTrue, reason: '${prop.refus?.code} ${prop.refus?.motif}');
    final vid = '${prop.version!['id']}';
    // Le fileul reçoit la proposition de la mère (configuration) : on lui donne les mêmes versions.
    final m = await _fileul(t);
    m.collection('versionsTarif').appliquerDistante(prop.version!);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await toucherM14(t, find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:alertes')).first);
    await _chercher(t, 'MG01');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui, valider'));
    expect(m.collection('versionsTarif').parId(vid)!['statut'], 'propose', reason: 'rien n\'est décidé chez le fileul : la demande attend la mère');
    final d = m.collection('propositionsTarif').toutes.where((x) => x['genre'] == 'decision').single;
    expect([d['versionId'], d['decision'], d['demandeRole'], d['etat']], [vid, 'oui', 'direction', 'deposee']);
    mere.collection('propositionsTarif').inserer({...d});
    final service = ServicePropositionsTarif(mere, donnees: () async => donneesNav, horloge: () => aujourdhui);
    expect(await t.runAsync(service.traiter), 1);
    final v = mere.collection('versionsTarif').parId(vid)!;
    expect([v['statut'], v['roleDecision']], ['valide', 'direction']);
  });

  casM14('les AUTRES rôles d\'un fileul restent en LECTURE : un rôle hors de la liste de la famille, même doté de l\'édition par la matrice, n\'a ni « Proposer » ni « Nouvelle prestation » et la règle le dit', (t) async {
    final m = await _fileul(t);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'comptable', donnees: _donneesAvecEdition('comptable', 'cfg-tarifs'));
    await _chercher(t, 'MG01');
    expect(find.byTooltip('Consulter'), findsWidgets, reason: 'la lecture reste offerte');
    expect(find.byTooltip('Proposer un changement'), findsNothing, reason: 'la commande est ABSENTE, jamais grisée');
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle prestation'), findsNothing);
    expect(find.textContaining('Réglé sur la mère'), findsWidgets);
  });

  casM14('hors fileul rattaché (la mère, un poste autonome), le même rôle doté de l\'édition a « Proposer un changement » : la différence est bien celle du rattachement ET de la liste de rôles', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'comptable', donnees: _donneesAvecEdition('comptable', 'cfg-tarifs'));
    await _chercher(t, 'MG01');
    expect(find.byTooltip('Proposer un changement'), findsWidgets);
  });

  casM14('les AUTRES écrans de configuration restent en lecture seule sur un fileul rattaché (seul « Tarifs et prix » dépose)', (t) async {
    final m = await _fileul(t);
    await ouvrirM14(t, m, 'cfg-organisation', role: 'direction');
    expect(find.textContaining('Réglé sur la mère'), findsWidgets);
  });
}
