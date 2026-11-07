// Rejoue les vecteurs du bloc, de l'anesthésie et des sorties (prototype_html/build/vecteurs-bloc.js) : huit écrans M3 réels pilotés dans Chrome.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final d = lireVecteurs('bloc');
  final auj = DateTime(2026, 8, 16, 10);
  Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();
  int k(Object? kpi, int rang) => int.parse(liste(kpi)[rang]['valeur'].toString().replaceAll(RegExp(r'\s'), ''));
  Map<String, Object?> patientDe(Map<String, Object?> f) {
    final nom = '${f['patient']}';
    final i = nom.indexOf(' ');
    return {'id': f['patientId'], 'nom': nom.substring(0, i), 'prenom': nom.substring(i + 1)};
  }

  test('référentiels : échelles ASA et Mallampati, techniques, conclusions, décisions, check-listes arrêtées le 01/09/2026', () {
    final r = m(d['referentiels']);
    expect([for (final o in blocAsa) [o.id, o.label]], (r['asa'] as List).map((x) => (x as List).cast<String>()).toList());
    expect([for (final o in blocMallampati) [o.id, o.label]], (r['mallampati'] as List).map((x) => (x as List).cast<String>()).toList());
    expect(blocTechniques, [for (final x in r['techniques'] as List) (x as List)[0]]);
    expect(blocConclusionsCpa, [for (final x in r['conclusions'] as List) (x as List)[0]]);
    expect(blocDecisionsReveil, [for (final x in r['decisions'] as List) (x as List)[0]]);
    final c = m(r['checklist']);
    expect(blocChecklistEntree, (c['entree'] as List).cast<String>());
    expect(blocChecklistSortie, (c['sortie'] as List).cast<String>());
    expect(blocChecklistArreteLe, c['arreteLe']);
    expect([for (final o in blocServicesDemandeurs) o.id], [for (final s in liste(r['servicesDemandeurs'])) s['id']]);
    expect([for (final o in blocServicesDemandeurs) o.label], [for (final s in liste(r['servicesDemandeurs'])) s['label']]);
    expect([for (final o in blocNiveauxUrgence) o.id], [for (final s in liste(r['niveauxUrgence'])) s['id']]);
    expect([for (final o in blocNiveauxUrgence) o.label], [for (final s in liste(r['niveauxUrgence'])) s['label']]);
  });

  test('amorçage de la CPA : six fiches tirées de la graine 701, adossées aux six premières admissions', () {
    final a = m(d['amorcageCpa']);
    final obtenu = blocAmorcerCpa(liste(a['admissions']));
    memes(obtenu, liste(a['cpa']), 'cpa');
    final kp = blocKpisCpa(obtenu, const []);
    expect(kp.cpa, k(a['kpis'], 0));
    expect(kp.aptes, k(a['kpis'], 1));
    expect(kp.reserves, k(a['kpis'], 2));
  });

  group('CPA et compte rendu opératoire', () {
    final c = m(d['cpa']);
    final jeu = m(c['jeu']);

    test('indicateurs : les interventions sans CPA sont des comptes rendus, SIGNALÉES jamais bloquées', () {
      final kp = blocKpisCpa(liste(jeu['cpa']), liste(jeu['cro']));
      final e = m(c['ecran'])['kpis'];
      expect([kp.cpa, kp.aptes, kp.reserves, kp.sansCpa], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
      // Une CPA créée pour le patient d'une intervention retire cette intervention de la liste des signalées.
      final cree = m(m(c['creation'])['creeApte']);
      final apres = blocKpisCpa([...liste(jeu['cpa']), m(m(m(c['creation'])['creeAvecReserves'])['fiche']), m(cree['fiche'])], liste(jeu['cro']));
      expect(apres.sansCpa, k(cree['kpis'], 3));
      expect(apres.aptes, k(cree['kpis'], 1));
    });

    test('réserves : une CPA « avec réserves » ou « à reporter » EXIGE ses réserves nommées, à la création comme à la modification', () {
      final refus = blocRefusCpa({'conclusion': 'Apte avec réserves', 'observations': ''})!;
      final attendu = ((m(c['creation'])['refusReserves'] as Map)['toasts'] as List)[0] as List;
      expect(refus.message, attendu[0]);
      expect(refus.detail, attendu[1]);
      expect(blocRefusCpa({'conclusion': 'Intervention à reporter', 'observations': '   '}), isNotNull);
      expect(blocRefusCpa({'conclusion': 'Apte avec réserves', 'observations': 'HTA'}), isNull);
      expect(blocRefusCpa({'conclusion': 'Apte à l’anesthésie', 'observations': ''}), isNull);
      final modif = ((m(c['modification'])['refus'] as Map)['toasts'] as List)[0] as List;
      expect(modif[0], refus.message);
    });

    test('création : référence lue sur le registre (E410), patient recopié depuis le code choisi', () {
      final cree = m(m(m(c['creation'])['creeAvecReserves'])['fiche']);
      final saisie = {
        for (final e in cree.entries)
          if (!{'id', 'statut', 'reference', 'patientId', 'patient'}.contains(e.key)) e.key: e.value
      };
      final f = blocConstruirePatientCode(saisie,
          patient: patientDe(cree), prefixeReference: 'CPA-2026-', toutes: liste(jeu['cpa']));
      memes(f, cree, 'cpa', ignorer: {'id', 'statut'});
    });

    test('modification : le NOM suit le patient corrigé (E411), la référence reste', () {
      final apres = m(m(c['modification'])['autrePatient'])['fiche'] as Map<String, Object?>;
      final f = blocConstruirePatientCode({'patientCode': apres['patientCode']}, patient: patientDe(apres.cast<String, Object?>()));
      expect(f['patient'], apres['patient']);
      expect(f['patientId'], apres['patientId']);
      expect(f.containsKey('reference'), isFalse);
    });

    test('compte rendu opératoire : indicateurs au mois de l’horloge ; trois intervenants NOMMÉS', () {
      final cro = m(c['cro']);
      final kp = blocKpisCro(liste(jeu['cro']), auj);
      final e = m(cro['ecran'])['kpis'];
      expect([kp.total, kp.mois, kp.sansAide], [k(e, 0), k(e, 1), k(e, 2)]);
      final cree = m(m(cro['creation'])['cree']);
      final fiche = m(cree['fiche']);
      final noms = {'SOI03': 'TAKI Orou', 'SOI12': 'OROU YO Alimatou', 'SOI15': 'ADAM Colette'};
      final saisie = {
        for (final x in fiche.entries)
          if (!{'id', 'statut', 'reference', 'patientId', 'patient', 'operateur', 'aideOperateur', 'anesthesiste'}.contains(x.key)) x.key: x.value
      };
      final f = blocConstruireCro(saisie,
          patient: patientDe(fiche), nomSoignant: (id) => noms['$id'] ?? '—', toutes: liste(jeu['cro']));
      memes(f, fiche, 'cro', ignorer: {'id', 'statut'});
      // Sans aide-opérateur : le champ est facultatif, la fiche porte null.
      final sans = m(m(m(cro['creation'])['sansAide'])['fiche']);
      expect(sans['aideOperateur'], isNull);
      final apresSans = blocKpisCro([...liste(jeu['cro']), fiche, sans], auj);
      expect(apresSans.sansAide, k(m(m(cro['creation'])['sansAide'])['kpis'], 2));
      expect(apresSans.mois, k(m(m(cro['creation'])['sansAide'])['kpis'], 1));
    });

    test('modification du compte rendu : l’opérateur corrigé change aussi le NOM porté (E411)', () {
      final apres = m(m(c['cro'])['modification'])['fiche'];
      expect(m(apres)['operateurId'], 'SOI04');
      final f = blocConstruireCro({'operateurId': 'SOI04', 'anesthesisteId': 'SOI15', 'aideOperateurId': '', 'patientCode': m(apres)['patientCode']},
          patient: patientDe(m(apres)),
          nomSoignant: (id) => {'SOI04': 'AHOHOU Rodrigue', 'SOI15': 'ADAM Colette'}['$id'] ?? '—',
          existante: m(apres),
          toutes: const []);
      expect(f['operateur'], m(apres)['operateur']);
      expect(f['operateur'], 'AHOHOU Rodrigue');
    });
  });

  test('compte rendu d’anesthésie : « aucun incident » s’écrit, un incident se NOMME', () {
    final c = m(d['cra']);
    final rows = liste(m(c['jeu'])['cra']);
    final kp = blocKpisCra(rows);
    final e = m(c['ecran'])['kpis'];
    expect([kp.total, kp.incidents, kp.prolonges, kp.cro], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
    expect(blocIncidentNomme('Aucun incident'), isFalse);
    expect(blocIncidentNomme('aucun'), isFalse);
    expect(blocIncidentNomme('Aucune difficulté'), isFalse);
    expect(blocIncidentNomme('Hypotension transitoire traitée'), isTrue);
    expect(blocIncidentNomme(''), isFalse);
    expect(blocIncidentNomme(null), isFalse);
    final cree = m(m(c['creation'])['cree']);
    final apres = blocKpisCra([...rows, m(cree['fiche'])]);
    expect([apres.total, apres.incidents, apres.prolonges, apres.cro], [k(cree['kpis'], 0), k(cree['kpis'], 1), k(cree['kpis'], 2), k(cree['kpis'], 3)]);
    final fiche = m(cree['fiche']);
    final saisie = {
      for (final x in fiche.entries)
        if (!{'id', 'statut', 'reference', 'patientId', 'patient'}.contains(x.key)) x.key: x.value
    };
    memes(blocConstruirePatientCode(saisie, patient: {'id': fiche['patientId'], 'nom': 'PARAISO', 'prenom': 'Sabi'}, prefixeReference: 'CRA-2026-', toutes: rows),
        fiche, 'cra', ignorer: {'id', 'statut'});
  });

  test('check-listes : DEUX listes séparées ; incomplète SIGNALÉE, jamais refusée', () {
    final c = m(d['checklist']);
    final rows = liste(c['jeu']);
    final kp = blocKpisChecklist(rows);
    final e = m(c['ecran'])['kpis'];
    expect([kp.total, kp.entree, kp.sortie, kp.incompletes], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
    // Rien coché : enregistrée, signalée « 9 point(s) NON vérifié(s) ».
    final rien = blocLignesChecklist(blocChecklistSortie, const {});
    expect([rien.coches, rien.total], [0, 9]);
    final msg = blocMessageChecklist(rien.coches, rien.total);
    expect(msg.complete, isFalse);
    expect(msg.message, ((m(m(c['remplirSortie'])['rienCoche'])['toasts'] as List)[0] as List)[0]);
    // Trois points cochés sur la check-liste de sortie.
    final trois = blocLignesChecklist(blocChecklistSortie, {'it0': true, 'it1': true, 'it2': true});
    final fiche = m(m(m(c['remplirSortie'])['incomplete'])['fiche']);
    expect(trois.coches, fiche['coches']);
    expect(trois.items, (fiche['items'] as List).cast<Map<String, Object?>>());
    // Entrée complète.
    final tout = blocLignesChecklist(blocChecklistEntree, {for (var i = 0; i < 12; i++) 'it$i': true});
    final complete = blocMessageChecklist(tout.coches, tout.total);
    expect(complete.complete, isTrue);
    expect(complete.message, ((m(c['remplirEntree'])['toasts'] as List)[0] as List)[0]);
    expect(tout.items, (m(m(c['remplirEntree'])['fiche'])['items'] as List).cast<Map<String, Object?>>());
    // Le « Modifier » d'une ligne lève une erreur dans la maquette (aucun champ déclaré) : porté sans cette commande (E421).
    expect(((m(c['modifier'])['erreurs']) as List), isNotEmpty);
  });

  test('fiche de demande d’examen : « un examen urgent » se NOMME ; le secteur demandeur ne vaut que pour la maternité', () {
    final c = m(d['demandeExamen']);
    final rows = blocDemandesService(liste(c['jeu']));
    expect(rows.length, 4);
    final kp = blocKpisDemandes(rows);
    final e = m(c['ecran'])['kpis'];
    expect([kp.fiches, kp.attente, kp.urgentes, kp.rendus], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
    final refus = blocRefusDemandeExamen({'urgence': 'examen', 'examenUrgent': ''})!;
    final attendu = ((m(c['refusExamenNonNomme'])['toasts'] as List)[0]) as List;
    expect([refus.message, refus.detail], [attendu[0], attendu[1]]);
    expect(blocRefusDemandeExamen({'urgence': 'bilan', 'examenUrgent': ''}), isNull);
    expect(blocRefusDemandeExamen({'urgence': 'examen', 'examenUrgent': 'L02'}), isNull);
    expect(blocSecteurDemandeur('maternite'), 'MATERNITÉ');
    expect(blocSecteurDemandeur('medecine'), isNull);
    expect(blocSecteurDemandeur('specialite'), isNull);
  });

  test('bons de pansement : une ligne payable PAR SÉANCE, 9 000 non assuré (colonnes inversées, ne pas « corriger »)', () {
    final p = m(d['pansements']);
    final actes = liste(p['actes']);
    expect(actes.firstWhere((a) => a['code'] == 'SO09')['prix'], 9000);
    expect([for (final a in actes) a['code']]..sort(), [...blocCodesPansement]..sort());
    final em = m(p['emission']);
    final ord = liste(em['ordonnances']);
    expect(blocBonsPansement(ord).length, 1);
    // Un bon qui porte aussi un médicament ou une analyse n'est pas un bon de pansement.
    expect(blocBonsPansement([{...ord.first, 'medicaments': [{}]}]), isEmpty);
    expect(blocBonsPansement([{...ord.first, 'analyses': [{}]}]), isEmpty);
    expect(blocBonsPansement([{'actes': [{'code': 'SO09'}, {'code': 'GY01'}], 'medicaments': [], 'analyses': []}]), isEmpty);
    final fac = liste(em['factures']);
    final s0 = blocSeancesDe(ord.first, fac);
    expect([s0.total, s0.reglees], [3, 0]);
    expect(fac.first['lignes'] is List && (fac.first['lignes'] as List).length == 3, isTrue);
    // Après le règlement de la première séance : « 1 / 3 ».
    final partiel = liste(m(p['partiel'])['lignes']);
    final facP = {...fac.first, 'lignes': [for (final l in partiel) {...l}]};
    final s1 = blocSeancesDe(ord.first, [facP]);
    expect([s1.total, s1.reglees], [3, 1]);
    final kp = blocKpisPansements(ord, fac);
    expect(kp.bons, k(em['kpis'], 0));
    expect(kp.attente, k(em['kpis'], 1));
    final kp1 = blocKpisPansements(ord, [facP]);
    expect(kp1.attente, k(m(p['apresPartiel'])['kpis'], 1));
    expect(blocNombreSeances('3'), 3);
    expect(blocNombreSeances(''), 1);
    expect(blocNombreSeances('0'), 1);
    expect(blocNombreSeances('40'), 12);
  });

  group('sorties d’hospitalisation', () {
    final s = m(d['sorties']);
    final jeu = m(s['jeu']);
    final adm = liste(jeu['admissions']);
    final fac = liste(jeu['factures']);

    test('solde = somme des restes dus de TOUTES les factures du patient ; indicateurs', () {
      expect(blocSoldePatient(fac, 'PAT0001'), 20000);
      expect(blocSoldePatient(fac, 'PAT0002'), 0);
      expect(blocSoldePatient(fac, 'PAT0099'), 0);
      final actives = [for (final a in adm) if (a['statut'] != 'archive') a];
      final kp = blocKpisSorties(actives, fac);
      final e = m(s['ecran'])['kpis'];
      expect([kp.hospitalises, kp.finalisables, kp.bloquees, kp.realisees], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
      // Après la finalisation de ADM1 les indicateurs se recalculent (E415).
      final finalisee = [for (final a in actives) a['id'] == 'ADM1' ? {...a, ...blocPatchSortie({'dateSortie': '2026-08-16', 'etatSortie': 'Amélioré', 'consignes': 'Repos 7 jours', 'derogation': 'x'})} : a];
      final k1 = blocKpisSorties(finalisee, fac);
      final f = m(s['finalisation'])['kpis'];
      expect([k1.hospitalises, k1.finalisables, k1.bloquees, k1.realisees], [k(f, 0), k(f, 1), k(f, 2), k(f, 3)]);
    });

    test('RG-07 puis RG-06 : trois signatures, puis dérogation motivée si le solde n’est pas apuré', () {
      String? msg(BlocRefus? r) => r == null ? null : '${r.message} | ${r.detail}';
      String attendu(String cle) {
        final t = ((m(s['refus'])[cle] as Map)['toasts'] as List)[0] as List;
        return '${t[0]} | ${t[1]}';
      }

      expect(msg(blocRefusSortie({}, 20000)), attendu('sansSignatures'));
      expect(msg(blocRefusSortie({'sigPatient': true, 'sigInfirmier': true}, 20000)), attendu('deuxSignatures'));
      final tous = {'sigPatient': true, 'sigInfirmier': true, 'constatGardien': true};
      expect(msg(blocRefusSortie(tous, 20000)), attendu('soldeSansDerogation'));
      expect(msg(blocRefusSortie({...tous, 'derogation': '   '}, 20000)), attendu('derogationBlanche'));
      expect(blocRefusSortie({...tous, 'derogation': 'Accord de la Direction'}, 20000), isNull);
      expect(blocRefusSortie(tous, 0), isNull);
    });

    test('finalisation : l’admission sort, le lit est libéré, la dérogation est portée', () {
      final avant = adm.firstWhere((a) => a['id'] == 'ADM1');
      final apres = m(m(s['finalisation'])['admission']);
      final patch = blocPatchSortie({
        'dateSortie': '2026-08-16',
        'etatSortie': 'Amélioré',
        'consignes': 'Repos 7 jours',
        'derogation': 'Accord de la Directrice Administrative'
      });
      memes({...avant, ...patch}, apres, 'admission');
      // Sortie nette : la dérogation vaut null.
      final nette = m(m(m(s['apure'])['sortie'])['admission']);
      memes({...adm.firstWhere((a) => a['id'] == 'ADM2'), ...blocPatchSortie({'dateSortie': '2026-08-16', 'etatSortie': 'Guéri', 'consignes': ''})}, nette, 'admission');
      expect(hosDureeSejour(avant, auj), 10);
    });
  });

  group('sortie contre avis médical (RG-08)', () {
    final a = m(d['avisMedical']);
    final jeu = m(a['jeu']);

    test('la référence du Procureur est obligatoire dès que son avis est coché', () {
      final refus = blocRefusAvisMedical({'avisProcureur': true, 'referenceProcureur': ''})!;
      expect(refus.message, (((m(a['creation'])['refusProcureur'] as Map)['toasts'] as List)[0] as List)[0]);
      expect(blocRefusAvisMedical({'avisProcureur': true, 'referenceProcureur': '  '}), isNotNull);
      expect(blocRefusAvisMedical({'avisProcureur': true, 'referenceProcureur': 'PR-1'}), isNull);
      expect(blocRefusAvisMedical({'avisProcureur': false, 'referenceProcureur': ''}), isNull);
    });

    test('indicateurs : lus à chaque geste (E418), hospitalisés = admissions en cours', () {
      final kp = blocKpisAvis(liste(jeu['sorties']), liste(jeu['admissions']));
      final e = m(a['ecran'])['kpis'];
      expect([kp.sorties, kp.procureur, kp.hospitalises, kp.clotures], [k(e, 0), k(e, 1), k(e, 2), k(e, 3)]);
    });

    test('création : patient, dossier et lit recopiés de l’admission ; série SAM lue sur le registre', () {
      final cree = m(m(m(a['creation'])['cree'])['fiche']);
      final admission = liste(jeu['admissions']).firstWhere((x) => x['id'] == 'ADM1');
      final saisie = {
        for (final x in cree.entries)
          if (!{'id', 'statut', 'patient', 'patientCode', 'lit', 'reference'}.contains(x.key)) x.key: x.value
      };
      final f = blocConstruireAvis(saisie, admission: admission, toutes: liste(jeu['sorties']));
      memes(f, cree, 'avis', ignorer: {'id', 'statut'});
      // Modification : la référence est CELLE de la fiche (la maquette la régénérait à chaque enregistrement).
      final existante = liste(jeu['sorties']).first;
      final g = blocConstruireAvis({'motif': 'x'}, admission: admission, existante: existante, toutes: liste(jeu['sorties']));
      expect(g['reference'], existante['reference']);
    });
  });
}
