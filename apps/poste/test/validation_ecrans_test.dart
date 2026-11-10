import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m13/qual_validations.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LE MOTEUR DE VALIDATION COMMUN AU POSTE (Direction, 07 et 08/11/2026) : le centre des validations lit les familles au magasin (vecteurs tirés de l'écran réel
/// de la maquette, `validation.json › centre`), et chacun des écrans qui portent un artefact à valider offre son bouton « Valider » aux seuls rôles de la famille
/// (ABSENT, jamais grisé, pour tout autre profil qui ouvre pourtant l'écran), un geste valide UN élément (marquage retiré, trois traces, UNE ligne de journal),
/// et modifier un élément validé le remet « à valider ». Les règles du domaine sont rejouées sur les mêmes vecteurs par `packages/domaine/test/validation_test.dart`.
typedef M = Map<String, Object?>;

M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];

final vecteurs = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/validation.json').readAsStringSync()));
final roles = [for (final r in (obj(jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()))['roles'] as List)) '${obj(r)['id']}'];

/// Les boutons Valider affichés (la clé porte famille et identifiant), tous éléments confondus.
Finder boutons(String famille) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('val:valider:$famille:'));

/// Le choix « Valider » du pied de la modale de mise à jour (la clé porte famille et identifiant), distinct des « Valider » du registre.
Finder modaleValider(String famille) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('val:modale:$famille:'));

String sp(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Magasin magasinDe(Map<String, List<M>> collections) => Magasin({
        'audit': const <Fiche>[],
        for (final e in collections.entries) e.key: [for (final f in e.value) {...f}],
      }, 'POSTE', const {});

  group('le centre des validations lit les familles au magasin (vecteurs de l’écran réel)', () {
    for (final c in fl(vecteurs['centre'])) {
      casM14('${c['nom']}', (t) async {
        final entree = obj(c['entree']);
        final m = magasinDe({for (final e in entree.entries) e.key: fl(e.value)});
        await ouvrirM14(t, m, 'adm-validations', role: '${c['role']}');
        // Les cartes, dans l'ordre (les files de poste et les arbitrages dépendent du jeu : seuls leurs titres se comparent).
        final titres = [for (final w in t.widgetList<CarteSigh>(find.byType(CarteSigh))) if (w.titre != null) w.titre!];
        expect(titres, [for (final x in (c['cartes'] as List)) '$x'], reason: 'cartes');
        // Les indicateurs des familles : comptes relus au magasin.
        final kpis = {for (final k in t.widgetList<KpiSigh>(find.byType(KpiSigh))) k.libelle: k.valeur};
        for (final k in fl(c['kpis'])) {
          final l = '${k['label']}';
          if (l == 'Référentiels en attente de validation' || l == 'Familles concernées') {
            expect(sp(kpis[l]), sp(k['valeur']), reason: l);
          } else {
            expect(kpis.containsKey(l), isTrue, reason: 'indicateur « $l » présent');
          }
        }
        // Une ligne par famille visible : compte lu, « sur N », mention d'amorçage, et aucune commande d'écriture.
        final familles = fl(c['familles']);
        expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('val:famille:')), findsNWidgets(familles.length));
        for (final f in familles) {
          expect(find.byKey(Key('val:famille:${f['famille']}')), findsOneWidget, reason: '${f['famille']}');
          final attendu = '${f['enAttente']}';
          final lu = t.widget<Text>(find.byKey(Key('val:en-attente:${f['famille']}'))).data;
          expect(lu, attendu.isEmpty ? '—' : attendu, reason: 'compte de ${f['famille']}');
        }
        final lignes = find.byKey(Key('val:famille:${familles.first['famille']}'));
        expect(find.descendant(of: lignes, matching: find.textContaining('Valide : ')), findsOneWidget);
        final ecriture = [
          for (final b in t.widgetList<BoutonSigh>(find.descendant(of: find.byType(EcranValidations), matching: find.byType(BoutonSigh))))
            if (b.libelle != 'Y aller' && b.libelle != 'Ouvrir') b.libelle
        ];
        expect(ecriture, isEmpty, reason: 'le centre oriente, il ne valide jamais en masse : aucune commande d’écriture');
      });
    }

    casM14('un profil dont aucune famille ne relève : la phrase le dit', (t) async {
      final m = magasinDe(const {});
      await ouvrirM14(t, m, 'adm-validations', role: 'agentadmin');
      // L'agent administratif voit l'écran en profil « élargi » : aucune famille ne relève de lui.
      expect(find.text('Aucun référentiel en attente de validation ne relève de votre profil.'), findsOneWidget);
    });
  });

  /// Chaque écran : (famille, écran, collections dont tous les éléments sont posés « à valider », onglet à ouvrir).
  final ecrans = <({String famille, String ecran, String col, String? onglet, M posee})>[
    (famille: 'enquetes', ecran: 'adm-enquetes', col: 'enquetes', onglet: null, posee: {'aValider': true}),
    (famille: 'labo_variables', ecran: 'm5-valeurs-reference', col: 'variablesLabo', onglet: null, posee: {'aValider': true}),
    (famille: 'labo_variables', ecran: 'm5-unites', col: 'unitesLabo', onglet: null, posee: {'aValider': true}),
    (famille: 'pathologies', ecran: 'm2-pathologies', col: 'pathologies', onglet: 'referentiel', posee: {'aValider': true}),
    (famille: 'imagerie', ecran: 'cfg-imagerie-catalogue', col: 'examensImagerie', onglet: null, posee: {'aValider': true}),
    (famille: 'imagerie', ecran: 'cfg-imagerie-catalogue', col: 'variablesImagerie', onglet: 'variables', posee: {'aValider': true}),
    (famille: 'actes', ecran: 'cfg-tarifs', col: 'actes', onglet: 'actes', posee: {'tarifProvisoire': true, 'prix': 1000}),
    (famille: 'analyses', ecran: 'cfg-tarifs', col: 'analyses', onglet: 'analyses', posee: {'tarifProvisoire': true, 'prix': 1000}),
    (famille: 'objectifs_pilotage', ecran: 'm12-tableau-decisionnel', col: 'objectifsPilotage', onglet: 'objectifs', posee: {'aValider': true}),
    (famille: 'modeles_badge', ecran: 'm10-badges-modeles', col: 'modelesBadge', onglet: null, posee: {'aValider': true}),
    (famille: 'modeles_messages', ecran: 'cfg-rappels', col: 'modelesMessage', onglet: 'modeles', posee: {'aValider': true}),
  ];

  group('un bouton Valider par écran : visible aux rôles de la famille, absent aux autres, un geste = un élément', () {
    for (final e in ecrans) {
      casM14('${e.famille} / ${e.ecran} (${e.col})', (t) async {
        final famille = valFamille(e.famille)!;
        final m = magasinM14();
        final col = m.collection(e.col);
        expect(col.actives, isNotEmpty, reason: 'le jeu porte des fiches ${e.col}');
        for (final f in col.actives) {
          col.mettreAJour(f['id'], {...e.posee, 'valideLe': null, 'validePar': null, 'valideRole': null}, journaliser: false);
        }
        Future<void> ouvrirOnglet() async {
          if (e.onglet == null) return;
          final onglet = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:${e.onglet}'));
          await toucherM14(t, onglet.first);
        }

        // Un rôle HORS famille qui ouvre pourtant l'écran : aucun bouton Valider, ni grisé.
        final autre = roles.where((r) => !famille.roles.contains(r) && donneesNav.matrice.droit(r, e.ecran).voir && !donneesNav.matrice.estArchive(r)).firstOrNull;
        // Un écran que nul profil hors famille n'ouvre ne peut porter de bouton chez un tiers : absence de fait, dite par le test.
        if (autre != null) {
          await ouvrirM14(t, m, e.ecran, role: autre);
          await ouvrirOnglet();
          expect(boutons(e.famille), findsNothing, reason: 'rôle « $autre » hors famille : commande ABSENTE');
        }

        // Un rôle de la famille : le bouton existe ; le clic valide UN élément.
        final role = famille.roles.firstWhere((r) => donneesNav.matrice.droit(r, e.ecran).voir, orElse: () => 'admin');
        await ouvrirM14(t, m, e.ecran, role: role);
        await ouvrirOnglet();
        final b = boutons(e.famille);
        expect(b, findsWidgets, reason: 'rôle « $role » de la famille : le bouton Valider est offert');
        final cle = (t.widget(b.first).key as ValueKey<String>).value;
        final id = cle.split(':').last;
        final avantJournal = m.collection('audit').toutes.length;
        final avantMarques = col.actives.where((f) => f['aValider'] == true || f['tarifProvisoire'] == true).length;
        await toucherM14(t, b.first);
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
        final f = col.parId(id)!;
        expect([f['aValider'] == true, f['tarifProvisoire'] == true], [false, false], reason: 'marquage retiré');
        expect(f['valideLe'], isNotNull);
        expect(f['validePar'], isNotEmpty);
        expect(f['valideRole'], isNotEmpty);
        expect(col.actives.where((x) => x['aValider'] == true || x['tarifProvisoire'] == true).length, avantMarques - 1, reason: 'UN seul élément validé');
        expect(m.collection('audit').toutes.length, avantJournal + 1, reason: 'UNE ligne de journal (RG-12)');
        final j = m.collection('audit').toutes.first;
        expect([j['action'], j['reference']], ['Validation', id]);
      });
    }

    casM14('les pièces du code : check-listes du bloc, répartition des charges, barème de l’ITS, jeu d’import (fiche VRF-<cible>)', (t) async {
      final cas = [
        (famille: 'checklists_bloc', ecran: 'm3-bloc-checklist', cible: 'checklist-bloc'),
        (famille: 'repartition_charges', ecran: 'm12-seuil-rentabilite', cible: 'repartition-fixe-variable'),
        (famille: 'bareme_its', ecran: 'cfg-comptabilite', cible: 'bareme-its'),
        (famille: 'jeux_import', ecran: 'imp-analyses', cible: 'imp-analyses'),
      ];
      for (final c in cas) {
        final famille = valFamille(c.famille)!;
        final m = magasinM14();
        m.collection(valCollectionValidations).remplacerContenu(const []);
        final autre = roles.where((r) => !famille.roles.contains(r) && donneesNav.matrice.droit(r, c.ecran).voir && !donneesNav.matrice.estArchive(r)).firstOrNull;
        if (autre != null) {
          await ouvrirM14(t, m, c.ecran, role: autre);
          expect(boutons(c.famille), findsNothing, reason: '${c.famille} : rôle « $autre » hors famille');
        }
        final role = famille.roles.firstWhere((r) => donneesNav.matrice.droit(r, c.ecran).voir, orElse: () => 'admin');
        await ouvrirM14(t, m, c.ecran, role: role);
        expect(find.byKey(Key('val:valider:${c.famille}:${c.cible}')), findsOneWidget, reason: '${c.famille} : le bouton de la pièce');
        final avant = m.collection('audit').toutes.length;
        await toucherM14(t, find.byKey(Key('val:valider:${c.famille}:${c.cible}')));
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
        final fiche = m.collection(valCollectionValidations).actives.where((f) => f['id'] == 'VRF-${c.cible}').firstOrNull;
        expect(fiche, isNotNull, reason: '${c.famille} : la fiche VRF-<cible> naît');
        expect(fiche!['valideLe'], isNotNull);
        expect(m.collection('audit').toutes.length, avant + 1, reason: '${c.famille} : UNE ligne de journal');
        expect(find.byKey(Key('val:valider:${c.famille}:${c.cible}')), findsNothing, reason: 'validée : plus de bouton');
        expect(find.byKey(Key('val:badge:${c.famille}:${c.cible}')), findsOneWidget);
        await t.pump(const Duration(seconds: 10));
      }
    });
  });

  group('enregistrer valide pour le profil de la famille, remet « à valider » hors famille (lot L1, 09/11/2026)', () {
    M validee() => {'aValider': false, 'valideLe': '2026-09-01', 'validePar': 'Dr X', 'valideRole': 'Directeur Médical'};

    Future<void> ouvrirPathologies(dynamic t, Magasin m, String role) async {
      await ouvrirM14(t, m, 'm2-pathologies', role: role);
      await toucherM14(t, find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:referentiel')).first);
    }

    casM14('profil de la famille (dm) : enregistrer un élément validé le LAISSE validé, UNE ligne « Modification » portant l’état', (t) async {
      final m = magasinM14();
      final col = m.collection('pathologies');
      for (final f in col.actives) {
        col.mettreAJour(f['id'], validee(), journaliser: false);
      }
      final avant = m.collection('audit').toutes.length;
      await ouvrirPathologies(t, m, 'dm');
      await toucherM14(t, find.byTooltip('Modifier').first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(col.actives.where((f) => f['aValider'] == true), isEmpty, reason: 'aucune pathologie ne repasse « à valider »');
      expect(m.collection('audit').toutes.length, avant + 1, reason: 'UNE ligne de journal (RG-12)');
      final j = m.collection('audit').toutes.first;
      expect(j['action'], 'Modification');
      expect('${j['apres']}', contains('validé'));
    });

    casM14('profil de la famille (dm) : enregistrer un élément « à valider » le VALIDE (trois traces), action « Validation »', (t) async {
      final m = magasinM14();
      final col = m.collection('pathologies');
      for (final f in col.actives) {
        col.mettreAJour(f['id'], {'aValider': true, 'valideLe': null, 'validePar': null, 'valideRole': null}, journaliser: false);
      }
      final avant = m.collection('audit').toutes.length;
      await ouvrirPathologies(t, m, 'dm');
      await toucherM14(t, find.byTooltip('Modifier').first);
      // Le registre porte lui aussi un « Valider » par ligne en attente (clé `val:valider:…`) : le choix du PIED DE MODALE se désigne par sa propre clé (`val:modale:…`).
      expect(modaleValider('pathologies'), findsOneWidget, reason: 'le choix Valider du pied de modale (profil de la famille, élément en attente)');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final validees = col.actives.where((f) => f['aValider'] == false && f['valideLe'] != null).toList();
      expect(validees.length, 1, reason: 'UNE pathologie est validée par l’enregistrement');
      expect(validees.first['validePar'], isNotEmpty);
      expect(m.collection('audit').toutes.length, avant + 1, reason: 'UNE ligne de journal');
      expect(m.collection('audit').toutes.first['action'], 'Validation');
    });

    casM14('hors famille (admin) : pas de choix Valider dans la modale ; enregistrer remet l’élément validé « à valider », UNE ligne « Remise à valider »', (t) async {
      final m = magasinM14();
      final col = m.collection('pathologies');
      for (final f in col.actives) {
        col.mettreAJour(f['id'], validee(), journaliser: false);
      }
      await ouvrirPathologies(t, m, 'admin');
      await toucherM14(t, find.byTooltip('Modifier').first);
      expect(modaleValider('pathologies'), findsNothing, reason: 'commande ABSENTE hors famille, jamais grisée');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(col.actives.where((f) => f['aValider'] == true).length, 1, reason: 'UNE pathologie est revenue « à valider »');
      expect(col.actives.where((f) => f['aValider'] == true).first['valideLe'], isNull);
      expect(m.collection('audit').toutes.where((x) => x['action'] == 'Remise à valider').length, 1);
    });
  });
}
