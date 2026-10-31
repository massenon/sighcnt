import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm10_aide.dart';
import 'm10_rhc_aide.dart';
import 'm14_aide.dart' show donneesLectureSeule, ouvrirM14;

/// M10 (C) — registre des badges, vérification, modèles, planche d'impression : les écrans MONTÉS sur le jeu du poste et comparés aux relevés de la maquette
/// (packages/domaine/test/vecteurs/rhc.json, engendrés par prototype_html/build/vecteurs-rh-c.js — écrans pilotés dans Chrome à l'horloge du 30/10/2026 10 h).
/// Les règles chiffrées sont rejouées par packages/domaine/test/rhc_regles_test.dart ; événements, participations, assurance et rotation : m10_rhc2_test.dart.
const ecrans = [
  'm10-badges',
  'm10-badges-verification',
  'm10-badges-modeles',
  'm10-badges-impression',
  'm10-evenements',
  'm10-participations',
  'm10-assurance-personnel',
  'm10-securite-entretien',
];

String texteDe(Finder f) => sansEspaces([for (final w in find.descendant(of: f, matching: find.byType(Text)).evaluate().map((e) => e.widget as Text)) w.data ?? w.textSpan?.toPlainText() ?? ''].join(' '));

Future<void> toucherCase(WidgetTester t, String libelle, {int rang = 0}) async {
  final f = find.descendant(of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == libelle).at(rang), matching: find.byType(InkWell));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('parité de contenu N1 : chaque libellé de la maquette figure à l’écran', () {
    for (final id in ecrans) {
      testWidgets(id, (t) async {
        await ouvrir(t, posteRhc(), id);
        expect(t.takeException(), isNull);
        expect(manquantsN1(t, id), isEmpty, reason: id);
        await fermerToasts(t);
      });
    }
  });

  group('m10-badges', () {
    final b = obj(vc['badges']);

    testWidgets('indicateurs, onglets, ordre du registre (numéro décroissant) et commandes de ligne par état identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges');
      kpisIdentiques(t, obj(b['ecran'])['kpis']);
      for (final o in (obj(b['ecran'])['onglets'] as List)) {
        expect(find.text('$o'), findsOneWidget, reason: '$o');
      }
      final refs = [for (final l in lignesTableau(b['ecran'])) l[0].split(' ').first];
      expect(ordreAffiche(t, refs), refs, reason: 'tri par numéro décroissant, comme la maquette');
      presentes(t, [for (final l in lignesTableau(b['ecran'])) ...l.skip(2)], raison: 'ligne');
      // Douze lignes à la première page : trois d'entre elles ne sont pas remises (BDG-00011, -00006, -00004).
      expect(find.byTooltip('Consulter le badge'), findsNWidgets(12));
      expect(find.byTooltip('Imprimer la carte'), findsNWidgets(12));
      expect(find.byTooltip('Retirer le badge'), findsNWidgets(12));
      expect(find.byTooltip('Marquer remis à l’agent'), findsNWidgets(3));
      expect(find.widgetWithText(BoutonSigh, 'Émettre un badge'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('onglets : agents sans badge (effectif rapproché du registre) et quatre décisions de la Direction MARQUÉES', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges');
      await cliquer(t, find.text('Agents sans badge (30)'));
      final sans = obj(obj(b['parOnglet'])['Agents sans badge (30)']);
      presentes(t, [for (final l in lignesTableau(sans)) ...l.take(4)].take(24), raison: 'sans badge');
      expect(find.widgetWithText(BoutonSigh, 'Émettre'), findsWidgets);
      await cliquer(t, find.text('À décider par la Direction'));
      for (final d in [
        'Durée de validité d’un badge',
        '24 mois',
        'Format du numéro de série',
        'BDG-NNNNN-AAAA',
        'Mentions portées au verso',
        'Le badge sert-il de support de POINTAGE ?',
        'Non — décision non prise'
      ]) {
        expect(find.text(d), findsWidgets, reason: d);
      }
      expect(find.textContaining('Quatre points ne sont fixés par aucun document de cadrage'), findsOneWidget);
      await cliquer(t, find.text('Retirés (0)'));
      expect(find.text('Aucun badge retiré.'), findsWidgets);
      await fermerToasts(t);
    });

    testWidgets('fiche : le QR ne porte que le matricule et le numéro de série ; le verdict est dit', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges');
      await chercher(t, 'BDG-00014');
      await cliquer(t, find.byTooltip('Consulter le badge').first);
      final tiroir = obj(b['tiroir']);
      for (final mot in ['BADGE VALIDE', 'Valable jusqu’au 16/11/2027.', 'CNT-BDG|MAT:14|SER:BDG-00014-2025', 'Le code ne porte que le matricule et le numéro de série.', 'PARAISO Abdoul']) {
        expect(find.textContaining(mot), findsWidgets, reason: mot);
      }
      expect(find.byKey(const Key('qual:qr')), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer la carte'), findsOneWidget);
      expect('${tiroir['texte']}'.contains('CNT-BDG|MAT:14|SER:BDG-00014-2025'), isTrue);
      await fermerToasts(t);
    });

    testWidgets('émission : défauts de la maquette ; l’agent qui porte déjà un badge est refusé EN NOMMANT le premier ; un agent sans badge reçoit le numéro suivant de la série', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-badges');
      final col = m.collection('badges');
      final n0 = col.toutes.length;
      await appuyer(t, 'Émettre un badge');
      final defauts = obj(obj(b['emission'])['defauts']);
      for (final k in ['personnelId', 'modeleId', 'emisLe', 'expireLe', 'etat']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      expect(find.textContaining('Le numéro de série est attribué automatiquement et ne se modifie pas.'), findsOneWidget);
      expect(find.textContaining('Le code QR portera le matricule et le numéro de série, rien d’autre.'), findsOneWidget);
      formulaire(t).poser('personnelId', 'EMP02');
      await t.tap(find.widgetWithText(BoutonSigh, 'Émettre le badge'));
      await t.pump(const Duration(milliseconds: 300));
      final refus = obj(b['emission'])['refusDejaPorteur'] as Map;
      expect(find.text('${((refus['toasts'] as List).first as List)[0]}'), findsOneWidget);
      expect(find.text('${((refus['toasts'] as List).first as List)[1]}'), findsOneWidget);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      await fermerToasts(t);
      formulaire(t).poser('personnelId', 'EMP30');
      formulaire(t).poser('etat', 'remis');
      await t.tap(find.widgetWithText(BoutonSigh, 'Émettre le badge'));
      await t.pump(const Duration(milliseconds: 400));
      final n = col.toutes.first;
      final attendue = obj(obj(b['emission'])['reussie'])['fiche'] as M;
      fichesEgales(n, attendue, ignores: {'personnelId', 'matricule', 'agent', 'poste', 'service', 'photo', ...champsAuteur});
      expect(n['numero'], 'BDG-00011-2026');
      expect([n['personnelId'], n['agent'], n['emisPar']], ['EMP30', 'BOUKARI Fatouma', utilisateurTest]);
      expect(find.text('Badge BDG-00011-2026 émis.'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('remise : confirmation nommée, état « remis » daté', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-badges');
      final r = obj(b['remis']);
      await chercher(t, '${r['numero']}');
      await cliquer(t, find.byTooltip('Marquer remis à l’agent').first);
      expect(find.text('Marquer le badge remis à l’agent ?'), findsOneWidget);
      expect(find.textContaining('Le badge BDG-00004-2025 sera enregistré comme remis à GBEDJI Hervé le 30/10/2026.'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Remis'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(m.collection('badges').toutes.firstWhere((x) => x['numero'] == r['numero']), obj(r['fiche']), ignores: champsAuteur);
      expect(find.text('Badge remis.'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('retrait : motif et date obligatoires, « perte » et « vol » → perdu, le reste → retiré ; le badge reste au registre (RG-14) et passe aux « Retirés »', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-badges');
      final col = m.collection('badges');
      for (final (cle, numero, motif) in [('retraitPerte', 'BDG-00013-2025', 'Perte'), ('retraitDepart', 'BDG-00012-2025', 'Départ de l’agent')]) {
        final r = obj(b[cle]);
        await chercher(t, numero);
        await cliquer(t, find.byTooltip('Retirer le badge').first);
        expect('${formulaire(t)['motifRetrait']}', '${r['motifDefaut']}');
        expect('${formulaire(t)['retireLe']}', '${r['defaut']}');
        expect(find.textContaining('Un badge se retire, il ne se supprime pas (RG-14).'), findsOneWidget);
        poser(t, {'motifRetrait': motif, 'observation': 'Signalé à la RH.'});
        await t.tap(find.widgetWithText(BoutonSigh, 'Retirer le badge'));
        await t.pump(const Duration(milliseconds: 400));
        final ecrite = col.toutes.firstWhere((x) => x['numero'] == numero);
        fichesEgales(ecrite, obj(r['fiche']), ignores: champsAuteur);
        expect(ecrite['retirePar'], utilisateurTest);
        await fermerToasts(t);
      }
      expect(col.toutes.length, 14, reason: 'rien n’est supprimé');
      expect(find.text('Badges en cours (12)'), findsOneWidget);
      expect(find.text('Retirés (2)'), findsOneWidget);
      await cliquer(t, find.text('Retirés (2)'));
      expect(find.byTooltip('Émettre un remplacement'), findsNWidgets(2));
      expect(find.text('Perdu / volé'), findsWidgets);
      presentes(t, ['Perte', 'Départ de l’agent'], raison: 'motifs');
      await fermerToasts(t);
    });

    testWidgets('droits : « Émettre », « Marquer remis » et « Retirer » sont ABSENTS d’un profil en lecture seule', (t) async {
      final d = donneesLectureSeule('direction', 'm10-badges');
      await ouvrirM14(t, posteRhc(), 'm10-badges', role: 'direction', donnees: d, horloge: auj);
      expect(find.byTooltip('Consulter le badge'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Émettre un badge'), findsNothing);
      expect(find.byTooltip('Marquer remis à l’agent'), findsNothing);
      expect(find.byTooltip('Retirer le badge'), findsNothing);
      await fermerToasts(t);
    });

    testWidgets('la matrice : la DAF émet, le surveillant consulte sans émettre', (t) async {
      await ouvrirM14(t, posteRhc(), 'm10-badges', role: 'da', horloge: auj);
      expect(find.widgetWithText(BoutonSigh, 'Émettre un badge'), findsOneWidget);
      await ouvrirM14(t, posteRhc(), 'm10-badges', role: 'surveillant', horloge: auj);
      expect(find.byTooltip('Consulter le badge'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Émettre un badge'), findsNothing);
      expect(find.byTooltip('Retirer le badge'), findsNothing);
      await fermerToasts(t);
    });
  });

  group('m10-badges-verification', () {
    final v = obj(vc['verification']);

    testWidgets('l’écran : saisie manuelle acceptée, retirés listés ; aucun badge retiré dans le jeu', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges-verification');
      final e = obj(v['ecran']);
      expect(find.text('${(e['champs'] as List).first}'), findsOneWidget);
      expect(find.text('${(e['notes'] as List).first}'), findsOneWidget);
      expect(find.text('Aucun badge retiré.'), findsOneWidget);
      expect(find.byKey(const Key('rhc:verdict')), findsNothing);
      await fermerToasts(t);
    });

    final cas = [for (final c in liste(v['cas'])) if (c['reponse'] != null) c];
    for (final c in cas) {
      testWidgets('« ${c['nom']} » : le verdict, le message et la ligne de journal sont ceux de la maquette', (t) async {
        final m = posteRhc();
        // Les états que la maquette fabrique AVANT de vérifier : la même mutation du badge.
        final badges = m.collection('badges');
        final cible = '${c['saisie']}'.contains('BDG-00003') ? 'BDG-00003-2026' : ('${c['nom']}'.startsWith('retiré') || '${c['nom']}'.contains('photographié') ? 'BDG-00002-2026' : null);
        if (cible != null) {
          final f = badges.toutes.firstWhere((x) => x['numero'] == cible);
          switch ('${c['nom']}') {
            case 'expiré':
              f['expireLe'] = '2026-10-29';
            case 'expire aujourd’hui : encore valide':
              f['expireLe'] = '2026-10-30';
            case 'retiré — perte':
              f..['etat'] = 'perdu'..['motifRetrait'] = 'Perte'..['retireLe'] = '2026-10-01';
            case 'retiré — sans motif ni date':
              f..['etat'] = 'retire'..remove('motifRetrait')..remove('retireLe');
            case 'retiré ET expiré : le retrait prime':
              f..['etat'] = 'retire'..['expireLe'] = '2020-01-01';
            case 'badge photographié (photo)':
              // 4 octets d'un PNG invalide : la carte n'affiche pas d'image, le verdict reste le même.
              f['photo'] = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
          }
        }
        await ouvrir(t, m, 'm10-badges-verification');
        await t.enterText(find.byKey(const Key('rhc:saisie')), '${c['saisie']}');
        await t.tap(find.widgetWithText(BoutonSigh, 'Vérifier'));
        await t.pump(const Duration(milliseconds: 300));
        final attendu = sansEspaces('${obj(c['reponse'])['texte']}'.replaceFirst('par $auteurMaquette.', 'par $utilisateurTest.'));
        final obtenu = texteDe(find.byKey(const Key('rhc:verdict')));
        expect(obtenu, attendu);
        final a = m.collection('audit').toutes.first;
        final j = obj(c['audit']);
        expect(a['utilisateur'], utilisateurTest);
        for (final k in ['action', 'module', 'entite', 'reference', 'cible', 'ecran', 'motif', 'trouve']) {
          expect(a[k], j[k], reason: k);
        }
        await fermerToasts(t);
      });
    }

    testWidgets('saisie vide : refus dit, rien n’est journalisé ; les retirés sont listés du plus récent, dix au plus', (t) async {
      final m = posteRhc();
      final badges = m.collection('badges').toutes;
      badges[3].addAll({'etat': 'retire', 'motifRetrait': 'Vol', 'retireLe': '2026-09-01'});
      badges[4].addAll({'etat': 'retire', 'motifRetrait': 'Départ de l’agent', 'retireLe': '2026-10-15'});
      badges[5].addAll({'etat': 'retire'});
      await ouvrir(t, m, 'm10-badges-verification');
      final att = lignesTableau({'tableaux': v['retiresTrois']});
      final refs = [for (final l in att) l[0]];
      expect(ordreAffiche(t, refs), refs);
      presentes(t, [for (final l in att) ...l]);
      final n0 = m.collection('audit').toutes.length;
      await t.tap(find.widgetWithText(BoutonSigh, 'Vérifier'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Saisir ou scanner un numéro de badge.'), findsOneWidget);
      expect(m.collection('audit').toutes.length, n0);
      await fermerToasts(t);
    });
  });

  group('m10-badges-modeles', () {
    final mo = obj(vc['modeles']);

    testWidgets('le registre des gabarits, l’aperçu à l’échelle (recto et verso) et le spécimen identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges-modeles');
      presentes(t, lignesTableau(obj(mo['ecran'])).first.take(6), raison: 'modèle');
      await cliquer(t, find.byTooltip('Consulter').first);
      expect(find.byKey(const Key('rhc:carte:recto')), findsOneWidget);
      expect(find.byKey(const Key('rhc:carte:verso')), findsOneWidget);
      for (final mot in ['Aperçu à l’échelle', 'SPÉCIMEN — APERÇU', 'BDG-00000-2026', 'Valable jusqu’au', '30/10/2028', 'Mentions du verso', '5 ligne(s)', 'CLINIQUE NASSIERA TOO']) {
        expect(find.textContaining(mot), findsWidgets, reason: mot);
      }
      // Le badge n'est PAS une pièce fiscale : ni IFU ni RCCM SUR LA CARTE (la règle de l'écran, elle, les nomme pour dire qu'ils n'y figurent pas).
      for (final face in ['rhc:carte:recto', 'rhc:carte:verso']) {
        for (final mot in ['IFU', 'RCCM']) {
          expect(find.descendant(of: find.byKey(Key(face)), matching: find.textContaining(mot)), findsNothing, reason: '$mot sur $face');
        }
      }
      await fermerToasts(t);
    });

    testWidgets('création : défauts de la maquette, refus sans intitulé, zones et mentions enregistrées ; modification : zones obligatoires ; archivage motivé', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-badges-modeles');
      final col = m.collection('modelesBadge');
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final d = obj(obj(mo['creation'])['defauts']);
      for (final k in ['format', 'orientation', 'defaut']) {
        expect('${formulaire(t)[k]}', '${d[k]}', reason: k);
      }
      expect(formulaire(t)['zones'], d['zones']);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(col.toutes.length, 1);
      await fermerToasts(t);
      poser(t, {'libelle': 'Badge visiteur — portrait', 'orientation': 'portrait', 'mentionsVerso': 'Badge à restituer en sortant.\n\n  À porter visiblement.  '});
      formulaire(t).poser('zones', ['photo', 'nom', 'qr']);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(mo['creation'])['creee'])['fiche'] as M);
      // Modifier : sans zone, refus.
      await chercher(t, 'visiteur');
      await cliquer(t, find.byTooltip('Modifier').first);
      formulaire(t).poser('zones', <String>[]);
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(col.toutes.first['zones'], ['photo', 'nom', 'qr']);
      await fermerToasts(t);
      formulaire(t).poser('zones', ['nom', 'fonction']);
      formulaire(t).poser('defaut', true);
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['libelle'] == 'Badge visiteur — portrait'), obj(obj(mo['modification'])['enregistre'])['fiche'] as M);
      // E745 : la maquette ne retire pas l'ancien « par défaut » : les deux le sont.
      expect(col.toutes.where((x) => x['defaut'] == true).length, 2);
      await archiverLigne(t, 'Doublon');
      expect(col.archivees.length, 1);
      expect(col.toutes.length, 2, reason: 'RG-14 : rien n’est supprimé');
      await fermerToasts(t);
    });
  });

  group('m10-badges-impression', () {
    final im = obj(vc['impression']);

    testWidgets('badges imprimables : ordre par agent, photo « à coller », filtres de la maquette ; commande de planche absente sans le droit', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges-impression');
      final att = lignesTableau(obj(im['ecran']));
      final refs = [for (final l in att) l[0]];
      expect(ordreAffiche(t, refs), refs, reason: 'trié par agent');
      presentes(t, [for (final l in att) ...l.skip(1).take(4)]);
      expect(find.text('À coller'), findsWidgets);
      expect(find.byTooltip('Imprimer la carte seule'), findsNWidgets(att.length));
      await fermerToasts(t);
    });

    testWidgets('planche : dix badges par feuille — quatorze cartes sélectionnées engendrent deux feuilles, dans l’ordre du tableau', (t) async {
      await ouvrir(t, posteRhc(), 'm10-badges-impression');
      expect(find.widgetWithText(BoutonSigh, 'Imprimer la planche'), findsNothing, reason: 'rien n’est sélectionné');
      await toucherCase(t, 'Tout sélectionner');
      expect(find.text('14 lignes sélectionnées'), findsOneWidget);
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Imprimer la planche'));
      expect(nombreFeuilles(t), 2);
      expect(find.byKey(const Key('rhc:carte:recto')), findsNWidgets(14), reason: 'quatorze cartes sur deux feuilles');
      expect(find.text('2 feuille(s) A4 — 14 carte(s)'), findsOneWidget);
      expect(find.text('PLANCHE DE BADGES — 10 CARTE(S)'), findsOneWidget);
      expect(find.text('PLANCHE DE BADGES — 4 CARTE(S)'), findsOneWidget);
      // La planche ne porte pas l'identité fiscale sur les cartes, mais le pied normalisé sur la feuille.
      expect(find.textContaining('Document généré par'), findsNWidgets(2));
      await fermerToasts(t);
    });

    testWidgets('carte seule : recto ET verso, avec les mentions du modèle ; un badge retiré n’est jamais proposé', (t) async {
      final m = posteRhc();
      m.collection('badges').toutes.firstWhere((x) => x['numero'] == 'BDG-00002-2026')['etat'] = 'retire';
      await ouvrir(t, m, 'm10-badges-impression');
      expect(find.text('BDG-00002-2026'), findsNothing);
      expect(find.byTooltip('Imprimer la carte seule'), findsNWidgets(13));
      await chercher(t, 'BDG-00005');
      await cliquer(t, find.byTooltip('Imprimer la carte seule').first);
      expect(find.byKey(const Key('rhc:carte:recto')), findsOneWidget);
      expect(find.byKey(const Key('rhc:carte:verso')), findsOneWidget);
      for (final mot in ['YENI M’PO FLORENT', 'Matricule 5', 'Médecin Généraliste', 'Ce badge est la propriété de la Clinique NASSIERA TOO SARL.', 'À restituer au départ de l’agent.', 'Contrôle SIGH']) {
        expect(find.textContaining(mot), findsWidgets, reason: mot);
      }
      expect(find.textContaining('IFU'), findsNothing);
      await fermerToasts(t);
    });
  });
}
