import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/organigramme_poste.dart';
import 'package:sigh_poste/donnees/verrou_secours_poste.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT ORG2 (Direction, 11/11/2026) AU POSTE : l'organigramme qui suit la photo sans être figé (réaffecter, renommer le titulaire, poser le titre de l'agent, archiver,
/// reprise qui épargne ce que la clinique a modifié, impression A4 paysage sans étoile), le verrou d'un poste de secours (5 minutes à valider, réglage en base, administrateur
/// et DAF seuls) et la garde soins comptée dans « Mes statistiques de garde ». Les règles sont rejouées sur les vecteurs de la maquette par packages/domaine/test/organigramme_test.dart ;
/// ici, le GESTE dans l'écran, ce qui s'écrit au magasin (journal, trace d'écran) et ce qui s'imprime.
typedef M = Map<String, Object?>;
List<M> fl(Object? v) => [for (final x in (v as List)) (x as Map).cast<String, Object?>()];
List<M> jeu(String nom) => fl(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  OrganigrammePoste org(Magasin m, {bool editer = true, bool annuler = true}) => OrganigrammePoste(m,
      droitEditer: editer,
      droitAnnuler: annuler,
      rolesConnus: {for (final r in jeu('rolesBase')) '${r['id']}'}..addAll({'admin', 'da', 'dm', 'medecin', 'infirmier', 'agentadmin', 'comptable', 'stock', 'pharmacien', 'laborantin', 'reception', 'ambulancier', 'aide_soignant'}),
      maintenant: () => aujourdhui,
      auteur: () => 'Sonde ORG2');

  M poste(Magasin m, String id) => m.collection('postes').parId(id)!;
  M audit(Magasin m) => m.collection('audit').toutes.first;

  group('le moteur du poste : un plan appliqué, journalisé, annulable', () {
    test('la semence de la photo : six intitulés, hiérarchie, titre porté par l\'agent', () {
      final m = magasinM14();
      final noms = [for (final p in m.collection('postes').actives) p['poste']];
      for (final x in ['Directrice Administrative (DA)', 'Echographiste', 'Aide-Soignante', 'Agents de Sécurités', 'Agents d’Entretiens', 'Assistant comptable']) {
        expect(noms, contains(x));
      }
      expect(poste(m, 'PST004')['parentId'], 'PST003');
      expect(poste(m, 'PST005')['parentId'], 'PST004');
      expect(poste(m, 'PST015')['parentId'], 'PST014');
      expect(poste(m, 'PST010')['parentId'], 'PST006');
      expect(m.collection('postes').toutes.any((p) => p.containsKey('etoile')), isFalse);
      final garba = m.collection('personnel').actives.firstWhere((a) => a['nomComplet'] == 'GARBA Yahouza');
      expect(garba['titreOrganigramme'], 'SG');
      expect(poste(m, 'PST014')['chef'], isFalse, reason: 'le surveillant général est un infirmier : le titre est porté par l\'agent, pas par `chef`');
      final arbre = org(m).arbre();
      OrgNoeud trouver(List<OrgNoeud> l, String id) {
        for (final n in l) {
          if (n.id == id) return n;
          final e = trouver(n.enfants, id);
          if (e.id == id) return e;
        }
        return OrgNoeud({'id': ''}, null);
      }

      expect(trouver(arbre, 'PST014').titreAgent, 'SG');
    });

    test('réaffecter : le poste change de parent, le journal nomme les deux rattachements, la trace d\'écran est posée, et « annuler » rend tout', () {
      final m = magasinM14();
      final o = org(m);
      final r = o.reaffecter('PST015', 'PST001');
      expect(r.refus, isNull);
      expect(poste(m, 'PST015')['parentId'], 'PST001');
      expect(poste(m, 'PST015')['_modifieLe'], isNotNull, reason: 'la reprise lit cette trace pour ne jamais réécrire un poste modifié');
      expect(poste(m, 'PST015')['_modifiePar'], 'Sonde ORG2');
      final a = audit(m);
      expect(a['action'], 'Réaffectation d’un poste');
      expect((a['avant'] as Map)['parentId'], 'Infirmiers');
      expect((a['apres'] as Map)['parentId'], 'Directeur Médical');
      r.annuler!();
      expect(poste(m, 'PST015')['parentId'], 'PST014');
      expect(poste(m, 'PST015').containsKey('_modifieLe'), isFalse, reason: 'annulé : le poste redevient intact');
    });

    test('renommer le titulaire, poser puis retirer le titre de l\'agent (porté par la fiche du personnel, journalisé sur sa ligne)', () {
      final m = magasinM14();
      final o = org(m);
      expect(o.renommerTitulaire('PST013', 'NOUVEAU Titulaire').refus, isNull);
      expect(poste(m, 'PST013')['titulaire'], 'NOUVEAU Titulaire');
      expect(audit(m)['action'], 'Changement de titulaire d’un poste');
      final r = o.poserTitre('PST012', 'ECH');
      expect(r.refus, isNull);
      final ahohou = m.collection('personnel').actives.firstWhere((a) => a['nomComplet'] == 'AHOHOU Rodrigue');
      expect(ahohou['titreOrganigramme'], 'ECH');
      expect(poste(m, 'PST012').containsKey('titreAgent'), isFalse, reason: 'le titre n\'est jamais écrit sur le poste');
      expect(audit(m)['action'], 'Titre d’un agent dans l’organigramme');
      expect(o.titreDe(poste(m, 'PST012')), 'ECH');
      expect(o.poserTitre('PST012', '').refus, isNull);
      expect(o.titreDe(poste(m, 'PST012')), isNull);
      r.annuler!();
      expect(ahohou.containsKey('titreOrganigramme'), isFalse, reason: 'l\'annulation du geste restitue l\'état d\'AVANT : aucun titre n\'avait été posé');
      expect(o.titreDe(poste(m, 'PST012')), isNull);
    });

    test('refus nommés : cycle, parent archivé, poste qui porte des postes, agent introuvable, poste vacant, droit ; rien n\'est écrit', () {
      final m = magasinM14();
      final o = org(m);
      final avant = jsonEncode(m.collection('postes').toutes);
      final nAudit = m.collection('audit').toutes.length;
      expect(o.reaffecter('PST002', 'PST004').refus!.code, 'RATTACHEMENT_CYCLE');
      expect(o.reaffecter('PST002', 'PST002').refus!.code, 'RATTACHEMENT_CYCLE');
      expect(o.archiver('PST014').refus!.code, 'POSTE_PORTE_DES_POSTES');
      expect(o.archiver('PST014').refus!.motif, contains('Aide-Soignante'));
      expect(o.poserTitre('PST013', 'XX').refus!.code, 'AGENT_INTROUVABLE');
      expect(o.poserTitre('PST015', 'SF').refus!.code, 'POSTE_VACANT');
      expect(o.poserTitre('PST012', 'TITRE BEAUCOUP TROP LONG').refus!.code, 'TITRE_TROP_LONG');
      expect(org(m, editer: false).reaffecter('PST015', 'PST001').refus!.code, 'ORGANIGRAMME_RESERVE');
      expect(org(m, annuler: false).archiver('PST015').refus!.code, 'ORGANIGRAMME_RESERVE', reason: 'écrire sans annuler : on ne peut pas archiver (RG-14)');
      expect(jsonEncode(m.collection('postes').toutes), avant);
      expect(m.collection('audit').toutes.length, nAudit, reason: 'un refus n\'écrit pas au journal');
      // Archiver une feuille, puis rattacher à ce poste archivé : refusé.
      final feuille = o.archiver('PST015');
      expect(feuille.refus, isNull);
      expect(poste(m, 'PST015')['statut'], 'archive');
      expect(o.reaffecter('PST013', 'PST015').refus!.code, 'PARENT_ARCHIVE');
    });

    test('création : un sommet sans rattachement, journalisée ; sous un poste archivé refusée', () {
      final m = magasinM14();
      final o = org(m);
      final n = m.collection('postes').toutes.length;
      final r = o.creer({'poste': 'Poste isolé', 'effectif': '2', 'role': 'infirmier', 'parentId': ''});
      expect(r.refus, isNull);
      expect(r.fiche!['parentId'], isNull);
      expect(r.fiche!['effectif'], 2);
      expect(m.collection('postes').toutes.length, n + 1);
      expect(audit(m)['action'], 'Création');
      o.archiver('PST015');
      expect(o.creer({'poste': 'Sous archivé', 'parentId': 'PST015', 'effectif': 1, 'role': 'agentadmin'}).refus!.code, 'PARENT_ARCHIVE');
    });

    test('la reprise : un poste intact est réécrit, un poste modifié ou archivé ne l\'est jamais, un champ étoile est retiré, une seconde passe ne fait rien, une ligne est journalisée', () {
      final m = magasinM14();
      List<M> anciens() => [for (final p in orgPrecedent()) {...p, 'statut': 'actif', 'source': 'Organigramme de la Clinique NASSIERA TOO'}]
        ..[2] = {...orgPrecedent()[2], 'statut': 'actif', '_modifieLe': '2026-11-01T08:00:00.000Z'}
        ..[3] = {...orgPrecedent()[3], 'statut': 'actif', 'effectif': 2}
        ..[4] = {...orgPrecedent()[4], 'statut': 'archive'}
        ..[5] = {...orgPrecedent()[5], 'statut': 'actif', 'etoile': true};
      m.collection('postes').remplacerContenu(anciens());
      final bilan = OrganigrammePoste.reprendre(m);
      expect(bilan.gardes, ['PST003', 'PST004', 'PST005']);
      expect(bilan.etoiles, 1);
      expect(poste(m, 'PST002')['poste'], 'Directrice Administrative (DA)');
      expect(poste(m, 'PST002')['semence'], 2);
      expect(poste(m, 'PST003').containsKey('semence'), isFalse);
      expect(poste(m, 'PST004')['poste'], 'Assistant Comptable', reason: 'effectif changé par la clinique : jamais réécrit');
      expect(poste(m, 'PST004')['effectif'], 2);
      expect(poste(m, 'PST005')['statut'], 'archive');
      expect(poste(m, 'PST006').containsKey('etoile'), isFalse);
      expect(audit(m)['action'], 'Reprise de l’organigramme');
      final n = m.collection('audit').toutes.length;
      final second = OrganigrammePoste.reprendre(m);
      expect(second.reecrits, isEmpty);
      expect(second.etoiles, 0);
      expect(m.collection('audit').toutes.length, n, reason: 'rien à faire : rien au journal');
    });
  });

  group('l\'écran « Organisation & organigramme » : les gestes et l\'impression paysage', () {
    Future<void> ouvrirOrganigramme(WidgetTester t, Magasin m, {String role = 'admin'}) async {
      await ouvrirM14(t, m, 'cfg-organisation', role: role);
      await toucherM14(t, find.text('Organigramme').first);
    }

    int rang(Magasin m, String id) => m.collection('postes').actives.indexWhere((p) => p['id'] == id);

    casM14('l\'arbre porte « (SG) » : le titre de l\'agent s\'affiche avec son titulaire', (t) async {
      final m = magasinM14();
      await ouvrirOrganigramme(t, m);
      expect(find.textContaining('GARBA Yahouza (SG)'), findsWidgets);
      expect(find.textContaining('Aucune étoile n’est tracée'), findsOneWidget);
    });

    casM14('réaffecter AU GESTE : la modale « Modifier », le rattachement, le journal « Réaffectation d’un poste »', (t) async {
      final m = magasinM14();
      await ouvrirOrganigramme(t, m);
      await toucherM14(t, find.byTooltip('Modifier').at(rang(m, 'PST015')));
      // La liste de 17 rattachements : on la FILTRE (le panneau ne construit que les lignes visibles).
      await toucherM14(t, find.descendant(of: find.byKey(const Key('kit:champ:parentId')), matching: find.byType(InkWell)).first);
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byType(TextField).last, 'Directeur');
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.descendant(of: find.byType(InkWell), matching: find.text('Directeur Médical')).last);
      await t.pump(const Duration(milliseconds: 400));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(poste(m, 'PST015')['parentId'], 'PST001');
      expect(audit(m)['action'], 'Réaffectation d’un poste');
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    casM14('renommer le titulaire et poser le titre de l\'agent AU GESTE', (t) async {
      final m = magasinM14();
      await ouvrirOrganigramme(t, m);
      await toucherM14(t, find.byTooltip('Modifier').at(rang(m, 'PST013')));
      await saisir(t, 'titulaire', 'NOUVEAU Titulaire');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(poste(m, 'PST013')['titulaire'], 'NOUVEAU Titulaire');
      await t.pump(const Duration(seconds: 10));
      await toucherM14(t, find.byTooltip('Modifier').at(rang(m, 'PST012')));
      await saisir(t, 'titreAgent', 'ECH');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final ahohou = m.collection('personnel').actives.firstWhere((a) => a['nomComplet'] == 'AHOHOU Rodrigue');
      expect(ahohou['titreOrganigramme'], 'ECH');
      expect(audit(m)['action'], 'Titre d’un agent dans l’organigramme');
    });

    casM14('un refus du moteur se DIT à l\'écran et rien n\'est écrit : archiver la DA, qui porte encore trois postes', (t) async {
      final m = magasinM14();
      await ouvrirOrganigramme(t, m);
      await toucherM14(t, find.byTooltip('Archiver').at(rang(m, 'PST002')));
      await t.enterText(find.byType(TextField).last, 'Sonde ORG2');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('porte encore 3 postes'), findsOneWidget);
      expect(poste(m, 'PST002')['statut'], 'actif');
    });

    casM14('l\'impression est A4 PAYSAGE : 16 boîtes, « GARBA Yahouza (SG) », aucune étoile, aucune boîte qui en chevauche une autre', (t) async {
      final m = magasinM14();
      await ouvrirOrganigramme(t, m);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'));
      final feuille = t.getSize(find.byKey(const Key('impression:a4')));
      expect(feuille.width, closeTo(mm(297), 1), reason: 'paysage : 297 mm de large');
      expect(t.widget<Text>(find.byKey(const Key('impression:titre'))).data, 'ORGANIGRAMME DE LA CLINIQUE NASSIERA TOO');
      final boites = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('organigramme:'));
      expect(boites, findsNWidgets(16));
      expect(find.descendant(of: find.byKey(const Key('organigramme:Infirmiers')), matching: find.text('GARBA Yahouza (SG)')), findsOneWidget);
      expect(find.textContaining('★'), findsNothing);
      expect(find.text('Effectif entre parenthèses. C/S : chef de service.'), findsOneWidget);
      final rects = [for (final e in boites.evaluate()) t.getRect(find.byWidget(e.widget))];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j].deflate(0.5)), isFalse, reason: 'les boîtes $i et $j se chevauchent');
        }
      }
    });

    casM14('lecture seule : ni « Modifier » ni « Archiver » (absentes, jamais grisées), « Imprimer l\'organigramme » reste ouverte', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'cfg-organisation', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-organisation'));
      await toucherM14(t, find.text('Organigramme').first);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'), findsOneWidget);
    });
  });

  testWidgets('PDF : l\'organigramme tient sur UNE page A4 en PAYSAGE (842 x 595 pt), les boîtes et le titre de l\'agent sont dans le document', (t) async {
    final m = magasinM14();
    final o = org(m);
    final mise = orgMiseEnPage(o.arbre())!;
    final piece = PieceA4(
        titre: 'ORGANIGRAMME DE LA CLINIQUE NASSIERA TOO',
        paysage: true,
        lieuDate: false,
        blocs: [BlocOrganigramme(mise), const BlocTexte('Effectif entre parenthèses. C/S : chef de service.')],
        reference: 'CNT-20261030-0001',
        utilisateur: 'Sonde ORG2',
        edite: aujourdhui);
    final p = await t.runAsync(PolicesPdf.charger);
    final pdf = (await t.runAsync(() => pdfA4(piece, p!, compresser: false)))!;
    final txt = latin1.decode(pdf);
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(txt)!;
    expect(double.parse(box.group(1)!), closeTo(841.89, 0.1), reason: 'paysage : la largeur est la grande dimension');
    expect(double.parse(box.group(2)!), closeTo(595.28, 0.1));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(txt).length, 1, reason: 'une seule page');
    // Le texte du PDF est encodé en glyphes : si pdftotext est présent, on le relit.
    final fichier = File('${Directory.systemTemp.path}/org2-${DateTime.now().microsecondsSinceEpoch}.pdf')..writeAsBytesSync(pdf);
    try {
      final r = await t.runAsync(() => Process.run('pdftotext', ['-raw', fichier.path, '-']));
      if (r != null && r.exitCode == 0) {
        final lu = '${r.stdout}'.replaceAll(RegExp(r'\s+'), ' ');
        for (final a in ['ORGANIGRAMME DE LA CLINIQUE NASSIERA TOO', 'GARBA Yahouza (SG)', 'Directrice Administrative (DA) (01)', 'Aide-Soignante (08)', 'Agents d’Entretiens (03)']) {
          expect(lu, contains(a));
        }
        expect(lu, isNot(contains('★')));
      }
    } finally {
      fichier.deleteSync();
    }
  });

  group('le verrou d\'un poste de secours (P3) : 5 minutes à valider, réglage en base, administrateur et DAF seuls', () {
    VerrouSecoursPoste vs(Magasin m, String role) => VerrouSecoursPoste(m, auteur: () => 'Sonde ORG2', role: role, horloge: () => aujourdhui);

    test('défaut : 5 minutes (secours), 15 (ordinaire), poste ordinaire ; le paramètre est au registre, à valider', () {
      final m = magasinM14();
      final v = vs(m, 'admin');
      expect(v.delaiSecours(), 5);
      expect(v.delaiOrdinaire(), 15);
      expect(v.posteDeSecours(), isFalse);
      expect(v.delaiPoste(), 15);
      expect(definitionDeParametre(cleDelaiVerrouSecours)!.source, contains('à valider'));
    });

    test('règle le délai : une NOUVELLE VERSION au registre, journalisée avec l\'ancienne et la nouvelle valeur ; refusé hors bornes et pour les autres rôles', () {
      final m = magasinM14();
      final v = vs(m, 'da');
      final r = v.definirDelai('7', motif: 'Sonde ORG2');
      expect(r['ok'], isTrue);
      expect(v.delaiSecours(), 7);
      expect(serviceParametres(m, auteur: () => 'x', horloge: () => aujourdhui).valeur(cleDelaiVerrouSecours, '2026-10-30'), 7);
      final a = m.collection('audit').toutes.first;
      expect(a['action'], 'Délai de verrou d’un poste de secours');
      expect(a['avant'], {'minutes': 5});
      expect((a['apres'] as Map)['minutes'], 7);
      for (final mauvais in ['', '2.5', '0', '121', 'abc']) {
        expect(v.definirDelai(mauvais)['code'], 'DELAI_INVALIDE', reason: mauvais);
      }
      expect(vs(m, 'direction').definirDelai('9')['code'], 'REGLAGE_RESERVE');
      expect(v.delaiSecours(), 7, reason: 'les refus n\'écrivent rien');
    });

    test('désigner CE poste de secours : le délai en force passe au délai de secours ; refusé hors administrateur et DAF', () async {
      final m = magasinM14();
      final v = vs(m, 'admin');
      expect((await v.definirPoste(true))['ok'], isTrue);
      expect(v.posteDeSecours(), isTrue);
      expect(v.delaiPoste(), 5);
      expect(m.collection('audit').toutes.first['action'], 'Poste de secours');
      expect((await vs(m, 'caissier').definirPoste(false))['code'], 'REGLAGE_RESERVE');
      expect(v.posteDeSecours(), isTrue);
      expect((await v.definirPoste(false))['ok'], isTrue);
      expect(v.delaiPoste(), 15);
    });

    test('la désignation est une donnée LOCALE du poste : rangée dans ses paramètres, jamais dans le magasin partagé', () {
      final p = ParametresPoste(uuidPoste: 'u', posteSecours: true);
      expect(ParametresPoste.depuisJson(p.toJson()).posteSecours, isTrue);
      expect(ParametresPoste.depuisJson(const ParametresPoste(uuidPoste: 'u').toJson()).posteSecours, isFalse);
      expect(ParametresPoste.depuisJson({'uuid_poste': 'u'}).posteSecours, isFalse, reason: 'un fichier d\'avant : poste ordinaire');
      expect(const ParametresPoste(uuidPoste: 'u').avec(posteSecours: true).posteSecours, isTrue);
    });

    casM14('la carte de « Sessions actives » : le délai, « À valider », les deux commandes pour l\'administrateur ; réglage AU GESTE', (t) async {
      final m = magasinM14();
      await ouvrirM14(t, m, 'm14-sessions');
      expect(find.text('Verrou d’un poste de secours'), findsOneWidget);
      expect(find.text('À valider'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('Poste ordinaire : verrou à 15 min'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Désigner ce poste comme poste de secours'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régler le délai de secours'));
      await saisir(t, 'minutes', '0');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('nombre entier de minutes, de 1 à 120'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await saisir(t, 'minutes', '3');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(VerrouSecoursPoste(m, auteur: () => 'x', role: 'admin', horloge: () => aujourdhui).delaiSecours(), 3);
      await t.pump(const Duration(seconds: 10));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Désigner ce poste comme poste de secours'));
      expect(find.text('Poste de secours : verrou à 3 min'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Retirer la désignation de ce poste'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer la désignation de ce poste'));
    });

    casM14('la Direction lit la carte sans pouvoir régler : les deux commandes sont ABSENTES', (t) async {
      await ouvrirM14(t, magasinM14(), 'm14-sessions', role: 'direction');
      expect(find.text('Verrou d’un poste de secours'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler le délai de secours'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Désigner ce poste comme poste de secours'), findsNothing);
    });
  });

  group('le verrou de la session : le poste de secours se verrouille au délai de secours', () {
    final donnees = donneesNav;
    const secret = 'Clinique#Natitingou26';

    Magasin posteMagasin() => Magasin({
          'audit': const <M>[],
          'utilisateurs': [for (final u in jeu('utilisateurs')) {...u}],
          'rbac': [for (final r in jeu('rbac')) {...r}],
          'tentativesConnexion': const <M>[],
          'personnel': jeu('personnel'),
          'soignants': jeu('soignants'),
          'rolesBase': jeu('rolesBase'),
          'support': const <M>[],
        }, 'POSTE');

    Future<void> connecterEn(WidgetTester t, Magasin m, SessionPoste s) async {
      t.view.physicalSize = const Size(1600, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(
          key: UniqueKey(),
          donnees: donnees,
          config: const ConfigPoste(mode: ModePoste.fileul, role: 'reception'),
          magasin: m,
          session: s,
          horloge: () => aujourdhui));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.enterText(find.byKey(const Key('acces:identifiant')), 'e.orou');
      await t.enterText(find.byKey(const Key('acces:motdepasse')), secret);
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Se connecter').first);
      await t.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 600));
    }

    for (final secours in [false, true]) {
      testWidgets('connexion sur un poste ${secours ? 'DE SECOURS : verrou à 5 minutes' : 'ORDINAIRE : verrou à 15 minutes (inchangé)'}', (t) async {
        ServiceIdentifiants.parametres = AccParametresHachage.tests;
        final m = posteMagasin();
        final compte = jeu('utilisateurs').firstWhere((u) => u['identifiant'] == 'e.orou');
        await t.runAsync(() => ServiceIdentifiants.de(m).definir('${compte['id']}', secret, par: 'test', doitChanger: false, maintenant: aujourdhui));
        await t.runAsync(() => ServiceInstallation.de(m).designerPosteDeSecours(secours));
        final s = SessionPoste(exigeConnexion: true, horloge: () => aujourdhui);
        await connecterEn(t, m, s);
        expect(s.etat, EtatSession.connectee);
        expect(s.verrou.delai, Duration(minutes: secours ? 5 : 15));
        await t.pump(const Duration(seconds: 10));
      });
    }
  });
}
