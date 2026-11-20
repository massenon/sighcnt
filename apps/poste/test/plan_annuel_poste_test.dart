import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/plan_annuel_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT PTA : le plan annuel de travail au poste. Aucune année, aucun axe, aucun état, aucun signataire écrit dans le code : tout se lit en base. Le moteur REFUSE (garde de la collection,
/// adoption réservée, plan adopté figé), l'adoption est un geste réservé de la fiche RBAC, une révision est une version datée, « Reconduire » copie sans réécrire la source, l'alerte de
/// retard est dérivée (une par action) et retombe, les signataires sont lus à l'organigramme. Les règles pures sont rejouées sur les vecteurs de la maquette (`plan_annuel_test.dart` du domaine).
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30);
String iso(DateTime d) => parametreDateIso(d);

Fiche exo(int a, {String etat = 'ouvert'}) => {'id': 'EXO-$a', 'annee': a, 'debut': '$a-01-01', 'fin': '$a-12-31', 'statut': 'actif', 'etat': etat};

Magasin magasin({DateTime? jour, List<int> annees = const [2026, 2027]}) {
  final j = jour ?? auj;
  final m = Magasin({
    'exercices': [for (final a in annees) exo(a)],
    'referentielsPlan': [
      {'id': 'RFP-001', 'statut': 'actif', 'type': 'axe', 'code': 'qualite', 'libelle': 'Qualité', 'ordre': 1},
      {'id': 'RFP-002', 'statut': 'actif', 'type': 'axe', 'code': 'finance', 'libelle': 'Finance', 'ordre': 2},
      {'id': 'RFP-003', 'statut': 'actif', 'type': 'etat', 'code': 'planifiee', 'libelle': 'Planifiée', 'nature': 'planifiee', 'ton': 'warning', 'ordre': 1},
      {'id': 'RFP-004', 'statut': 'actif', 'type': 'etat', 'code': 'en_cours', 'libelle': 'En cours', 'nature': 'en_cours', 'ton': 'info', 'ordre': 2},
      {'id': 'RFP-005', 'statut': 'actif', 'type': 'etat', 'code': 'realisee', 'libelle': 'Réalisée', 'nature': 'realisee', 'ton': 'success', 'ordre': 3},
    ],
    'personnel': [
      {'id': 'AG1', 'statut': 'actif', 'nomComplet': 'AGENT UN', 'poste': 'Comptable'}
    ],
    'postes': [
      {'id': 'PS1', 'statut': 'actif', 'poste': 'Directrice Administrative', 'titulaire': 'TITULAIRE UNE', 'role': 'da'},
      {'id': 'PS2', 'statut': 'actif', 'poste': 'Directeur Médical', 'titulaire': 'TITULAIRE DEUX', 'role': 'dm'},
      {'id': 'PS3', 'statut': 'actif', 'poste': 'Comptable', 'titulaire': null, 'role': 'comptable'},
    ],
    'budgets': [
      {'id': 'BUD1', 'statut': 'actif', 'exercice': 2026, 'reference': 'BG-2026-001', 'centre': 'Laboratoire', 'prevu': 1000000}
    ],
    'reglagesPlan': [
      {'id': 'RPL-001', 'statut': 'actif', 'dateEffet': null, 'signataires': [{'posteId': 'PS1'}, {'posteId': 'PS2'}]}
    ],
    'planAnnuel': const [],
    'adoptionsPlan': const [],
    'audit': const [],
  });
  m.horloge = () => j;
  serviceParametres(m, auteur: () => 'semis', horloge: () => j).semerDefauts();
  return m;
}

Fiche saisie({int annee = 2026, String action = 'Audit qualité', int d = 1, int f = 2, String etat = 'en_cours', String resp = 'poste:PS3', Map<String, Object?> plus = const {}}) =>
    {'exercice': annee, 'action': action, 'axe': 'qualite', 'trimestreDebut': d, 'trimestreFin': f, 'avancement': etat, 'responsable': resp, ...plus};

Fiche ajouter(Magasin m, Fiche s, {String? motif}) {
  final r = ajouterActionPlan(m, s, motif: motif);
  expect(r.refus, isNull, reason: '${r.refus}');
  return r.fiche!;
}

Future<void> ouvrir(WidgetTester t, Magasin m, {DateTime? jour, String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.mere, role: role), ecranInitial: 'm13-plan-annuel', magasin: m, horloge: () => jour ?? auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  test('création : la référence PA-<année de l\'exercice>-NNN, le responsable est une RÉFÉRENCE (agent ou poste), jamais un texte libre ; le moteur refuse en nommant', () {
    final m = magasin();
    final a = ajouter(m, saisie());
    final b = ajouter(m, saisie(action: 'Formation', resp: 'agent:AG1'));
    final c27 = ajouter(m, saisie(annee: 2027, action: 'Plan 2027'));
    expect([a['reference'], b['reference'], c27['reference']], ['PA-2026-001', 'PA-2026-002', 'PA-2027-001'], reason: 'un compteur par année, l\'année est celle de l\'exercice');
    expect(libelleResponsablePlan(m, a), 'Comptable (poste vacant)');
    expect(libelleResponsablePlan(m, b), 'AGENT UN (Comptable)');
    final libre = ajouterActionPlan(m, {...saisie(), 'responsable': 'KASSA Augustin'});
    expect(libre.refus?.code, 'RESPONSABLE_TEXTE_LIBRE');
    expect(ajouterActionPlan(m, saisie(resp: 'poste:INCONNU')).refus?.code, 'RESPONSABLE_INCONNU');
    expect(ajouterActionPlan(m, saisie(annee: 1999)).refus?.code, 'EXERCICE_INCONNU');
    expect(ajouterActionPlan(m, saisie(plus: {'tauxAvancement': 150})).refus?.code, 'POURCENTAGE_HORS_BORNES');
    expect(ajouterActionPlan(m, saisie(plus: {'tauxAvancement': -1})).refus?.code, 'POURCENTAGE_HORS_BORNES');
    expect(ajouter(m, saisie(action: 'Zéro', plus: {'tauxAvancement': 0}))['tauxAvancement'], 0);
    expect(() => m.collection('planAnnuel').inserer({'exercice': 2026, 'action': 'Direct', 'axe': 'qualite', 'avancement': 'en_cours', 'trimestreDebut': 1, 'trimestreFin': 1, 'responsable': 'KASSA'}),
        throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('RESPONSABLE_TEXTE_LIBRE'))),
        reason: 'la GARDE de la collection refuse aussi : un import ou un autre écran ne contourne pas le moteur');
    expect(() => m.collection('planAnnuel').mettreAJour(a['id'], {'tauxAvancement': 101}), throwsA(isA<EcritureRefusee>()));
  });

  test('adoption : geste réservé (refus nommé sans le droit), motif exigé, une fois ; le contenu est FIGÉ (le moteur refuse), le suivi reste libre ; réviser crée une version datée', () {
    final m = magasin();
    final a = ajouter(m, saisie());
    expect(adopterPlan(m, annee: 2026, motif: 'Délibération', gesteAccorde: false, libelleRole: 'Comptable')?.code, 'ADOPTION_RESERVEE');
    expect(adopterPlan(m, annee: 2026, motif: '', gesteAccorde: true, libelleRole: 'Direction')?.code, 'MOTIF_OBLIGATOIRE');
    expect(adopterPlan(m, annee: 2025, motif: 'Test', gesteAccorde: true, libelleRole: 'Direction')?.code, 'EXERCICE_INCONNU');
    expect(adopterPlan(m, annee: 2027, motif: 'Test', gesteAccorde: true, libelleRole: 'Direction')?.code, 'PLAN_VIDE');
    expect(adopterPlan(m, annee: 2026, motif: 'Délibération du conseil', gesteAccorde: true, libelleRole: 'Direction'), isNull);
    expect(adopterPlan(m, annee: 2026, motif: 'Encore', gesteAccorde: true, libelleRole: 'Direction')?.code, 'PLAN_DEJA_ADOPTE');
    final ad = adoptionPlan(m, 2026)!;
    expect([ad['dateAdoption'], ad['motif'], ad['nbActions']], ['2026-10-30', 'Délibération du conseil', 1]);
    expect(m.collection('audit').toutes.any((e) => '${e['action']}'.contains('adoption')), isTrue, reason: 'journal RG-12');
    expect(() => m.collection('planAnnuel').mettreAJour(a['id'], {'action': 'Autre libellé'}), throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('PLAN_ADOPTE_FIGE'))));
    expect(() => m.collection('planAnnuel').mettreAJour(a['id'], {'budgetPrevu': 1}), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('planAnnuel').archiver(a['id']), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('adoptionsPlan').mettreAJour(ad['id'], {'motif': 'x'}), throwsA(isA<EcritureRefusee>()), reason: 'une adoption ne se réécrit pas');
    m.collection('planAnnuel').mettreAJour(a['id'], {'tauxAvancement': 40, 'budgetRealise': 1000});
    expect(m.collection('planAnnuel').parId(a['id'])!['tauxAvancement'], 40, reason: 'le suivi reste libre après l\'adoption');
    expect(ajouterActionPlan(m, saisie(action: 'Ajout')).refus?.code, 'MOTIF_OBLIGATOIRE');
    final ajout = ajouter(m, saisie(action: 'Ajout', d: 4, f: 4), motif: 'Demande de la Direction');
    expect(ajout['ajouteApresAdoption'], true);
    expect(reviserActionPlan(m, a['id'], {'trimestreFin': 3}, '').refus?.code, 'MOTIF_OBLIGATOIRE');
    expect(reviserActionPlan(m, a['id'], {'tauxAvancement': 5}, 'Motif').refus?.code, 'CHAMP_HORS_REVISION');
    final rv = reviserActionPlan(m, a['id'], {'trimestreFin': 3}, 'Report au troisième trimestre');
    expect(rv.refus, isNull);
    expect(rv.fiche!['version'], 2);
    expect(rv.fiche!['reference'], a['reference'], reason: 'la référence ne change pas, la version si');
    expect(m.collection('planAnnuel').parId(a['id'])!['statut'], 'archive', reason: 'l\'ancienne version est archivée (RG-14)');
    expect(actionsPlan(m, 2026).where((x) => x['reference'] == a['reference']).length, 1);
    expect(reviserActionPlan(m, a['id'], {'trimestreFin': 4}, 'Encore').refus?.code, 'ACTION_INCONNUE', reason: 'on révise la version courante, pas l\'ancienne');
  });

  test('reconduire : copie datée des actions NON réalisées vers l\'exercice suivant, une seule fois, source intacte ; refusée vers un plan adopté', () {
    final m = magasin();
    final a = ajouter(m, saisie(action: 'A reconduire', plus: {'budgetPrevu': 500000, 'indicateur': 'Taux', 'cible': 90}));
    ajouter(m, saisie(action: 'Terminée', etat: 'realisee'));
    ajouter(m, saisie(action: 'En attente', etat: 'planifiee', d: 3, f: 4));
    ajouter(m, saisie(action: 'Avec suivi', plus: {'tauxAvancement': 60, 'budgetRealise': 100}));
    final avant = m.collection('planAnnuel').toutes.length;
    final r = reconduirePlan(m, 2026, 2027);
    expect(r.refus, isNull);
    expect(r.copiees.length, 3, reason: 'trois non réalisées sur quatre');
    expect(r.copiees.first, startsWith('PA-2027-'));
    final copies = actionsPlan(m, 2027);
    expect(copies.every((c) => c['avancement'] == 'planifiee' && !c.containsKey('tauxAvancement') && !c.containsKey('budgetRealise')), isTrue, reason: 'le suivi repart de zéro');
    final cp = copies.firstWhere((c) => c['reconduiteDepuis'] == a['reference']);
    expect([cp['budgetPrevu'], cp['indicateur'], cp['cible'], cp['reconduiteDe']], [500000, 'Taux', 90, a['id']]);
    expect(m.collection('planAnnuel').toutes.length, avant + 3);
    expect(actionsPlan(m, 2026).length, 4, reason: 'la source n\'est pas réécrite');
    expect(reconduirePlan(m, 2026, 2027).copiees, isEmpty, reason: 'une seconde fois : rien n\'est dupliqué');
    expect(reconduirePlan(m, 2026, 2026).refus?.code, 'RECONDUCTION_MEME_EXERCICE');
    expect(adopterPlan(m, annee: 2027, motif: 'Délibération', gesteAccorde: true, libelleRole: 'Direction'), isNull);
    expect(reconduirePlan(m, 2026, 2027).refus?.code, 'PLAN_ADOPTE_FIGE');
  });

  test('l\'alerte de retard est DÉRIVÉE, une par action, retombe quand l\'action est réalisée ou replanifiée ; la tolérance est un paramètre de clinique en base', () {
    final m = magasin();
    final a = ajouter(m, saisie(action: 'Fin T2', d: 1, f: 2));
    ajouter(m, saisie(action: 'Fin T4', d: 1, f: 4));
    ajouter(m, saisie(action: 'Déjà faite', d: 1, f: 1, etat: 'realisee'));
    List<String> al(String jour) => [for (final x in alertesRetardPlan(m, jour)) '${x.action['action']}'];
    expect(al('2026-06-30'), isEmpty, reason: 'le dernier jour du trimestre, pas de retard');
    expect(al('2026-07-01'), ['Fin T2']);
    expect(al('2026-10-30'), ['Fin T2'], reason: 'une alerte par action : la T4 n\'est pas en retard, la réalisée jamais');
    expect(alertesRetardPlan(m, '2026-10-30').single.jours, 122);
    m.collection('planAnnuel').mettreAJour(a['id'], {'trimestreFin': 4});
    expect(al('2026-10-30'), isEmpty, reason: 'replanifiée : retombée');
    m.collection('planAnnuel').mettreAJour(a['id'], {'trimestreFin': 2});
    expect(al('2026-10-30'), ['Fin T2']);
    m.collection('planAnnuel').mettreAJour(a['id'], {'avancement': 'realisee'});
    expect(al('2026-10-30'), isEmpty, reason: 'réalisée : retombée');
    expect(al('2027-01-02'), ['Fin T4'], reason: 'le trimestre de fin est lu sur le premier jour de l\'exercice, plus loin dans l\'année');
    expect(graceRetardPlan(m, '2026-10-30'), 0);
    expect(reglerParametreGrace(m, 30), isNull);
    expect(al('2027-01-02'), isEmpty, reason: 'une tolérance de 30 jours repousse l\'alerte');
  });

  test('le centre de notifications : UNE alerte par action en retard, vers les détenteurs du geste d\'adoption (fiche RBAC), sans donnée de santé ; elle retombe quand l\'action est réalisée', () {
    final m = magasin();
    final a = ajouter(m, saisie(action: 'Fin T2', d: 1, f: 2));
    ajouter(m, saisie(action: 'Fin T4', d: 1, f: 4));
    List<AlerteNotif> pour(String role) => CentreNotifications(magasin: m, donnees: () => donnees, role: () => role, horloge: () => auj).collecter(detaille: true).where((n) => n.source == 'plan_retard').toList();
    final avec = [for (final r in ['admin', 'da', 'direction', 'agentadmin', 'comptable']) if (donnees.matrice.droitGeste(r, paGesteAdopter)) r];
    final sans = [for (final r in ['admin', 'da', 'direction', 'agentadmin', 'comptable']) if (!donnees.matrice.droitGeste(r, paGesteAdopter)) r];
    expect(avec.toSet(), {'da', 'direction'}, reason: 'défaut proposé : la Direction et la Directrice Administrative');
    final x = pour(avec.first);
    expect(x, hasLength(1), reason: 'la fin T4 n\'est pas en retard au 30/10 ; une alerte par action');
    expect(x.single.titre, 'Action en retard : ${a['reference']} Fin T2');
    expect('${x.single.titre} ${x.single.detail}', isNot(contains(RegExp('patient|diagnostic|ordonnance', caseSensitive: false))));
    for (final r in sans) {
      expect(pour(r), isEmpty, reason: '$r ne détient pas le geste d\'adoption');
    }
    m.collection('planAnnuel').mettreAJour(a['id'], {'avancement': 'realisee'});
    expect(pour(avec.first), isEmpty, reason: 'réalisée : l\'alerte retombe');
  });

  test('signataires : lus au paramétrage (fonction par référence à un poste, titulaire lu au poste à la date), réglés par une version datée et un geste réservé', () {
    final m = magasin();
    var s = signatairesPlan(m, '2026-10-30');
    expect([for (final x in s) x.fonction], ['Directrice Administrative', 'Directeur Médical']);
    expect([for (final x in s) x.nom], ['TITULAIRE UNE', 'TITULAIRE DEUX']);
    m.collection('postes').mettreAJour('PS1', {'titulaire': 'NOUVELLE TITULAIRE'});
    expect(signatairesPlan(m, '2026-10-30').first.nom, 'NOUVELLE TITULAIRE', reason: 'le titulaire est lu au poste, jamais écrit dans l\'impression');
    expect(definirSignatairesPlan(m, posteIds: ['PS3'], dateEffet: '2026-11-01', motif: 'Test', gesteAccorde: false, libelleRole: 'Comptable')?.code, 'PARAMETRE_CLINIQUE_RESERVE');
    expect(definirSignatairesPlan(m, posteIds: [], dateEffet: '2026-11-01', motif: 'Test', gesteAccorde: true, libelleRole: 'Admin')?.code, 'SIGNATAIRES_NOMBRE');
    expect(definirSignatairesPlan(m, posteIds: ['XX'], dateEffet: '2026-11-01', motif: 'Test', gesteAccorde: true, libelleRole: 'Admin')?.code, 'SIGNATAIRE_INCONNU');
    expect(definirSignatairesPlan(m, posteIds: ['PS3'], dateEffet: '2026-11-01', motif: '', gesteAccorde: true, libelleRole: 'Admin')?.code, 'PARAMETRE_MOTIF_OBLIGATOIRE');
    expect(definirSignatairesPlan(m, posteIds: ['PS2', 'PS3'], dateEffet: '2026-11-15', motif: 'Changement de signataire', gesteAccorde: true, libelleRole: 'Admin'), isNull);
    expect([for (final x in signatairesPlan(m, '2026-11-14')) x.fonction], ['Directrice Administrative', 'Directeur Médical'], reason: 'la veille, l\'ancien réglage');
    expect([for (final x in signatairesPlan(m, '2026-11-15')) x.fonction], ['Directeur Médical', 'Comptable']);
    expect(definirSignatairesPlan(m, posteIds: ['PS3'], dateEffet: '2026-11-01', motif: 'Rétroactif', gesteAccorde: true, libelleRole: 'Admin')?.code, 'DATE_EFFET_ANTERIEURE');
  });

  testWidgets('l\'écran : l\'exercice est celui du JOUR (jamais une année écrite), le plan se lit et se chiffre, « non calculable » n\'est pas zéro', (t) async {
    final m = magasin(jour: DateTime(2027, 3, 1));
    ajouter(m, saisie(annee: 2027, action: 'Action 2027', plus: {'budgetPrevu': 1200000, 'tauxAvancement': 25}));
    ajouter(m, saisie(annee: 2026, action: 'Action 2026'));
    await ouvrir(t, m, jour: DateTime(2027, 3, 1), role: 'da');
    expect(find.text('Plan annuel de travail 2027'), findsOneWidget, reason: 'l\'exercice du jour est choisi par défaut');
    expect(find.text('Plan annuel de travail 2026'), findsNothing);
    expect(find.text('Action 2027'), findsWidgets);
    expect(find.text('Action 2026'), findsNothing);
    expect(find.text('Plan non adopté'), findsOneWidget);
    final libelles = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-libelle')))) w.data!];
    final valeurs = [for (final w in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur')))) w.data!];
    final k = {for (var i = 0; i < libelles.length; i++) libelles[i]: valeurs[i]};
    expect(k['Actions programmées'], '1');
    expect(k['Avancement moyen'], '25 %');
    expect(k['Budget réalisé'], 'Non renseigné', reason: 'aucun réalisé saisi : non renseigné, pas zéro');
    expect(find.text('Adopter le plan'), findsOneWidget, reason: 'la Directrice Administrative détient le geste d\'adoption (défaut proposé)');
  });

  testWidgets('l\'écran : « Adopter le plan » et « Signataires » sont ABSENTS sans le geste (jamais grisés) ; l\'écran d\'un agent administratif ne les offre pas', (t) async {
    final m = magasin();
    ajouter(m, saisie());
    await ouvrir(t, m, role: 'agentadmin');
    expect(find.text('Adopter le plan'), findsNothing);
    expect(find.text('Signataires de l’impression'), findsNothing);
  });
}

/// Règle la tolérance de l'alerte (paramètre de clinique) comme le fait l'écran de réglage.
RefusParametreClinique? reglerParametreGrace(Magasin m, int v) => pcControler(pcCleGraceRetardPlan, v) ??
    () {
      final s = serviceParametres(m, auteur: () => 'test', horloge: () => DateTime(2026, 10, 30));
      final w = s.regler(pcCleGraceRetardPlan, v, '2026-10-01', motif: 'test');
      return w.ok ? null : RefusParametreClinique('X', '${w.refus}', '');
    }();
