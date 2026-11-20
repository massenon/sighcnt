// MESURE DE PARITÉ N1 des écrans de la suite du mobile contre les fiches extraites des pages RÉELLES du simulateur
// (`docs/architecture/ecrans-mobile/<id>.json`, engendrées par `node build/vecteurs-mobile-suite.js`) : chaque libellé que la page affiche (titre, cartes,
// champs, exemples, choix des listes, notes, commandes, compteurs, lignes de réglage, textes) doit figurer à l'écran Flutter.
//
// Ce qui n'est PAS comparé, et pourquoi (chaque exclusion est comptée et écrite dans le rapport, jamais silencieuse) :
//  - la barre d'onglets du simulateur (Accueil, Synchro, À traiter, Réglages) : l'application n'a pas cette barre, ses écrans s'atteignent par l'accueil ;
//  - les VALEURS du jeu de démonstration (nom de l'agent, appareil « u-06 · version 1.0.1 · schéma v66 », dossiers de la tournée, sous-titre) ;
//  - « Démonstration : 1234 » : le code de démonstration n'a pas de sens sur un vrai téléphone ;
//  - « Activées » (notifications) : l'écran dit « Non branchées », parce que la notification de réveil n'est pas branchée (E1571).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';
import 'package:sigh_mobile/ui/formulaire_suite.dart';
import 'package:sigh_mobile/ui/lot.dart';
import 'package:sigh_mobile/ui/orientation.dart';
import 'package:sigh_mobile/ui/pin.dart';
import 'package:sigh_mobile/ui/reglages.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
String normaliser(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

M fiche(String id) {
  final f = File('../../docs/architecture/ecrans-mobile/$id.json');
  expect(f.existsSync(), isTrue, reason: 'fiche absente : node build/vecteurs-mobile-suite.js');
  return obj(jsonDecode(f.readAsStringSync()));
}

/// Ce que l'agent LIT : les textes, les libellés et exemples de champ, les infobulles (les choix d'une liste fermée sont dans l'arbre).
Set<String> textesAgent(WidgetTester t) {
  final out = <String>{};
  void ajouter(String? s) {
    if (s != null && s.trim().isNotEmpty) out.add(normaliser(s));
  }

  for (final w in t.widgetList<Text>(find.byType(Text, skipOffstage: false))) {
    ajouter(w.data ?? w.textSpan?.toPlainText());
  }
  for (final w in t.widgetList<InputDecorator>(find.byType(InputDecorator, skipOffstage: false))) {
    ajouter(w.decoration.labelText);
    ajouter(w.decoration.hintText);
  }
  for (final w in t.widgetList<Tooltip>(find.byType(Tooltip, skipOffstage: false))) {
    ajouter(w.message);
  }
  return out;
}

class Mesure {
  Mesure(this.id, this.attendus, this.manquants, this.exclus);
  final String id;
  final List<String> attendus, manquants;
  final Map<String, int> exclus;
  int get presents => attendus.length - manquants.length;
}

/// Les libellés attendus d'une fiche, hors exclusions déclarées.
Mesure comparer(String id, M f, Set<String> textes, {Set<String> exclure = const {}, Map<String, String> motifs = const {}}) {
  final attendus = <String>[];
  void ajouter(Object? v) {
    if (v is String && v.trim().isNotEmpty) attendus.add(normaliser(v));
    if (v is List) v.forEach(ajouter);
  }

  ajouter(f['titre']);
  ajouter(f['cartes']);
  for (final n in (f['notes'] as List)) {
    ajouter(obj(n)['texte']);
  }
  ajouter(f['boutons']);
  for (final c in (f['champs'] as List)) {
    final m = obj(c);
    ajouter(m['libelle']);
    ajouter(m['placeholder']);
    if (m['type'] == 'select') ajouter(m['options']);
  }
  for (final k in (f['kpis'] as List)) {
    ajouter((k as List).first);
  }
  for (final it in (f['items'] as List)) {
    final m = obj(it);
    if (id.startsWith('parametres')) {
      ajouter(m['titre']);
      ajouter(m['detail']);
      ajouter(m['fin']);
    }
  }
  ajouter(f['vide']);
  for (final tx in (f['textes'] as List)) {
    ajouter(tx);
  }
  final exclus = <String, int>{'onglets de la barre du simulateur': (f['onglets'] as List).length};
  final uniques = attendus.toSet().toList();
  final retenus = <String>[];
  for (final a in uniques) {
    final motif = exclure.contains(a) ? motifs[a] ?? 'valeur de démonstration' : null;
    if (motif != null) {
      exclus[motif] = (exclus[motif] ?? 0) + 1;
    } else {
      retenus.add(a);
    }
  }
  final chiffres = RegExp(r'\d+');
  final neutres = {for (final t in textes) t.replaceAll(chiffres, '#')};
  final manquants = [
    for (final a in retenus)
      if (!(a.length <= 3 ? textes.contains(a) : (textes.any((t) => t.contains(a)) || neutres.any((t) => t.contains(a.replaceAll(chiffres, '#'))))) ) a
  ];
  return Mesure(id, retenus, manquants, exclus);
}

final rapport = <String, Object?>{};

Future<void> monter(WidgetTester t, Widget ecran) async {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: ecran));
  await t.pumpAndSettle();
}

void verifier(String id, Mesure m) {
  rapport[id] = {'attendus': m.attendus.length, 'presents': m.presents, 'manquants': m.manquants, 'exclus': m.exclus};
  expect(m.manquants, isEmpty, reason: '$id : ${m.presents}/${m.attendus.length} présents, manquants ${m.manquants}');
}

void main() {
  testWidgets('N1 cpn : chaque libellé de la page (carte Examen, carte Prévention, listes, exemples, commande)', (t) async {
    await monter(t, FormulaireSuite(ecran: 'cpn', sous: 'SOUROU Mariam', enregistrer: (s) async {}));
    verifier('cpn', comparer('cpn', fiche('cpn'), textesAgent(t), exclure: {normaliser('SOUROU Mariam')}));
  });

  testWidgets('N1 cpon : mère et nouveau-né', (t) async {
    await monter(t, FormulaireSuite(ecran: 'cpon', sous: 'KPOGNON Rose', enregistrer: (s) async {}));
    verifier('cpon', comparer('cpon', fiche('cpon'), textesAgent(t)));
  });

  testWidgets('N1 surveillance : la note de la grille unique, Mère, Bébé', (t) async {
    await monter(t, FormulaireSuite(ecran: 'surveillance', sous: 'SOUROU Mariam', notes: [mobNoteEcranSuite('surveillance')!], enregistrer: (s) async {}));
    verifier('surveillance', comparer('surveillance', fiche('surveillance'), textesAgent(t)));
  });

  testWidgets('N1 orientation (avec dossiers) : Patient, Orienter vers, Degré, les six destinations, les trois degrés', (t) async {
    final m = FauxMoteurSuite(source: accueilDeSecours())..profil = ProfilMobile.receptionSecours;
    await monter(t, OrienterPatient(service: ServiceSuite.reception(m)));
    final f = fiche('orientation');
    // Les choix de la liste « Patient » viennent du jeu de la page (deux dossiers inventés) : valeurs de démonstration.
    final valeurs = {for (final c in (f['champs'] as List)) if (obj(c)['id'] == 'pat') ...[for (final o in (obj(c)['options'] as List)) normaliser('$o')]};
    verifier('orientation', comparer('orientation', f, textesAgent(t), exclure: valeurs));
  });

  testWidgets('N1 orientation (sans dossier) : « Ouvrez d’abord un dossier. »', (t) async {
    final m = FauxMoteurSuite(source: SourceMemoire({'patients': []}))..profil = ProfilMobile.receptionSecours;
    await monter(t, OrienterPatient(service: ServiceSuite.reception(m)));
    verifier('orientation-vide', comparer('orientation-vide', fiche('orientation-vide'), textesAgent(t)));
  });

  testWidgets('N1 lot : Lot du jour, Dossiers, Validité restante, la note de l\'expiration', (t) async {
    final m = FauxMoteurSuite(fonction: 'sage_femme', agent: 'Sage-femme de garde', source: lotSageFemme())..profil = ProfilMobile.soignant;
    await monter(t, EcranLot(moteur: m, service: ServiceSuite.depuisSoignant(m.soignant!)));
    final f = fiche('lot');
    final noms = {for (final it in (f['items'] as List)) ...[normaliser('${obj(it)['titre']}'), normaliser('${obj(it)['detail']}')]};
    final mesure = comparer('lot', f, textesAgent(t), exclure: noms);
    verifier('lot', mesure);
  });

  for (final e in const {'soignant': 'infirmier', 'medecin': 'medecin', 'sagefemme': 'sage_femme', 'reception': ''}.entries) {
    testWidgets('N1 parametres (${e.key}) : Ce téléphone, Profil, Agent, trois garanties, réinitialisation', (t) async {
      final f = fiche('parametres-${e.key}');
      final m = e.key == 'reception' ? (FauxMoteurSuite(source: accueilDeSecours())..profil = ProfilMobile.receptionSecours) : (FauxMoteurSuite(fonction: e.value)..profil = ProfilMobile.soignant);
      await monter(t, EcranReglages(moteur: m, profil: e.key, agent: 'agent', verrouillageActif: true));
      final textes = f['textes'] as List;
      // Valeurs de démonstration : le nom de l'agent, la ligne « Appareil u-06 · version 1.0.1 · schéma v66 ».
      final valeurs = {normaliser('${textes[3]}'), normaliser('${textes[4]}')};
      final mesure = comparer('parametres-${e.key}', f, textesAgent(t), exclure: {...valeurs, normaliser('Activées')}, motifs: {normaliser('Activées'): 'garantie fausse : « Non branchées » (E1571)'});
      verifier('parametres-${e.key}', mesure);
    });
  }

  testWidgets('N1 verrou (Code PIN) : titre et invite', (t) async {
    await monter(t, EcranPin(pin: MobPin(CoffrePinMemoire('1234')), ouvrir: () {}));
    final f = fiche('verrou');
    verifier('verrou', comparer('verrou', f, textesAgent(t), exclure: {normaliser('Démonstration : 1234')}, motifs: {normaliser('Démonstration : 1234'): 'code de démonstration'}));
    // Le pavé : les onze touches de la page, dans l'ordre (le vide est un blanc).
    for (final k in mobPinPave.where((k) => k.isNotEmpty)) {
      expect(find.byKey(Key(k == '⌫' ? 'touche-effacer' : 'touche-$k')), findsOneWidget, reason: k);
    }
  });

  tearDownAll(() {
    final env = Platform.environment['SIGH_RAPPORT_MOBILE'];
    if (env != null) File(env).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rapport));
  });
}
