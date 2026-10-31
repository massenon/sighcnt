import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// m10-planning et m10-presences : les écrans MONTÉS sur le jeu du poste, les gestes de l'agent accomplis, et ce qui est écrit au magasin comparé aux relevés de la
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
      expect(dico(cas['toast'])['message'], 'Incompatibilité — le repos de 48 h qui suit une garde n’est pas respecté.');
      expect(find.text('${dico(cas['toast'])['message']}'), findsOneWidget);
      // La garde en cause est lue sur le planning du jeu (le relevé de la maquette en avait posé une de contrôle au 15/08).
      final conflit = rhbIncompatibiliteGarde(m.collection('planning').actives, employeId: 'EMP01', jour: DateTime(2026, 8, 16), type: 'garde', repos: 'repos48');
      expect(conflit, isNotNull);
      expect(find.text('Garde déjà programmée le ${dateFR(DateTime.parse(conflit!))} pour BASSONGUI Chabi Séko.'), findsOneWidget);
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
      expect({for (final e in attendu.entries) e.key: f[e.key]}, attendu);
      expect(f['statut'], 'validee');
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

  group('m10-presences', () {
    casM14('ouverture : trente jours, les quatre compteurs de la maquette, le registre et ses quatre graphiques', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      final c = liste(maquette('presences')['cas']).first;
      final v = {for (final x in liste(c['kpis'])) x['label'] as String: norm(x['valeur'])};
      for (final e in v.entries) {
        expect(norm(kpis(t)[e.key]), e.value, reason: e.key);
      }
      expect(find.text('Registre des présences — 17/07/2026 au 16/08/2026'), findsOneWidget);
      for (final titre in ['Taux de présence par service', 'Répartition des pointages', 'Volume de pointages par service', 'Retards et absences au fil des jours']) {
        expect(find.text(titre), findsWidgets, reason: titre); // « Taux de présence par service » est aussi une pastille du ruban
      }
      expect(find.text('Critère NS 131'), findsOneWidget);
      expect(find.text('Ajouter un pointage'), findsOneWidget);
    });

    casM14('« Mois en cours » et « Sept derniers jours » règlent la plage ET l\'appliquent', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      final cas = liste(maquette('presences')['cas']);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Mois en cours'));
      expect(find.text('Registre des présences — 01/08/2026 au 16/08/2026'), findsOneWidget);
      expect(norm(kpis(t)['Pointages de la période']), norm(liste(cas[1]['kpis']).first['valeur']));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Sept derniers jours'));
      expect(find.text('Registre des présences — 10/08/2026 au 16/08/2026'), findsOneWidget);
      expect(norm(kpis(t)['Pointages de la période']), norm(liste(cas[2]['kpis']).first['valeur']));
    });

    casM14('les dates se règlent, puis « Appliquer » : rien ne change avant', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      final avant = kpis(t)['Pointages de la période'];
      await regler(t, 'du', '2026-08-01');
      await regler(t, 'au', '2026-08-10');
      expect(kpis(t)['Pointages de la période'], avant);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      final c = liste(maquette('presences')['cas']).firstWhere((x) => x['du'] == '2026-08-01' && x['au'] == '2026-08-10');
      expect([for (final x in liste(c['kpis'])) norm(x['valeur'])], [norm(kpis(t)['Pointages de la période']), norm(kpis(t)['Présences']), norm(kpis(t)['Retards']), norm(kpis(t)['Absences'])]);
    });

    casM14('une plage sans pointage : « Aucun pointage sur la plage retenue. », aucun graphique', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16);
      await regler(t, 'du', '2030-01-01');
      await regler(t, 'au', '2030-01-02');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      expect(find.text('Aucun pointage sur la plage retenue.'), findsOneWidget);
      expect(find.text('Répartition des pointages'), findsNothing);
    });

    casM14('ajouter un pointage : agent, état, heures, motif ; la fiche porte le nom, le matricule et le service de l\'agent', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final avant = m.collection('presences').toutes.length;
      final agent = m.collection('personnel').actives.firstWhere((e) => e['nomComplet'] == 'BASSONGUI Chabi Séko');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter un pointage'));
      expect(find.text('Nouveau pointage'), findsOneWidget);
      await choisirM14(t, 'employeId', '${agent['matricule']} — ${agent['nomComplet']} (${agent['poste']})');
      await choisirM14(t, 'etat', 'Retard');
      await taper(t, 'heureArrivee', '09:15');
      await taper(t, 'heureDepart', '17:00');
      await taper(t, 'motif', 'Embouteillage');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final c = dico(maquette('presences')['creation']);
      final attendu = net(dico(c['nouvelle']));
      final f = net(premiere(m, 'presences'));
      expect({for (final e in attendu.entries) e.key: f[e.key]}, attendu);
      expect(m.collection('presences').toutes.length, avant + 1);
      expect(find.text('Pointage créé.'), findsOneWidget);
      expect(norm(kpis(t)['Retards']), '${int.parse(norm(liste(maquette('presences')['cas']).first['kpis'] is List ? liste(liste(maquette('presences')['cas']).first['kpis'])[2]['valeur'] : '0')) + 1}');
    });

    casM14('un pointage sans heure ni motif : les valeurs par défaut de la maquette (aujourd\'hui, présent, 07:45)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter un pointage'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
      final f = premiere(m, 'presences');
      expect([f['date'], f['etat'], f['heureArrivee']], ['2026-08-16', 'present', '07:45']);
      final premierAgent = (m.collection('personnel').actives.toList()..sort((a, b) => '${a['nomComplet']}'.compareTo('${b['nomComplet']}'))).first;
      expect(f['employeId'], premierAgent['id'], reason: 'la liste présélectionne sa première entrée');
    });

    casM14('modifier un pointage (le droit d\'écrire) et l\'archiver (motif exigé, annulable) — jamais de suppression', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-presences', horloge: auj16);
      final avant = m.collection('presences').actives.length;
      await toucherM14(t, find.byTooltip('Modifier').first);
      await choisirM14(t, 'etat', 'Absent');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(m.collection('presences').actives.where((x) => x['etat'] == 'absent').length, greaterThan(0));
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      await toucherM14(t, find.byTooltip('Archiver').first);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('presences').actives.length, avant, reason: 'sans motif, rien n\'est archivé');
      await t.enterText(find.byType(TextField).last, 'Doublon de saisie');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver'));
      expect(m.collection('presences').actives.length, avant - 1);
      expect(m.collection('presences').archivees.length, 1);
    });

    casM14('lecture seule : ni « Ajouter un pointage » ni « Modifier » ni « Archiver »', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-presences', horloge: auj16, role: 'da', donnees: donneesLectureSeule('da', 'm10-presences'));
      expect(find.text('Pointages de la période'), findsOneWidget);
      expect(find.text('Ajouter un pointage'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
    });
  });
}
