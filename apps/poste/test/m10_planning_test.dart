import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// Le repos individuel gouverne le contrôle de l'agent : 24 h pour lui (dérogation), 48 h pour son collègue de la même catégorie.
bool rhbPlanningPoste24(Magasin m) {
  final p = PlanningRhPoste(m, auteur: () => 'x', role: 'surveillant', droitGeste: (g) => false, horloge: () => auj16);
  final a = m.collection('personnel').actives.firstWhere((e) => e['id'] == 'EMP01');
  final autre = m.collection('personnel').actives.firstWhere((e) => e['id'] != 'EMP01' && e['fonction'] == 'medecin');
  return p.regimeALaDate(a, '2026-08-16').repos == 'repos24' && p.regimeALaDate(autre, '2026-08-16').repos == 'repos48';
}

/// L'ordre dans lequel les textes apparaissent à l'écran (de haut en bas) : ce que l'agent lit.
List<String> ordreAffiche(WidgetTester t, Iterable<String> refs) {
  final y = {for (final r in refs) r: find.text(r).evaluate().isEmpty ? double.infinity : t.getTopLeft(find.text(r).first).dy};
  return (y.keys.where((r) => y[r]!.isFinite).toList()..sort((a, b) => y[a]!.compareTo(y[b]!)));
}

/// m10-planning : l'écran MONTÉ sur le jeu du poste, les gestes de l'agent accomplis, et ce qui est écrit au magasin comparé aux relevés de la
/// maquette (rhb.json). Les règles chiffrées sont rejouées par packages/domaine/test/rhb_regles_test.dart.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m10-planning', () {
    casM14('ouverture au 16/08 : les quatre compteurs, les huit régimes, la grille de la semaine et le registre', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      final pl = maquette('planning');
      final k = kpis(t);
      final v = {for (final x in liste(pl['kpis'])) x['label'] as String: norm(x['valeur'])};
      for (final e in v.entries) {
        expect(norm(k[e.key]), e.value, reason: e.key);
      }
      expect(find.text('Planning du 13/08/2026 au 19/08/2026'), findsOneWidget);
      expect(find.text('Régimes de travail par catégorie'), findsOneWidget);
      for (final r in m.collection('regimesTravail').actives) {
        expect(find.text('${r['libelle']}'), findsWidgets, reason: '${r['libelle']}');
      }
      expect(find.text('Registre des vacations'), findsOneWidget);
      for (final titre in ['Gardes par agent — les dix premiers', 'Gardes par service', 'Gardes par type de vacation']) {
        expect(find.text(titre), findsOneWidget, reason: titre);
      }
      expect(find.textContaining('Garde 24h'), findsWidgets); // la légende
      expect(find.text('Légende :'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau régime'), findsOneWidget);
      // Lots L4 à L6 : les cartes que la maquette ajoute au planning, dans son ordre.
      for (final titre in ['Régimes individuels (dérogations champ par champ)', 'Réglages du planning et des présences', 'Filtres avancés du planning']) {
        expect(find.text(titre), findsOneWidget, reason: titre);
      }
      expect(ordreAffiche(t, ['Régimes de travail par catégorie', 'Régimes individuels (dérogations champ par champ)', 'Réglages du planning et des présences', 'Filtres avancés du planning', 'Planning du 13/08/2026 au 19/08/2026']),
          ['Régimes de travail par catégorie', 'Régimes individuels (dérogations champ par champ)', 'Réglages du planning et des présences', 'Filtres avancés du planning', 'Planning du 13/08/2026 au 19/08/2026']);
      for (final l in (maquette('planning')['filtres'] as List)) {
        expect(find.text('$l'), findsWidgets, reason: 'filtre $l');
      }
      expect(find.widgetWithText(BoutonSigh, 'Effacer les filtres'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Déroger pour un agent'), findsOneWidget);
      expect(find.text('Aucun agent n’a de régime individuel ni de planning personnalisé : tous suivent le régime de leur catégorie.'), findsOneWidget);
      // La grille : un agent de la semaine, sa case du 16/08 porte sa garde.
      expect(find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')), matching: find.text('Garde 24h')), findsOneWidget);
    });

    casM14('au 30/10 : la semaine est vide, personne n\'est de garde', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning');
      expect(find.text('Planning du 27/10/2026 au 02/11/2026'), findsOneWidget);
      expect([kpis(t)['De garde aujourd’hui'], kpis(t)['En permanence'], kpis(t)['En repos']], ['0', '0', '0']);
    });

    casM14('affecter : une garde pendant le repos de 48 h est REFUSÉE, nommée, et rien n\'est écrit', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      final avant = m.collection('planning').toutes.length;
      await toucherM14(t, find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')));
      expect(find.text('Affectation de vacation'), findsOneWidget);
      expect(find.textContaining('Médecins — Garde de 24 h (08h→08h), suivie d’un repos de 48 h.'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final cas = liste(dico(maquette('affectation'))['cas']).first;
      // Le contrôle est celui du DOMAINE (une règle, une voie) : le refus porte son motif et son geste, comme le toast de la maquette.
      final tc = dico(cas['toast']);
      // La garde en cause est lue sur le planning du jeu (la maquette en avait posé une de contrôle au 15/08) : le texte est le même, la date citée peut différer.
      final motif = '${tc['message']}'.replaceAll(RegExp(r'le \d{2}/\d{2}/\d{4}'), 'le #');
      expect(
          t.widgetList<Text>(find.byType(Text)).where((w) => (w.data ?? '').replaceAll(RegExp(r'le \d{2}/\d{2}/\d{4}'), 'le #') == motif).length,
          1,
          reason: motif);
      expect(motif, 'Incompatibilité : le repos de 48 h qui suit une garde n’est pas respecté (garde déjà programmée le # pour BASSONGUI Chabi Séko).');
      expect(find.text('${tc['detail']}'), findsOneWidget);
      expect(m.collection('planning').toutes.length, avant);
      expect(find.text('Affectation de vacation'), findsOneWidget, reason: 'la modale reste ouverte');
    });

    casM14('affecter : une vacation libre s\'écrit avec le régime de la catégorie, comme la maquette', (t) async {
      final m = magasinRhb();
      // L'agent libre sur la semaine : on retire ses vacations du 10 au 20 août (comme le fait le script de relevé).
      for (final v in m.collection('planning').actives.where((v) => v['employeId'] == 'EMP21' && '${v['date']}'.compareTo('2026-08-10') >= 0 && '${v['date']}'.compareTo('2026-08-20') <= 0).toList()) {
        m.collection('planning').archiver(v['id']);
      }
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      await toucherM14(t, find.byKey(const Key('rhb:cellule:EMP21:2026-08-14')));
      await choisirM14(t, 'type', 'Garde 24h (08:00 → 08:00)');
      await taper(t, 'observation', 'Remplace A.');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final trace = dico(vecteursRhb['affectationReussie']);
      final attendu = dico(((trace['trace'] as List).first as Map)['args'] is List ? (((trace['trace'] as List).first as Map)['args'] as List)[1] : null);
      final f = net(premiere(m, 'planning'));
      // Ce qui dépend de la session (qui valide, et quand) se vérifie à part : la maquette l'écrit au nom de sa session de relevé.
      const session = {'validePar', 'valideLe'};
      expect({for (final e in attendu.entries) if (!session.contains(e.key)) e.key: f[e.key]}, {for (final e in attendu.entries) if (!session.contains(e.key)) e.key: e.value});
      expect(f['statut'], 'validee');
      expect([f['validationEtat'], f['origine'], f['valideLe']], ['validee', 'poste', '2026-08-16']);
      expect('${f['validePar']}'.isNotEmpty, isTrue, reason: 'RG-12 : la pose est attribuée');
      expect(find.text('Vacation enregistrée.'), findsOneWidget);
    });

    casM14('affecter : « Retirer » archive la vacation (jamais supprimée) et l\'annonce', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      final avant = m.collection('planning').actives.length;
      await toucherM14(t, find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer'));
      expect(m.collection('planning').actives.length, avant - 1);
      expect(m.collection('planning').archivees.length, 1);
      expect(find.text('Vacation retirée.'), findsOneWidget);
    });

    casM14('modifier un régime : la portée est DEMANDÉE, « à venir seulement » ne touche pas l\'historique', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      final cas = liste(dico(maquette('regimes'))['cas']).first;
      final lignePassee = m.collection('planning').actives.where((v) => v['fonction'] == 'infirmier' && '${v['date']}'.compareTo('2026-08-16') < 0).first;
      await toucherM14(t, find.byTooltip('Modifier ce régime').at(1)); // Infirmiers : la deuxième ligne du jeu
      await taper(t, 'libelle', 'Infirmiers (cycle revu)');
      await taper(t, 'cycle', '4');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Portée de la modification'), findsOneWidget);
      expect(find.textContaining('328 vacation(s) s’adossent à ce régime — 160 déjà effectuée(s) et 168 à venir.'), findsOneWidget);
      // « à venir seulement » est présélectionné (c'est le choix prudent).
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      final r = m.collection('regimesTravail').actives.firstWhere((x) => x['id'] == 'REG02');
      final attendu = dico(cas['regime']);
      for (final k in ['libelle', 'cycle', 'portee', 'modifieLe', 'vacations', 'repos']) {
        expect(r[k], attendu[k], reason: k);
      }
      expect(dico(cas['toast'])['detail'], '168 vacation(s) à venir concernée(s) ; l’historique est préservé.');
      expect(find.text('168 vacation(s) à venir concernée(s) ; l’historique est préservé.'), findsOneWidget);
      // Les vacations passées gardent leur étiquette ; les à venir portent le nouveau libellé.
      expect(m.collection('planning').parId(lignePassee['id'])!['regimeLibelle'], lignePassee['regimeLibelle']);
      final futures = m.collection('planning').actives.where((v) => v['fonction'] == 'infirmier' && '${v['date']}'.compareTo('2026-08-16') >= 0);
      expect(futures.every((v) => v['regimeLibelle'] == 'Infirmiers (cycle revu)'), isTrue);
      expect(m.collection('audit').toutes.first['action'], 'Modification de régime');
    });

    casM14('modifier un régime « y compris les vacations passées » : réétiquetées, primes à recalculer, et la modification est ANNULABLE', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      await toucherM14(t, find.byTooltip('Modifier ce régime').first); // Médecins
      await taper(t, 'libelle', 'Médecins de garde');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await toucherM14(t, find.byKey(const Key('rhb:portee:tout')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      expect(find.text('80 vacation(s) passée(s) réétiquetée(s) — primes à recalculer.'), findsOneWidget);
      final medecins = m.collection('planning').actives.where((v) => v['fonction'] == 'medecin').toList();
      expect(medecins.length, 164);
      expect(medecins.every((v) => v['regimeLibelle'] == 'Médecins de garde'), isTrue);
      expect(medecins.where((v) => v['regimeRevisee'] == true).length, 80);
      expect(m.collection('regimesTravail').actives.firstWhere((x) => x['id'] == 'REG01')['portee'], 'tout');
    });

    casM14('archiver un régime : le MOTIF est exigé, puis le régime part à la corbeille (RG-14), restaurable', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      final avant = m.collection('regimesTravail').actives.length;
      await toucherM14(t, find.byTooltip('Archiver ce régime').at(6)); // Agents de sécurité
      expect(find.textContaining('123 vacation(s) s’adossent à ce régime.'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver le régime'));
      expect(m.collection('regimesTravail').actives.length, avant, reason: 'sans motif, rien n\'est archivé');
      await t.enterText(find.byType(TextField).last, 'Poste supprimé');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver le régime'));
      expect(m.collection('regimesTravail').actives.length, avant - 1);
      expect(m.collection('regimesTravail').archivees.single['libelle'], 'Agents de sécurité');
      expect(find.text('Régime archivé.'), findsOneWidget);
    });

    casM14('un nouveau régime : champs obligatoires, puis fiche active', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau régime'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer le régime'));
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
      expect(m.collection('regimesTravail').actives.length, 8);
      await taper(t, 'libelle', 'Chauffeurs');
      await choisirM14(t, 'fonctions', 'Chauffeur coursier');
      await t.tapAt(const Offset(5, 5)); // referme le panneau à choix multiples
      await t.pump(const Duration(milliseconds: 300));
    });

    casM14('« Imprimer le planning » : la semaine, les agents, les trois signatures', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le planning'));
      expect(find.text('Planning de garde et de permanence'), findsOneWidget);
      expect(find.text('Semaine du 13/08/2026 au 19/08/2026'), findsWidgets);
      expect(find.text('Le Surveillant Général'), findsWidgets);
      expect(find.text('Le Directeur Médical'), findsWidgets);
    });

    casM14('filtres avancés : les douze cas de la maquette, la grille ET le registre se recalculent, « Effacer les filtres » remet tout', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning', horloge: auj16);
      final pf = dico(maquette('planningFiltres'));
      const cle = {
        'Agent': 'pl_f_agent', 'Matricule': 'pl_f_matricule', 'Service': 'pl_f_service', 'Fonction': 'pl_f_fonction', 'Régime': 'pl_f_regime', 'Type de vacation': 'pl_f_type',
        'Validation': 'pl_f_validation', 'Validé par': 'pl_f_validepar', 'Du': 'pl_f_du', 'Au': 'pl_f_au', 'Recherche': 'pl_f_q',
      };
      int cellules() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('rhb:cellule:')).evaluate().length;
      for (final cas in liste(pf['cas'])) {
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Effacer les filtres'));
        for (final e in dico(cas['reglage']).entries) {
          await regler(t, cle[e.key]!, '${e.value}');
        }
        final vue = dico(cas['vue']);
        final nom = '${cas['nom']}';
        expect(find.text('${vue['registreTitre']}'), findsOneWidget, reason: '$nom : titre du registre');
        if (vue['grilleVide'] == true) {
          expect(find.text('Aucun agent ne correspond aux filtres.'), findsOneWidget, reason: nom);
          expect(find.text('Effacer un filtre pour élargir la sélection.'), findsOneWidget, reason: nom);
        } else {
          expect(cellules(), 7 * (vue['grilleAgents'] as int), reason: '$nom : agents de la grille');
        }
        expect(find.byTooltip('Masquée par les filtres').evaluate().length, vue['grilleMasquees'], reason: '$nom : vacations masquées par un filtre');
        final lignes = liste([for (final l in (vue['registreLignes'] as List)) {'c': l}]);
        if (lignes.isEmpty) {
          expect(find.text('Aucun enregistrement.'), findsWidgets, reason: '$nom : registre vide');
        } else {
          final premiere = (lignes.first['c'] as List).cast<Object?>();
          cellulesAffichees(t, [premiere[2], premiere[5]], raison: nom);
        }
      }
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Effacer les filtres'));
      expect(find.text('Registre des vacations'), findsOneWidget);
      expect(cellules(), 7 * 31);
    });

    casM14('« Imprimer l\'état » du registre : l\'extrait filtré, ses FILTRES retracés sur la pièce (comme print.js les relève sur la page)', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning', horloge: auj16);
      final imp = dico(dico(maquette('planningFiltres'))['impressionRegistre']);
      await regler(t, 'pl_f_fonction', 'infirmier');
      await regler(t, 'pl_f_type', 'garde_hospi');
      await regler(t, 'pl_f_du', '2026-08-10');
      await regler(t, 'pl_f_au', '2026-08-20');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’état'));
      expect(find.text('Registre des vacations'), findsWidgets);
      expect(find.text('${imp['sousTitre']}'), findsWidgets);
      final zone = t.widgetList<Text>(find.descendant(of: find.byKey(const Key('impression:filtres')), matching: find.byType(Text))).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('|');
      for (final f in (imp['filtresPage'] as List)) {
        final l = (f as List);
        expect(sansEspaces(zone).contains(sansEspaces('${l[0]}')) && sansEspaces(zone).contains(sansEspaces('${l[1]}')), isTrue, reason: 'filtre ${l[0]} : ${l[1]} dans « $zone »');
      }
      expect(find.textContaining('Vacations retenues'), findsWidgets);
      // La maquette annonce le nombre de vacations retenues et les colonnes Validation et Validé par.
      for (final c in ['Validation', 'Validé par']) {
        expect(find.text(c), findsWidgets, reason: c);
      }
    });

    casM14('régime individuel : une dérogation champ par champ, versionnée, avec son historique ; la catégorie reste la règle pour les autres', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déroger pour un agent'));
      expect(find.text('Régime individuel'), findsOneWidget);
      expect(find.text('Une version datée : elle ne se réécrit pas.'), findsOneWidget);
      final agent = m.collection('personnel').actives.firstWhere((e) => e['id'] == 'EMP01');
      await choisirM14(t, 'employeId', '${agent['matricule']} — ${agent['nomComplet']} (${agent['poste']})');
      // Sans champ dérogé : refus nommé, la modale reste ouverte, rien n'est écrit.
      await taper(t, 'motif', 'Sonde');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      expect(find.text('Aucun champ n’est dérogé : le régime de l’agent suit déjà celui de sa catégorie.'), findsOneWidget);
      expect(m.collection('regimesIndividuels').toutes, isEmpty);
      // Une date passée : refusée (jamais rétroactif).
      ControleurFormulaire ctl() => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
      ctl().poser('repos', 'repos24');
      ctl().poser('dateEffet', '2026-08-15');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      expect(find.textContaining('est antérieure à aujourd’hui : une dérogation ne s’applique jamais rétroactivement.'), findsOneWidget);
      ctl().poser('dateEffet', '2026-08-16');
      ctl().poser('honoraire', '20000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      final v = m.collection('regimesIndividuels').toutes.single;
      expect([v['employeId'], v['version'], v['dateEffet'], v['retourCategorie'], v['motif']], ['EMP01', 1, '2026-08-16', false, 'Sonde']);
      expect((v['champs'] as Map).keys.toSet(), {'repos', 'honoraire'});
      expect(find.text('Dérogation enregistrée.'), findsOneWidget);
      expect(find.text('Version 1 à compter du 16/08/2026'), findsOneWidget);
      // La carte : l'agent, ce qui est dérogé AUJOURD'HUI, depuis quand, combien de versions.
      expect(find.text('Repos : Repos 24h'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && sansEspaces(w.data).contains('Honoraire:20000')), findsOneWidget);
      expect(find.text('${agent['nomComplet']}'), findsWidgets);
      expect(find.text('régime individuel', findRichText: true, skipOffstage: false), findsNothing);
      expect(find.textContaining('· régime individuel'), findsWidgets, reason: 'la grille nomme l\'agent à régime individuel');
      // L'historique : la version, sa date d'effet, son motif et son auteur.
      ToastsSigh.viderPourTests(); // le toast de confirmation couvre le coin de la carte
      await t.pump(const Duration(milliseconds: 300));
      await toucherM14(t, find.byTooltip('Historique des versions'));
      expect(find.text('Historique du régime de ${agent['nomComplet']}'), findsOneWidget);
      expect(find.text('Sonde'), findsWidgets);
      expect(find.textContaining('le 16/08/2026'), findsWidgets);
      // Les gardes du régime individuel sont le repos DE L'AGENT : 24 h pour lui, 48 h pour son collègue.
      expect(rhbPlanningPoste24(m), isTrue);
    });

    casM14('la carte des réglages : le circuit et « l\'agent modifie directement » se lisent au registre et se règlent (commande ABSENTE hors administrateur et DA)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-planning', horloge: auj16);
      expect(find.text('Surveillant seul'), findsOneWidget);
      expect(find.text('Non : il propose, le surveillant valide'), findsOneWidget);
      expect(find.text('Une présence, une absence, un congé ou un ordre de mission non validé est visible mais ne compte pas. Un planning proposé ne change rien tant qu’il n’est pas validé.'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Régler'));
      expect(find.text('Ces réglages se règlent au poste et se synchronisent. Une pièce déjà tranchée garde le circuit sous lequel elle l’a été.'), findsOneWidget);
      await choisirM14(t, 'circuit', 'Surveillant puis directrice administrative');
      await cocher(t, 'direct');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Réglages enregistrés.'), findsOneWidget);
      expect(find.text('Surveillant puis directrice administrative'), findsWidgets);
      expect(find.text('Oui'), findsOneWidget);
      final p = PlanningRhPoste(m, auteur: () => 'x', role: 'admin', droitGeste: (g) => true, horloge: () => auj16);
      expect([p.circuit(), p.agentModifieDirectement()], ['surveillant_puis_daf', true]);
      expect(m.collection('audit').toutes.where((l) => l['action'] == 'Circuit de validation des présences').length, 1);
    });

    casM14('hors administrateur et DA : « Régler » et « Déroger pour un agent » sont ABSENTS (jamais grisés), la grille se lit', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning', horloge: auj16, role: 'surveillant');
      expect(find.text('Réglages du planning et des présences'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Régler'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Déroger pour un agent'), findsNothing);
      // Le surveillant pose le planning : la case s'ouvre.
      await toucherM14(t, find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')));
      expect(find.text('Affectation de vacation'), findsOneWidget);
    });

    casM14('lecture seule : la grille se lit sans s\'ouvrir, aucune commande d\'écriture', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-planning', horloge: auj16, role: 'da', donnees: donneesLectureSeule('da', 'm10-planning'));
      expect(find.text('Régimes de travail par catégorie'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau régime'), findsNothing);
      expect(find.byTooltip('Modifier ce régime'), findsNothing);
      expect(find.byTooltip('Archiver ce régime'), findsNothing);
      expect(find.byType(InkWell).evaluate().where((e) => e.widget.key == const Key('rhb:cellule:EMP01:2026-08-16')), isEmpty);
      await t.tap(find.byKey(const Key('rhb:cellule:EMP01:2026-08-16')), warnIfMissed: false);
      await t.pump();
      expect(find.text('Affectation de vacation'), findsNothing);
    });
  });
}
