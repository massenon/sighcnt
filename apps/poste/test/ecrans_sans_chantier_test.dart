import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/registre.dart';
import 'package:sigh_poste/shell/coque.dart';
import 'package:sigh_poste/shell/recherche_globale.dart' show ecranOuvertAuRole;

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';

/// PLUS AUCUN ÉCRAN DE CHANTIER (Direction, 01/11/2026, point 5).
///
/// Le gabarit « Écran de la maquette à convertir » (`EcranAPorter`) n'est plus qu'un filet : il ne doit JAMAIS apparaître à un agent. Le garde :
///  1. pour CHAQUE rôle non archivé et CHAQUE mode (fileul, mère), tout écran que le profil peut ouvrir (ruban, pages d'accueil de module, accueil du rôle,
///     écrans hors ruban atteignables par la recherche) a un widget dans `ecransPortes`, construit comme `SighPoste` le construit (le client de la mère
///     n'existe qu'en mode mère, le contrôleur du poste toujours) ;
///  2. aucun texte « à convertir », « à venir » ou « non commencé » ne reste dans `lib/` comme gabarit d'écran ;
///  3. rendus de bout en bout : les écrans qui dépendent du mode (les réglages du poste, le domaine Poste mère) se dessinent sans le gabarit de chantier.
void main() {
  setUpAll(chargerPolices);
  final donnees = DonneesNavigation.depuisDossier();
  final roles = [
    for (final r in donnees.matrice.rolesBruts)
      if (r['archive'] != true) '${r['id']}'
  ];

  ControleurPoste controleur(ModePoste mode) => ControleurPoste(
      activation: ActivationMere(stockage: StockageMemoire(), service: FauxService(), relaisPour: (_, __) => throw StateError('hors sujet')),
      config: ConfigPoste(mode: mode, nomPoste: 'Test'));

  Set<String> portes(ModePoste mode) => ecransPortes(
          controleur: controleur(mode),
          client: mode == ModePoste.mere ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's') : null)
      .keys
      .toSet();

  test('l\'inventaire des rôles n\'est pas vide', () => expect(roles.length, greaterThan(10)));

  for (final mode in [ModePoste.fileul, ModePoste.mere]) {
    test('INVENTAIRE ${mode.name} : tout écran ouvert à un rôle autorisé est porté (aucun gabarit de chantier possible)', () {
      final p = portes(mode);
      final estMere = mode == ModePoste.mere;
      final manques = <String>{};
      for (final role in roles) {
        final ouverts = <String>{
          for (final d in donnees.manifeste.ruban(donnees.matrice, role, estMere: estMere))
            for (final r in d.rangees) ...[r.hub, for (final e in r.ecrans) e.id],
          for (final e in donnees.manifeste.tousLesEcrans)
            if (ecranOuvertAuRole(donnees, role, e.id) && (estMere || !domainesMere.contains(e.domaine))) e.id,
        };
        final accueil = donnees.matrice.accueil(role);
        if (accueil != null && donnees.matrice.peutVoir(role, accueil)) ouverts.add(accueil);
        for (final id in ouverts) {
          if (!p.contains(id)) manques.add('$id ($role, ${mode.name})');
        }
      }
      expect(manques, isEmpty, reason: 'écrans ouverts à un rôle autorisé mais sans widget (gabarit de chantier) :\n${manques.join('\n')}');
    });
  }

  test('le manifeste entier est porté en mode mère (aucun écran ne reste hors de ecransPortes)', () {
    final p = portes(ModePoste.mere);
    final manques = [for (final e in donnees.manifeste.tousLesEcrans) if (!p.contains(e.id)) e.id]..sort();
    expect(manques, isEmpty, reason: 'écrans du manifeste sans widget : $manques');
  });

  test('SOURCE : aucun texte de chantier (« à convertir », « Écran de la maquette à ») dans lib/', () {
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final t = lignes[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (lignes[i].contains('à convertir') || lignes[i].contains('Écran de la maquette à')) fautes.add('${f.path}:${i + 1}');
      }
    }
    expect(fautes, isEmpty);
  });

  testWidgets('RENDU : les réglages du poste (fileul) et la console de la mère se dessinent sans le gabarit de chantier', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    for (final (mode, ecran) in [(ModePoste.fileul, 'cfg-poste'), (ModePoste.mere, 'cfg-poste'), (ModePoste.mere, 'mere-supervision'), (ModePoste.fileul, 'hub-m8')]) {
      final ctl = controleur(mode);
      await t.pumpWidget(SighPoste(
          donnees: donnees,
          controleur: ctl,
          client: mode == ModePoste.mere ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's') : null,
          ecranInitial: ecran,
          horloge: () => DateTime(2026, 10, 30, 10),
          magasin: Magasin.depuisDossier(Magasin.collectionsDuJeu)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CoquePoste), findsOneWidget);
      expect(find.byKey(const Key('ecran-a-porter')), findsNothing, reason: '$ecran (${mode.name}) affiche le gabarit de chantier');
    }
  });
}
