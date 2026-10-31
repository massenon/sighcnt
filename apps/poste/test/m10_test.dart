import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm10_aide.dart';

/// M10 — RH (premier lot) : les écrans rejouent les vecteurs `rh.json`, tirés des écrans RÉELS de la maquette (Chrome, horloge 30/10/2026 10 h, jeu du
/// poste) : indicateurs, ordre des lignes, saisies (création, refus nommé, modification), archivage, droits, impressions.
void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-personnel', () {
    final p = obj(v['personnel']);
    final agents = {for (final a in jeu('personnel')) a['matricule']: a};

    testWidgets('KPI et ordre des quinze premières lignes identiques à la maquette ; ancienneté de la ligne', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm10-personnel');
      kpisIdentiques(t, obj(p['ecran'])['kpis']);
      final lignes = (obj((obj(p['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      final noms = [for (final l in lignes) '${agents['${l[0]}']!['nomComplet']}'];
      expect(ordreAffiche(t, noms), noms);
      expect(find.text('8 a. 4 m.'), findsWidgets, reason: 'ancienneté du Directeur Médical au 30/10/2026');
      expect(find.textContaining('Tous les agents'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : valeurs par défaut, refus nommé, fiche écrite comme la maquette (nom complet), KPI mis à jour', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm10-personnel');
      final col = m.collection('personnel');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final ctl = formulaire(t);
      final defauts = obj(obj(p['creation'])['defauts']);
      for (final k in ['sexe', 'fonction', 'service', 'categorie', 'dateEmbauche', 'salaireBase']) {
        expect('${ctl[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'matricule': '99', 'nom': 'AGBO', 'prenom': 'Rosine', 'fonction': 'infirmier', 'service': 'Soins infirmiers', 'poste': 'Infirmière', 'salaireBase': '120000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      fichesEgales(col.toutes.first, obj(obj(p['creation'])['creee'])['fiche'] as M);
      expect(find.text('Nouveau agent créé.'), findsWidgets, reason: 'le message de la maquette');
      kpisIdentiques(t, obj(obj(p['creation'])['apres'])['kpis']);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('modification : le nom complet suit le prénom ; archivage : motif exigé, fiche archivée (RG-14), effectif revenu à 44', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm10-personnel');
      final col = m.collection('personnel');
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      poser(t, {'matricule': '99', 'nom': 'AGBO', 'prenom': 'Rosine', 'fonction': 'infirmier', 'service': 'Soins infirmiers', 'poste': 'Infirmière', 'salaireBase': '120000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      await chercher(t, 'AGBO');
      await cliquer(t, find.byTooltip('Modifier').first);
      final ctl = formulaire(t);
      for (final e in obj(obj(p['modification'])['valeurs']).entries) {
        if (e.key == 'dateEmbauche') continue;
        expect('${ctl[e.key]}', '${e.value}', reason: 'valeur à la modification : ${e.key}');
      }
      poser(t, {'prenom': 'Rosine-Marie', 'telephone': '0197000000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final f = col.toutes.firstWhere((x) => x['matricule'] == '99');
      fichesEgales(f, obj(obj(obj(p['modification'])['enregistre'])['fiche']));
      expect(f['nomComplet'], 'AGBO Rosine-Marie');
      await archiverLigne(t, 'Départ');
      expect(col.toutes.firstWhere((x) => x['matricule'] == '99')['statut'], 'archive');
      expect(col.toutes.length, 45, reason: 'jamais supprimée');
      await chercher(t, '');
      kpisIdentiques(t, obj(p['archivage'])['kpis']);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('le tiroir porte la fiche employé : six onglets, informations de la maquette', (t) async {
      final m = poste({for (final n in ['presences', 'conges', 'planning', 'evaluations', 'grillePrimes']) n: jeu(n)});
      await ouvrir(t, m, 'm10-personnel');
      await chercher(t, 'BASSONGUI');
      await cliquer(t, find.byTooltip('Consulter').first);
      await t.pump(const Duration(seconds: 1)); // le tiroir glisse depuis la droite
      for (final o in (obj(p['tiroir'])['onglets'] as List)) {
        expect(find.text('$o'), findsWidgets, reason: 'onglet $o');
      }
      final infos = obj(obj(obj(p['tiroir'])['parOnglet'])['Informations'])['texte'] as String;
      for (final x in ['27/06/2018', '8 an(s) 4 mois', '294011540', '0741137731', 'Célibataire', '450 000 FCFA', 'Directeur Médical']) {
        expect(infos.replaceAll(RegExp(r'[\s  ]'), '').contains(sansEspaces(x)), isTrue, reason: 'le vecteur porte $x');
        expect(texteAffiche(t).contains(sansEspaces(x).toLowerCase()), isTrue, reason: 'l’écran porte $x');
      }
      await cliquer(t, find.text('Planning du mois').last);
      expect(find.text('Aucune vacation programmée ce mois-ci.'), findsOneWidget);
      await cliquer(t, find.text('Primes (NS 132)').last);
      expect(find.text('Aucune prime prévue pour cette fonction par la note NS 132.'), findsOneWidget);
      await cliquer(t, find.text('Présences & congés').last);
      final pc = obj(obj(obj(p['tiroir'])['parOnglet'])['Présences & congés']);
      for (final tab in (pc['tableaux'] as List)) {
        for (final l in (obj(tab)['lignes'] as List).cast<List>()) {
          cellulesAffichees(t, l, raison: 'présences');
        }
      }
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('fiche imprimée : l’état de la maquette (cartouche, rubriques, signatures)', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm10-personnel');
      await chercher(t, 'BASSONGUI');
      await cliquer(t, find.byTooltip('Imprimer l’état').first);
      final e = obj(p['etat']);
      expect(find.text('${e['titre']}'), findsWidgets);
      for (final c in (e['cartouche'] as List).cast<List>()) {
        expect(find.textContaining('${c[1]}'), findsWidgets, reason: '${c[0]}');
      }
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : sans le droit d’annuler la commande « Archiver » est ABSENTE (jamais grisée) ; le médecin n’a pas M10', (t) async {
      final m = poste({});
      await ouvrir(t, m, 'm10-personnel', role: 'direction');
      expect(find.byTooltip('Archiver'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-contrats', () {
    final c = obj(v['contrats']);

    testWidgets('KPI, onglets, ordre des quinze premières lignes et ÉCHÉANCE de chaque ligne identiques à la maquette', (t) async {
      final m = poste({'contrats': jeu('contrats')});
      await ouvrir(t, m, 'm10-contrats');
      kpisIdentiques(t, obj(c['ecran'])['kpis']);
      ordreIdentique(t, (obj(c['ecran'])['tableaux'] as List).first);
      final lignes = (obj((obj(c['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      for (final l in lignes) {
        if ('${l[6]}'.startsWith('Dans') || l[6] == 'Échu') expect(find.text('${l[6]}'), findsWidgets, reason: '${l[0]} : ${l[6]}');
      }
      expect(find.text('Indéterminée'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : référence CT-0045 (série du registre, E620), valeurs par défaut, refus nommé, KPI ; modification qui GARDE la référence', (t) async {
      final m = poste({'contrats': jeu('contrats')});
      await ouvrir(t, m, 'm10-contrats');
      final col = m.collection('contrats');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final defauts = obj(obj(c['creation'])['defauts']);
      for (final k in ['employeId', 'nature']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0);
      poser(t, {'employeId': 'EMP10', 'nature': 'CDD', 'dateDebut': '2026-10-01', 'dateFin': '2027-09-30', 'essai': '3 mois', 'salaire': '150000'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      fichesEgales(col.toutes.first, obj(obj(c['creation'])['creee'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'CT-0045');
      kpisIdentiques(t, obj(obj(c['creation'])['apres'])['kpis']);
      await chercher(t, 'CT-0045');
      await cliquer(t, find.byTooltip('Modifier').first);
      for (final e in obj(obj(c['modification'])['valeurs']).entries) {
        expect('${formulaire(t)[e.key]}', '${e.value}', reason: 'valeur à la modification : ${e.key}');
      }
      poser(t, {'salaire': '160000', 'nature': 'CDI', 'dateFin': ''});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final f = col.toutes.firstWhere((x) => x['reference'] == 'CT-0045');
      fichesEgales(f, obj(obj(obj(c['modification'])['enregistre'])['fiche']));
      expect(col.toutes.where((x) => x['reference'] == 'CT-0001').length, 1, reason: 'la modification ne réécrit pas la référence (CT-0001 reste unique)');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('archivage : motif exigé, fiche archivée, KPI revenus ; contrat imprimé : six articles de la maquette', (t) async {
      final m = poste({'contrats': jeu('contrats')});
      await ouvrir(t, m, 'm10-contrats');
      await chercher(t, '${c['refCDD']}');
      await cliquer(t, find.byTooltip('Imprimer l’état').first);
      final etat = obj(c['etatCDD']);
      expect(find.text('${etat['titre']}'), findsWidgets);
      expect(find.textContaining('Contrat à durée déterminée, prenant fin le 27/06/2019.'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('archivage d’une ligne : fiche archivée (RG-14), jamais supprimée', (t) async {
      final m = poste({'contrats': jeu('contrats')});
      await ouvrir(t, m, 'm10-contrats');
      await chercher(t, 'CT-0003');
      await archiverLigne(t, 'Erreur de saisie');
      expect(m.collection('contrats').toutes.firstWhere((x) => x['reference'] == 'CT-0003')['statut'], 'archive');
      expect(m.collection('contrats').toutes.length, 44);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-conges', () {
    final c = obj(v['conges']);

    testWidgets('KPI, ordre, décisions et lecture graphique (cartes) identiques à la maquette', (t) async {
      final m = poste({'conges': jeu('conges')});
      await ouvrir(t, m, 'm10-conges');
      kpisIdentiques(t, obj(c['ecran'])['kpis']);
      ordreIdentique(t, (obj(c['ecran'])['tableaux'] as List).first);
      for (final x in ['Accordé', 'En attente', 'Refusé']) {
        expect(find.text(x), findsWidgets);
      }
      await t.scrollUntilVisible(find.text('Jours de congé accordés par mois'), 400, scrollable: find.byType(Scrollable).first);
      for (final titre in (obj(c['ecran'])['cartes'] as List)) {
        expect(find.text('$titre'), findsWidgets, reason: '$titre');
      }
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : refus nommé (fin avant début), référence CG-0023, durée calculée ; modification qui garde la référence', (t) async {
      final m = poste({'conges': jeu('conges')});
      await ouvrir(t, m, 'm10-conges');
      final col = m.collection('conges');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final defauts = obj(obj(c['creation'])['defauts']);
      for (final k in ['employeId', 'nature', 'dateDebut', 'statutConge']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      poser(t, {'employeId': 'EMP10', 'dateDebut': '2026-11-10', 'dateFin': '2026-11-05'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('La date de fin doit être postérieure à la date de début.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'dateFin': '2026-11-16', 'remplacant': 'GARBA Yahouza', 'motif': 'Repos annuel'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(c['creation'])['creee'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'CG-0023');
      expect(col.toutes.first['duree'], 6);
      kpisIdentiques(t, obj(obj(c['creation'])['apres'])['kpis']);
      await chercher(t, 'CG-0023');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'statutConge': 'valide', 'dateFin': '2026-11-20'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final f = col.toutes.firstWhere((x) => x['reference'] == 'CG-0023');
      fichesEgales(f, obj(obj(obj(c['modification'])['enregistre'])['fiche']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('décision imprimée : accordée avec remplaçant (texte de la maquette) ; archivage motivé', (t) async {
      final m = poste({'conges': jeu('conges')});
      await ouvrir(t, m, 'm10-conges');
      final x = obj(obj(c['etats'])['valide']);
      await chercher(t, '${x['reference']}');
      await cliquer(t, find.byTooltip('Imprimer l’état').first);
      expect(find.text('Décision de congé'), findsWidgets);
      expect(find.textContaining('Accorde à YENI M’PO Florent'), findsWidgets);
      expect(find.textContaining('remplacé(e) par TAKI Orou'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-prestataires', () {
    final c = obj(v['prestataires']);

    testWidgets('KPI, ordre, classement des huit mieux rémunérés et note fiscale identiques à la maquette', (t) async {
      final m = poste({'prestataires': jeu('prestataires')});
      await ouvrir(t, m, 'm10-prestataires');
      kpisIdentiques(t, obj(c['ecran'])['kpis']);
      ordreIdentique(t, (obj(c['ecran'])['tableaux'] as List).first);
      await t.scrollUntilVisible(find.text('Les huit prestataires les plus rémunérés'), 400, scrollable: find.byType(Scrollable).first);
      final classement = (c['cartes'] as List)[4] as String;
      for (final nom in ['Dr KORA Colette — Circoncision', 'Dr PARAISO Moussa — Anesthésie', 'M. DAOUDA Idrissou — Anesthésie']) {
        expect(classement.contains(nom), isTrue);
        expect(find.text(nom), findsOneWidget);
      }
      expect(find.textContaining('Un prestataire sans facture normalisée expose la clinique'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : PE-0015, montant dû = tarif × actes, KPI ; modification (facture fournie) qui garde la référence', (t) async {
      final m = poste({'prestataires': jeu('prestataires')});
      await ouvrir(t, m, 'm10-prestataires');
      final col = m.collection('prestataires');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final defauts = obj(obj(c['creation'])['defauts']);
      for (final k in ['specialite', 'actesRealises', 'factureNormalisee']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0);
      poser(t, {'nom': 'Dr ZOUMAROU Ali', 'specialite': 'Échographie', 'tarifActe': '15000', 'actesRealises': '4'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.first, obj(obj(c['creation'])['creee'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'PE-0015');
      kpisIdentiques(t, obj(obj(c['creation'])['apres'])['kpis']);
      await chercher(t, 'PE-0015');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'actesRealises': '6', 'factureNormalisee': true, 'ifu': '3201700000001'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['reference'] == 'PE-0015'), obj(obj(obj(c['modification'])['enregistre'])['fiche']));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('état de rémunération : MONTANT TOTAL DÛ de la maquette ; archivage motivé', (t) async {
      final m = poste({'prestataires': jeu('prestataires')});
      await ouvrir(t, m, 'm10-prestataires');
      final x = obj(obj(c['etats'])['sansFacture']);
      await chercher(t, '${x['reference']}');
      await cliquer(t, find.byTooltip('Imprimer l’état').first);
      expect(find.text('État de rémunération — prestataire externe'), findsWidgets);
      expect(find.text('MONTANT TOTAL DÛ'), findsWidgets);
      expect(texteAffiche(t).contains(sansEspaces('39 000')), isTrue, reason: 'montant total dû de la maquette');
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-fiches-poste', () {
    final f = obj(v['fichesPoste']);

    testWidgets('KPI, note « à rédiger », ordre (tri par intitulé), états Rédigée / À rédiger identiques à la maquette', (t) async {
      final m = poste({'fichesPoste': jeu('fichesPoste')});
      await ouvrir(t, m, 'm10-fiches-poste');
      kpisIdentiques(t, obj(f['ecran'])['kpis']);
      ordreIdentique(t, (obj(f['ecran'])['tableaux'] as List).first, max: 12);
      expect(find.textContaining('Seules deux fiches proviennent d’un document remis par la clinique'), findsOneWidget);
      expect(find.text('Rédigée'), findsWidgets);
      expect(find.text('À rédiger'), findsWidgets);
      expect(find.text('Nouvelle fiche de poste'), findsWidgets);
      // l'ordre des commandes de ligne de la maquette : imprimer, consulter, modifier, archiver
      final cmds = [for (final b in (f['boutonsLigne'] as List)) '$b'];
      expect(cmds, ['Imprimer la fiche de poste', 'Consulter', 'Modifier', 'Archiver']);
      for (final b in cmds) {
        expect(find.byTooltip(b), findsWidgets, reason: b);
      }
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('fiche documentée (Infirmier Général) : missions, indicateurs et relations ; une mission sans indicateur le DIT', (t) async {
      final m = poste({'fichesPoste': jeu('fichesPoste')});
      await ouvrir(t, m, 'm10-fiches-poste');
      await chercher(t, 'Infirmier Général');
      await cliquer(t, find.byTooltip('Consulter').first);
      await t.pump(const Duration(seconds: 1));
      for (final x in ['213/10/CNT/DA/2023', '26/10/2023', 'Mission 1 — Contrôler le personnel', '95 % des retards constatés et notifiés', 'Mission 5 — Représenter la clinique et faire le planning du personnel paramédical', 'Au moins 12 staffs cliniques par an']) {
        expect(texteAffiche(t).contains(sansEspaces(x).toLowerCase()), isTrue, reason: x);
      }
      expect(find.text('Aucun indicateur chiffré au document.'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('fiche vide : « n’a pas encore été rédigée » (jamais de mission inventée)', (t) async {
      final m = poste({'fichesPoste': jeu('fichesPoste')});
      await ouvrir(t, m, 'm10-fiches-poste');
      await chercher(t, 'Comptable');
      await cliquer(t, find.byTooltip('Consulter').first);
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Cette fiche n’a pas encore été rédigée'), findsOneWidget);
      expect(find.textContaining('Mission 1'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : refus nommé, fiche « rédigée » sans mission, KPI de la maquette ; modification ; archivage', (t) async {
      final m = poste({'fichesPoste': jeu('fichesPoste')});
      await ouvrir(t, m, 'm10-fiches-poste');
      final col = m.collection('fichesPoste');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouvelle fiche de poste').first);
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'intitule': 'Responsable qualité', 'rattachement': 'Direction', 'resume': 'Suivre les indicateurs de qualité.'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      final nouvelle = col.toutes.first;
      expect(nouvelle['redigee'], isTrue);
      expect(nouvelle['source'], 'Rédigée dans l’application');
      expect(nouvelle['missions'], isEmpty);
      expect(find.text('Fiche de poste créé.'), findsWidgets);
      kpisIdentiques(t, obj(obj(f['creation'])['apres'])['kpis']);
      // modification : la fiche vide « Comptable » ; le « statut du titulaire » est le champ `statut` de la fiche (collision signalée, E626)
      await chercher(t, 'Comptable');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'resume': 'Tenir les livres.', 'archivage': '999/CNT'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      final comptable = col.toutes.firstWhere((x) => x['intitule'] == 'Comptable');
      fichesEgales(comptable, obj(obj(obj(f['modification'])['enregistre'])['fiche']), ignores: {'id'});
      // archivage
      await chercher(t, 'Responsable qualité');
      await archiverLigne(t, 'Doublon');
      expect(col.toutes.firstWhere((x) => x['intitule'] == 'Responsable qualité')['statut'], 'archive');
      expect(col.toutes.length, n0 + 1, reason: 'jamais supprimée (RG-14)');
      await chercher(t, '');
      kpisIdentiques(t, obj(f['archivage'])['kpis']);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('impression : la description de poste en quatre parties', (t) async {
      final m = poste({'fichesPoste': jeu('fichesPoste')});
      await ouvrir(t, m, 'm10-fiches-poste');
      await chercher(t, 'Infirmier Général');
      await cliquer(t, find.byTooltip('Imprimer la fiche de poste').first);
      expect(find.text('DESCRIPTION DE POSTE'), findsWidgets);
      for (final x in ['I — Identification du poste', 'II — Missions, activités et tâches', 'III — Relations fonctionnelles et environnement de travail', 'IV — Compétences et qualifications requises', 'Mission 1 : Contrôler le personnel']) {
        expect(find.textContaining(x), findsWidgets, reason: x);
      }
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-missions', () {
    final o = obj(v['missions']);

    testWidgets('KPI, note de validation, ordre (date de départ décroissante), états identiques à la maquette', (t) async {
      final m = poste({'missions': jeu('missions')});
      await ouvrir(t, m, 'm10-missions');
      kpisIdentiques(t, obj(o['ecran'])['kpis']);
      ordreIdentique(t, (obj(o['ecran'])['tableaux'] as List).first, max: 14);
      expect(find.textContaining('2 ordre(s) en attente de validation. Aucun départ ne devrait intervenir avant la signature de la Directrice Administrative.'), findsOneWidget);
      expect(find.text('En attente de validation DA'), findsWidgets);
      expect(find.text('non validé'), findsWidgets);
      expect(find.text('Registre des ordres de mission'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('commandes de la ligne selon l’état : valider seulement pour un ordre à valider', (t) async {
      final m = poste({'missions': jeu('missions')});
      await ouvrir(t, m, 'm10-missions');
      expect(find.byTooltip('Valider (Directrice Administrative)'), findsNWidgets(2), reason: 'deux ordres en attente');
      expect(find.byTooltip('Marquer terminée'), findsNothing, reason: 'aucun ordre validé ou en cours au jeu');
      expect(find.byTooltip('Imprimer l’ordre'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('validation : confirmation nommée, état « Validée », validatrice et date, KPI de la maquette', (t) async {
      final m = poste({'missions': jeu('missions')});
      await ouvrir(t, m, 'm10-missions');
      final col = m.collection('missions');
      await chercher(t, 'OM-2026-0004');
      await cliquer(t, find.byTooltip('Valider (Directrice Administrative)').first);
      expect(find.text('Valider l’ordre de mission OM-2026-0004 ?'), findsOneWidget);
      expect(find.textContaining('La validation autorise le départ de NKOUÉ Jean du 18/11/2026 au 22/11/2026, aux frais de Ministère de la Santé.'), findsOneWidget);
      await t.tap(find.widgetWithText(BoutonSigh, 'Valider l’ordre'));
      await t.pump(const Duration(milliseconds: 400));
      final f = col.toutes.firstWhere((x) => x['reference'] == 'OM-2026-0004');
      fichesEgales(f, obj(obj(obj(o['validation'])['apres'])['fiche']));
      expect(f['valideePar'], 'TAKI Alimatou');
      expect(f['valideeLe'], '2026-10-30');
      await chercher(t, '');
      kpisIdentiques(t, obj(obj(o['validation'])['ecran'])['kpis']);
      expect(find.text('Ordre de mission validé.'), findsWidgets);
      // la mission validée peut être terminée ou reportée
      await chercher(t, 'OM-2026-0004');
      expect(find.byTooltip('Marquer terminée'), findsOneWidget);
      expect(find.byTooltip('Reporter'), findsOneWidget);
      await cliquer(t, find.byTooltip('Marquer terminée'));
      expect(col.toutes.firstWhere((x) => x['reference'] == 'OM-2026-0004')['statutMission'], 'terminee');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('création : OM-2026-0015, refus nommé, KPI ; modification ; archivage motivé', (t) async {
      // état de la maquette au moment de la création : l'ordre OM-2026-0004 a été validé puis terminé (un seul ordre reste à valider avant le nouveau)
      final jeuMissions = [
        for (final x in jeu('missions'))
          if (x['reference'] == 'OM-2026-0004') {...x, 'statutMission': 'terminee', 'valideePar': 'TAKI Alimatou', 'valideeLe': '2026-10-30'} else x
      ];
      final m = poste({'missions': jeuMissions});
      await ouvrir(t, m, 'm10-missions');
      final col = m.collection('missions');
      final n0 = col.toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final defauts = obj(obj(o['creation'])['defauts']);
      for (final k in ['nature', 'agentId', 'structurePrise', 'dateDepart', 'dateRetour', 'statutMission']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes.length, n0, reason: 'refus : rien n’est écrit');
      poser(t, {'libelle': 'Formation en gestion de stock', 'objet': 'Se former à la gestion des stocks de médicaments.', 'agentId': 'EMP37', 'destination': 'Parakou'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, n0 + 1);
      fichesEgales(col.toutes.first, obj(obj(o['creation'])['creee'])['fiche'] as M);
      expect(col.toutes.first['reference'], 'OM-2026-0015');
      kpisIdentiques(t, obj(obj(o['creation'])['apres'])['kpis']);
      await chercher(t, 'OM-2026-0015');
      await cliquer(t, find.byTooltip('Modifier').first);
      poser(t, {'destination': 'Djougou', 'statutMission': 'projet'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer'));
      await t.pump(const Duration(milliseconds: 400));
      fichesEgales(col.toutes.firstWhere((x) => x['reference'] == 'OM-2026-0015'), obj(obj(obj(o['modification'])['enregistre'])['fiche']));
      await archiverLigne(t, 'Doublon');
      expect(col.toutes.firstWhere((x) => x['reference'] == 'OM-2026-0015')['statut'], 'archive');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('ordre imprimé : formulation de la maquette, deux visas', (t) async {
      final m = poste({'missions': jeu('missions')});
      await ouvrir(t, m, 'm10-missions');
      await chercher(t, 'OM-2026-0004');
      await cliquer(t, find.byTooltip('Imprimer l’ordre').first);
      expect(find.text('Ordre de mission'), findsWidgets);
      expect(find.textContaining('donne ordre à NKOUÉ Jean, Infirmier, de se rendre à Parakou du 18/11/2026 au 22/11/2026, à l’effet de : Formation en hygiène hospitalière.'), findsWidgets);
      expect(find.text('Visa de départ'), findsWidgets);
      expect(find.text('Visa de retour'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : un profil qui lit M10 sans écrire n’a NI « Valider » NI « Nouveau » (commandes ABSENTES, jamais grisées)', (t) async {
      final m = poste({'missions': jeu('missions')});
      await ouvrir(t, m, 'm10-missions', role: 'direction');
      expect(find.byTooltip('Valider (Directrice Administrative)'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      expect(find.byTooltip('Imprimer l’ordre'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-dashboard', () {
    final d = obj(v['dashboard']);

    testWidgets('KPI, cartes et règles métier identiques à la maquette à 30/10/2026 (aucune vacation ce jour)', (t) async {
      final m = poste({'planning': jeu('planning')});
      await ouvrir(t, m, 'm10-dashboard');
      kpisIdentiques(t, obj(d['ecran'])['kpis']);
      for (final c in (obj(d['ecran'])['cartes'] as List)) {
        expect(find.text('$c'), findsWidgets, reason: 'carte $c');
      }
      for (final l in (obj((obj(d['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>()) {
        for (final cel in l) {
          expect(find.textContaining('$cel'), findsWidgets, reason: 'règle : $cel');
        }
      }
      // le classement par fonction : ordre de la maquette
      final texte = (d['cartes'] as List)[1] as String;
      final l = rhaEffectifParFonction(m.collection('personnel').actives);
      expect(sansEspaces(texte), sansEspaces('Effectif par fonction ${[for (final x in l) '${x.libelle} ${x.valeur}'].join(' ')}'));
      expect(ordreAffiche(t, [for (final x in l) x.libelle]), [for (final x in l) x.libelle]);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('20/08/2026 : gardes, permanences et repos du jour calculés depuis le planning, identiques à la maquette', (t) async {
      final m = poste({'planning': jeu('planning')});
      await ouvrir(t, m, 'm10-dashboard', horloge: aout);
      kpisIdentiques(t, obj(obj(v['dashboardAout'])['ecran'])['kpis']);
      expect(int.parse(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'De garde aujourd’hui')).valeur), greaterThan(0));
      await t.pump(const Duration(seconds: 10));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------------------------------
  group('m10-employe-profil', () {
    final pr = obj(v['profil']);
    Magasin complet() => poste({for (final n in ['presences', 'conges', 'planning', 'evaluations', 'grillePrimes', 'assurancesPersonnel']) n: jeu(n)});

    Future<void> choisir(WidgetTester t, String id) async {
      t.widget<FormulaireSigh>(find.byType(FormulaireSigh).first).controleur.poser('agent', id);
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('s’ouvre sur le premier agent par matricule, avec ses six onglets, le lien de retour et le sélecteur « Agent »', (t) async {
      await ouvrir(t, complet(), 'm10-employe-profil');
      expect(find.text('BASSONGUI Chabi Séko'), findsWidgets);
      for (final o in (obj(obj(pr['octobre'])['agents'])['EMP01'] as Map)['onglets'] as List) {
        expect(find.text('$o'), findsWidgets, reason: 'onglet $o');
      }
      expect(find.text('Retour à la liste'), findsOneWidget);
      expect(find.text('Agent'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    for (final id in ['EMP18', 'EMP10', 'EMP44']) {
      testWidgets('$id au 20/08/2026 : planning du mois (gardes, permanences), primes NS 132 et évaluations de la maquette', (t) async {
        await ouvrir(t, complet(), 'm10-employe-profil', horloge: aout);
        await choisir(t, id);
        final onglets = obj(obj(obj(pr['aout'])['agents'])[id])['parOnglet'];
        final plan = obj(obj(onglets)['Planning du mois']);
        await cliquer(t, find.text('Planning du mois').last);
        if ((plan['kpis'] as List).isEmpty) {
          expect(find.text('Aucune vacation programmée ce mois-ci.'), findsOneWidget);
        } else {
          kpisIdentiques(t, plan['kpis']);
          for (final l in (obj((plan['tableaux'] as List).first)['lignes'] as List).take(6).cast<List>()) {
            cellulesAffichees(t, l, raison: 'planning');
          }
        }
        await cliquer(t, find.text('Primes (NS 132)').last);
        final primes = obj(obj(onglets)['Primes (NS 132)']);
        if ((primes['tableaux'] as List).isEmpty) {
          expect(find.text('Aucune prime prévue pour cette fonction par la note NS 132.'), findsOneWidget);
        } else {
          for (final l in (obj((primes['tableaux'] as List).first)['lignes'] as List).cast<List>()) {
            cellulesAffichees(t, l, raison: 'primes');
          }
          expect(find.textContaining('Grille issue de la note de service NS n° 132/07/DM/DA/CNT/2026, en vigueur depuis le 13/07/2026.'), findsOneWidget);
        }
        await cliquer(t, find.text('Évaluations & sanctions').last);
        final ev = obj(obj(onglets)['Évaluations & sanctions']);
        if ((ev['tableaux'] as List).isEmpty) {
          expect(find.text('Aucune évaluation NS 131 enregistrée.'), findsOneWidget);
        } else {
          for (final l in (obj((ev['tableaux'] as List).first)['lignes'] as List).cast<List>()) {
            cellulesAffichees(t, l, raison: 'évaluations');
          }
          expect(find.textContaining('évaluation(s) ayant entraîné une retenue'), findsOneWidget);
        }
        await cliquer(t, find.text('Présences & congés').last);
        for (final tab in (obj(obj(onglets)['Présences & congés'])['tableaux'] as List)) {
          for (final l in (obj(tab)['lignes'] as List).take(4).cast<List>()) {
            cellulesAffichees(t, l, raison: 'présences & congés');
          }
        }
        await t.pump(const Duration(seconds: 10));
      });
    }

    testWidgets('onglet Congés : « Type » et « Jours » sont lus sous les bons noms (E621), pas « — » partout', (t) async {
      await ouvrir(t, complet(), 'm10-employe-profil', horloge: aout);
      await choisir(t, 'EMP18');
      await cliquer(t, find.text('Présences & congés').last);
      final c18 = jeu('conges').firstWhere((x) => x['employeId'] == 'EMP18');
      expect(find.text('${c18['nature']}'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('assurances du personnel : création d’une couverture (dossier RH, aucune écriture comptable), fiche et ligne de la maquette', (t) async {
      final m = complet();
      await ouvrir(t, m, 'm10-employe-profil');
      await choisir(t, 'EMP10');
      await cliquer(t, find.text('Assurances').last);
      expect(find.text('Aucune couverture enregistrée pour cet agent.'), findsOneWidget);
      expect(find.textContaining('Couvertures de l’agent — dossier RH. Elles ne figurent pas dans les recettes de la clinique.'), findsOneWidget);
      final col = m.collection('assurancesPersonnel');
      final ecritures = m.collection('ecritures').toutes.length;
      await cliquer(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
      final defauts = obj(obj(obj(v['profilAssurance'])['creation'])['defauts']);
      for (final k in ['type', 'taux', 'dateDebut', 'beneficiaires']) {
        expect('${formulaire(t)[k]}', '${defauts[k]}', reason: 'défaut $k');
      }
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
      expect(col.toutes, isEmpty, reason: 'refus : rien n’est écrit');
      poser(t, {'organisme': 'CNSS Bénin', 'numeroAdhesion': 'ADH-7788'});
      await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
      await t.pump(const Duration(milliseconds: 400));
      expect(col.toutes.length, 1);
      fichesEgales(col.toutes.first, obj(obj(obj(v['profilAssurance'])['creation'])['creee'])['fiche'] as M);
      expect(m.collection('ecritures').toutes.length, ecritures, reason: 'aucune écriture comptable : la prise en charge du personnel n’est ni recette ni charge');
      cellulesAffichees(t, ['CNSS Bénin', 'ADH-7788', '80 %', 'en cours']);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
