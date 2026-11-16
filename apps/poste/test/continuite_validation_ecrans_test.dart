import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT CONT (exigence de la Direction du 14/11/2026), au GESTE D'ÉCRAN sur un FILEUL rattaché : avant ce lot, le bouton « Valider » y était ABSENT pour les quinze familles (la configuration
/// voyage de la mère) et le profil devait se rendre sur le poste de la mère. Désormais le profil de la famille décide depuis son poste : la décision est SIGNÉE et déposée, rien n'est validé chez
/// le fileul tant que la mère n'a pas appliqué, le badge et la pastille de la barre le disent (nombre réel et âge), le bouton disparaît (jamais deux décisions), le reste de l'écran reste utilisable.
/// Passé le délai lu de la base, une ALERTE (jamais un blocage) va au profil de la famille et à l'administrateur, pas aux autres.
Finder boutons(String famille) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('val:valider:$famille:'));

Future<Magasin> _fileul(WidgetTester t) async {
  final m = magasinM14();
  await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
  expect(ServiceInstallation.de(m).rattache, isTrue);
  return m;
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  for (final e in [
    (famille: 'labo_variables', ecran: 'm5-valeurs-reference', col: 'variablesLabo', role: 'laborantin'),
    (famille: 'enquetes', ecran: 'adm-enquetes', col: 'enquetes', role: 'direction'),
  ]) {
    casM14('${e.famille} sur un FILEUL : le profil de la famille (${e.role}) décide depuis son poste, la décision est déposée et dite, jamais validée en local, jamais doublée', (t) async {
      final m = await _fileul(t);
      final col = m.collection(e.col);
      expect(col.actives, isNotEmpty);
      for (final f in col.actives) {
        col.mettreAJour(f['id'], {'aValider': true, 'valideLe': null, 'validePar': null, 'valideRole': null}, journaliser: false);
      }
      await ouvrirM14(t, m, e.ecran, role: e.role);
      final b = boutons(e.famille);
      expect(b, findsWidgets, reason: 'le bouton Valider est offert au profil de la famille sur un fileul (il était absent avant le lot CONT)');
      expect(find.byKey(const Key('pastille-decisions')), findsNothing, reason: 'rien n\'attend : pas de pastille');
      final nBoutons = t.widgetList(b).length;
      final id = (t.widget(b.first).key as ValueKey<String>).value.split(':').last;
      await toucherM14(t, b.first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
      final d = m.collection(valCollectionDemandes).toutes;
      expect(d, hasLength(1), reason: 'la décision est déposée');
      expect([d.single['famille'], '${d.single['cible']}', d.single['etat'], d.single['demandeRole']], [e.famille, id, valEtatDeposee, e.role]);
      expect(d.single['demandePar'], isNotEmpty, reason: 'signée : le nom de la personne');
      expect(col.parId(id)!['aValider'], true, reason: 'rien n\'est validé chez le fileul : la mère applique, la règle en vigueur reste');
      expect(col.parId(id)!['valideLe'], isNull);
      expect(find.textContaining('décision enregistrée'), findsOneWidget);
      expect(find.text('Décision déposée, en attente de la mère'), findsWidgets, reason: 'le badge dit l\'état, jamais un verrou');
      expect(find.byKey(Key('val:valider:${e.famille}:$id')), findsNothing, reason: 'jamais deux décisions sur le même élément : la commande est ABSENTE');
      expect(t.widgetList(boutons(e.famille)).length, nBoutons - 1, reason: 'les AUTRES éléments restent décidables : rien ne se bloque');
      expect(find.textContaining('1 décision en attente de la mère'), findsOneWidget, reason: 'la pastille de la barre dit le nombre réel');
      expect(m.collection('audit').toutes.first['action'], 'Validation : décision déposée à la mère (signée)');
    });
  }

  casM14('l\'alerte d\'une décision en retard va au profil de la famille et à l\'administrateur, au-delà du délai LU de la base, jamais avant ; elle ne bloque rien', (t) async {
    final m = magasinM14();
    final signe = DateTime(2026, 11, 14, 8);
    m.collection(valCollectionDemandes).inserer({
      'id': 'DVT1', 'statut': 'actif', 'famille': 'labo_variables', 'cible': 'VL1', 'etat': valEtatDeposee, 'demandePar': 'Dr KINNOU', 'demandeRole': 'laborantin', 'demandeLe': valInstant(signe),
    });
    List<AlerteNotif> pour(String role, DateTime quand) => CentreNotifications(magasin: m, donnees: () => donneesNav, role: () => role, horloge: () => quand)
        .collecter()
        .where((n) => n.source == 'decisions_en_attente')
        .toList();
    expect(pour('laborantin', signe.add(const Duration(hours: 23))), isEmpty, reason: 'en deçà du délai semé (24 h) : aucune alerte');
    final a = pour('laborantin', signe.add(const Duration(hours: 25)));
    expect(a, hasLength(1));
    expect(a.single.titre, 'Décision en attente de la mère depuis 1 jour 1 h : Variables et unités du laboratoire (bornes suppléées)');
    expect(a.single.detail, contains('rien n\'est bloqué ni validé d\'office'));
    expect(pour('admin', signe.add(const Duration(hours: 25))), hasLength(1), reason: 'l\'administrateur aussi');
    expect(pour('caissier', signe.add(const Duration(hours: 25))), isEmpty, reason: 'pas les autres profils');
    expect(m.collection(valCollectionDemandes).parId('DVT1')!['etat'], valEtatDeposee, reason: 'jamais une validation d\'office');
  });
}
