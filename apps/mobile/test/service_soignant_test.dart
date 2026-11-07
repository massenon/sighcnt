// Le service du profil soignant, sur un lot en mémoire : les gestes d'écriture sont des opérations `creer` (jamais de suppression, RG-14), nommées
// à l'agent (RG-12), refusées en le disant (code, motif, geste) ; les règles viennent de packages/domaine.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';

ServiceSoignant service(SourceMemoire s, {String fonction = 'medecin', String agent = 'Dr YENI M’PO Florent'}) =>
    ServiceSoignant(s, session: SessionSoignant(agent: agent, fonction: fonction), maintenant: () => horloge);

Future<RefusMobile> refuse(Future<Object?> Function() f) async {
  try {
    await f();
  } on RefusMobile catch (r) {
    expect(r.motif, isNotEmpty);
    expect(r.geste, isNotEmpty);
    return r;
  }
  fail('un refus nommé était attendu');
}

void main() {
  group('lecture', () {
    test('agenda du jour : les rendez-vous d\'aujourd\'hui par heure, le planifié passé signalé à part, l\'archivé et le futur absents', () async {
      final a = await service(lotDeDemonstration()).agenda();
      expect(a.duJour.map((l) => '${l.heure} ${l.patient}'), ['09h30 DOSSOU Aline', '10h45 KPOGNON Rose']);
      expect(a.duJour.first.motif, 'Suivi HTA');
      expect(a.duJour.first.statut, 'Planifiée');
      expect(a.duJour.first.patientId, 'p1');
      expect(a.enSouffrance.map((l) => l.patient), ['TAMOU Félix']);
      expect(a.enSouffrance.single.enSouffrance, isTrue);
    });

    test('dossier en lecture : couverture à la date (RG-09), allergies, dernière constante hors bornes, motif du rendez-vous du jour', () async {
      final s = service(lotDeDemonstration());
      final d = await s.dossier('p1');
      expect(d.resume.couverture, MobCouverture.carteValide);
      expect(d.resume.allergies, ['Pénicilline']);
      expect(d.resume.horsBornes, ['température']);
      expect(d.resume.age, 67);
      expect(d.rendezVous?.motif, 'Suivi HTA');
      expect((await s.dossier('p2')).resume.couverture, MobCouverture.carteNonValide);
      expect((await s.dossier('p3')).resume.couverture, MobCouverture.nonAssure);
      final inconnu = await refuse(() => s.dossier('absent'));
      expect(inconnu.code, 'PATIENT_HORS_LOT');
    });
  });

  group('constantes', () {
    test('une opération creer, nommée à l\'agent, visible aussitôt', () async {
      final src = lotDeDemonstration();
      final id = await service(src).enregistrerConstantes('p2', {'temperature': '37,2', 'sys': '110', 'dia': '70'});
      expect(id, isNotEmpty);
      final c = src.de('constantes').single;
      expect(c['releveePar'], 'Dr YENI M’PO Florent');
      expect(c['patientCode'], 'CNT/174/26');
      expect(c['tension'], '110/70');
      expect((await src.liste('constantes')).length, 2);
    });

    test('valeur improbable ou absente : refus nommé par champ, rien d\'écrit', () async {
      final src = lotDeDemonstration();
      final r = await refuse(() => service(src).enregistrerConstantes('p2', {'temperature': '57'}));
      expect(r.code, 'SAISIE_INVALIDE');
      expect(r.champs['temperature'], 'La température : valeur improbable (30 à 45).');
      final v = await refuse(() => service(src).enregistrerConstantes('p2', {}));
      expect(v.champs['temperature'], 'La température est obligatoire.');
      expect(src.ecritures, isEmpty);
    });

    test('aucune action anonyme (RG-12) : sans agent nommé, rien ne s\'écrit', () async {
      final src = lotDeDemonstration();
      final r = await refuse(() => service(src, agent: '  ').enregistrerConstantes('p1', {'temperature': '37'}));
      expect(r.code, 'ACTEUR_INCONNU');
      expect(src.ecritures, isEmpty);
    });

    test('un patient hors lot ne se touche pas', () async {
      final src = lotDeDemonstration();
      expect((await refuse(() => service(src).enregistrerConstantes('hors', {'temperature': '37'}))).code, 'PATIENT_HORS_LOT');
      expect(src.ecritures, isEmpty);
    });

    test('lot expiré : écriture refusée en le disant, avec la date et le geste', () async {
      final src = lotDeDemonstration()..fin = horloge.millisecondsSinceEpoch - 60000;
      final r = await refuse(() => service(src).enregistrerConstantes('p1', {'temperature': '37'}));
      expect(r.code, 'LOT_EXPIRE');
      expect(r.motif, contains('31/10/2026'));
      expect(r.geste, 'Se connecter pour recevoir le lot du jour');
      expect(src.ecritures, isEmpty);
      // Les trois écritures sont gardées par le même contrôle.
      expect((await refuse(() => service(src).enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'}))).code, 'LOT_EXPIRE');
      expect((await refuse(() => service(src).prescrireMedicament('p1', {'med': 'x', 'poso': 'y', 'duree': '3'}))).code, 'LOT_EXPIRE');
    });
  });

  group('note de consultation', () {
    test('la note reprend la dernière constante du patient et part en creer sur « notes »', () async {
      final src = lotDeDemonstration();
      await service(src).enregistrerNote('p1', {'motif': 'Suivi HTA', 'diagnostic': 'Hypertension artérielle', 'orientation': 'domicile', 'palpation': 'RAS'});
      final n = src.de('notes').single;
      expect(n['redigePar'], 'Dr YENI M’PO Florent');
      expect(n['fonction'], 'medecin');
      expect((n['constantesAccueil'] as Map)['temperature'], 38.6);
      expect(n['orientationLabel'], 'Domicile — traitement ambulatoire');
      expect(n['examenClinique'], {'palpation': 'RAS'});
    });

    test('motif vide : refus nommé ; la fonction sans écran « consultation » est refusée au moteur, pas seulement masquée', () async {
      final src = lotDeDemonstration();
      expect((await refuse(() => service(src).enregistrerNote('p1', {'motif': '', 'diagnostic': 'Gastro-entérite'}))).champs['motif'], 'Le motif est obligatoire.');
      final inf = await refuse(() => service(src, fonction: 'infirmier').enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'}));
      expect(inf.code, 'ECRAN_FERME_AU_PROFIL');
      expect(src.ecritures, isEmpty);
    });
  });

  group('prescription selon droits', () {
    test('les commandes offertes suivent la fonction', () {
      final src = lotDeDemonstration();
      expect(service(src).peutSaisirNote, isTrue);
      expect(service(src).naturesPrescriptibles, ['medicament', 'analyse']);
      for (final f in ['infirmier', 'aide_soignant', 'sage_femme']) {
        expect(service(src, fonction: f).naturesPrescriptibles, isEmpty, reason: f);
      }
      expect(service(src, fonction: 'infirmier').peutSaisirNote, isFalse);
    });

    test('sans note du jour : refus SANS_NOTE ; après la note, l\'ordonnance part, rattachée à la note, pièce émise', () async {
      final src = lotDeDemonstration();
      final s = service(src);
      final sans = await refuse(() => s.prescrireMedicament('p1', {'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp x 3/j', 'duree': '5'}));
      expect(sans.code, 'SANS_NOTE');
      expect(src.de('prescriptions'), isEmpty);
      final noteId = await s.enregistrerNote('p1', {'motif': 'Suivi HTA', 'diagnostic': 'Hypertension artérielle'});
      await s.prescrireMedicament('p1', {'med': 'PRD0001', 'quantite': '2', 'poso': '1 cp x 3/j', 'duree': '5'});
      final o = src.de('prescriptions').single;
      expect(o['noteId'], noteId);
      expect(o['emise'], isTrue);
      expect(o['nature'], 'medicament');
      expect(o['prescripteur'], 'Dr YENI M’PO Florent');
      // La note d'un autre patient ne couvre pas celui-ci.
      expect((await refuse(() => s.prescrireMedicament('p2', {'med': 'x', 'poso': 'y', 'duree': '1'}))).code, 'SANS_NOTE');
    });

    test('analyses : au moins un examen, catalogue du mobile, urgence connue ; rien ne se prélève avant paiement (le texte est celui de l\'écran)', () async {
      final src = lotDeDemonstration();
      final s = service(src);
      await s.enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'});
      expect((await refuse(() => s.prescrireAnalyses('p1', [], ''))).champs['examens'], 'Cochez au moins un examen.');
      expect((await refuse(() => s.prescrireAnalyses('p1', ['Scanner cérébral'], ''))).code, 'EXAMEN_INCONNU');
      await s.prescrireAnalyses('p1', ['NFS', 'CRP'], 'Urgent — bilan entier');
      final a = src.de('prescriptions').single;
      expect(a['examens'], ['NFS', 'CRP']);
      expect(a['urgence'], 'Urgent — bilan entier');
      expect(a['nature'], 'analyse');
    });

    test('une fonction non habilitée est refusée AU MOTEUR même si l\'écran est contourné : code, motif, geste', () async {
      final src = lotDeDemonstration();
      final inf = service(src, fonction: 'infirmier', agent: 'Infirmière');
      final r = await refuse(() => inf.prescrireMedicament('p1', {'med': 'x', 'poso': 'y', 'duree': '1'}));
      expect(r.code, 'FONCTION_NON_HABILITEE');
      expect(r.motif, contains('Infirmier'));
      expect(r.geste, 'Demander la prescription à un médecin');
      final sf = service(src, fonction: 'sage_femme', agent: 'Sage-femme');
      expect((await refuse(() => sf.prescrireMedicament('p1', {'med': 'x', 'poso': 'y', 'duree': '1'}))).code, 'ECRAN_FERME_AU_PROFIL');
      expect(src.ecritures, isEmpty);
    });

    test('aucune suppression : le service n\'écrit que des creer', () async {
      final src = lotDeDemonstration();
      final s = service(src);
      await s.enregistrerConstantes('p1', {'temperature': '37'});
      await s.enregistrerNote('p1', {'motif': 'm', 'diagnostic': 'Gastro-entérite'});
      await s.prescrireMedicament('p1', {'med': 'PRD0001', 'quantite': '1', 'poso': 'y', 'duree': '1'});
      expect(src.ecritures.map((e) => e.$1), ['constantes', 'notes', 'prescriptions']);
    });
  });
}
