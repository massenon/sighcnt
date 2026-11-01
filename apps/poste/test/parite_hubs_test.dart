import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/shell/ecran_hub.dart';

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';
import 'parite/extracteur.dart';

/// LES PAGES D'ACCUEIL DE MODULE (hubs). La fiche N1 d'un hub ne porte que son titre et sa description (l'extracteur ne voit pas les cartes) : ce test
/// mesure ce que la fiche ne dit pas, à partir de sources INDÉPENDANTES du code porté : le manifeste engendré (`packages/referentiels/data`) pour la
/// composition du module, et les fiches de chaque écran (`docs/architecture/ecrans/<id>.json`) pour le titre et la description de chaque carte.
void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  final brut = (jsonDecode(File('../../packages/referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>();
  final hubsManifeste = [
    for (final e in (brut['ecrans'] as List))
      if ((e as Map)['hub'] == true) '${e['id']}'
  ];

  Map<String, Object?>? fiche(String id) {
    final f = File('../../docs/architecture/ecrans/$id.json');
    return f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>() : null;
  }

  /// Les écrans d'un module comme la maquette les agrège (`N.module`) : toutes les rangées non alias portant le code, dans l'ordre du manifeste.
  List<String> ecransDuModule(String code) => [
        for (final m in (brut['modules'] as List))
          if ((m as Map)['alias'] != true && m['code'] == code) ...[for (final e in (m['ecrans'] as List)) '$e']
      ];

  final magasin = Magasin.depuisDossier(Magasin.collectionsDuJeu);

  Future<void> monter(WidgetTester t, String hub, String role) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final client = ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('[]', 200)));
    final act = ActivationMere(stockage: StockageMemoire(), service: FauxService(), relaisPour: (_, __) => throw StateError('hors sujet'));
    final ctl = ControleurPoste(
        activation: act,
        config: ConfigPoste(mode: hub == 'hub-mere' || hub == 'hub-rls' ? ModePoste.mere : ModePoste.fileul, role: role, nomPoste: 'Test'));
    await t.pumpWidget(SighPoste(
        donnees: donnees, controleur: ctl, client: client, ecranInitial: hub, horloge: () => DateTime(2026, 10, 30, 10), magasin: magasin));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  test('les hubs déclarés dans le poste sont exactement ceux du manifeste', () {
    expect(hubsDuManifeste.toSet(), hubsManifeste.toSet());
    expect(hubsDuManifeste.length, hubsManifeste.length);
  });

  for (final role in ['admin', 'reception', 'caissier', 'medecin', 'aide_soignant']) {
    testWidgets('hubs : une carte par écran du module que le rôle $role voit, titre et description repris de la maquette', (t) async {
      for (final hub in hubsManifeste) {
        await monter(t, hub, role);
        final entree = donnees.manifeste.ecran(hub)!;
        expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$hub affiche la coque « à convertir »');
        final textes = textesVisibles(t);
        final attendus = [
          for (final id in ecransDuModule(entree.module))
            if (donnees.manifeste.ecran(id) != null && donnees.matrice.peutVoir(role, id)) id
        ];
        final masques = [
          for (final id in ecransDuModule(entree.module))
            if (donnees.manifeste.ecran(id) != null && !donnees.matrice.peutVoir(role, id)) id
        ];
        if (role == 'admin') expect(attendus, isNotEmpty, reason: '$hub : l’administrateur doit voir au moins une carte');
        if (attendus.isEmpty) {
          expect(textes.any((x) => x.contains('aucun écran de ce module n’est accessible à votre profil')), isTrue, reason: '$hub ($role) : état vide non dit');
        }
        for (final id in attendus) {
          expect(find.byKey(Key('hub-carte:$id')), findsOneWidget, reason: '$hub ($role) : carte de $id absente');
          final f = fiche(id);
          final titre = normaliser('${f?['titre'] ?? ''}'.isEmpty ? donnees.manifeste.ecran(id)!.label : '${f!['titre']}');
          expect(textes.any((x) => x == titre), isTrue, reason: '$hub ($role) : titre « $titre » de $id absent');
          final desc = '${f?['description'] ?? ''}';
          final voulue = normaliser(desc.isEmpty ? 'Écran du module ${donnees.manifeste.rangees.firstWhere((r) => !r.alias && !r.secondaire && r.code == entree.module).label}.' : desc);
          expect(textes.any((x) => x == voulue), isTrue, reason: '$hub ($role) : description de $id absente (« $voulue »)');
        }
        for (final id in masques) {
          expect(find.byKey(Key('hub-carte:$id')), findsNothing, reason: '$hub ($role) : la carte de $id devrait être absente (écran fermé au profil)');
        }
        // La description de page est celle de la maquette.
        expect(textes.any((x) => x.startsWith('tous les écrans du module ${entree.module.toLowerCase()} ')), isTrue, reason: '$hub : description de page absente');
      }
    });
  }

  testWidgets('hubs : un clic sur une carte ouvre l’écran visé', (t) async {
    await monter(t, 'hub-m8', 'admin');
    final premiere = ecransDuModuleM8(donnees);
    await t.tap(find.byKey(Key('hub-carte:$premiere')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(Key('hub-carte:$premiere')), findsNothing);
  });
}

String ecransDuModuleM8(DonneesNavigation d) => d.manifeste.rangees.firstWhere((r) => r.code == 'M8' && !r.alias).ecrans.first;
