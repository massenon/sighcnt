import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// m10-evaluations, m10-sanctions, m10-primes : les écrans MONTÉS sur le jeu du poste, la porte du barème, la portée de chaque modification, et ce qui est écrit au
/// magasin comparé aux relevés de la maquette (rhb.json).
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  ControleurFormulaire formulaireDe(WidgetTester t) => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;

  /// La porte du barème est ouverte « depuis Paramètres système » : ici, la fiche qu'elle écrit.
  void ouvrirPorte(Magasin m) => m.collection('reglages').inserer({'id': 'baremeModifiable', 'valeur': true, 'statut': 'actif'});

  group('m10-evaluations', () {
    casM14('ouverture : compteurs, barème CONSULTABLE (porte fermée : aucune commande de modification), tableau des évaluations', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      final e = maquette('evaluations');
      final v = {for (final x in liste(e['kpis'])) x['label'] as String: norm(x['valeur'])};
      for (final x in v.entries) {
        expect(norm(kpis(t)[x.key]), x.value, reason: x.key);
      }
      expect(find.textContaining('Le barème est consultable. Pour le modifier, ouvrir la porte depuis « Paramètres système »'), findsOneWidget);
      expect(find.text('Barème d’évaluation — NS 131/07/DM/DA/CNT/2026'), findsOneWidget);
      expect(find.text('Évaluations mensuelles'), findsWidgets);
      // La porte est fermée : la modification est ABSENTE, pas grisée.
      for (final c in ['Nouveau critère', 'Modifier ce critère', 'Retirer ce critère']) {
        expect(find.text(c), findsNothing, reason: c);
        expect(find.byTooltip(c), findsNothing, reason: c);
      }
      expect(find.widgetWithText(BoutonSigh, 'Paramètres système'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Imprimer la note'), findsOneWidget);
      expect(find.text('Ponctualité et assiduité'), findsOneWidget);
      expect(find.textContaining('Retard · Sortie non autorisée'), findsOneWidget);
    });

    casM14('nouvelle évaluation : le prélèvement se calcule à l\'écran, la fiche écrite est celle de la maquette', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      final avant = m.collection('evaluations').toutes.length;
      final agent = m.collection('personnel').actives.firstWhere((x) => x['nomComplet'] == 'TAKI Alimatou');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle évaluation'));
      expect(find.text('Nouvelle fiche d’évaluation'), findsOneWidget);
      await choisirM14(t, 'employeId', '${agent['matricule']} — ${agent['nomComplet']} (${agent['poste']})');
      await choisirM14(t, 'periode', 'Août 2026');
      await choisirM14(t, 'crit_ponctualite', 'Moyenne (− 6 %)');
      await choisirM14(t, 'crit_execution', 'Faible à mauvaise (− 15 %)');
      await choisirM14(t, 'crit_hierarchie', 'Moyenne (− 6 %)');
      await taper(t, 'observations', 'Retards répétés.');
      final ap = maquette('evaluations')['apercuModifie'] as String;
      expect(find.text('Prélèvement total'), findsOneWidget);
      expect(find.text('27 %'), findsOneWidget);
      expect(find.text(money(94500)), findsOneWidget);
      expect(norm(ap), contains('Prélèvement total 27 %'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’évaluation'));
      final c = dico(maquette('evaluations')['creation']);
      final attendu = net(dico(c['nouvelle']));
      final f = net(premiere(m, 'evaluations'));
      for (final k in attendu.keys) {
        if (k == 'reference' || k == 'evaluateur') continue;
        expect(f[k], attendu[k], reason: k);
      }
      expect(f['reference'], attendu['reference'], reason: 'la série de l\'année, lue sur les fiches EXISTANTES : EV-2026-0025');
      expect(f['reference'], matches(RegExp(r'^EV-2026-\d{4}$')));
      expect(m.collection('evaluations').toutes.length, avant + 1);
      expect(find.text('Évaluation enregistrée — prélèvement de 27 %.'), findsOneWidget);
      expect(find.text('${money(94500)} seront retenus sur le salaire brut.'), findsOneWidget);
    });

    casM14('sans agent choisi, le formulaire présélectionne le premier ; une évaluation sans manquement : « Aucune sanction. »', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle évaluation'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’évaluation'));
      final f = premiere(m, 'evaluations');
      expect(f['prelevementPct'], 0);
      expect(f['prelevementMontant'], 0);
      expect(f['periode'], 'Août 2026');
      expect(find.text('Aucune sanction.'), findsOneWidget);
    });

    casM14('modifier une évaluation : la fiche garde sa référence, le prélèvement est recalculé', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      final cible = m.collection('evaluations').actives.first;
      await toucherM14(t, find.byTooltip('Modifier').first);
      for (final k in ['ponctualite', 'execution', 'attitude', 'hierarchie']) {
        await choisirM14(t, 'crit_$k', 'Bonne (aucune sanction)');
      }
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final f = m.collection('evaluations').parId(cible['id'])!;
      expect(f['prelevementPct'], 0);
      expect(f['prelevementMontant'], 0);
      expect(f['reference'], cible['reference']);
      expect(f['evaluateur'], isNotNull);
    });

    casM14('« Imprimer la fiche » : la fiche d\'évaluation et de solde, le total à prélever et les trois signatures', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.byTooltip('Imprimer la fiche').first);
      final fiche = liste(maquette('evaluations')['fiches']).first;
      final piece = dico(fiche['piece']);
      expect(find.text('${piece['titre']}'), findsOneWidget);
      expect(find.textContaining('TOTAL À PRÉLEVER : ${money(45000, avecDevise: false)}'), findsOneWidget);
      expect(find.text('SALAIRE DE BASE'), findsOneWidget);
      expect(find.text('PRIME D’ANCIENNETÉ'), findsOneWidget);
      expect(find.text(money(72000, avecDevise: false)), findsOneWidget);
      expect(find.text('L’Évaluateur'), findsOneWidget);
      expect(find.text('TAKI Alimatou épse BASSONGUI'), findsOneWidget);
    });

    casM14('consulter une évaluation : le tiroir donne le détail par critère', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.text('TAKI Alimatou').first);
      expect(find.text('Évaluation — TAKI Alimatou'), findsOneWidget);
      expect(find.text('Détail par critère'), findsOneWidget);
      expect(find.text('− 10 %'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Modifier l’évaluation'), findsOneWidget);
    });

    casM14('« Imprimer la note » : la note de service NS 131 et son signataire', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la note'));
      expect(find.text('Note de service'), findsOneWidget);
      expect(find.text('N/Réf. : NS 131/07/DM/DA/CNT/2026'), findsOneWidget);
      expect(find.text('BASSONGUI C. Séko Y., Directeur Médical'), findsOneWidget);
      expect(find.textContaining('Ampliation : Intéressés 41 — Archive 01'), findsOneWidget);
    });

    casM14('PORTE OUVERTE : « Nouveau critère » et les commandes de ligne paraissent', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      expect(find.textContaining('Modification autorisée. La porte a été ouverte depuis « Paramètres système ».'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau critère'), findsOneWidget);
      expect(find.byTooltip('Modifier ce critère'), findsNWidgets(4));
      expect(find.byTooltip('Retirer ce critère'), findsNWidgets(4));
    });

    casM14('porte ouverte, droit d\'écrire retiré : la modification reste ABSENTE', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16, role: 'da', donnees: donneesLectureSeule('da', 'm10-evaluations'));
      expect(find.widgetWithText(BoutonSigh, 'Nouveau critère'), findsNothing);
      expect(find.byTooltip('Modifier ce critère'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle évaluation'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
    });

    casM14('modifier un critère « à venir seulement » : la version sortante est archivée avec sa période, la nouvelle prend effet aujourd\'hui', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      final cas = liste(dico(maquette('bareme'))['cas']).first;
      await toucherM14(t, find.byTooltip('Modifier ce critère').first);
      await taper(t, 'moyenne', '7');
      await taper(t, 'faible', '12');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Portée de la modification'), findsOneWidget);
      expect(find.textContaining('19 évaluation(s) ont déjà donné lieu à une retenue.'), findsOneWidget);
      expect(find.text('+1 pt'), findsOneWidget);
      expect(find.text('+2 pt'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      final b = m.collection('baremeNS131').actives.firstWhere((x) => x['num'] == '01');
      final attendu = net(dico(cas['critere']));
      expect({for (final k in attendu.keys) k: b[k]}, attendu);
      final h = net(m.collection('historiqueBareme').toutes.single);
      final ha = net(liste(cas['historique']).single);
      expect({for (final k in ha.keys) k: h[k]}, ha);
      expect(find.text('Applicable à compter du 16/08/2026 ; l’historique est préservé.'), findsOneWidget);
      expect(find.text('Versions antérieures du barème'), findsOneWidget);
      expect(m.collection('audit').toutes.first['action'], 'Modification du barème NS 131');
    });

    casM14('modifier un critère « y compris les évaluations prononcées » : rétroactif, AUCUNE version antérieure, et le message le dit', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.byTooltip('Modifier ce critère').at(1));
      await taper(t, 'faible', '20');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await toucherM14(t, find.byKey(const Key('rhb:portee:tout')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      expect(m.collection('historiqueBareme').toutes, isEmpty);
      final b = m.collection('baremeNS131').actives.firstWhere((x) => x['num'] == '02');
      expect((b['sanctions'] as Map)['faible'], 20);
      expect(b['dateEffet'], '2026-07-13');
      expect(b['portee'], 'tout');
      expect(find.text('Application RÉTROACTIVE — les évaluations prononcées changeront de retenue.'), findsOneWidget);
    });

    casM14('un critère nouveau : identifiant en minuscules, source « à couvrir par un avenant » ; retiré, il part à la corbeille avec son motif', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau critère'));
      await taper(t, 'label', 'Hygiène et tenue');
      await taper(t, 'criteresTexte', 'Tenue incorrecte\nMains non lavées');
      await taper(t, 'moyenne', '4');
      await taper(t, 'faible', '8');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer le critère'));
      final cas = dico(maquette('bareme'));
      final attendu = net(dico(dico(cas['creation'])['critere']));
      final f = net(premiere(m, 'baremeNS131'));
      expect({for (final k in attendu.keys) k: f[k]}, attendu);
      expect(find.text('Critère créé.'), findsOneWidget);
      // Retrait : le motif est exigé, puis archivage logique (RG-14) et version antérieure écrite.
      await toucherM14(t, find.byTooltip('Retirer ce critère').at(4));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer le critère'));
      expect(m.collection('baremeNS131').archivees, isEmpty, reason: 'sans motif, rien n\'est retiré');
      await t.enterText(find.byType(TextField).last, 'Critère abrogé');
      await t.pump();
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer le critère'));
      expect(m.collection('baremeNS131').archivees.single['label'], 'Hygiène et tenue');
      final h = m.collection('historiqueBareme').toutes.single;
      expect(h['remplacePar'], 'Critère retiré — Critère abrogé');
    });

    casM14('LE BARÈME MODIFIÉ REJOINT LES ÉVALUATIONS : le formulaire et la retenue lisent le barème en vigueur à leur date (écart E650 levé)', (t) async {
      final m = magasinRhb();
      ouvrirPorte(m);
      await ouvrirM14(t, m, 'm10-evaluations', horloge: auj16);
      await toucherM14(t, find.byTooltip('Modifier ce critère').first);
      await taper(t, 'moyenne', '7');
      await taper(t, 'faible', '12');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle évaluation'));
      final apres = dico(maquette('bareme'));
      // Le formulaire propose le barème relevé, comme la maquette : « Moyenne (− 7 %) ».
      expect((apres['optionsCritere'] as List).map(norm), contains('Moyenne (− 7 %)'));
      await choisirM14(t, 'crit_ponctualite', 'Moyenne (− 7 %)');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider l’évaluation'));
      final nouvelle = premiere(m, 'evaluations');
      expect(nouvelle['prelevementPct'], 7);
      expect(nouvelle['dateBareme'], '2026-08-16');
      // Le barème d'alors reste celui d'alors : une évaluation du 15/08 se calcule encore à 6 %.
      expect(
          rhbPrelevementALaDate({'ponctualite': 'moyenne'}, m.collection('baremeNS131').actives, m.collection('historiqueBareme').actives, '2026-08-15'), 6);
      expect(
          rhbPrelevementALaDate({'ponctualite': 'moyenne'}, m.collection('baremeNS131').actives, m.collection('historiqueBareme').actives, '2026-08-16'), 7);
    });
  });

  group('m10-sanctions', () {
    casM14('ouverture : retenues > 0 seulement, compteurs de la maquette, aucune commande d\'écriture', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-sanctions', horloge: auj16);
      final s = maquette('sanctions');
      final v = {for (final x in liste(s['kpis'])) x['label'] as String: norm(x['valeur'])};
      for (final x in v.entries) {
        expect(norm(kpis(t)[x.key]), x.value, reason: x.key);
      }
      expect(find.text('Registre des sanctions'), findsOneWidget);
      expect(find.textContaining('Les sanctions sont exclusivement issues du barème NS 131/07/DM/DA/CNT/2026.'), findsOneWidget);
      for (final titre in ['Sanctions par direction et service', 'Critères sanctionnés (NS 131)', 'Montant retenu par critère']) {
        expect(find.text(titre), findsOneWidget, reason: titre);
      }
      expect(find.text('Évolution des retenues'), findsNothing, reason: 'une seule période : pas de courbe');
      for (final c in ['Nouveau', 'Nouvelle sanction', 'Modifier', 'Archiver']) {
        expect(find.byTooltip(c), findsNothing, reason: c);
        expect(find.widgetWithText(BoutonSigh, c), findsNothing, reason: c);
      }
      // L'évaluation sans retenue ne figure pas au registre.
      final zero = m.collection('evaluations').actives.firstWhere((e) => (e['prelevementPct'] as num) == 0);
      expect(find.text('${zero['reference']}'), findsNothing);
    });

    casM14('une sanction se lit avec ses critères sanctionnés (badges), la première ligne est celle de la maquette', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-sanctions', horloge: auj16);
      final l = ((maquette('sanctions')['table'] as Map)['lignes'] as List).first as List;
      expect(find.text('${l[0]}'), findsOneWidget);
      expect(find.text('Respect de la hiérarchie'), findsWidgets);
    });

    casM14('« Notification de sanction » : le montant, le barème, les trois signatures dont « Pris connaissance »', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-sanctions', horloge: auj16);
      await toucherM14(t, find.byTooltip('Notification de sanction').first);
      final n = dico(maquette('sanctions')['notification']);
      expect(find.text('${n['titre']}'), findsOneWidget);
      expect(find.text('${n['sousTitre']}'), findsOneWidget);
      expect(find.textContaining('il est procédé à une retenue de 10 % sur votre salaire brut, soit un montant de ${money(45000)}.'), findsOneWidget);
      expect(find.text('Pris connaissance'), findsOneWidget);
      expect(find.text('La Directrice Administrative'), findsWidgets);
    });

    casM14('registre vide : « Aucune sanction prononcée. », quatre zéros', (t) async {
      final m = magasinRhb();
      for (final e in m.collection('evaluations').actives.toList()) {
        m.collection('evaluations').archiver(e['id']);
      }
      await ouvrirM14(t, m, 'm10-sanctions', horloge: auj16);
      expect(find.text('Aucune sanction prononcée.'), findsOneWidget);
      expect(kpis(t)['Sanctions prononcées'], '0');
      expect(kpis(t)['Prélèvement moyen'], '0 %');
      expect(find.text('Sanctions par direction et service'), findsNothing);
    });
  });

  group('m10-primes', () {
    casM14('ouverture : la grille NS 132 (onze primes, six fonctions), les primes acquises d\'août', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      final p = maquette('primes');
      final v = {for (final x in liste(p['kpis'])) x['label'] as String: norm(x['valeur'])};
      for (final x in v.entries) {
        expect(norm(kpis(t)[x.key]), x.value, reason: x.key);
      }
      expect(find.text('Grille des primes — NS n° 132/07/DM/DA/CNT/2026'), findsOneWidget);
      expect(find.text('Primes acquises — août 2026'), findsOneWidget);
      for (final p in m.collection('grillePrimes').actives) {
        expect(find.text('${p['label']}'), findsWidgets, reason: '${p['label']}');
      }
      expect(find.byTooltip('Modifier cette prime'), findsNWidgets(11));
      expect(find.byTooltip('Retirer cette prime'), findsNWidgets(11));
      expect(find.text('Version 1 — ACTIVE'), findsOneWidget);
      expect(find.text('Forfait mensuel'), findsWidgets);
      expect(find.text('Par occurrence'), findsWidgets);
    });

    casM14('modifier une prime « à venir seulement » : la version sortante est figée, la nouvelle prend effet aujourd\'hui, la modification est journalisée', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      final cas = liste(dico(maquette('primesEcritures'))['cas']).first;
      await toucherM14(t, find.byTooltip('Modifier cette prime').at(1)); // Garde
      await taper(t, 'm_infirmier', '2000');
      await taper(t, 'm_tsl', '1700');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Portée de la modification'), findsOneWidget);
      expect(find.textContaining('2 montant(s) modifié(s).'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('+200'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      final fiche = m.collection('grillePrimes').actives.firstWhere((x) => x['primeId'] == 'garde');
      final attendu = net(dico(cas['fiche']));
      expect({for (final k in attendu.keys) k: fiche[k]}, attendu);
      final h = net(m.collection('historiquePrimes').toutes.single);
      final ha = net(liste(cas['historique']).single);
      expect({for (final k in ha.keys) k: h[k]}, ha);
      expect(find.text('Applicable à compter du 16/08/2026 ; l’historique est préservé.'), findsOneWidget);
      final grille = m.collection('grillePrimes').actives, hist = m.collection('historiquePrimes').actives;
      expect(rhbMontantPrime(grille, hist, 'garde', 'infirmier', '2026-08-15'), 1500);
      expect(rhbMontantPrime(grille, hist, 'garde', 'infirmier', '2026-08-16'), 2000);
      expect(m.collection('audit').toutes.first['action'], 'Modification de la grille des primes');
      expect(find.text('Versions antérieures'), findsOneWidget);
    });

    casM14('modifier une prime « y compris les primes déjà calculées » : rétroactif, aucune version antérieure, message d\'alerte', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.byTooltip('Modifier cette prime').first); // Permanence
      await taper(t, 'label', 'Permanence (révisée)');
      await taper(t, 'm_aide_soignant', '650');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await toucherM14(t, find.byKey(const Key('rhb:portee:tout')));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Appliquer'));
      expect(m.collection('historiquePrimes').toutes, isEmpty);
      final f = m.collection('grillePrimes').actives.firstWhere((x) => x['primeId'] == 'permanence');
      final attendu = net(dico(liste(dico(maquette('primesEcritures'))['cas'])[1]['fiche']));
      expect({for (final k in attendu.keys) k: f[k]}, attendu);
      expect(find.text('Application RÉTROACTIVE — les bulletins passés changeront de montant.'), findsOneWidget);
    });

    casM14('une prime dont aucun montant ne change : la portée le dit', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.byTooltip('Modifier cette prime').at(2)); // Aide bloc
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.text('Cette modification touche des salaires. Aucun montant n’est modifié ; seul l’intitulé ou le mode change.'), findsOneWidget);
    });

    casM14('une prime nouvelle : identifiant en tirets, version 2, « couverte par un avenant »', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle prime'));
      expect(find.textContaining('Une prime créée hors note de service devra être couverte par un avenant.'), findsOneWidget);
      await taper(t, 'label', 'Prime de nuit');
      await choisirM14(t, 'mode', 'Par occurrence');
      await taper(t, 'm_infirmier', '1200');
      await taper(t, 'm_sage_femme', '1300');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer la prime'));
      final attendu = net(dico(dico(dico(maquette('primesEcritures'))['creation'])['fiche']));
      final f = net(premiere(m, 'grillePrimes'));
      expect({for (final k in attendu.keys) k: f[k]}, attendu);
      expect(find.text('Prime créée.'), findsOneWidget);
      expect(find.byTooltip('Modifier cette prime'), findsNWidgets(12));
    });

    casM14('un libellé vide ou un montant négatif : refusé, rien n\'est écrit', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle prime'));
      await taper(t, 'm_infirmier', '-5');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer la prime'));
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(find.text('Un montant ne peut pas être négatif.'), findsOneWidget);
      expect(m.collection('grillePrimes').actives.length, 11);
    });

    casM14('retirer une prime : date de fin et motif exigés, version antérieure écrite, archivage logique, la paie ne la lit plus après (écart E651 levé)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.byTooltip('Retirer cette prime').at(6)); // Caisse
      expect(find.textContaining('Dernier jour de la prime'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer la prime'));
      expect(m.collection('grillePrimes').actives.length, 11, reason: 'sans motif, rien n\'est retiré');
      await taper(t, 'motif', 'Prime abrogée par note');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer la prime'));
      expect(m.collection('grillePrimes').actives.length, 10);
      expect(m.collection('grillePrimes').archivees.single['primeId'], 'caisse');
      final h = m.collection('historiquePrimes').toutes.single;
      final r = dico(dico(maquette('primesEcritures'))['retrait']);
      final attendu = net(liste(r['historique']).single);
      expect({for (final k in attendu.keys) k: h[k]}, attendu);
      expect(h['retiree'], true);
      expect(h['dateFin'], '2026-08-15');
      expect(find.text('Prime retirée de la grille.'), findsOneWidget);
      final g = m.collection('grillePrimes').actives, hs = m.collection('historiquePrimes').actives;
      for (final x in (r['aLaDate'] as List).cast<List>()) {
        expect(rhbMontantPrime(g, hs, 'caisse', 'caissiere', x[0] as String?), x[1], reason: '$x');
      }
      expect(rhbMontantPrime(g, hs, 'caisse', 'caissiere'), 0);
      expect(r['montantCaisse'], 0);
    });

    casM14('une date de fin avant l\'entrée en vigueur de la prime est refusée, nommée', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      await toucherM14(t, find.byTooltip('Retirer cette prime').at(6));
      formulaireDe(t).poser('dateFin', '2026-07-01');
      await taper(t, 'motif', 'Test');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer la prime'));
      expect(find.text('La date de fin précède l’entrée en vigueur de la prime.'), findsOneWidget);
      expect(m.collection('grillePrimes').actives.length, 11);
      expect(m.collection('historiquePrimes').toutes, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    casM14('les bénéficiaires d\'un forfait : règle d\'attente dite, désignation datée, forfait réservé aux désignés, fin de désignation (écart E654 levé)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      final accueils = [for (final a in m.collection('personnel').actives) if (a['fonction'] == 'accueil') a];
      expect(accueils.length, greaterThan(1));
      await toucherM14(t, find.byTooltip('Bénéficiaires du forfait').at(3)); // Accueil
      expect(find.textContaining('Aucun bénéficiaire désigné. Règle d’attente'), findsOneWidget);
      formulaireDe(t).poser('agents', ['${accueils.first['id']}']);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Désigner'));
      final d = m.collection('beneficiairesPrimes').toutes.single;
      expect(d['primeId'], 'accueil');
      expect(d['agentId'], accueils.first['id']);
      expect(d['debut'], '2026-08-16');
      expect(d['fin'], isNull);
      expect(find.textContaining('Seuls les agents désignés'), findsOneWidget);
      final g = m.collection('grillePrimes').actives, hs = m.collection('historiquePrimes').actives, ds = m.collection('beneficiairesPrimes').actives;
      expect(rhbMontantAgent(g, hs, ds, 'accueil', accueils.first['id'], 'accueil', '2026-08-16'), 7000);
      expect(rhbMontantAgent(g, hs, ds, 'accueil', accueils.last['id'], 'accueil', '2026-08-16'), 0);
      expect(m.collection('audit').toutes.first['action'], 'Désignation des bénéficiaires d’une prime fixe');
      await toucherM14(t, find.byTooltip('Mettre fin à la désignation'));
      expect(m.collection('beneficiairesPrimes').toutes.single['fin'], '2026-08-16');
      await t.pump(const Duration(seconds: 10));
    });

    casM14('une prime FIXE créée à l\'écran entre dans les primes fixes du mois (écart E651 levé)', (t) async {
      final m = magasinRhb();
      await ouvrirM14(t, m, 'm10-primes', horloge: auj16);
      final avant = rhbPrimesAcquises(
          personnelActif: m.collection('personnel').actives,
          planningActif: m.collection('planning').actives,
          grille: m.collection('grillePrimes').actives,
          historique: const [],
          date: '2026-08-16',
          annee: 2026,
          mois: 8);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle prime'));
      await taper(t, 'label', 'Prime de sujétion');
      await choisirM14(t, 'mode', 'Forfait mensuel');
      await taper(t, 'm_infirmier', '4000');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer la prime'));
      final c = dico(dico(maquette('primesEcritures'))['primeFixeCreee']);
      final fiche = premiere(m, 'grillePrimes');
      expect(fiche['primeId'], dico(c['fiche'])['primeId']);
      final apres = rhbPrimesAcquises(
          personnelActif: m.collection('personnel').actives,
          planningActif: m.collection('planning').actives,
          grille: m.collection('grillePrimes').actives,
          historique: const [],
          date: '2026-08-16',
          annee: 2026,
          mois: 8);
      final nb = m.collection('personnel').actives.where((x) => x['fonction'] == 'infirmier').length;
      expect(apres.fold<num>(0, (a, x) => a + x.primesFixes) - avant.fold<num>(0, (a, x) => a + x.primesFixes), 4000 * nb);
      await t.pump(const Duration(seconds: 10));
    });

    casM14('« Imprimer la note » et « Éditer l\'état des primes » : la grille d\'origine, puis les agents primés avec leur total', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-primes', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la note'));
      expect(find.text('Note de service — primes diverses'), findsOneWidget);
      expect(find.textContaining('Reçu par : KASSA A. B. Augustin — reçu le 13/07/2026'), findsOneWidget);
      expect(find.textContaining('* Pour les primes qui varient en fonction du nombre'), findsOneWidget);
    });

    casM14('« Éditer l\'état des primes » : total du mois, quatre colonnes totalisées', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-primes', horloge: auj16);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Éditer l’état des primes'));
      expect(find.text('État des primes diverses'), findsOneWidget);
      expect(find.text('août 2026 — barème NS n° 132/07/DM/DA/CNT/2026'), findsOneWidget);
      expect(find.text('Le Responsable RH'), findsOneWidget);
      expect(find.text(money(460500, avecDevise: false)), findsWidgets);
    });

    casM14('lecture seule : ni « Nouvelle prime » ni « Modifier » ni « Retirer »', (t) async {
      await ouvrirM14(t, magasinRhb(), 'm10-primes', horloge: auj16, role: 'da', donnees: donneesLectureSeule('da', 'm10-primes'));
      expect(find.text('Agents primés'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle prime'), findsNothing);
      expect(find.byTooltip('Modifier cette prime'), findsNothing);
      expect(find.byTooltip('Retirer cette prime'), findsNothing);
    });
  });
}
