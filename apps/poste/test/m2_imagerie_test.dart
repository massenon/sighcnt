import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// L'imagerie médicale (cinq modalités) et la mécanique du compte rendu. Les règles sont rejouées dans `packages/domaine` sur les vecteurs tirés
/// des écrans RÉELS ; ici, l'ÉCRAN : ce qui s'affiche, ce qui s'écrit, ce qui est refusé, ce qui s'annule.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

final Map<String, Object?> vecteurs = (jsonDecode(
        File('../../packages/domaine/test/vecteurs/imagerie-cr.json')
            .readAsStringSync()) as Map)
    .cast<String, Object?>();

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  // Au milieu de l'écran : l'alignement par défaut collerait le champ sous la barre supérieure de la coque.
  await Scrollable.ensureVisible(t.element(f.first), alignment: 0.5);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Finder champ(String nom) => find.byKey(Key('kit:champ:$nom'));

Future<void> choisir(WidgetTester t, String nom, String cible) async {
  await toucher(
      t, find.descendant(of: champ(nom), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> saisir(WidgetTester t, String nom, String texte) async {
  final f = find.descendant(of: champ(nom), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, texte);
  await t.pump(const Duration(milliseconds: 100));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Map<String, Object?> ecranVecteur(String modalite) =>
    ((vecteurs['ecrans'] as Map)[modalite] as Map).cast<String, Object?>();

/// Les textes des KPI affichés : (libellé, valeur).
List<(String, String)> kpisAffiches(WidgetTester t) {
  final l = [
    for (final w
        in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle'))))
      w.data ?? ''
  ];
  final v = [
    for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
      w.data ?? ''
  ];
  return [for (var i = 0; i < l.length; i++) (l[i], v[i])];
}

const ecrans = {
  'echographie': 'm2-imagerie',
  'radiographie': 'm2-imagerie-radiographie',
  'mammographie': 'm2-imagerie-mammographie',
  'scanner': 'm2-imagerie-scanner',
  'irm': 'm2-imagerie-irm',
};

/// Le premier brouillon d'une modalité, lié à une demande.
Fiche brouillon(Magasin m, String modalite, {bool avecDemande = true}) {
  final ex = m.collection('examensImagerie').actives;
  return m.collection('resultatsImagerie').actives.firstWhere((r) {
    final x = ex.firstWhere((e) => e['code'] == r['examenCode']);
    return x['modalite'] == modalite &&
        r['statut'] != 'rendu' &&
        ((r['demandeImagerieId'] != null) == avecDemande);
  });
}

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('les cinq tableaux : ce que la maquette affiche', () {
    for (final e in ecrans.entries) {
      cas('${e.value} : indicateurs, première page et commandes', (t) async {
        final v = ecranVecteur(e.key);
        await ouvrir(t, magasin(), e.value);
        // Les quatre indicateurs, libellés ET valeurs, tels que la maquette les a calculés sur le même jeu.
        expect(kpisAffiches(t), [
          for (final k in (v['kpis'] as List))
            ((k as Map)['label'] as String, k['value'] as String)
        ]);
        // La première page, dans l'ordre : date décroissante, ex æquo dans l'ordre inverse du magasin.
        final attendues = [
          for (final l in ((v['pages'] as List).first as List))
            ((l as Map)['cellules'] as List).first as String
        ];
        final affichees = [
          for (final w in t
              .widgetList<Text>(find.textContaining(RegExp(r'^IMG-\d{4}$'))))
            w.data!
        ];
        expect(affichees.take(attendues.length).toList(), attendues);
        // Les colonnes et les commandes.
        for (final c in [
          'Référence',
          'Date',
          'Patient',
          'Examen',
          'Prescripteur',
          'Réalisé par',
          'État'
        ]) {
          expect(find.text(c.toUpperCase()), findsWidgets, reason: c);
        }
        expect(find.text('Nouveau compte rendu'), findsOneWidget);
      });
    }

    cas('les quatre modalités sans modèle remis le DISENT ; l\'échographie, non',
        (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-irm');
      expect(find.textContaining('Examens et variables proposés, à valider'),
          findsOneWidget);
      expect(find.textContaining('Aucun modèle de compte rendu de irm'),
          findsOneWidget);
      await ouvrir(t, magasin(), 'm2-imagerie');
      expect(
          find.textContaining('Examens et variables proposés'), findsNothing);
      expect(find.textContaining('brouillon manuscrit de l’échographiste'),
          findsOneWidget);
    });

    cas('un tableau ne montre que les comptes rendus de la modalité de SON examen',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm2-imagerie-mammographie');
      final refs = {
        for (final w
            in t.widgetList<Text>(find.textContaining(RegExp(r'^IMG-\d{4}$'))))
          w.data!
      };
      final ex = m.collection('examensImagerie').actives;
      final mam = m.collection('resultatsImagerie').actives.where((r) =>
          ex.firstWhere((e) => e['code'] == r['examenCode'])['modalite'] ==
          'mammographie');
      expect(refs, {for (final r in mam) r['reference']});
    });
  });

  group('les gestes de ligne', () {
    cas('les commandes d\'une ligne : imprimer et consulter toujours ; saisie et rendu seulement sur un brouillon ; « Modifier » absent (E121)',
        (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-irm');
      expect(find.byTooltip('Imprimer le compte rendu'), findsWidgets);
      expect(find.byTooltip('Consulter'), findsWidgets);
      expect(find.byTooltip('Archiver'), findsWidgets);
      // Le tableau IRM porte 2 brouillons sur 13 : la saisie et le rendu n'existent que pour eux.
      expect(find.byTooltip('Poursuivre la saisie'), findsNWidgets(2));
      expect(find.byTooltip('Rendre au prescripteur'), findsNWidgets(2));
      expect(find.byTooltip('Modifier'), findsNothing);
    });

    cas('Consulter ouvre le tiroir : grille, résultats par rubrique, rubriques rédigées',
        (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.byTooltip('Consulter').first);
      expect(find.text('IMG-0156 — IRM du rachis lombaire'), findsOneWidget);
      expect(find.text('SOUMANOU Awaou — CNT/1109/26'), findsNWidgets(2),
          reason: 'la ligne et le tiroir');
      expect(find.text('Résultats'), findsOneWidget);
      expect(find.text('Contre-indications vérifiées'), findsOneWidget);
      expect(find.text('T2, FLAIR'), findsOneWidget);
      expect(find.text('En rédaction'), findsWidgets);
    });

    cas('Imprimer édite la pièce sans rien écrire', (t) async {
      final m = magasin();
      final avant = m.collection('resultatsImagerie').toutes.length;
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.byTooltip('Imprimer le compte rendu').first);
      await t.pump(const Duration(milliseconds: 600));
      expect(m.collection('resultatsImagerie').toutes.length, avant);
    });

    cas('Rendre sans conclusion : refusé en le disant, rien n\'est écrit',
        (t) async {
      final m = magasin();
      final r = brouillon(m, 'irm');
      m
          .collection('resultatsImagerie')
          .mettreAJour(r['id'], {'conclusion': ''});
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.byTooltip('Rendre au prescripteur').first);
      expect(
          find.text(
              'La conclusion est obligatoire avant de rendre le compte rendu.'),
          findsOneWidget);
      expect(
          find.text('Rendre le compte rendu au prescripteur ?'), findsNothing);
      expect(m.collection('resultatsImagerie').parId(r['id'])!['statut'],
          isNot('rendu'));
    });

    cas('Rendre avec conclusion : confirmation, « rendu », demande « validée », poste de consultation avisé, et annulation du message impossible à confondre',
        (t) async {
      final m = magasin();
      // Les deux brouillons IRM : on rend celui que la ligne propose en premier (tri du registre).
      final avantNotifs = m.collection('notifications').toutes.length;
      final r = brouillon(m, 'irm');
      final dem =
          m.collection('demandesImagerie').parId(r['demandeImagerieId'])!;
      m
          .collection('demandesImagerie')
          .mettreAJour(dem['id'], {'statut': 'executee'});
      m
          .collection('resultatsImagerie')
          .mettreAJour(r['id'], {'conclusion': 'Pas d’anomalie.'});
      await ouvrir(t, m, 'm2-imagerie-irm');
      // Les deux brouillons ont une conclusion : on rend la ligne de r en la cherchant par sa référence.
      await t.enterText(find.byType(TextField).first, '${r['reference']}');
      await t.pump(const Duration(milliseconds: 500));
      await toucher(t, find.byTooltip('Rendre au prescripteur').first);
      expect(find.text('Rendre le compte rendu au prescripteur ?'),
          findsOneWidget);
      expect(
          find.textContaining(
              '${r['reference']} sera transmis à ${r['prescripteur']}'),
          findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rendre'));
      final apres = m.collection('resultatsImagerie').parId(r['id'])!;
      expect(apres['statut'], 'rendu');
      expect(apres['renduLe'], isNotNull);
      expect(m.collection('demandesImagerie').parId(dem['id'])!['statut'],
          'validee');
      final notifs = m.collection('notifications').toutes;
      expect(notifs.length, avantNotifs + 1);
      expect(notifs.first['type'], 'imagerie_rendue');
      expect(notifs.first['poste'], 'consultation');
      expect(notifs.first['reference'], r['reference']);
      expect(find.text('Compte rendu rendu au prescripteur.'), findsOneWidget);
      // Rendu : la ligne n'offre plus la saisie ni le rendu.
      expect(find.byTooltip('Rendre au prescripteur'), findsNothing);
    });

    cas('Archiver demande un motif, archive (RG-14) et s\'annule', (t) async {
      final m = magasin();
      final avant = m.collection('resultatsImagerie').actives.length;
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.byTooltip('Archiver').first);
      expect(find.text('Archiver cet enregistrement ?'), findsOneWidget);
      // Sans motif : refusé.
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(find.text('Le motif est obligatoire.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
      expect(m.collection('resultatsImagerie').actives.length, avant - 1);
      expect(m.collection('resultatsImagerie').archivees.length, 1);
      expect(
          m.collection('resultatsImagerie').archivees.single['_motifArchivage'],
          'Doublon');
      await toucher(t, find.text('Annuler').last);
      expect(m.collection('resultatsImagerie').actives.length, avant);
      expect(find.text('Archivage annulé.'), findsOneWidget);
    });
  });

  group('nouveau compte rendu : l\'en-tête en modale, la rédaction en page',
      () {
    cas('l\'en-tête manquant est refusé ; valide, il ouvre la page SANS rien écrire',
        (t) async {
      final m = magasin();
      final avant = m.collection('resultatsImagerie').toutes.length;
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.text('Nouveau compte rendu'));
      expect(
          find.text(
              'Nouveau compte rendu — IRM — imagerie par résonance magnétique'),
          findsOneWidget);
      for (final l in [
        'Examen *',
        'Patient *',
        'Indication *',
        'Prescripteur *',
        'Réalisé par *',
        'Provenance',
        'Condition de l’examen'
      ]) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      // La DDR est une donnée d'échographie : absente ici.
      expect(find.textContaining('DDR'), findsNothing);
      // Le prescripteur extérieur n'ouvre son champ que choisi.
      expect(find.textContaining('Prescripteur extérieur — nom'), findsNothing);
      await toucher(
          t, find.widgetWithText(BoutonSigh, 'Continuer vers la saisie'));
      expect(find.text('L’en-tête comporte des erreurs.'), findsOneWidget);
      expect(
          find.text(
              'Nouveau compte rendu — IRM — imagerie par résonance magnétique'),
          findsOneWidget,
          reason: 'la modale reste ouverte');

      final patient = m
          .collection('patients')
          .actives
          .firstWhere((p) => p['code'] == 'CNT/1/25');
      await choisir(t, 'examenCode', 'IRM du genou');
      await choisir(t, 'patientCode',
          '${patient['code']} — ${patient['nom']} ${patient['prenom']}');
      await saisir(t, 'indication', 'Entorse');
      await choisir(
          t, 'prescripteurId', '— Prescripteur extérieur à la clinique —');
      expect(
          find.textContaining('Prescripteur extérieur — nom'), findsOneWidget);
      await saisir(
          t, 'prescripteurIdExterne', 'Dr SALIFOU Aminou, CS de Perma');
      await choisir(t, 'realisateurId', 'AHOHOU Rodrigue — Échographiste');
      await toucher(
          t, find.widgetWithText(BoutonSigh, 'Continuer vers la saisie'));
      await t.pump(const Duration(milliseconds: 400));

      // La page : l'en-tête rappelé en LECTURE, les rubriques de l'examen, rien d'écrit.
      expect(find.text('Compte rendu d’imagerie'), findsWidgets);
      expect(
          find.text(
              'Nouveau compte rendu — IRM — imagerie par résonance magnétique'),
          findsOneWidget);
      expect(find.text('Dr SALIFOU Aminou, CS de Perma (extérieur)'),
          findsOneWidget);
      expect(find.text('IRM du genou'), findsOneWidget);
      expect(find.text('Ménisques'), findsOneWidget);
      expect(find.text('Conclusion'), findsOneWidget);
      expect(find.textContaining('Rien n’est encore écrit au registre'),
          findsOneWidget);
      expect(m.collection('resultatsImagerie').toutes.length, avant);
    });

    cas('l\'enregistrement fait NAÎTRE la fiche — IMG-0157, le rang suivant du registre (E120) — et ramène au tableau',
        (t) async {
      final m = magasin();
      final avant = m.collection('resultatsImagerie').toutes.length;
      await ouvrir(t, m, 'm2-imagerie-irm');
      await toucher(t, find.text('Nouveau compte rendu'));
      final patient = m
          .collection('patients')
          .actives
          .firstWhere((p) => p['code'] == 'CNT/1/25');
      await choisir(t, 'examenCode', 'IRM du genou');
      await choisir(t, 'patientCode',
          '${patient['code']} — ${patient['nom']} ${patient['prenom']}');
      await saisir(t, 'indication', 'Entorse');
      await choisir(
          t, 'prescripteurId', '— Prescripteur extérieur à la clinique —');
      await saisir(
          t, 'prescripteurIdExterne', 'Dr SALIFOU Aminou, CS de Perma');
      await choisir(t, 'realisateurId', 'AHOHOU Rodrigue — Échographiste');
      await saisir(t, 'provenance', 'CS de Perma');
      await toucher(
          t, find.widgetWithText(BoutonSigh, 'Continuer vers la saisie'));
      await t.pump(const Duration(milliseconds: 400));

      // Sans conclusion (obligatoire pour la radiologie) : refusé, aucune fiche.
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Enregistrer le compte rendu').last);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('resultatsImagerie').toutes.length, avant);

      await saisir(t, 'conclusion', 'Lésion méniscale.');
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Enregistrer le compte rendu').last);
      expect(m.collection('resultatsImagerie').toutes.length, avant + 1);
      final n = m.collection('resultatsImagerie').toutes.first;
      expect(n['reference'], 'IMG-0157');
      expect(n['statut'], 'brouillon');
      expect(n['examenCode'], 'IMG-IRM-GEN');
      expect(n['examen'], 'IRM du genou');
      expect(n['patientCode'], 'CNT/1/25');
      expect(n['patient'], '${patient['nom']} ${patient['prenom']}');
      expect(n['prescripteur'], 'Dr SALIFOU Aminou, CS de Perma (extérieur)');
      expect(n['prescripteurId'], isNull);
      expect(n['realisateur'], 'AHOHOU Rodrigue');
      expect(n['provenance'], 'CS de Perma');
      expect(n['conclusion'], 'Lésion méniscale.');
      expect(n['demandeImagerieId'], isNull,
          reason: 'saisie directe : aucune demande liée');
      expect(find.text('Compte rendu enregistré.'), findsOneWidget);
      expect(find.text('Tableau IRM — imagerie par résonance magnétique'),
          findsWidgets);
      expect(find.text('IMG-0157'), findsWidgets);
    });

    cas('une adresse ouverte à froid ne devine pas un patient : elle renvoie au tableau',
        (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-cr');
      expect(find.text('Nouveau compte rendu — Échographie'), findsOneWidget);
      expect(
          find.textContaining(
              'L’en-tête de ce compte rendu n’a pas été relevé'),
          findsOneWidget);
      expect(find.text('Enchaînement du parcours'), findsOneWidget);
      expect(find.text('Règles de saisie'), findsOneWidget);
      expect(find.text('Revenir au tableau'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Enregistrer le compte rendu'), findsWidgets);
    });
  });

  group('poursuivre la saisie d\'un brouillon', () {
    cas('la page rappelle l\'examen en lecture ; l\'enregistrement met la fiche à jour et exécute la demande payée',
        (t) async {
      final m = magasin();
      final r = brouillon(m, 'radiographie');
      final dem =
          m.collection('demandesImagerie').parId(r['demandeImagerieId'])!;
      m
          .collection('demandesImagerie')
          .mettreAJour(dem['id'], {'statut': 'payee'});
      final avant = m.collection('resultatsImagerie').toutes.length;
      await ouvrir(t, m, 'm2-imagerie-radiographie');
      await t.enterText(find.byType(TextField).first, '${r['reference']}');
      await t.pump(const Duration(milliseconds: 500));
      await toucher(t, find.byTooltip('Poursuivre la saisie').first);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Examen'), findsWidgets);
      expect(find.text('${r['reference']}'), findsOneWidget);
      for (final lib in [
        'Résultats — description rédigée',
        'Conclusion',
        'Recommandation'
      ]) {
        expect(find.text(lib), findsWidgets, reason: lib);
      }
      await saisir(t, 'resultats', 'Pas de lésion osseuse.');
      await saisir(t, 'conclusion', 'Examen normal.');
      await saisir(t, 'recommandation', 'Contrôle si douleur.');
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Enregistrer le compte rendu').last);
      final apres = m.collection('resultatsImagerie').parId(r['id'])!;
      expect(apres['conclusion'], 'Examen normal.');
      expect(apres['resultats'], 'Pas de lésion osseuse.');
      expect(apres['recommandation'], 'Contrôle si douleur.');
      // Les rubriques rédigées ne sont pas rangées parmi les valeurs.
      expect((apres['valeurs'] as Map).containsKey('conclusion'), isFalse);
      expect(m.collection('demandesImagerie').parId(dem['id'])!['statut'],
          'executee');
      expect(m.collection('resultatsImagerie').toutes.length, avant,
          reason: 'aucune fiche créée');
      expect(find.text('Compte rendu enregistré.'), findsOneWidget);
      // Retour au tableau de la modalité.
      expect(find.text('Tableau Radiographie'), findsWidgets);
      expect(find.text('Nouveau compte rendu'), findsOneWidget);
    });

    cas('sans conclusion, une radiographie n\'est PAS enregistrée (rubrique obligatoire)',
        (t) async {
      final m = magasin();
      final r = brouillon(m, 'radiographie');
      m
          .collection('resultatsImagerie')
          .mettreAJour(r['id'], {'conclusion': ''});
      await ouvrir(t, m, 'm2-imagerie-radiographie');
      await t.enterText(find.byType(TextField).first, '${r['reference']}');
      await t.pump(const Duration(milliseconds: 500));
      await toucher(t, find.byTooltip('Poursuivre la saisie').first);
      await t.pump(const Duration(milliseconds: 400));
      await saisir(t, 'resultats', 'x');
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Enregistrer le compte rendu').last);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(m.collection('resultatsImagerie').parId(r['id'])!['resultats'],
          isNot('x'));
    });

    cas('le nombre de sacs déclaré fait paraître les blocs n°2 et n°3 ; une valeur retirée ne s\'enregistre pas',
        (t) async {
      final m = magasin();
      final fiche = m.collection('resultatsImagerie').inserer({
        'reference': 'IMG-9999',
        'date': '2026-10-30T10:00:00.000Z',
        'examenCode': 'IMG-ECHO-OBS1',
        'examen': 'Échographie obstétricale du 1er trimestre',
        'patient': 'TEST',
        'patientCode': 'CNT/0/26',
        'prescripteur': 'P',
        'realisateur': 'R',
        'valeurs': <String, Object?>{},
        'conclusion': 'ok',
        'statut': 'brouillon'
      }, prefixe: 'IMG').fiche;
      await ouvrir(t, m, 'm2-imagerie');
      await t.enterText(find.byType(TextField).first, 'IMG-9999');
      await t.pump(const Duration(milliseconds: 500));
      await toucher(t, find.byTooltip('Poursuivre la saisie').first);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Sac gestationnel n°2'), findsNothing);
      await choisir(t, 'SG_NB', '02');
      expect(find.text('Sac gestationnel n°2'), findsOneWidget);
      expect(find.text('Sac gestationnel n°3'), findsNothing);
      await choisir(t, 'SG_NB', '03');
      expect(find.text('Sac gestationnel n°3'), findsOneWidget);
      await saisir(t, 'SG_DIM__2', '8 mm');
      // « Autre » ouvre sa précision ; revenir en arrière la retire.
      await choisir(t, 'SG_LOC', 'Autre');
      expect(champ('SG_LOC_AUTRE'), findsOneWidget);
      await saisir(t, 'SG_LOC_AUTRE', 'tubaire');
      await choisir(t, 'SG_LOC', 'intra-utérine');
      expect(champ('SG_LOC_AUTRE'), findsNothing);
      await choisir(t, 'SG_NB', '01');
      expect(find.text('Sac gestationnel n°2'), findsNothing);
      await toucher(t,
          find.widgetWithText(BoutonSigh, 'Enregistrer le compte rendu').last);
      final v = (m
          .collection('resultatsImagerie')
          .parId(fiche['id'])!['valeurs'] as Map);
      expect(v['SG_NB'], '01');
      expect(v['SG_LOC'], 'intra-utérine');
      expect(v.containsKey('SG_LOC_AUTRE'), isFalse,
          reason: 'une précision masquée ne s\'enregistre pas');
      expect(v.containsKey('SG_DIM__2'), isFalse,
          reason: 'un bloc non déclaré ne s\'enregistre pas');
    });
  });

  group('droits', () {
    cas('un profil sans droit sur le module n\'ouvre pas le tableau (la coque refuse)',
        (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-irm', role: 'caissier');
      expect(find.text('Nouveau compte rendu'), findsNothing);
      expect(find.text('Comptes rendus'), findsNothing);
    });

    cas('l\'échographiste exécute : il saisit et rend', (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-irm', role: 'echographiste');
      expect(find.text('Nouveau compte rendu'), findsOneWidget);
      expect(find.byTooltip('Poursuivre la saisie'), findsWidgets);
    });

    cas('un profil en lecture seule consulte sans commande d\'écriture et la page de saisie le dit',
        (t) async {
      await ouvrir(t, magasin(), 'm2-imagerie-irm', role: 'chirurgien');
      expect(find.text('Comptes rendus'), findsOneWidget);
      expect(find.text('Nouveau compte rendu'), findsNothing);
      expect(find.byTooltip('Poursuivre la saisie'), findsNothing);
      expect(find.byTooltip('Rendre au prescripteur'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
      // La page de saisie : « direction » lit le registre ET la page (le rbac.json livré porte pour le chirurgien et l'échographiste des droits de page
      // qui ne résolvent pas `servant` — écart E122, signalé : on ne les verrouille pas ici).
      await ouvrir(t, magasin(), 'm2-imagerie-cr', role: 'direction');
      expect(
          find.text(
              'Votre profil consulte les comptes rendus sans les saisir.'),
          findsOneWidget);
      expect(find.text('Enregistrer le compte rendu'), findsNothing);
    });
  });
}
