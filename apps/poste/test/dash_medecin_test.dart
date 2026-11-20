import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit;
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/dash/tba_medecin.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'dash_aide.dart';

/// `dash-medecin` : l'écran Flutter est comparé au relevé de l'écran réel de la maquette (premier regard, indicateurs, file du praticien, parcours,
/// consultations récentes, classement des motifs) ; les gestes sont accomplis par les boutons.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  final v = obj(vecteurs()['dash-medecin']);

  testWidgets('relevé de la maquette : premier regard, indicateurs, cartes, tableaux, parcours', (t) async {
    await ouvrir(t, magasin(), 'dash-medecin', role: 'medecin');
    comparer(t, v);
    await finir(t);
  });

  testWidgets('l\'ordre de lecture est celui du kit : alerte du poste, premier regard, accès rapides, file, parcours, indicateurs, tableaux', (t) async {
    await ouvrir(t, magasin(), 'dash-medecin', role: 'medecin');
    double haut(Finder f) => t.getTopLeft(f.first).dy;
    final ordre = [
      haut(find.text('Actes prescrits en attente d’exécution')),
      haut(find.text('À REGARDER EN PREMIER')),
      haut(find.text('Accès rapides')),
      haut(find.text('Vos patients en attente')),
      haut(find.text('Ce que vous faites ici — vos parcours')),
      haut(find.text('Consultations du jour')),
      haut(find.text('File d’attente et consultations récentes')),
    ];
    for (var i = 1; i < ordre.length; i++) {
      expect(ordre[i], greaterThan(ordre[i - 1]), reason: 'bloc $i après le bloc ${i - 1}');
    }
    await finir(t);
  });

  testWidgets('une étape d\'un autre poste est nommée par une pastille, jamais cliquable', (t) async {
    await ouvrir(t, magasin(), 'dash-medecin', role: 'medecin');
    for (final poste in ['Caisse', 'Laboratoire']) {
      expect(find.text(poste), findsWidgets);
    }
    expect(find.byKey(const Key('tba:etape:null')), findsNothing);
    await finir(t);
  });

  testWidgets('sous le nom d\'un praticien adressé nommément, la file « Adressés à… » paraît avec la commande Recevoir', (t) async {
    final m = magasin();
    final nomme = obj(vecteurs()['dash-medecin#nomme']);
    // Le poste lit l'intitulé du profil : on pose un ticket adressé à CET intitulé (écart E923 — le poste ne porte pas le nom de l'agent).
    final ticket = m.collection('fileAttente').actives.firstWhere((x) => x['poste'] == 'consultation' && x['etat'] == 'attente');
    m.collection('fileAttente').mettreAJour(ticket['id'], {'praticien': 'Médecin'});
    await ouvrir(t, m, 'dash-medecin', role: 'medecin');
    expect(find.textContaining('vous attendent nommément'), findsOneWidget);
    expect(find.text('Adressés à Médecin'), findsOneWidget);
    expect(find.text('Recevoir'), findsWidgets);
    expect(nomme['nom'], isNotNull);
    await finir(t);
  });

  testWidgets('une commande interdite est ABSENTE : sans accès à la fiche de consultation, ni « Recevoir » ni bouton d\'ouverture de parcours', (t) async {
    final m = magasin();
    final ticket = m.collection('fileAttente').actives.firstWhere((x) => x['poste'] == 'consultation' && x['etat'] == 'attente');
    m.collection('fileAttente').mettreAJour(ticket['id'], {'praticien': 'Administrateur système'});
    t.view.physicalSize = const Size(1600, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    Future<void> monter(bool Function(String) ouvre) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ContexteEcran(
                      ecranId: 'dash-medecin',
                      role: 'medecin',
                      droit: const Droit(voir: true, editer: false, annuler: false),
                      magasin: m,
                      aller: (_) {},
                      utilisateur: 'Administrateur système',
                      horloge: () => aujourdhui,
                      ouvre: ouvre,
                      child: const EcranDashMedecin())))));
      await t.pump(const Duration(milliseconds: 300));
    }

    await monter((_) => true);
    expect(find.text('Recevoir'), findsWidgets);
    expect(find.text('Ouvrir la consultation'), findsOneWidget);
    await monter((id) => id != 'm2-consultation-fiche' && id != 'm2-dossiers-consultation');
    expect(find.text('Recevoir'), findsNothing, reason: 'la commande refusée est absente, pas grisée');
    // La première étape du parcours « Recevoir un patient » est fermée : visible, non cliquable, et le bouton d'ouverture n'existe pas.
    expect(find.text('Enregistrer le dossier de consultation'), findsOneWidget);
    expect(find.byKey(const Key('tba:etape:m2-dossiers-consultation')), findsNothing);
    expect(find.text('Ouvrir la consultation'), findsNothing);
    expect(find.text('— fermé à votre profil'), findsWidgets);
    await finir(t);
  });
}
