import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m10/rhc_evenements.dart';

import 'aide_polices.dart';
import 'm10_aide.dart';
import 'm10_rhc_aide.dart';
import 'm14_aide.dart' show donneesLectureSeule, ouvrirM14;

/// M10 (C), suite — événements du personnel, frais de participation, assurance du personnel, rotation sécurité & entretien : les écrans MONTÉS sur le jeu du poste et comparés aux
/// relevés de la maquette (rhc.json, pilotée dans Chrome à l'horloge du 30/10/2026 10 h). Badges : m10_rhc_test.dart ; règles chiffrées : packages/domaine/test/rhc_regles_test.dart.

/// Règle le filtre [nom] de la barre d'un écran (son contrôleur est celui du champ affiché).
Future<void> regler(WidgetTester t, String nom, String valeur) async {
  t.widget<FormulaireSigh>(find.byKey(Key('rhb:filtre:$nom'))).controleur.poser(nom, valeur);
  await t.pump(const Duration(milliseconds: 100));
}

String texteEcran(WidgetTester t) => texteAffiche(t);

/// Le texte [x] figure à l'écran, espaces (dont les insécables des montants) ôtés et casse ignorée.
bool aff(WidgetTester t, String x) => texteAffiche(t).contains(sansEspaces(x).toLowerCase());

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m10-evenements', () {
    final e = obj(vc['evenements']);

    testWidgets('indicateurs, ordre par date décroissante, cartes et graphiques identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-evenements');
      kpisIdentiquesRhc(t, obj(e['ecran'])['kpis']);
      final lignes = lignesTableau(e['ecran']);
      final dates = [for (final l in lignes) l[0]];
      expect(ordreAffiche(t, dates), dates);
      presentes(t, [for (final l in lignes) ...l.skip(1).take(5)], raison: 'ligne');
      expect(find.byTooltip('Voir les participations'), findsNWidgets(9));
      expect(find.byTooltip('Imprimer la liste de collecte'), findsNWidgets(9));
      expect(find.byTooltip('Modifier l’événement'), findsNWidgets(9));
      expect(find.byTooltip('Annuler l’événement'), findsNWidgets(9));
      final g = liste(e['graphes']);
      await t.scrollUntilVisible(find.text('Événements au fil des mois'), 400, scrollable: find.byType(Scrollable).first);
      final anneau = t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first);
      expect(anneau.etiquettes, g[0]['etiquettes']);
      expect(anneau.valeurs, g[0]['donnees']);
      final barres = t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres).first);
      expect(barres.etiquettes, g[1]['etiquettes']);
      expect([for (final s in barres.series) s.donnees], [for (final s in (g[1]['donnees'] as List)) (obj(s)['data'] as List)]);
      final ligne = t.widget<GraphiqueLigne>(find.byType(GraphiqueLigne).first);
      expect(ligne.etiquettes, g[2]['etiquettes']);
      expect(aff(t, 'Source : Usage de la clinique — participation du personnel aux événements — montant standard 1 000 par agent.'), isTrue);
      await fermerToasts(t);
    });

    testWidgets('« Voir les participations » ouvre le registre déjà réglé sur l’événement (lien profond)', (t) async {
      await ouvrir(t, posteRhc(), 'm10-evenements');
      await cliquer(t, find.byTooltip('Voir les participations').first);
      expect(find.text('Frais de participation'), findsWidgets);
      expect(rhcEvenementCible, isNull, reason: 'le message est consommé UNE fois');
      final k = kpisRhc(t);
      expect(k['Participations'], '43', reason: 'les 43 participations de l’événement le plus récent');
      expect(texteEcran(t).contains(sansEspaces('Mariage — KASSA Augustin — 11/08/2026').toLowerCase()), isTrue);
      await fermerToasts(t);
    });

    testWidgets('liste de collecte : la maquette (cartouche, une ligne par agent triée par nom, total refait, mention « ni recette ni charge »)', (t) async {
      await ouvrir(t, posteRhc(), 'm10-evenements');
      await cliquer(t, find.byTooltip('Imprimer la liste de collecte').first);
      final p = obj(e['collecte']);
      expect(find.text('Liste de collecte — participation du personnel'.toUpperCase()), findsOneWidget);
      for (final c in (p['cartouche'] as List)) {
        presentes(t, [(c as List)[0], c[1]], raison: 'cartouche');
      }
      final lignes = [for (final l in (obj((p['tableaux'] as List).first)['lignes'] as List)) (l as List).cast<Object?>()];
      expect(lignes.length, 43);
      presentes(t, [for (final l in lignes.take(6)) ...l.take(4)], raison: 'ligne');
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.textContaining('transitent par la clinique pour le compte du collectif'), findsOneWidget);
      expect(find.text('Le Caissier'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('création : refus sans intitulé ; UNE participation par agent hors bénéficiaire ; référence EVT-0010 en série ; journal ; annulation visible', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-evenements');
      final col = m.collection('evenements'), parts = m.collection('participations');
      final n0 = col.toutes.length, p0 = parts.toutes.length;
      await appuyer(t, 'Nouvel événement');
      final cr = obj(e['creation']);
      final d = obj(cr['defauts']);
      for (final k in ['nature', 'beneficiaireId', 'portee', 'date', 'montantParAgent', 'periodePaiement', 'modeParDefaut']) {
        expect('${formulaire(t)[k]}', '${d[k]}', reason: 'défaut $k');
      }
      expect(find.textContaining('une participation est créée pour chacun des 43 autres agents'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer et engendrer les participations'));
      await t.pump(const Duration(milliseconds: 300));
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'nature': 'mariage', 'libelle': 'Mariage de KORA Salifou', 'beneficiaireId': 'EMP05', 'montantParAgent': '1500', 'periodePaiement': '2026-12', 'modeParDefaut': 'comptant', 'observation': 'Cotisation de service.'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer et engendrer les participations'));
      await t.pump(const Duration(milliseconds: 400));
      final ok = obj(cr['creee']);
      final evt = col.toutes.first;
      fichesEgales(evt, obj(ok['fiche']), ignores: {'beneficiaire'});
      expect(evt['beneficiaire'], 'YENI M’PO Florent');
      expect(evt['reference'], 'EVT-0010', reason: 'la série SUIT le registre (E743)');
      final nouvelles = parts.toutes.take(parts.toutes.length - p0).toList();
      expect(nouvelles.length, ok['nbParticipations']);
      expect([for (final p in nouvelles) p['employeId']], ok['agents']);
      expect(nouvelles.any((p) => p['employeId'] == 'EMP05'), isFalse, reason: 'le bénéficiaire ne cotise pas à son propre événement');
      fichesEgales(nouvelles.first, obj(ok['premiere']), ignores: {'evenementId'});
      expect(find.text('Événement créé.'), findsOneWidget);
      expect(aff(t, '43 participation(s) engendrée(s) — 64 500 FCFA attendus.'), isTrue);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Création d’un événement du personnel'), isTrue);
      kpisIdentiquesRhc(t, [
        {'libelle': 'Événements enregistrés', 'valeur': '10', 'indice': null},
      ]);
      await fermerToasts(t);
    });

    testWidgets('sélection d’agents : le bénéficiaire en est exclu même choisi ; une sélection vide retombe sur tout le personnel ; un montant nul retombe sur 1 000', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-evenements');
      final parts = m.collection('participations');
      final p0 = parts.toutes.length;
      await appuyer(t, 'Nouvel événement');
      poser(t, {'nature': 'deces', 'libelle': 'Décès du père de TEPA Séraphine', 'beneficiaireId': 'EMP10', 'portee': 'selection', 'montantParAgent': '0', 'periodePaiement': '2026-11'});
      formulaire(t).poser('participants', ['EMP10', 'EMP11', 'EMP12']);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer et engendrer les participations'));
      await t.pump(const Duration(milliseconds: 400));
      final s = obj(e['selection']);
      fichesEgales(m.collection('evenements').toutes.first, obj(s['fiche']), ignores: {'beneficiaire', 'reference'});
      expect(m.collection('evenements').toutes.first['reference'], 'EVT-0010');
      expect([for (final p in parts.toutes.take(parts.toutes.length - p0)) [p['employeId'], p['montant']]], s['participants']);
      await fermerToasts(t);
      final p1 = parts.toutes.length;
      await appuyer(t, 'Nouvel événement');
      poser(t, {'nature': 'bapteme', 'libelle': 'Baptême test', 'beneficiaireId': 'EMP11', 'portee': 'selection', 'periodePaiement': '2026-11'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer et engendrer les participations'));
      await t.pump(const Duration(milliseconds: 400));
      expect(parts.toutes.length - p1, e['selectionVide'] == null ? 0 : obj(e['selectionVide'])['participants']);
      await fermerToasts(t);
    });

    testWidgets('modification : SEULES les participations non réglées suivent le nouveau montant ; les règlements déjà encaissés restent intacts', (t) async {
      final m = posteRhc();
      final parts = m.collection('participations');
      final cible = m.collection('evenements').toutes.firstWhere((x) => x['libelle'] == 'Mariage — KASSA Augustin');
      final miens = parts.toutes.where((p) => p['evenementId'] == cible['id']).toList();
      miens[0]..['statutPaiement'] = 'paye'..['datePaiement'] = '2026-10-30';
      miens[1]..['statutPaiement'] = 'paye'..['datePaiement'] = '2026-10-30';
      await ouvrir(t, m, 'm10-evenements');
      await chercher(t, 'KASSA');
      await cliquer(t, find.byTooltip('Modifier l’événement').first);
      expect(find.textContaining('2 participation(s) sont déjà réglées pour cet événement.'), findsOneWidget);
      poser(t, {'montantParAgent': '2000', 'periodePaiement': '2027-01', 'libelle': 'Mariage de KASSA A.'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('41 participation(s) non réglée(s) mise(s) à jour ; 2 déjà encaissée(s) laissée(s) intacte(s).'), findsOneWidget);
      final apres = parts.toutes.where((p) => p['evenementId'] == cible['id']).toList();
      expect(apres.where((p) => p['statutPaiement'] == 'paye').every((p) => p['montant'] == 1000 && p['evenementLibelle'] == 'Mariage — KASSA Augustin'), isTrue);
      expect(apres.where((p) => p['statutPaiement'] != 'paye').every((p) => p['montant'] == 2000 && p['periodeRetenue'] == '2027-01' && p['evenementLibelle'] == 'Mariage de KASSA A.'), isTrue);
      await fermerToasts(t);
    });

    testWidgets('annulation : un avertissement réglé sur ce qu’il y a à perdre, le motif exigé, RG-14 (rien n’est supprimé), et l’annulation restitue l’événement ET ses participations', (t) async {
      final m = posteRhc();
      final evts = m.collection('evenements'), parts = m.collection('participations');
      final cible = evts.toutes.firstWhere((x) => x['libelle'] == 'Mariage — KASSA Augustin');
      for (final p in parts.toutes.where((p) => p['evenementId'] == cible['id']).take(2)) {
        p..['statutPaiement'] = 'paye'..['datePaiement'] = '2026-10-30';
      }
      await ouvrir(t, m, 'm10-evenements');
      await chercher(t, 'KASSA');
      await cliquer(t, find.byTooltip('Annuler l’événement').first);
      expect(aff(t, 'Attention. 2 participation(s) sur 43 ont déjà été réglées, pour 2 000 FCFA.'), isTrue);
      expect(find.textContaining('les sommes déjà encaissées restent tracées et devront être restituées hors application'), findsOneWidget);
      // Le motif est OBLIGATOIRE : sans motif, rien ne part.
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler l’événement').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(evts.archivees, isEmpty);
      await t.enterText(find.byType(TextField).last, 'Doublon');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler l’événement').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Événement annulé.'), findsOneWidget);
      expect(find.text('41 participation(s) non réglée(s) archivée(s).'), findsOneWidget);
      expect(evts.archivees.length, 1);
      expect(parts.archivees.length, 41);
      expect(parts.toutes.length, 387, reason: 'RG-14 : rien n’est supprimé');
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Motif d’archivage' && (a['apres'] as Map)['motif'] == 'Doublon'), isTrue);
      // L'annulation est visible et restitue TOUT.
      await t.tap(find.text('Annuler').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(evts.archivees, isEmpty);
      expect(parts.archivees, isEmpty);
      await fermerToasts(t);
    });

    testWidgets('trois situations, trois messages : aucune participation, aucune réglée', (t) async {
      final m = posteRhc();
      m.collection('evenements').inserer({'statut': 'actif', 'reference': 'EVT-9999', 'nature': 'autre', 'libelle': 'Sans participation', 'beneficiaire': 'X', 'date': '2026-10-01', 'montantParAgent': 1000, 'periodePaiement': '2026-10'});
      await ouvrir(t, m, 'm10-evenements');
      await chercher(t, 'Sans participation');
      await cliquer(t, find.byTooltip('Annuler l’événement').first);
      expect(find.textContaining('Aucune participation n’a encore été engendrée pour cet événement : l’annulation n’a donc aucune conséquence financière.'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler').first);
      await t.pump(const Duration(milliseconds: 300));
      await chercher(t, 'Naissance — TAKI Bibata');
      await cliquer(t, find.byTooltip('Annuler l’événement').first);
      expect(find.textContaining('43 participation(s) ont été engendrées, aucune n’a encore été réglée. L’annulation les archive toutes : rien n’a été encaissé, rien n’est à restituer.'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('droits : en lecture seule, ni création, ni modification, ni annulation (commandes ABSENTES) ; imprimer et voir restent offerts', (t) async {
      await ouvrirM14(t, posteRhc(), 'm10-evenements', role: 'direction', donnees: donneesLectureSeule('direction', 'm10-evenements'), horloge: auj);
      expect(find.widgetWithText(BoutonSigh, 'Nouvel événement'), findsNothing);
      expect(find.byTooltip('Modifier l’événement'), findsNothing);
      expect(find.byTooltip('Annuler l’événement'), findsNothing);
      expect(find.byTooltip('Voir les participations'), findsWidgets);
      expect(find.byTooltip('Imprimer la liste de collecte'), findsWidgets);
      await fermerToasts(t);
    });
  });

  group('m10-participations', () {
    final p = obj(vc['participations']);
    final evtId = '${obj(obj(p['parEvenement'])['regles'])['Événement']}';

    testWidgets('ouverture : indicateurs, vingt premières lignes triées par agent, filtres et trois cartes identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-participations');
      final o = obj(p['ouverture']);
      kpisIdentiquesRhc(t, obj(o['ecran'])['kpis']);
      final lignes = lignesTableau(o['ecran']);
      presentes(t, [for (final l in lignes.take(10)) ...l.take(5)], raison: 'ligne');
      expect(find.byTooltip('Changer de mode de règlement'), findsNWidgets(20));
      expect(find.byTooltip('Encaisser au comptant').evaluate().length + find.byTooltip('Confirmer la retenue sur salaire').evaluate().length, 20);
      final g = liste(o['graphes']);
      await t.scrollUntilVisible(find.text('Participations par service'), 400, scrollable: find.byType(Scrollable).first);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).etiquettes, g[0]['etiquettes']);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).valeurs, g[0]['donnees']);
      expect(t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres).first).etiquettes, g[2]['etiquettes']);
      await fermerToasts(t);
    });

    testWidgets('filtres : par événement, par mode, par état ; l’état vide se dit', (t) async {
      await ouvrir(t, posteRhc(), 'm10-participations');
      await regler(t, 'evenement', evtId);
      kpisIdentiquesRhc(t, obj(p['parEvenement'])['kpis']);
      await regler(t, 'evenement', '');
      await regler(t, 'mode', 'comptant');
      kpisIdentiquesRhc(t, obj(p['parMode'])['kpis']);
      await regler(t, 'mode', '');
      await regler(t, 'etat', 'paye');
      kpisIdentiquesRhc(t, obj(p['parEtat'])['kpis']);
      expect(find.text('Aucune participation pour ces critères.'), findsOneWidget);
      expect(find.textContaining('Les participations naissent de la création d’un événement'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('le parcours de règlement : changer de mode, encaisser (reçu en série), confirmer la retenue, reçu imprimé, annuler avec motif — dans l’ordre de la maquette', (t) async {
      final m = posteRhc();
      final col = m.collection('participations');
      await ouvrir(t, m, 'm10-participations');
      await regler(t, 'evenement', evtId);
      final cm = obj(p['changerMode']);
      final salaire = '${obj(obj(cm['versComptant'])['fiche'])['agent']}';
      final comptant = '${obj(obj(obj(p['encaisser'])['reussi'])['fiche'])['agent']}';
      Fiche ficheDe(String agent) => col.toutes.firstWhere((x) => x['evenementId'] == evtId && x['agent'] == agent);
      // Les commandes de la ligne suivent son mode : « confirmer la retenue » au salaire, « encaisser » au comptant.
      await chercher(t, salaire);
      expect(find.byTooltip('Confirmer la retenue sur salaire'), findsOneWidget);
      expect(find.byTooltip('Encaisser au comptant'), findsNothing);
      // 1. salaire → comptant
      await cliquer(t, find.byTooltip('Changer de mode de règlement').first);
      expect({for (final k in ['mode', 'periodeRetenue']) k: '${formulaire(t)[k]}'}, obj(cm['defauts']));
      expect(aff(t, 'L’imputation sur salaire porte 1 000 en retenue au bulletin du mois choisi.'), isTrue);
      poser(t, {'mode': 'comptant'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(ficheDe(salaire), obj(obj(cm['versComptant'])['fiche']), ignores: {'id'});
      expect(find.text('Versement attendu à la caisse.'), findsOneWidget);
      await fermerToasts(t);
      // 2. comptant → salaire, mois de décembre
      await chercher(t, salaire);
      await cliquer(t, find.byTooltip('Changer de mode de règlement').first);
      poser(t, {'mode': 'salaire', 'periodeRetenue': '2026-12'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(ficheDe(salaire), obj(obj(cm['versSalaire'])['fiche']), ignores: {'id'});
      expect(find.text('Retenue portée au bulletin de décembre 2026.'), findsOneWidget);
      await fermerToasts(t);
      // 3. sur salaire sans mois saisi : l'ancien est GARDÉ
      await chercher(t, salaire);
      await cliquer(t, find.byTooltip('Changer de mode de règlement').first);
      poser(t, {'mode': 'salaire', 'periodeRetenue': ''});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(ficheDe(salaire)['periodeRetenue'], '2026-12');
      expect(find.text('Retenue portée au bulletin de la période choisie.'), findsOneWidget);
      await fermerToasts(t);
      // 4. encaisser : montant obligatoire, reçu REC-PART-0001
      final enc = obj(p['encaisser']);
      await chercher(t, comptant);
      await cliquer(t, find.byTooltip('Encaisser au comptant').first);
      expect({for (final k in ['montantVerse', 'datePaiement']) k: '${formulaire(t)[k]}'}, {'montantVerse': '1000', 'datePaiement': '2026-10-30'});
      poser(t, {'montantVerse': ''});
      await t.tap(find.widgetWithText(BoutonSigh, 'Valider l’encaissement'));
      await t.pump(const Duration(milliseconds: 300));
      expect(ficheDe(comptant)['statutPaiement'], isNot('paye'), reason: 'refus : rien n’est écrit');
      poser(t, {'montantVerse': '1200', 'observation': 'Versé en main propre.'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Valider l’encaissement'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(ficheDe(comptant), obj(obj(enc['reussi'])['fiche']), ignores: {'id', ...champsAuteur});
      expect(ficheDe(comptant)['encaissePar'], utilisateurTest);
      expect(aff(t, 'Reçu REC-PART-0001 — 1 200 FCFA'), isTrue);
      final audit = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Encaissement d’une participation');
      expect([audit['avant'], audit['apres']], [{'statut': 'du'}, {'statut': 'paye', 'recu': 'REC-PART-0001'}]);
      await fermerToasts(t);
      // La ligne réglée n'offre plus que le reçu et l'annulation.
      await chercher(t, comptant);
      expect(find.byTooltip('Imprimer le reçu'), findsOneWidget);
      expect(find.byTooltip('Annuler le règlement'), findsOneWidget);
      expect(find.byTooltip('Changer de mode de règlement'), findsNothing);
      expect(find.text('Réglée'), findsWidgets);
      expect(find.textContaining('REC-PART-0001'), findsWidgets);
      // 5. le reçu SUIT la série
      final second = '${obj(obj(enc['second'])['fiche'])['agent']}';
      await chercher(t, second);
      await cliquer(t, find.byTooltip('Encaisser au comptant').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Valider l’encaissement'));
      await t.pump(const Duration(milliseconds: 400));
      expect(ficheDe(second)['recu'], 'REC-PART-0002');
      await fermerToasts(t);
      // 6. confirmer la retenue : le mois est NOMMÉ au message
      final rt = obj(p['retenue']);
      await chercher(t, salaire);
      await cliquer(t, find.byTooltip('Confirmer la retenue sur salaire').first);
      expect(find.text('Confirmer la retenue sur salaire ?'), findsOneWidget);
      expect(find.textContaining('est portée en retenue sur le bulletin de décembre 2026.'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Confirmer la retenue'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(ficheDe(salaire), obj(obj(rt['resultat'])['fiche']), ignores: {'id', ...champsAuteur});
      expect(find.text('Retenue confirmée.'), findsOneWidget);
      await fermerToasts(t);
      // 7. reçu imprimé : montant en lettres, mention « ni recette ni charge »
      await chercher(t, comptant);
      await cliquer(t, find.byTooltip('Imprimer le reçu').first);
      expect(find.text('Reçu de participation'.toUpperCase()), findsOneWidget);
      expect(find.text('Arrêté le présent reçu à la somme de mille deux cents francs CFA.'), findsOneWidget);
      expect(find.textContaining('elle ne constitue ni une recette de l’établissement ni une charge.'), findsOneWidget);
      presentes(t, ['REC-PART-0001', comptant, 'Versé']);
      await t.tap(find.widgetWithText(BoutonSigh, 'Fermer').last);
      await t.pump(const Duration(milliseconds: 300));
      // 8. annulation : motif obligatoire, la fiche ne garde que le motif et l'auteur
      final an = obj(p['annulation']);
      await chercher(t, comptant);
      await cliquer(t, find.byTooltip('Annuler le règlement').first);
      expect(aff(t, 'Le règlement de 1 000 FCFA par $comptant (reçu REC-PART-0001) est annulé et la participation redevient due.'), isTrue);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler le règlement').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(ficheDe(comptant)['statutPaiement'], 'paye', reason: 'sans motif, rien ne part');
      await t.enterText(find.byType(TextField).last, 'Erreur de caisse');
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler le règlement').last);
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(ficheDe(comptant), obj(obj(an['resultat'])['fiche']), ignores: {'id', ...champsAuteur});
      expect(find.text('Règlement annulé.'), findsOneWidget);
      final j = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Annulation d’un règlement de participation');
      expect(j['apres'], {'statut': 'du', 'motif': 'Erreur de caisse'});
      expect(col.toutes.length, 387, reason: 'RG-14 : rien n’est supprimé');
      await fermerToasts(t);
    });

    testWidgets('états imprimés : l’état filtré sur l’événement porte son filtre ; le pied refait le montant ENCAISSÉ depuis les lignes', (t) async {
      final m = posteRhc();
      final col = m.collection('participations');
      for (final x in col.toutes.where((x) => x['evenementId'] == evtId).take(3)) {
        x..['statutPaiement'] = 'paye'..['recu'] = 'REC-PART-X';
      }
      await ouvrir(t, m, 'm10-participations');
      await regler(t, 'evenement', evtId);
      await appuyer(t, 'Imprimer l’état');
      expect(find.text('État des participations du personnel'.toUpperCase()), findsOneWidget);
      expect(find.text('Mariage — KASSA Augustin — 11/08/2026'), findsWidgets);
      presentes(t, ['Participations', '43', 'Montant attendu', '43 000 FCFA', 'Montant encaissé', '3 000 FCFA', 'Établi par', utilisateurTest]);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('La Directrice Administrative'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('droits : en lecture seule, aucune commande d’écriture ; le reçu d’une participation réglée reste imprimable', (t) async {
      final m = posteRhc();
      m.collection('participations').toutes.first
        ..['statutPaiement'] = 'paye'
        ..['recu'] = 'REC-PART-0001';
      await ouvrirM14(t, m, 'm10-participations', role: 'direction', donnees: donneesLectureSeule('direction', 'm10-participations'), horloge: auj);
      expect(find.byTooltip('Changer de mode de règlement'), findsNothing);
      expect(find.byTooltip('Encaisser au comptant'), findsNothing);
      expect(find.byTooltip('Confirmer la retenue sur salaire'), findsNothing);
      expect(find.byTooltip('Annuler le règlement'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer l’état'), findsOneWidget);
      await fermerToasts(t);
    });
  });

  group('m10-assurance-personnel', () {
    final a = obj(vc['assurance']);

    testWidgets('ouverture sur « douze derniers mois » : indicateurs, tableau trié du plus récent, cartes et graphiques identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-assurance-personnel');
      final o = obj(a['ouverture']);
      kpisIdentiquesRhc(t, obj(o['ecran'])['kpis']);
      expect('${formulaire2(t, 'periode')}', '365');
      final lignes = lignesTableau(o['ecran']);
      presentes(t, [for (final l in lignes.take(8)) ...[l[0], ...l.skip(2).take(5)]], raison: 'ligne');
      expect(find.text('Prestations prises en charge — Douze derniers mois'), findsOneWidget);
      expect(find.byTooltip('Ouvrir le dossier du patient'), findsNWidgets(20));
      // « Ce tableau ne se saisit pas » : AUCUNE commande d'écriture.
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.textContaining('Ce tableau ne se saisit pas.'), findsOneWidget);
      final g = liste(o['graphes']);
      await t.scrollUntilVisible(find.text('Valeur mensuelle de l’avantage'), 400, scrollable: find.byType(Scrollable).first);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).etiquettes, g[0]['etiquettes']);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).valeurs, g[0]['donnees']);
      expect(t.widget<GraphiqueLigne>(find.byType(GraphiqueLigne).first).etiquettes, g.last['etiquettes']);
      await fermerToasts(t);
    });

    for (final periode in ['toujours', '30', '90', '180', '365']) {
      testWidgets('période « $periode » : indicateurs et vide dit', (t) async {
        await ouvrir(t, posteRhc(), 'm10-assurance-personnel');
        await regler(t, 'periode', periode == 'toujours' ? '' : periode);
        final cas = obj(obj(a['periodes'])[periode]);
        kpisIdentiquesRhc(t, cas['kpis']);
        if ((cas['nb'] as int?) == 0) {
          expect(find.text('Aucune prestation sur la période retenue.'), findsOneWidget);
          expect(find.textContaining('Élargir la période, ou vérifier que l’agent dispose bien d’un dossier patient à son nom.'), findsOneWidget);
        }
        await fermerToasts(t);
      });
    }

    testWidgets('filtre de fonction, état imprimé (pied refait) et ouverture du dossier par le répertoire des patients', (t) async {
      await ouvrir(t, posteRhc(), 'm10-assurance-personnel');
      await regler(t, 'fonction', 'caissiere');
      expect(find.text('Aucune prestation sur la période retenue.'), findsOneWidget);
      await regler(t, 'fonction', 'medecin');
      kpisIdentiquesRhc(t, obj(obj(a['parFonction'])['medecin'])['kpis']);
      await regler(t, 'fonction', '');
      await appuyer(t, 'Imprimer l’état');
      final et = obj(obj(obj(a['periodes'])['365'])['etat']);
      expect(find.text('État de la prise en charge du personnel'.toUpperCase()), findsOneWidget);
      for (final c in (et['cartouche'] as List)) {
        final l = c as List;
        presentes(t, [l[0], l[0] == 'Établi par' ? utilisateurTest : l[1]], raison: 'cartouche');
      }
      final tab = obj((et['tableaux'] as List).first);
      presentes(t, [for (final l in (tab['lignes'] as List).take(5)) ...(l as List)], raison: 'ligne');
      presentes(t, (tab['pied'] as List).first as List, raison: 'pied');
      expect(find.textContaining('ne donnent lieu à aucune écriture comptable'), findsOneWidget);
      expect(find.text('Le Directeur Médical'), findsOneWidget);
      await fermerToasts(t);
    });

    testWidgets('le tableau ne naît d’aucune saisie : une consultation d’agent apparaît, une hospitalisation sans montant vaut 0, un agent sans dossier patient n’y figure pas', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-assurance-personnel');
      expect(kpisRhc(t)['Prestations prises en charge'], '71');
      final patients = m.collection('patients');
      patients.toutes.where((p) => p['personnelId'] == 'EMP01').forEach((p) => p.remove('personnelId'));
      await ouvrir(t, m, 'm10-assurance-personnel');
      expect(int.parse(kpisRhc(t)['Agents ayant un dossier patient']!), 17);
      expect(int.parse(kpisRhc(t)['Prestations prises en charge']!) < 71, isTrue);
      await fermerToasts(t);
    });
  });

  group('m10-securite-entretien', () {
    final s = obj(vc['securite']);

    testWidgets('indicateurs, légendes reprises telles quelles, rotation sur 14 jours et agents identiques à la maquette', (t) async {
      await ouvrir(t, posteRhc(), 'm10-securite-entretien');
      kpisIdentiquesRhc(t, obj(s['ecran'])['kpis']);
      for (final mot in ['Garde — 24 h', 'Soirée — de 18h à 8h', 'Entretien général de la journée', 'Rotation à trois agents sur un cycle de 3 jours.', 'Rotation à trois agents : une permanence, deux entretiens généraux.']) {
        expect(find.text(mot), findsWidgets, reason: mot);
      }
      expect(find.textContaining('G = GARDE 24H, S = SOIRÉE 18H à 8H, R = REPOS'), findsOneWidget);
      final grille = obj(s['grille']);
      // 14 jours, de J-3 à J+10 : « ma27 » … « lu9 ».
      for (final h in (grille['entetes'] as List).skip(2)) {
        expect(find.byTooltip('${h}'.replaceAll(' ', '').toLowerCase()), findsWidgets, reason: '$h');
      }
      for (final l in (grille['lignes'] as List)) {
        expect(find.text('${(l as List)[0]}'), findsWidgets, reason: '${l[0]}');
      }
      expect(find.byTooltip('Affecter une vacation'), findsNWidgets(6 * 14), reason: 'aucune vacation dans la fenêtre : chaque case est « + »');
      presentes(t, [for (final l in lignesTableau({'tableaux': [(s['agents'] as Map)]}) .take(6)) ...l.take(5)], raison: 'agents');
      expect(find.byTooltip('Modifier'), findsNWidgets(6));
      expect(find.byTooltip('Archiver'), findsNWidgets(6));
      expect(find.textContaining('Source : Plannings des agents d’entretien et des agents de sécurité de la clinique.'), findsOneWidget);
      expect(find.text('Aucune vacation de sécurité ou d’entretien enregistrée.'), findsNothing, reason: 'le jeu porte des vacations : les statistiques se dessinent');
      final g = liste(s['graphes']);
      expect(t.widget<GraphiqueBarres>(find.byType(GraphiqueBarres).first).etiquettes, g[0]['etiquettes']);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).etiquettes, g[1]['etiquettes']);
      expect(t.widget<GraphiqueAnneau>(find.byType(GraphiqueAnneau).first).valeurs, g[1]['donnees']);
      await fermerToasts(t);
    });

    Future<void> ouvrirCase(WidgetTester t, String agent, DateTime jour) async {
      final f = find.byKey(Key('rhc:cellule:${'$agent'}:${jour.toIso8601String().substring(0, 10)}'));
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('affecter : les types suivent la FONCTION ; enregistrer écrit au planning VALIDÉ ; modifier ; retirer (archivage annulable)', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-securite-entretien');
      final plan = m.collection('planning');
      // Un agent de sécurité : garde, soirée, repos ; un agent d'entretien : quatre types.
      await ouvrirCase(t, 'EMP38', DateTime(2026, 11, 8));
      expect(find.text('Rotation — OURTCHA Tereyama'), findsOneWidget);
      expect(find.text('Vacation actuelle'), findsOneWidget);
      expect(find.text('Aucune'), findsOneWidget);
      final types = [for (final x in obj(s['modaleSecurite'])['types'] as List) '${(x as List)[1]}'];
      expect(t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur.champs.firstWhere((c) => c.nom == 'type').options.map((o) => o.libelle).toList(), types);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler').last);
      await t.pump(const Duration(milliseconds: 300));
      await ouvrirCase(t, 'EMP41', DateTime(2026, 11, 8));
      final ent = [for (final x in obj(s['modaleEntretien'])['types'] as List) '${(x as List)[1]}'];
      expect(t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur.champs.firstWhere((c) => c.nom == 'type').options.map((o) => o.libelle).toList(), ent);
      await t.tap(find.widgetWithText(BoutonSigh, 'Annuler').last);
      await t.pump(const Duration(milliseconds: 300));
      // Affecter : une soirée le 27/10.
      final n0 = plan.toutes.length;
      await ouvrirCase(t, 'EMP38', DateTime(2026, 10, 27));
      poser(t, {'type': 'soiree', 'observation': 'Remplacement.'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final cree = plan.toutes.first;
      fichesEgales(cree, obj(obj(s['affectation'])['fiche']), ignores: {'id'});
      expect(plan.toutes.length, n0 + 1);
      expect(find.text('OURTCHA Tereyama — Soirée le 27/10/2026'), findsOneWidget);
      await fermerToasts(t);
      // Modifier : le bouton « Retirer » apparaît, la vacation devient un repos.
      await ouvrirCase(t, 'EMP38', DateTime(2026, 10, 27));
      expect(find.text('Soirée'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Retirer'), findsOneWidget);
      poser(t, {'type': 'repos24'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(plan.parId(cree['id'])!['type'], 'repos24');
      expect(plan.toutes.length, n0 + 1, reason: 'modifier ne crée pas de seconde vacation');
      await fermerToasts(t);
      // Retirer : confirmation, archivage (RG-14), la case redevient « + », annulation visible.
      await ouvrirCase(t, 'EMP38', DateTime(2026, 10, 27));
      await t.tap(find.widgetWithText(BoutonSigh, 'Retirer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('La vacation est archivée, pas supprimée (RG-14)'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Retirer').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(plan.parId(cree['id'])!['statut'], 'archive');
      expect(plan.toutes.length, n0 + 1, reason: 'rien n’est supprimé');
      expect(find.text('Vacation retirée.'), findsOneWidget);
      await t.tap(find.text('Annuler').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(plan.parId(cree['id'])!['statut'], isNot('archive'));
      await fermerToasts(t);
    });

    testWidgets('une garde la veille interdit la suivante : refus NOMMÉ, la modale reste ouverte, rien n’est écrit ; une soirée, elle, passe', (t) async {
      final m = posteRhc();
      final plan = m.collection('planning');
      plan.inserer({'statut': 'validee', 'date': '2026-10-28', 'employeId': 'EMP38', 'employe': 'OURTCHA Tereyama', 'fonction': 'securite', 'service': 'Direction', 'type': 'garde'});
      await ouvrir(t, m, 'm10-securite-entretien');
      final n0 = plan.toutes.length;
      await ouvrirCase(t, 'EMP38', DateTime(2026, 10, 29));
      poser(t, {'type': 'garde'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 300));
      final inc = obj(s['incompatibilite']);
      expect(find.text('${((inc['toasts'] as List).first as List)[0]}'), findsOneWidget);
      expect(find.text('${((inc['toasts'] as List).first as List)[1]}'), findsOneWidget);
      expect(plan.toutes.length, n0, reason: 'refus : rien n’est écrit');
      expect(find.text('Rotation — OURTCHA Tereyama'), findsOneWidget, reason: 'la modale reste ouverte');
      poser(t, {'type': 'soiree'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(plan.toutes.length, n0 + 1);
      await fermerToasts(t);
    });

    testWidgets('nouvel agent : refus sans nom, matricule SE-001 puis SE-002 EN SÉRIE, rattaché à la Direction, poste par défaut ; l’indicateur et la grille suivent (E749) ; modifier ; archiver avec motif', (t) async {
      final m = posteRhc();
      await ouvrir(t, m, 'm10-securite-entretien');
      final col = m.collection('personnel');
      final c = obj(s['creation']);
      await appuyer(t, 'Nouvel agent');
      final d = obj(c['defauts']);
      for (final k in ['fonction', 'dateEmbauche', 'salaireBase']) {
        expect('${formulaire(t)[k]}', '${d[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      await fermerToasts(t);
      poser(t, {'nomComplet': 'ADAM Ibrahim', 'fonction': 'entretien', 'salaireBase': '45000', 'telephone': '0190000000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(c['creee'])['fiche']), ignores: {'id'});
      expect(find.text('Agent créé.'), findsOneWidget);
      await fermerToasts(t);
      await appuyer(t, 'Nouvel agent');
      poser(t, {'nomComplet': 'BIO Mama'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(c['seconde'])['fiche']), ignores: {'id'});
      await fermerToasts(t);
      // E749 : l'indicateur et la grille suivent la création.
      kpisIdentiquesRhc(t, obj(s['apresCreation'])['kpis']);
      expect(find.byTooltip('Affecter une vacation'), findsNWidgets(8 * 14));
      // Modifier : le matricule et le service sont GARDÉS.
      final modif = obj(s['modificationAgent']);
      await chercher(t, 'ADAM Ibrahim');
      await cliquer(t, find.byTooltip('Modifier').first);
      for (final k in ['nomComplet', 'fonction', 'poste', 'dateEmbauche', 'salaireBase', 'telephone']) {
        expect('${formulaire(t)[k]}', '${obj(modif['valeurs'])[k]}', reason: 'valeur $k');
      }
      poser(t, {'salaireBase': '47000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['nomComplet'] == 'ADAM Ibrahim'), obj(obj(modif['resultat'])['fiche']), ignores: {'id'});
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      await fermerToasts(t);
      // Archiver : motif exigé, RG-14.
      await chercher(t, 'ADAM Ibrahim');
      await archiverLigne(t, 'Doublon');
      expect(col.archivees.length, 1);
      expect(col.toutes.firstWhere((x) => x['nomComplet'] == 'ADAM Ibrahim')['statut'], 'archive');
      kpisIdentiquesRhc(t, obj(s['archivageAgent'])['kpis']);
      await fermerToasts(t);
    });

    testWidgets('planning imprimé : la période, les vacations par jour, les deux signatures ; droits : en lecture seule, ni case ouvrable ni commande d’écriture', (t) async {
      await ouvrir(t, posteRhc(), 'm10-securite-entretien');
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Imprimer le planning'));
      final p = obj(s['impression']);
      expect(find.text('Planning des agents de sécurité et d’entretien'.toUpperCase()), findsOneWidget);
      expect(find.text('Du 27/10/2026 au 09/11/2026'), findsOneWidget);
      expect(find.text('Le Chef de service'), findsOneWidget);
      expect(find.text('OURTCHA TEREYAMA'), findsOneWidget);
      presentes(t, [for (final h in (obj((p['tableaux'] as List).first)['entetes'] as List)) h]);
      await t.tap(find.widgetWithText(BoutonSigh, 'Fermer').last);
      await t.pump(const Duration(milliseconds: 300));
      await fermerToasts(t);
      await ouvrirM14(t, posteRhc(), 'm10-securite-entretien', role: 'direction', donnees: donneesLectureSeule('direction', 'm10-securite-entretien'), horloge: auj);
      expect(find.byTooltip('Affecter une vacation'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Nouvel agent'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Archiver'), findsNothing);
      expect(find.text('—'), findsWidgets, reason: 'la case se LIT, elle ne s’ouvre pas');
      await fermerToasts(t);
    });
  });
}

/// La valeur d'un filtre de la barre.
Object? formulaire2(WidgetTester t, String nom) => t.widget<FormulaireSigh>(find.byKey(Key('rhb:filtre:$nom'))).controleur[nom];
