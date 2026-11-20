// Rejoue les vecteurs du mobile soignant (prototype_html/build/vecteurs-mobile.js) : les pages du simulateur mobile PILOTÉES dans Chrome (messages de
// refus, bornes, listes, écrans ouverts par profil, bandeau de couverture), PR.peutPrescrire de la maquette complète, et l'agenda du médecin de
// l'accueil M2 (ag_agenda.json) pour l'agenda du jour. Les jours se lisent à l'heure locale : les vecteurs sont engendrés en UTC.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/mobile/mob_donnees.dart' show mobDonnees;
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('mobile');
  final horsUtc = DateTime.now().timeZoneOffset != Duration.zero ? 'les vecteurs sont engendrés en UTC' : null;
  final maintenant = DateTime(2026, 8, 16, 12, 0, 0);
  Map<String, String> saisie(Object? m) => {for (final e in (m as Map).entries) '${e.key}': '${e.value}'};

  group('saisie : les messages et les bornes sont ceux de l\'écran', () {
    test('constantes : ${liste(v['constantes']).length} cas pilotés', () {
      for (final c in liste(v['constantes'])) {
        final obtenu = mobErreursConstantes(saisie(c['saisie']));
        expect(obtenu, saisie(c['erreurs']), reason: 'saisie ${c['saisie']}');
      }
    });

    test('note de consultation : le motif est obligatoire, les libellés sont ceux de la fiche', () {
      final nc = (v['consultation'] as Map).cast<String, Object?>();
      for (final c in liste(nc['cas'])) {
        expect(mobValider(mobReglesNote, saisie(c['saisie'])), saisie(c['erreurs']), reason: 'saisie ${c['saisie']}');
      }
      final champs = (nc['champs'] as Map).cast<String, Object?>();
      expect(mobDiagnostics, ((champs['diagnostic'] as Map)['options'] as List).cast<String>());
      for (final t in mobTempsExamen) {
        expect(((champs[t.code] as Map)['libelle']), t.libelle, reason: 'temps ${t.code}');
      }
      expect(mobDiagnostics, contains(mobDiagnosticAutre));
    });

    test('prescription : médicament, posologie et durée (1 à 90) sont obligatoires', () {
      final p = (v['prescription'] as Map).cast<String, Object?>();
      for (final c in liste(p['cas'])) {
        expect(mobValider(mobReglesPrescription, saisie(c['saisie'])), saisie(c['erreurs']), reason: 'saisie ${c['saisie']}');
      }
    });

    test('demande d\'analyses : le catalogue et le refus « aucun examen » viennent de l\'écran', () {
      final a = (v['analyses'] as Map).cast<String, Object?>();
      expect(mobExamensAnalyses, (a['examens'] as List).cast<String>());
      expect(mobUrgencesAnalyses, (a['urgences'] as List).cast<String>());
      final aucun = (a['aucunExamen'] as Map).cast<String, Object?>();
      expect(aucun['visible'], isTrue);
      final fiche = {'code': 'CNT/1/26', 'nom': 'DOSSOU', 'prenom': 'Aline'};
      try {
        mobChampsDemandeAnalyses(patient: fiche, patientId: 'p1', noteId: 'n1', examens: const [], urgence: '', acteur: 'X', fonction: 'medecin', maintenant: maintenant);
        fail('une demande sans examen doit être refusée');
      } on RefusMobile catch (e) {
        expect(e.motif, aucun['message']);
        expect(e.code, 'SAISIE_INVALIDE');
      }
      expect((a['unExamen'] as Map)['visible'], isFalse);
    });
  });

  group('prescription selon droits', () {
    final d = (v['droitsPrescription'] as Map).cast<String, Object?>();
    test('la matrice fonction par nature rejoue PR.peutPrescrire (${liste(d['lignes']).length} lignes)', () {
      for (final l in liste(d['lignes'])) {
        expect(mobPeutPrescrire('${l['fonction']}', '${l['nature']}'), l['autorise'], reason: '${l['fonction']} / ${l['nature']}');
      }
      expect(mobPeutPrescrire('inconnue', 'medicament'), isFalse, reason: 'une fonction inconnue ne prescrit rien');
    });

    test('les écrans ouverts par fonction sont ceux du simulateur', () {
      final profils = (v['profils'] as Map).cast<String, Object?>();
      expect(mobEcransOuverts('medecin'), ((profils['medecin'] as Map)['ecrans'] as List).cast<String>());
      expect(mobEcransOuverts('sage_femme'), ((profils['sagefemme'] as Map)['ecrans'] as List).cast<String>());
      expect(mobEcransOuverts('infirmier'), ((profils['soignant'] as Map)['ecrans'] as List).cast<String>());
      expect(mobEcransOuverts('aide_soignant'), mobEcransOuverts('infirmier'));
      final dossier = (v['dossier'] as Map).cast<String, Object?>();
      expect((dossier['boutons'] as List), ['Saisir les constantes']);
      expect((dossier['boutonsMedecin'] as List), contains('Consultation à domicile'));
      expect(mobEcranOuvert('medecin', 'consultation'), isTrue);
      expect(mobEcranOuvert('infirmier', 'consultation'), isFalse);
      expect(mobEcranOuvert('infirmier', 'prescription'), isFalse);
    });

    test('la commande de prescription : le médecin les deux natures, les autres aucune (le plus restrictif des deux sources)', () {
      expect(mobNaturesPrescriptibles('medecin'), ['medicament', 'analyse']);
      expect(mobNaturesPrescriptibles('infirmier'), isEmpty);
      expect(mobNaturesPrescriptibles('aide_soignant'), isEmpty);
      // La sage-femme PEUT prescrire (D.CAPACITES) mais le simulateur ne lui ouvre pas l'écran : on suit le plus restrictif, et on le signale.
      expect(mobPeutPrescrire('sage_femme', 'medicament'), isTrue);
      expect(mobNaturesPrescriptibles('sage_femme'), isEmpty);
    });

    final notes = [
      {'patientId': 'p1', 'date': '2026-08-16T09:10', 'motif': 'Suivi HTA'},
      {'patientId': 'p2', 'date': '2026-08-15T09:10', 'motif': 'La veille'},
    ];
    void refus(String code, void Function() f, {String? motif}) {
      try {
        f();
        fail('le refus $code était attendu');
      } on RefusMobile catch (e) {
        expect(e.code, code);
        expect(e.motif, isNotEmpty);
        expect(e.geste, isNotEmpty);
        if (motif != null) expect(e.motif, contains(motif));
      }
    }

    test('refus nommés : lot expiré, fonction non habilitée, écran fermé, sans note', () {
      void controle(String fonction, String patient, {int? lot, String nature = 'medicament'}) => mobControlerPrescription(
          fonction: fonction, nature: nature, patientId: patient, notes: notes, maintenant: maintenant, lotExpire: lot);
      controle('medecin', 'p1');
      controle('medecin', 'p1', nature: 'analyse');
      refus('LOT_EXPIRE', () => controle('medecin', 'p1', lot: maintenant.millisecondsSinceEpoch - 1000), motif: '16/08/2026');
      refus('FONCTION_NON_HABILITEE', () => controle('infirmier', 'p1'), motif: 'Infirmier');
      refus('FONCTION_NON_HABILITEE', () => controle('aide_soignant', 'p1'));
      refus('ECRAN_FERME_AU_PROFIL', () => controle('sage_femme', 'p1'));
      refus('SANS_NOTE', () => controle('medecin', 'p2'), motif: 'fiche');
      refus('SANS_NOTE', () => controle('medecin', 'p3'));
      refus('NATURE_NON_PORTEE', () => controle('medecin', 'p1', nature: 'acte'));
      // Le lot encore valide ne bloque rien.
      controle('medecin', 'p1', lot: maintenant.millisecondsSinceEpoch + 60000);
    });
  });

  group('lot', () {
    test('expiré à la milliseconde près ; sans lot reçu, rien n\'est expiré', () {
      final t = maintenant.millisecondsSinceEpoch;
      expect(mobLotExpire(t, maintenant), isTrue);
      expect(mobLotExpire(t + 1, maintenant), isFalse);
      expect(mobLotExpire(0, maintenant), isFalse);
      expect(mobLotExpire(null, maintenant), isFalse);
    });
  });

  group('constantes et note : ce que le mobile écrit', () {
    final patient = {'code': 'CNT/12/26', 'nom': 'DOSSOU', 'prenom': 'Aline'};
    test('la fiche des constantes reprend les champs du relevé de l\'accueil', () {
      final c = mobChampsConstantes(patient: patient, patientId: 'p1', saisie: saisie({'temperature': '38,5', 'sys': '120', 'dia': '80', 'poids': '62'}), acteur: 'YENI M’PO Florent', maintenant: maintenant);
      expect(c['temperature'], 38.5);
      expect(c['tension'], '120/80');
      expect(c['tensionSys'], 120);
      expect(c['dateHeure'], '2026-08-16T12:00');
      expect(c['releveePar'], 'YENI M’PO Florent');
      expect(c['patientCode'], 'CNT/12/26');
      expect(c.containsKey('pouls'), isFalse, reason: 'un champ non saisi n\'est pas écrit');
      expect(mobFievre(saisie({'temperature': '38'})), isTrue);
      expect(mobFievre(saisie({'temperature': '37,9'})), isFalse);
      try {
        mobChampsConstantes(patient: patient, patientId: 'p1', saisie: saisie({'temperature': '57'}), acteur: 'X', maintenant: maintenant);
        fail('57 °C doit être refusé');
      } on RefusMobile catch (e) {
        expect(e.code, 'SAISIE_INVALIDE');
        expect(e.champs['temperature'], 'La température : valeur improbable (30 à 45).');
        expect(e.geste, 'Corriger le champ indiqué');
      }
    });

    test('la note reprend la dernière constante (copie datée), range l\'orientation de la fiche, exige un diagnostic', () {
      final constantes = [
        {'patientId': 'p1', 'patientCode': 'CNT/12/26', 'dateHeure': '2026-08-16T08:00', 'temperature': 37.0, 'pouls': 80},
        {'patientId': 'p1', 'patientCode': 'CNT/12/26', 'dateHeure': '2026-08-16T11:00', 'temperature': 38.5, 'pouls': 96, 'tension': '12/8'},
        {'patientId': 'p2', 'patientCode': 'CNT/174/26', 'dateHeure': '2026-08-16T11:30', 'temperature': 36.0},
      ];
      final n = mobChampsNote(
          patient: patient,
          patientId: 'p1',
          saisie: {'motif': 'Suivi HTA', 'diagnostic': 'Hypertension artérielle', 'palpation': 'Abdomen souple', 'auscultation': '  ', 'orientation': 'domicile'},
          acteur: 'YENI M’PO Florent',
          fonction: 'medecin',
          maintenant: maintenant,
          constantes: constantes);
      expect((n['constantesAccueil'] as Map)['temperature'], 38.5, reason: 'la plus récente, du bon patient');
      expect(n['examenClinique'], {'palpation': 'Abdomen souple'});
      expect(n['orientationLabel'], 'Domicile — traitement ambulatoire');
      expect(n['redigePar'], 'YENI M’PO Florent');
      expect(n['type'], 'Domicile');
      final autre = mobChampsNote(
          patient: patient, patientId: 'p1', saisie: {'motif': 'm', 'diagnostic': mobDiagnosticAutre, 'precision': 'Dermatose'}, acteur: 'X', fonction: 'medecin', maintenant: maintenant);
      expect(autre['diagnostic'], 'Dermatose');
      expect(autre.containsKey('constantesAccueil'), isFalse);
      for (final (saisieNote, champ, message) in [
        ({'motif': '', 'diagnostic': 'Gastro-entérite'}, 'motif', 'Le motif est obligatoire.'),
        ({'motif': 'm', 'diagnostic': mobDiagnosticAutre}, 'diagnostic', mobMessageDiagnosticVide),
        ({'motif': 'm', 'diagnostic': 'Gastro-entérite', 'orientation': 'inconnue'}, 'orientation', 'L’orientation « inconnue » n’est pas dans la liste de la fiche.'),
      ]) {
        try {
          mobChampsNote(patient: patient, patientId: 'p1', saisie: saisieNote, acteur: 'X', fonction: 'medecin', maintenant: maintenant);
          fail('refus attendu sur $champ');
        } on RefusMobile catch (e) {
          expect(e.champs[champ], message);
        }
      }
    });

    final produits = [
      {'id': 'PRD0001', 'designation': 'PARACETAMOL 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'prixAchat': 500, 'stockDetail': 10, 'stock': 40},
      {'id': 'PRD0002', 'designation': 'AMOXICILLINE 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'prixAchat': 1200, 'stockDetail': 2},
      {'id': 'PRD0003', 'designation': 'GANTS', 'unite': 'Boîte', 'categorie': 'conso_medical', 'prixAchat': 300, 'stock': 5},
      {'id': 'PRD0004', 'designation': 'ARCHIVE', 'categorie': 'medicament', 'statut': 'archive', 'stock': 5},
      {'id': 'PRD0005', 'designation': 'RAYON', 'categorie': 'reactif', 'stock': 5},
    ];
    Map<String, Object?> ordonnance(Map<String, String> saisie) => mobChampsOrdonnance(
        patient: patient, patientId: 'p1', noteId: 'n1', saisie: saisie, acteur: 'YENI M’PO Florent', fonction: 'medecin', maintenant: maintenant, produits: produits);

    test('le catalogue du lot : médicaments et consommables médicaux, par ordre alphabétique, sans archivés ni réactifs ; le stock du jour est le détail', () {
      final l = mobProduitsPrescriptibles(produits);
      expect([for (final x in l) x.designation], ['AMOXICILLINE 500 MG', 'GANTS', 'PARACETAMOL 500 MG']);
      expect(l.last.stock, 10, reason: 'le stock de la pharmacie (détail), pas celui du gros');
      expect(l.last.prixAchat, 500);
    });

    test('l\'ordonnance est une pièce ÉMISE rattachée à la note : le médicament est CHOISI dans le catalogue, avec sa quantité, jamais un prix', () {
      final o = ordonnance({'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp × 3/j', 'duree': '5'});
      expect(o['emise'], isTrue);
      expect(o['noteId'], 'n1');
      expect((o['lignes'] as List).single, {'produitId': 'PRD0001', 'medicament': 'PARACETAMOL 500 MG', 'quantite': 2, 'posologie': '1 cp × 3/j', 'dureeJours': 5});
      expect(o.toString().contains('prix'), isFalse, reason: 'le prix ne part pas du téléphone (RG-02 : le poste lit le catalogue)');
    });

    test('refus nommés : durée hors bornes, quantité absente ou non entière, médicament hors catalogue, stock insuffisant (RG-03)', () {
      RefusMobile refus(Map<String, String> s) {
        try {
          ordonnance(s);
        } on RefusMobile catch (e) {
          return e;
        }
        fail('refus attendu pour $s');
      }

      expect(refus({'med': 'PRD0001', 'quantite': '1', 'poso': 'y', 'duree': '91'}).champs['duree'], 'La durée : valeur improbable (1 à 90).');
      expect(refus({'med': 'PRD0001', 'quantite': '', 'poso': 'y', 'duree': '5'}).champs['quantite'], 'La quantité est obligatoire.');
      expect(refus({'med': 'PRD0001', 'quantite': '1,5', 'poso': 'y', 'duree': '5'}).champs['quantite'], 'La quantité doit être un entier d’au moins 1.');
      expect(refus({'med': 'PRD0001', 'quantite': '0', 'poso': 'y', 'duree': '5'}).champs['quantite'], 'La quantité doit être un entier d’au moins 1.');
      expect(refus({'med': '', 'quantite': '1', 'poso': 'y', 'duree': '5'}).champs['med'], 'Le médicament est obligatoire.');
      final inconnu = refus({'med': 'PRD9999', 'quantite': '1', 'poso': 'y', 'duree': '5'});
      expect((inconnu.code, inconnu.geste), ('PRODUIT_INCONNU', 'Choisir le médicament dans la liste du lot'));
      final archive = refus({'med': 'PRD0004', 'quantite': '1', 'poso': 'y', 'duree': '5'});
      expect(archive.code, 'PRODUIT_INCONNU', reason: 'un produit archivé n\'est plus prescriptible');
      final stock = refus({'med': 'PRD0002', 'quantite': '3', 'poso': 'y', 'duree': '5'});
      expect((stock.code, stock.motif, stock.geste), ('STOCK_INSUFFISANT', 'Stock insuffisant pour « AMOXICILLINE 500 MG » : disponible : 2 ; demandé : 3 (RG-03).', 'Corriger la quantité ou demander un transfert du gros.'));
      expect(ordonnance({'med': 'PRD0002', 'quantite': '2', 'poso': 'y', 'duree': '5'})['emise'], isTrue, reason: 'le stock exactement épuisé est accepté');
    });
  });

  group('dossier en lecture', () {
    final cartes = ((v['dossier'] as Map)['cartes'] as Map).cast<String, Object?>();
    String couv(String p) => ((cartes[p] as Map)['Couverture']) as String;
    test('trois états de couverture, comme le bandeau du simulateur (RG-09 à la date)', () {
      final valide = {'code': 'CNT/12/26', 'assureur': 'NSIA', 'carteExpiration': '2026-12-31'};
      final expiree = {'code': 'CNT/174/26', 'assureur': 'NSIA', 'carteExpiration': '2026-08-15'};
      final lejour = {'code': 'CNT/9/26', 'assureur': 'NSIA', 'carteExpiration': '2026-08-16'};
      final aucune = {'code': 'CNT/1109/26'};
      expect(mobCouvertureDe(valide, maintenant), MobCouverture.carteValide);
      expect(mobCouvertureDe(expiree, maintenant), MobCouverture.carteNonValide);
      expect(mobCouvertureDe(lejour, maintenant), MobCouverture.carteValide, reason: 'la carte qui expire le jour même reste valide');
      expect(mobCouvertureDe(aucune, maintenant), MobCouverture.nonAssure);
      expect(mobLibellesCouverture[MobCouverture.carteValide], couv('p1'));
      expect(mobLibellesCouverture[MobCouverture.nonAssure], couv('p3'));
      expect('${mobLibellesCouverture[MobCouverture.carteNonValide]}$mobExplicationCarteNonValide', couv('p2'));
      expect(((mobDonnees['textes'] as Map)['carteNonValide']), couv('p2'));
    });

    test('identité, allergies, dernières constantes hors bornes, notes et prescriptions du patient seulement', () {
      final p = {'code': 'CNT/12/26', 'nom': 'DOSSOU', 'prenom': 'Aline', 'quartier': 'Kouba', 'telephone': '97 11 22 33', 'ageDeclare': 67, 'allergies': ['Pénicilline'], 'assureur': 'NSIA', 'carteExpiration': '2026-12-31'};
      final d = mobDossier(
          patient: p,
          patientId: 'p1',
          maintenant: maintenant,
          constantes: [
            {'patientId': 'p1', 'dateHeure': '2026-08-16T11:00', 'temperature': 39.0, 'pouls': 96},
            {'patientId': 'p2', 'dateHeure': '2026-08-16T11:30', 'temperature': 36.0},
          ],
          notes: [
            {'patientId': 'p1', 'date': '2026-08-14T10:00', 'motif': 'ancienne'},
            {'patientId': 'p1', 'date': '2026-08-16T10:00', 'motif': 'récente'},
            {'patientId': 'p2', 'date': '2026-08-16T10:00', 'motif': 'autre patient'},
          ],
          prescriptions: [
            {'patientId': 'p2', 'date': '2026-08-16T10:00'}
          ]);
      expect(d.nom, 'DOSSOU Aline');
      expect(d.age, 67);
      expect(d.allergies, ['Pénicilline']);
      expect(d.horsBornes, ['température']);
      expect(d.notes.map((n) => n['motif']), ['récente', 'ancienne']);
      expect(d.prescriptions, isEmpty);
      expect(d.couverture, MobCouverture.carteValide);
      final nu = mobDossier(patient: {'nom': 'AKPO', 'prenom': 'Marc'}, patientId: 'n0', maintenant: maintenant);
      expect(nu.code, 'en attente de numéro');
      expect(nu.allergies, isEmpty);
      expect(nu.dernierReleve, isNull);
      expect(nu.age, isNull);
    });
  });

  group('agenda du jour', () {
    final a = lireVecteurs('ag_agenda');
    final fixtures = [for (final f in liste(a['agendaFixtures'])) if (f['statut'] != 'archive') {...f}];
    final praticiens = liste((a['agendaMedecin'] as Map)['praticiens']);

    test('le compte du jour égale l\'indicateur « Aujourd\'hui » de l\'agenda du médecin, praticien par praticien', () {
      for (final p in praticiens) {
        final nom = '${p['praticien']}';
        final kpis = {for (final k in liste((p['lu'] as Map)['kpis'])) k['label']: k['valeur']};
        final r = mobAgendaDuJour([for (final f in fixtures) if (f['medecin'] == nom) f], maintenant);
        expect('${r.duJour.length}', kpis['Aujourd’hui'], reason: nom);
      }
    }, skip: horsUtc);

    test('les heures et l\'ordre sont ceux de l\'écran du médecin (du plus tôt au plus tard)', () {
      final p = praticiens.firstWhere((x) => x['praticien'] == 'BASSONGUI Chabi Séko');
      final table = (((p['lu'] as Map)['tables'] as List).first as Map)['lignes'] as List;
      final duJourEcran = [
        for (final l in table)
          if ('${(l as Map)['cellules'][0]}'.startsWith('16/08/2026')) '${l['cellules'][0]}'.split(' à ').last
      ].reversed.toList(); // l'écran trie du plus récent au plus ancien
      final r = mobAgendaDuJour([for (final f in fixtures) if (f['medecin'] == 'BASSONGUI Chabi Séko') f], maintenant);
      expect(r.duJour.map(mobHeureRendezVous).toList(), duJourEcran);
    }, skip: horsUtc);

    test('un rendez-vous planifié d\'un jour passé est SIGNALÉ, non tranché ; les autres états ne le sont pas', () {
      final r = mobAgendaDuJour([
        {'date': '2026-08-15T09:00', 'statut': 'planifiee'},
        {'date': '2026-08-15T10:00', 'statut': 'terminee'},
        {'date': '2026-08-15T11:00', 'statut': 'non_honore'},
        {'date': '2026-08-17T09:00', 'statut': 'planifiee'},
        {'date': 'illisible', 'statut': 'planifiee'},
        {'date': '2026-08-16T08:00', 'statut': 'planifiee'},
      ], maintenant);
      expect(r.duJour.map(mobHeureRendezVous), ['08h00']);
      expect(r.enSouffrance.length, 1);
      expect(r.enSouffrance.single['date'], '2026-08-15T09:00');
    });
  });
}
