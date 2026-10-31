import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// PILOTAGE (PIL) — le COMPORTEMENT des treize écrans (la parité N1 est dans `pil_test.dart`). Les règles (filtres, durée moyenne sur les séjours terminés,
/// deux colonnes jamais additionnées, rapprochement arrêté, « non calculable » ≠ zéro, périodes calendaires…) sont rejouées sur les vecteurs de la maquette
/// par `packages/domaine/test/pilotage_test.dart` ; ici, l'ÉCRAN : ce qui est lu, annoncé, refusé — et ce qui n'est JAMAIS inventé. Les chiffres attendus
/// viennent du vecteur tiré de l'écran réel de la maquette quand il existe : le même chiffre doit sortir de l'écran Flutter.
Map<String, Object?> vecteurs() =>
    (jsonDecode(File('../../packages/domaine/test/vecteurs/pilotage.json').readAsStringSync()) as Map).cast<String, Object?>();
Map<String, Object?> cm(Object? v) => (v as Map).cast<String, Object?>();
List<List<Object?>> kp(Object? v) => [for (final k in (v as List)) (k as List).cast<Object?>()];
String valeurVecteur(Object? kpis, String libelle) => '${kp(kpis).firstWhere((k) => k[0] == libelle)[1]}';

Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);
/// Un texte affiché, comparé SANS tenir compte de la nature des espaces (insécables du formatage français, ordinaires du vecteur).
Finder ft(Object? attendu) => find.byWidgetPredicate((w) => w is Text && w.data != null && nt(w.data) == nt(attendu), description: 'texte « ${nt(attendu)} »');
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

/// Pose [valeur] dans le champ [champ] (un champ de date : la saisie est une chaîne ISO, comme celle que rend le sélecteur de dates).
Future<void> poserChamp(WidgetTester t, String champ, String valeur) async {
  final f = t.widgetList<FormulaireSigh>(find.byType(FormulaireSigh)).firstWhere((x) => x.controleur.champs.any((c) => c.nom == champ));
  f.controleur.poser(champ, valeur);
  await t.pump(const Duration(milliseconds: 300));
}

void archiverTout(Magasin m, String collection) {
  for (final f in m.collection(collection).actives.toList()) {
    m.collection(collection).archiver(f['id']);
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('m5-stats-examens : chaque axe est un FILTRE', () {
    final e = cm(vecteurs()['examens']);
    final sc = cm(e['scenarios']);

    casM14('sans filtre : la population entière du jeu (358 examens), comme la maquette', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm5-stats-examens');
      expect(valeurVecteur(cm(e['defaut'])['kpis'], 'Examens (population filtrée)'), '358');
      expect(find.text('358'), findsOneWidget);
      expect(find.text('Par section d’examen'), findsOneWidget);
      expect(find.text('NFS COMPLETE (HEMOGRAMME)'), findsOneWidget);
    });

    casM14('le service demandeur filtre : « Maternité » ne garde que ses examens (le chiffre de la maquette)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm5-stats-examens');
      await choisirM14(t, 'service', 'Maternité');
      final attendu = valeurVecteur(cm(sc['service:Maternité'])['kpis'], 'Examens (population filtrée)');
      expect(attendu, '12');
      expect(find.text('358'), findsNothing);
      expect(find.text(attendu), findsWidgets);
    });

    casM14('l’origine : les patients externes ne sont comptés que sur l’axe externe', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm5-stats-examens');
      await choisirM14(t, 'origine', 'Patients internes');
      final interne = cm(sc['origine:interne'])['kpis'];
      expect(valeurVecteur(interne, 'Patients externes'), '0');
      expect(find.text(valeurVecteur(interne, 'Examens (population filtrée)')), findsWidgets);
      await choisirM14(t, 'origine', 'Patients externes');
      expect(find.text(valeurVecteur(cm(sc['origine:externe'])['kpis'], 'Examens (population filtrée)')), findsWidgets);
    });

    casM14('une plage qui ne retient rien : « 0 », jamais un tableau inventé, et la raison est dite', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm5-stats-examens');
      await poserChamp(t, 'du', '2030-01-01');
      await poserChamp(t, 'au', '2030-02-01');
      expect(find.text('Rien à compter sur ces axes.'), findsOneWidget);
      expect(find.text('Aucun examen dans la population filtrée.'), findsOneWidget);
      expect(find.text('Aucun service à compter.'), findsOneWidget);
    });
  });

  group('m2-stats-echographie : calculées depuis les registres', () {
    final im = cm(vecteurs()['imagerie']);
    casM14('les chiffres du jeu sont ceux de la maquette : 156 comptes rendus, 145 rendus, part obstétricale, 67 h sur 5 paires tracées', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm2-stats-echographie');
      for (final k in kp(cm(im['defaut'])['kpis'])) {
        expect(ft(k[1]), findsWidgets, reason: '${k[0]}');
        if (k[2] != null) expect(find.text('${k[2]}'), findsOneWidget);
      }
      expect(find.text('AHOHOU Rodrigue'), findsOneWidget);
    });
    casM14('aucun registre : « — » et le délai dit qu’aucune paire n’est tracée, jamais un zéro', (t) async {
      final m = magasinComplet();
      archiverTout(m, 'resultatsImagerie');
      archiverTout(m, 'demandesImagerie');
      await ouvrirM14(t, m, 'm2-stats-echographie');
      expect(find.text('Aucune paire demande/CR tracée'), findsOneWidget);
      expect(find.text('Aucun compte rendu à compter.'), findsOneWidget);
      expect(find.text('Aucune donnée.'), findsOneWidget);
    });
  });

  group('m2-stats-consultations : par praticien, par type, plage de dates', () {
    final c = cm(vecteurs()['consultations']);
    casM14('le jeu : 282 consultations, 53 à domicile ; chaque praticien avec son service à l’organigramme', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm2-stats-consultations');
      expect(find.text('282'), findsOneWidget);
      expect(find.text('53'), findsWidgets);
      expect(find.text('BASSONGUI Chabi Séko — Direction'), findsOneWidget);
      expect(find.text('TAKI Orou — Médecine générale'), findsOneWidget);
    });
    casM14('la plage filtre ; « Toute la période » la lève', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm2-stats-consultations');
      await poserChamp(t, 'du', '2026-08-01');
      final attendu = valeurVecteur(cm(cm(c['scenarios'])['depuis-aout'])['kpis'], 'Consultations au registre');
      expect(attendu, '43');
      expect(find.text('282'), findsNothing);
      expect(find.text(attendu), findsWidgets);
      await toucherM14(t, find.byKey(const Key('pil:toute-periode')));
      expect(find.text('282'), findsOneWidget);
    });
    casM14('une plage inversée ne compte rien : « Aucune donnée. »', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm2-stats-consultations');
      await poserChamp(t, 'du', '2026-10-31');
      await poserChamp(t, 'au', '2026-10-01');
      expect(find.text('Aucune donnée.'), findsOneWidget);
    });
  });

  group('m3-stats-bloc : sans CPA signalées, jamais bloquées', () {
    Magasin avecBloc() {
      final m = magasinComplet();
      final ops = m.collection('crOperatoires').actives.toList();
      m.collection('cpa').inserer({'id': 'CPA-T1', 'patientId': ops[0]['patientId'], 'date': '2026-09-02', 'conclusion': 'Apte'});
      m.collection('crAnesthesie').inserer({'id': 'CRA-T1', 'dateOperation': '2026-09-02', 'technique': 'Rachianesthésie', 'incidents': 'Aucun incident'});
      m.collection('crAnesthesie').inserer({
        'id': 'CRA-T2',
        'dateOperation': '2026-09-20',
        'technique': 'Anesthésie générale',
        'incidents': 'Hypotension transitoire',
        'decisionSortie': 'Surveillance prolongée en salle de réveil'
      });
      return m;
    }

    casM14('les interventions sans CPA sont comptées et le disent : « Signalées, jamais bloquées »', (t) async {
      await ouvrirM14(t, avecBloc(), 'm3-stats-bloc');
      expect(find.text('26'), findsOneWidget, reason: 'comptes rendus opératoires');
      expect(find.text('25'), findsOneWidget, reason: 'interventions sans CPA : 26 moins celle dont la CPA est posée');
      expect(find.text('Signalées, jamais bloquées'), findsOneWidget);
    });
    casM14('« aucun incident » s’écrit et ne compte pas ; un incident NOMMÉ compte (1 sur 2 comptes rendus), et la surveillance prolongée aussi', (t) async {
      await ouvrirM14(t, avecBloc(), 'm3-stats-bloc');
      expect(find.byKey(const Key('kit:kpi')), findsNWidgets(6));
      final kpis = t.widgetList<KpiSigh>(find.byType(KpiSigh)).map((k) => '${k.libelle}=${k.valeur}').toList();
      expect(kpis, contains('Incidents per-opératoires NOMMÉS=1'));
      expect(kpis, contains('Surveillances prolongées en réveil=1'));
      expect(kpis, contains('Comptes rendus d’anesthésie=2'));
    });
    casM14('registres vides : chaque carte dit ce qu’elle ne trouve pas', (t) async {
      final m = magasinComplet();
      archiverTout(m, 'crOperatoires');
      await ouvrirM14(t, m, 'm3-stats-bloc');
      expect(find.text('Aucun compte rendu opératoire au registre.'), findsOneWidget);
      expect(find.text('Aucun compte rendu d’anesthésie.'), findsOneWidget);
      expect(find.text('Aucune CPA au registre.'), findsOneWidget);
    });
  });

  group('m3-stats-hospitalisations : la durée moyenne ne porte que sur les séjours TERMINÉS', () {
    casM14('le jeu : 91 séjours dont 77 terminés, 585 journées, 7,6 j, 14 lits occupés sur 19', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm3-stats-hospitalisations');
      final k = t.widgetList<KpiSigh>(find.byType(KpiSigh)).map((k) => '${k.libelle}=${k.valeur}').toList();
      expect(k, [
        'Séjours de la période=91',
        'Séjours terminés=77',
        'Journées d’hospitalisation=585',
        'Durée moyenne de séjour=7.6 j',
        'Séjours en cours=14',
        'Taux d’occupation=${pourcent(73.7)}',
      ]);
      expect(find.text('14 lit(s) occupé(s) sur 19 — à ce jour'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text(money(2150000, avecDevise: false)), findsWidgets);
    });
    casM14('un séjour en cours, même long, n’abaisse pas la durée moyenne : elle reste à 7,6 j', (t) async {
      final m = magasinComplet();
      m.collection('admissions').inserer({'id': 'ADM-T', 'dateEntree': '2026-09-01', 'typeChambre': 'vip', 'diagnosticEntree': 'Test'});
      await ouvrirM14(t, m, 'm3-stats-hospitalisations');
      final k = t.widgetList<KpiSigh>(find.byType(KpiSigh)).map((k) => '${k.libelle}=${k.valeur}').toList();
      expect(k, contains('Durée moyenne de séjour=7.6 j'));
      expect(k, contains('Séjours de la période=92'));
      expect(k, contains('Séjours en cours=15'));
      expect(find.text('Sur les séjours terminés seulement'), findsOneWidget);
    });
    casM14('l’état imprimé : cartouche, tableau avec TOTAL calculé et la note de méthode', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm3-stats-hospitalisations');
      await toucherM14(t, find.byKey(const Key('pil:editer-etat')));
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text(money(4855000, avecDevise: false)), findsWidgets);
      expect(find.textContaining('La durée moyenne ne porte que sur les séjours TERMINÉS'), findsWidgets);
      expect(find.text('Durée moyenne de séjour : 7.6 jours'), findsOneWidget);
    });
  });

  group('m4-stats-maternite : indicateurs DHIS2 calculés', () {
    final mat = cm(vecteurs()['maternite']);
    casM14('le jeu : les huit indicateurs de la maquette, au chiffre près', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm4-stats-maternite');
      for (final k in kp(cm(mat['defaut'])['kpis'])) {
        expect(ft(k[1]), findsWidgets, reason: '${k[0]}');
        if (k[2] != null) expect(ft(k[2]), findsWidgets, reason: '${k[0]} : indice');
      }
      expect(find.text(pourcent(61.1)), findsOneWidget);
      expect(find.text('Vitamine K1'), findsOneWidget);
    });
    casM14('registre des grossesses vide : 0 %, pas une division par zéro', (t) async {
      final m = magasinComplet();
      archiverTout(m, 'grossesses');
      await ouvrirM14(t, m, 'm4-stats-maternite');
      expect(find.text('0 / 0 grossesses suivies'), findsOneWidget);
      expect(find.text(pourcent(0)), findsWidgets);
    });
  });

  group('m10-cout-agent : DEUX colonnes à ne jamais additionner', () {
    casM14('sans agent : l’écran dit de choisir, il n’invente aucun coût', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm10-cout-agent');
      expect(find.text('Choisir un agent pour lire son coût global et l’historique de ses paies.'), findsOneWidget);
      expect(find.text('Coût employeur mensuel'), findsNothing);
    });
    casM14('un agent à 450 000 F : 541 800 F de coût employeur, la CNSS ouvrière à part, ORTB 4 000 F (radio + télé qui se CUMULENT)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm10-cout-agent');
      await choisirM14(t, 'agent', 'BASSONGUI Chabi Séko — Directeur Médical');
      expect(find.text(money(541800)), findsOneWidget);
      expect(find.text('COÛT EMPLOYEUR'), findsOneWidget);
      expect(find.text('Retenue à l’agent'), findsOneWidget);
      expect(find.text(money(16200, avecDevise: false)), findsOneWidget);
      expect(find.text(money(4000)), findsOneWidget);
      expect(find.text('Radio 1 000 + Télé 3 000 — elles se CUMULENT'), findsOneWidget);
      expect(find.text(money(541800 + 16200)), findsNothing, reason: 'jamais d’addition des deux colonnes');
    });
    casM14('l’historique des paies LIT les bulletins et ne génère rien ; sans bulletin il dit où la paie se calcule', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm10-cout-agent');
      await choisirM14(t, 'agent', 'BASSONGUI Chabi Séko — Directeur Médical');
      expect(find.textContaining('Aucun bulletin émis pour cet agent'), findsOneWidget);
      final m = magasinComplet();
      final id = m.collection('personnel').actives.firstWhere((p) => p['nomComplet'] == 'BASSONGUI Chabi Séko')['id'];
      m.collection('bulletins').inserer({'id': 'BUL-T', 'personnelId': id, 'annee': 2026, 'mois': 8, 'brut': 450000, 'net': 364500});
      await ouvrirM14(t, m, 'm10-cout-agent');
      await choisirM14(t, 'agent', 'BASSONGUI Chabi Séko — Directeur Médical');
      expect(find.text('septembre 2026'), findsOneWidget);
      expect(find.text(money(364500, avecDevise: false)), findsOneWidget);
    });
  });

  group('m12-rentabilite-groupes : deux registres, un rapprochement ARRÊTÉ', () {
    final r = cm(vecteurs()['rentabilite']);
    casM14('les recettes (lignes de facture) et les charges (écritures validées) du jeu, au franc près', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm12-rentabilite-groupes');
      for (final k in kp(cm(r['defaut'])['kpis'])) {
        expect(ft(k[1]), findsWidgets, reason: '${k[0]}');
      }
      expect(find.text('Transverse — non ventilé'), findsOneWidget);
      expect(find.textContaining('ne sont PAS ventilées'), findsOneWidget);
    });
    casM14('une écriture sans centre est « Non imputé » et transverse ; un brouillon est écarté et compté', (t) async {
      final m = magasinComplet();
      m.collection('ecritures').inserer({'id': 'ECR-T1', 'numero': 'OD-T-1', 'date': '2026-10-10', 'compte': '601000', 'statut': 'validee', 'debit': 12345, 'credit': 0});
      m.collection('ecritures')
          .inserer({'id': 'ECR-T2', 'numero': 'OD-T-2', 'date': '2026-10-11', 'compte': '604000', 'statut': 'brouillon', 'debit': 999, 'credit': 0, 'centreCout': 'laboratoire'});
      await ouvrirM14(t, m, 'm12-rentabilite-groupes');
      expect(find.text('Non imputé'), findsOneWidget);
      expect(find.text(money(35885345)), findsOneWidget, reason: 'le brouillon n’est pas un fait comptable');
      expect(find.text('1'), findsWidgets);
    });
    casM14('la plage filtre recettes ET charges', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm12-rentabilite-groupes');
      await poserChamp(t, 'du', '2030-01-01');
      expect(find.text(money(0)), findsWidgets);
      expect(find.text('Aucune charge validée sur la période.'), findsOneWidget);
    });
  });

  group('m12-tableau-decisionnel : objectif fixé / réel atteint — aucun objectif n’est documenté', () {
    casM14('huit cibles proposées, dites « à valider » ; 2 atteintes, 5 seuils franchis ; le BFR en jours', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm12-tableau-decisionnel');
      expect(find.textContaining('8 cible(s) en attente d’arbitrage de la Direction.'), findsOneWidget);
      expect(find.text('À VALIDER'), findsNWidgets(8));
      expect(find.text('Besoin en fonds de roulement au 30/10/2026 : ${money(5011584)}, soit 305 jours de chiffre d’affaires.'), findsOneWidget);
      expect(find.text('174 j'), findsOneWidget);
      expect(find.text('Seuil d’alerte franchi'), findsNWidgets(5));
      expect(find.text('Objectif atteint'), findsNWidgets(2));
      final k = t.widgetList<KpiSigh>(find.byType(KpiSigh)).map((k) => '${k.libelle}=${k.valeur}').toList();
      expect(k, ['Objectifs atteints=2', 'Sous surveillance=1', 'Seuils franchis=5', 'Non calculables=0']);
    });
    casM14('sans facture, les indicateurs qui en dépendent sont « Non calculable » — jamais zéro, jamais en échec', (t) async {
      final m = magasinComplet();
      archiverTout(m, 'factures');
      await ouvrirM14(t, m, 'm12-tableau-decisionnel');
      expect(find.text('Non calculable'), findsWidgets);
      expect(find.text('donnée manquante, jamais un zéro'), findsOneWidget);
      expect(find.text('174 j'), findsNothing, reason: 'le DSO n’est pas calculable sans chiffre d’affaires : il ne devient pas un zéro');
    });
    casM14('corriger une cible l’ARRÊTE : la mention « à valider » tombe, la date et l’auteur sont portés', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-tableau-decisionnel');
      await toucherM14(t, find.text('Objectifs & seuils'));
      expect(find.text('Proposition'), findsNWidgets(8));
      await toucherM14(t, find.byTooltip('Modifier').first);
      await saisir(t, 'cible', '40');
      await toucherM14(t, find.byKey(const Key('pil:enregistrer-objectif')));
      final dso = m.collection('objectifsPilotage').actives.firstWhere((o) => o['id'] == 'dso');
      expect(dso['cible'], 40);
      expect(dso['aValider'], false);
      expect(dso['arreteLe'], '2026-10-30');
      expect(find.text('Arrêté par la Direction'), findsOneWidget);
      expect(find.text('Proposition'), findsNWidgets(7));
    });
    casM14('sans le droit d’éditer, la commande « Modifier » est ABSENTE (RG-13) ; la consultation reste', (t) async {
      final m = magasinComplet();
      await ouvrirM14(t, m, 'm12-tableau-decisionnel', role: 'direction', donnees: donneesLectureSeule('direction', 'm12-tableau-decisionnel'));
      await toucherM14(t, find.text('Objectifs & seuils'));
      expect(find.byTooltip('Modifier'), findsNothing);
      expect(find.byTooltip('Consulter'), findsWidgets);
    });
    casM14('les compagnies au-delà du seuil, avec leur NOM, et le geste qui y mène', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm12-tableau-decisionnel');
      expect(find.text('Compagnies au-delà du seuil d’ancienneté'), findsOneWidget);
      expect(find.text('OLEA ASSURANCE'), findsOneWidget);
      expect(find.text('295 j'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Ouvrir les relances'), findsOneWidget);
    });
    casM14('la grille s’imprime avec ses cibles « à valider »', (t) async {
      await ouvrirM14(t, magasinComplet(), 'm12-tableau-decisionnel');
      await toucherM14(t, find.byKey(const Key('pil:imprimer-grille')));
      expect(find.text('Objectif fixé / réel atteint — arrêté au 30/10/2026'), findsOneWidget);
      expect(find.textContaining('(à valider)'), findsWidgets);
    });
  });

  group('dash-direction', () {
    casM14('le bandeau d’alertes, le premier regard et le BFR : 51 produits sous seuil, 13 échéances dépassées, BFR 305 jours de CA', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-direction');
      expect(find.text('51 produit(s) sous le seuil d’alerte'), findsOneWidget);
      expect(find.text('17 lot(s) périmé(s) à retourner'), findsOneWidget);
      expect(find.text('37 lot(s) à péremption proche (FEFO)'), findsOneWidget);
      expect(find.textContaining('13 échéance(s) fiscale(s) dépassée(s) — engagent la clinique'), findsOneWidget);
      expect(find.text(money(5011584)), findsOneWidget);
      expect(find.text('305 jours de CA'), findsOneWidget);
      expect(find.textContaining('5 indicateur(s) au-delà du seuil d’alerte'), findsOneWidget);
    });
    casM14('les variations « +8,4 % vs mois dernier » de la maquette étaient des constantes : elles ne sont pas portées (E1002)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-direction');
      expect(find.textContaining('vs mois dernier'), findsNothing);
    });
    casM14('aucune échéance en retard : le premier regard énonce une phrase', (t) async {
      final m = magasinComplet();
      for (final e in m.collection('echeancesFiscales').actives.toList()) {
        m.collection('echeancesFiscales').mettreAJour(e['id'], {'paye': true});
      }
      await ouvrirM14(t, m, 'dash-direction');
      expect(find.text('Aucune échéance fiscale en retard.'), findsOneWidget);
    });
    casM14('un composant du BFR non amorcé SE DIT (les dettes fournisseurs)', (t) async {
      final m = magasinComplet();
      archiverTout(m, 'facturesFournisseurs');
      await ouvrirM14(t, m, 'dash-direction');
      expect(find.textContaining('Calcul incomplet — les factures fournisseurs ne sont pas amorcés sur ce poste'), findsOneWidget);
    });
    casM14('le mode de paiement absent s’affiche « undefined » (porté fidèlement, signalé E1001)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-direction');
      expect(find.textContaining('undefined'), findsWidgets);
    });
    casM14('le rapport de direction s’imprime avec le mois, les indicateurs et les deux signatures', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-direction');
      await toucherM14(t, find.byKey(const Key('pil:rapport-direction')));
      expect(find.text('Rapport d’activité — Direction'), findsOneWidget);
      expect(find.text('Période : octobre 2026'), findsWidgets);
      expect(find.text('Masse salariale mensuelle'), findsOneWidget);
      expect(find.text('BASSONGUI Chabi Séko'), findsWidgets);
    });
    casM14('les liens du BFR mènent aux écrans de la Direction', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-direction');
      await toucherM14(t, find.byKey(const Key('pil:tableau-decisionnel')));
      expect(find.text('Grille objectif / réel'), findsOneWidget);
    });
  });

  group('dash-admin', () {
    casM14('les quatre indicateurs de la maquette ; la journalisation compte 400 actions (RG-12)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-admin');
      expect(find.text('44'), findsWidgets);
      expect(find.text('400'), findsOneWidget);
      expect(find.text('RG-12 — aucune action anonyme'), findsOneWidget);
      expect(find.text('Aujourd’hui'), findsOneWidget);
    });
    casM14('une tentative de connexion refusée est le signal vu en premier ; sans tentative, la phrase le dit', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-admin');
      expect(find.text('Aucune tentative de connexion refusée.'), findsOneWidget);
      final m2 = magasinComplet();
      m2.collection('tentativesConnexion').inserer({'id': 'TC1'});
      m2.collection('tentativesConnexion').inserer({'id': 'TC2'});
      await ouvrirM14(t, m2, 'dash-admin');
      expect(find.textContaining('2 tentative(s) de connexion refusée(s) — à examiner'), findsOneWidget);
    });
    casM14('l’intégrité des référentiels est comptée : 210 patients, 184 produits, 48 analyses, 13 assureurs, 112 comptes', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-admin');
      for (final v in ['210', '184', '48', '13', '112']) {
        expect(find.text(v), findsWidgets, reason: v);
      }
      expect(find.text('POSTE-LOCAL'), findsWidgets);
    });
  });

  group('dash-da : la caisse du jour et les cumuls', () {
    final da = cm(vecteurs()['da']);
    casM14('l’encaissé n’est pas le facturé : deux grandeurs, et la note le dit', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-da');
      expect(find.text('Encaissé aujourd’hui'), findsOneWidget);
      expect(find.text('Facturé aujourd’hui'), findsOneWidget);
      expect(find.textContaining('Les confondre ferait prendre une créance pour de l’argent en caisse.'), findsOneWidget);
      expect(find.text('Aucun encaissement enregistré aujourd’hui.'), findsOneWidget);
    });
    casM14('une période SE NOMME : le jour, ses bornes calendaires, et la période précédente de même nature', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-da');
      expect(find.text('Période retenue : journée du 30/10/2026 — du 30/10/2026 au 30/10/2026. Comparée à journée du 29/10/2026 (du 29/10/2026 au 29/10/2026).'), findsOneWidget);
      expect(find.text('pas de base de comparaison'), findsWidgets);
    });
    casM14('choisir juin 2026 : les chiffres de la maquette, et la variation sur mai', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-da');
      await toucherM14(t, find.text('Mois'));
      await choisirM14(t, 'p', 'Juin 2026');
      final u = cm(cm(cm(da['onglets'])['mois'])['unites'])['5'];
      expect(ft(cm(u)['note']), findsOneWidget);
      final premiere = ((cm(u)['tables'] as List).first as Map)['lignes'] as List;
      final ligne = (premiere.first as List).map(nt).toList();
      expect(find.text(ligne[0]), findsWidgets);
      expect(ft(ligne[1]), findsWidgets, reason: 'Chiffre d’affaires facturé de juin');
      expect(ft(ligne[3]), findsWidgets, reason: 'variation sur mai');
    });
    casM14('l’analyse libre : une plage nommée donne les pièces émises, le facturé, l’encaissé et les dépenses', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-da');
      expect(find.text('Pièces émises sur la plage'), findsNothing);
      await poserChamp(t, 'du', '2026-09-01');
      await poserChamp(t, 'au', '2026-09-30');
      expect(find.text('Pièces émises sur la plage'), findsOneWidget);
      final k = kp(cm(cm(da['plage'])['sept'])['kpis']);
      expect(ft(k[3][1]), findsWidgets, reason: 'Dépenses de la plage');
    });
    casM14('le BFR est posé avant la caisse du jour, avec son renvoi', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-da');
      expect(find.text('Trésorerie & besoin en fonds de roulement'), findsOneWidget);
      expect(find.text(money(5011584)), findsOneWidget);
      expect(find.byKey(const Key('pil:detail-bfr')), findsOneWidget);
    });
  });

  group('dash-croise : une source, deux axes, une mesure, une période', () {
    final cr = cm(vecteurs()['croise']);
    casM14('par défaut (30 derniers jours) le jeu ne porte rien : l’écran le dit et propose d’élargir', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-croise');
      expect(find.text('Aucune donnée sur la période choisie.'), findsOneWidget);
      expect(find.text('0 × 0'), findsOneWidget);
      expect(find.text('30 derniers jours'), findsWidgets);
    });
    casM14('« Tout l’historique » : 282 consultations croisées mois × médecin, le tableau et son TOTAL calculés', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-croise');
      await choisirM14(t, 'periode', 'Tout l’historique');
      final d = cm(cm(cm(cr['sources'])['consultations'])['toutDefaut']);
      expect(ft(kp(d['kpis'])[3][1]), findsOneWidget);
      expect(find.text('282'), findsWidgets);
      expect(find.text('Nombre de consultations — Mois × Médecin'), findsOneWidget);
      expect(find.text('juillet 2026'), findsOneWidget);
      expect(find.text('Les douze premières valeurs — Mois'), findsOneWidget);
    });
    casM14('changer de source change les axes proposés et la mesure : Facturation → montant en FCFA', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-croise');
      await choisirM14(t, 'periode', 'Tout l’historique');
      await choisirM14(t, 'source', 'Facturation');
      expect(find.text('Nombre de factures'), findsWidgets);
      await choisirM14(t, 'mesure', 'Montant total');
      final r = cm(cm(cm(cr['sources'])['factures'])['mesuresLues'])['montant'];
      expect(ft(kp(cm(r)['kpis'])[2][1]), findsWidgets, reason: 'Montant total');
    });
    casM14('un effectif ne s’additionne pas avec un montant : la mesure est déclarée par la source (Patients : un seul choix)', (t) async {
      await ouvrirM14(t, magasinComplet(), 'dash-croise');
      await choisirM14(t, 'source', 'Patients');
      expect(find.text('Nombre de patients'), findsWidgets);
      expect(find.text('Montant'), findsNothing);
    });
  });
}
