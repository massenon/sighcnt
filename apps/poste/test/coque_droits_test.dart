import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// DROITS À CHAUD dans la coque (A4, E203, E596) : la matrice engendrée est superposée, à l'exécution, aux collections `rbac` (surcharges de
/// m14-roles) et `modulesActifs` (activités fermées de cfg-modules), comme `N.can()` de la maquette. Une fiche écrite change le ruban, les accès
/// et les adresses AUSSITÔT, sans redémarrage.
final donnees = DonneesNavigation.depuisDossier();

Magasin jeu() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'audit', 'poches', 'donneurs', 'produits', 'lots', 'demandesAnalyses', 'examensLabo']);

Future<void> monter(WidgetTester t, Magasin m, {String role = 'admin', String? ecran}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role, nomPoste: 'Test'),
      magasin: m,
      ecranInitial: ecran,
      horloge: () => DateTime(2026, 8, 16, 10)));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> domaine(WidgetTester t, String nom) async {
  // Un clic sur l'onglet du domaine déjà ouvert referme le panneau : on rouvre alors.
  await t.tap(find.byKey(Key('domaine-$nom')));
  await t.pump();
  if (find.byKey(const Key('panneau-ruban')).evaluate().isEmpty) {
    await t.tap(find.byKey(Key('domaine-$nom')));
    await t.pump();
  }
}

/// Les deux fiches de fermeture du jeu (banque de sang et transfusion), archivées : l'activité est rouverte.
void rouvrir(Magasin m) {
  for (final f in m.collection('modulesActifs').actives.toList()) {
    m.collection('modulesActifs').archiver(f['id']);
  }
}

void main() {
  setUpAll(chargerPolices);

  testWidgets('ACTIVITÉ FERMÉE : la banque de sang est absente du ruban de l\'administrateur, ses adresses disent « Activité fermée » avec le motif de la fiche', (t) async {
    final m = jeu();
    expect(m.collection('modulesActifs').actives, hasLength(2), reason: 'le jeu ferme la banque de sang et la transfusion');
    await monter(t, m, ecran: 'm5-banque-sang');
    expect(find.byKey(const Key('activite-fermee')), findsOneWidget);
    expect(find.text('Activité fermée'), findsWidgets);
    expect(find.textContaining('La clinique ne pratique pas la banque de sang.'), findsOneWidget, reason: 'le motif de la fiche, comme le 403 le nomme');
    expect(find.textContaining('pour tous les rôles, administrateur compris'), findsOneWidget);
    await domaine(t, 'Soins');
    expect(find.byKey(const Key('pastille-m5-demandes')), findsOneWidget, reason: 'le laboratoire reste ouvert : la fermeture porte sur des écrans nommés');
    expect(find.byKey(const Key('pastille-m5-banque-sang')), findsNothing);
    expect(find.byKey(const Key('pastille-m5-donneurs')), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('ACTIVITÉ ROUVERTE (fiches archivées, RG-14) : la coque SERT m5-banque-sang et m5-donneurs', (t) async {
    final m = jeu();
    rouvrir(m);
    await monter(t, m, ecran: 'm5-banque-sang');
    expect(find.byKey(const Key('activite-fermee')), findsNothing);
    expect(find.text('Banque de sang'), findsWidgets);
    expect(find.text('Poches de sang'), findsWidgets);
    await domaine(t, 'Soins');
    expect(find.byKey(const Key('pastille-m5-banque-sang')), findsOneWidget);
    expect(find.byKey(const Key('pastille-m5-donneurs')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('À CHAUD : rouvrir l\'activité fait paraître l\'écran sans redémarrer, la refermer le retire et l\'adresse ouverte le DIT', (t) async {
    final m = jeu();
    await monter(t, m, ecran: 'm5-banque-sang');
    expect(find.byKey(const Key('activite-fermee')), findsOneWidget);
    // Rouverte : la page courante se sert d'elle-même.
    for (final f in m.collection('modulesActifs').actives.toList()) {
      m.collection('modulesActifs').archiver(f['id']);
    }
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('activite-fermee')), findsNothing);
    expect(find.text('Poches de sang'), findsWidgets);
    await domaine(t, 'Soins');
    expect(find.byKey(const Key('pastille-m5-banque-sang')), findsOneWidget);
    // Refermée par la restauration de la fiche : la page affiche de nouveau le refus nommé, le ruban perd la pastille.
    m.collection('modulesActifs').restaurer('MOD01');
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('activite-fermee')), findsOneWidget);
    expect(find.byKey(const Key('pastille-m5-banque-sang')), findsNothing);
    expect(find.byKey(const Key('pastille-m5-donneurs')), findsOneWidget, reason: 'la fiche des donneurs, elle, reste archivée donc rouverte');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('LE NOYAU NE SE FERME PAS : une fiche qui fermerait CFG en entier est sans effet sur le ruban', (t) async {
    final m = jeu();
    m.collection('modulesActifs').inserer({'id': 'MODX', 'module': 'CFG', 'libelle': 'Configuration', 'actif': false});
    await monter(t, m);
    await domaine(t, 'Système');
    expect(find.byKey(const Key('pastille-cfg-modules')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('RBAC À CHAUD (E596) : fermer un écran à un rôle le retire de son ruban aussitôt ; le rendre le fait reparaître', (t) async {
    final m = jeu();
    await monter(t, m, role: 'reception');
    await domaine(t, 'Administration');
    expect(find.byKey(const Key('pastille-m13-repertoire-ambulances')), findsOneWidget, reason: 'l\'accueil tient le répertoire des ambulances');
    final fiche = m.collection('rbac').toutes.firstWhere((f) => f['role'] == 'reception');
    final droitsEcrans = {...(fiche['droitsEcrans'] as Map).cast<String, Object?>()};
    final annule = m.collection('rbac').mettreAJour(fiche['id'], {
      'droitsEcrans': {
        ...droitsEcrans,
        'm13-repertoire-ambulances': {'voir': false}
      }
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('pastille-m13-repertoire-ambulances')), findsNothing, reason: 'écran fermé par la fiche : plus de pastille');
    annule();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('pastille-m13-repertoire-ambulances')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('RBAC À CHAUD : un rôle ARCHIVÉ n\'ouvre plus rien (RG-14), la restauration lui rend son ruban', (t) async {
    final m = jeu();
    await monter(t, m, role: 'comptable');
    expect(find.byKey(const Key('domaine-Financier')), findsOneWidget);
    final fiche = m.collection('rbac').toutes.firstWhere((f) => f['role'] == 'comptable');
    m.collection('rbac').archiver(fiche['id']);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('domaine-Financier')), findsNothing);
    expect(find.text('Aucun module n’est ouvert à votre profil.'), findsOneWidget);
    m.collection('rbac').restaurer(fiche['id']);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('domaine-Financier')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('LES DROITS DE L\'ÉCRAN suivent la fiche : lecture seule posée à chaud, la note de lecture seule paraît et la commande de création disparaît', (t) async {
    final m = Magasin.depuisDossier(['rbac', 'modulesActifs', 'audit', 'factures', 'patients', 'naturesFacture', 'avoirs', 'taches', 'actes']);
    await monter(t, m, ecran: 'm8-factures');
    expect(find.textContaining('Lecture seule : le profil'), findsNothing);
    final avant = find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length;
    expect(avant, greaterThan(0), reason: 'l\'administrateur écrit : la commande de création est là');
    m.collection('rbac').inserer({
      'id': 'RBACT1',
      'role': 'admin',
      'statut': 'actif',
      'droitsEcrans': {
        'm8-factures': {'voir': true, 'editer': false, 'annuler': false}
      }
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Lecture seule : le profil'), findsOneWidget);
    expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, 0, reason: 'une commande interdite est ABSENTE, pas grisée');
    await t.pump(const Duration(seconds: 10));
  });

  test('DonneesNavigation.aChaud : sans fiche dans le magasin, la matrice engendrée reste en force (pas de recalcul)', () {
    final m = Magasin(const {}, 'POSTE');
    expect(identical(donnees.aChaud(m), donnees), isTrue);
    final avec = Magasin({
      'modulesActifs': [
        {'id': 'M', 'module': 'M13', 'libelle': 'Administration', 'actif': false}
      ]
    }, 'POSTE');
    final vive = donnees.aChaud(avec);
    expect(identical(vive, donnees), isFalse);
    expect(vive.matrice.peutVoir('admin', 'm13-courriers'), isFalse);
    expect(donnees.matrice.peutVoir('admin', 'm13-courriers'), isTrue, reason: 'la matrice engendrée n\'est jamais modifiée');
  });
}
