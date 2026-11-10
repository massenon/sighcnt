// Le planning RH (lots L4 à L6) : rejoue les vecteurs engendrés par le moteur de la maquette (prototype_html/build/vecteurs-planning-rh.js) sur les MÊMES
// entrées : régime en vigueur à une date, refus nommés d'une dérogation, contrôle de repos, circuit de validation, propositions de planning.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();

void main() {
  final j = lireVecteurs('planning_rh');
  final regimesActifs = liste(j['regimesActifs']);

  RegimeRhResolu regimeDe(Map<String, Object?> agent, List<Map<String, Object?>> versions, String date) => regimeRhALaDate(
        regimesActifs: regimesActifs,
        versions: [for (final v in versions) if (v['employeId'] == agent['id']) v],
        fonction: agent['fonction'] as String?,
        date: date,
      );

  group('le régime en vigueur à une date (vecteurs de la maquette)', () {
    for (final c in liste(j['regime'])) {
      test(c['nom'] as String, () {
        final r = regimeRhALaDate(regimesActifs: regimesActifs, versions: liste(c['versions']), fonction: c['fonction'] as String?, date: c['date'] as String);
        memes(r.toJson(), c['attendu'], 'régime');
      });
    }
    test('les champs dérogeables sont ceux de la décision du 09/11/2026', () {
      expect(champsDerogeablesRh, ['vacations', 'repos', 'cycle', 'honoraire', 'honorairePeriodicite']);
    });
  });

  group('la dérogation : refus nommés et champs retenus', () {
    for (final c in liste(j['deroger'])) {
      test(c['nom'] as String, () {
        final r = validerDerogationRh(
          role: c['role'] as String,
          agentExiste: c['agentExiste'] as bool,
          dateEffet: c['dateEffet'] as String?,
          motif: c['motif'] as String?,
          retourCategorie: c['retour'] as bool,
          champs: m(c['champs']),
          versions: liste(c['versions']),
          aujourdhui: '2026-10-30',
        );
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r.refus, isNull, reason: 'attendu accepté');
          memes(r.champs, a['champs'], 'champs');
        } else {
          expect(r.refus, isNotNull, reason: 'attendu refusé : ${a['code']}');
          expect(r.refus!.code, a['code']);
          expect(r.refus!.motif, a['motif']);
          expect(r.refus!.geste, a['geste']);
        }
      });
    }
  });

  group('le contrôle de repos et de double affectation', () {
    for (final c in liste(j['controle'])) {
      test(c['nom'] as String, () {
        final agent = m(c['agent']);
        final versions = liste(c['versions']);
        final date = c['date'] as String;
        final regime = date.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.substring(0, 10)) ? regimeDe(agent, versions, date.substring(0, 10)) : null;
        final r = controlerVacationRh(
          agent: agent,
          planningActif: liste(c['planning']),
          regime: regime,
          date: date,
          type: c['type'] as String?,
          ignoreId: c['ignoreId'] as String?,
        );
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r, isNull, reason: 'attendu acceptable');
          expect(regime!.individuel, a['individuel']);
          expect(regime.repos, a['repos']);
        } else {
          expect(r, isNotNull, reason: 'attendu refusé : ${a['code']}');
          expect(r!.code, a['code']);
          expect(r.motif, a['motif']);
          expect(r.geste, a['geste']);
          expect(r.extra['reposHeures'], a['reposHeures']);
          expect(r.extra['individuel'], a['individuel']);
          expect(r.extra['autre'] ?? r.extra['existante'], a['autre']);
        }
      });
    }
  });

  group('l\'état de validation d\'une pièce et ce qui compte', () {
    for (final c in liste(j['etats'])) {
      test(c['nom'] as String, () {
        final rec = m(c['rec']);
        final a = m(c['attendu']);
        expect(etatValidationRh(c['collection'] as String, rec), a['etat']);
        expect(compteRh(c['collection'] as String, rec), a['compte']);
      });
    }
    test('le circuit par défaut est le surveillant seul ; une valeur inconnue y ramène', () {
      expect(circuitRhDefaut, 'surveillant');
      expect(circuitRhEnVigueur(null), 'surveillant');
      expect(circuitRhEnVigueur('inconnu'), 'surveillant');
      expect(circuitRhEnVigueur('daf'), 'daf');
      expect(circuitsRh['surveillant_puis_daf'], ['surveillant', 'daf']);
    });
  });

  group('le circuit de validation (décision du surveillant et patch écrit)', () {
    for (final c in liste(j['circuit'])) {
      test(c['nom'] as String, () {
        final collection = c['collection'] as String;
        final rec = Map<String, Object?>.from(m(c['rec']))..addAll({'id': c['id'] == 'PIECE' ? 'PIECE' : 'PIECE', 'statut': 'actif', 'employeId': agentDe(j), 'agentId': agentDe(j)});
        final existe = c['id'] == 'PIECE';
        final r = trancherRh(
          collection: collection,
          rec: existe ? rec : null,
          decision: c['decision'] as String,
          motif: c['motif'] as String?,
          role: c['role'] as String,
          circuit: c['circuit'] as String,
          acteur: c['acteur'] as String,
          aujourdhui: '2026-10-30',
          moiId: c['moiId'] as String?,
          moiNom: c['moiNom'] as String?,
        );
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r.refus, isNull, reason: 'attendu accepté');
          expect(r.etat, a['etat']);
          expect(r.etape, a['etape']);
          expect(r.complet, a['complet']);
          memes(r.patch, a['patch'], 'patch', sousEnsemble: true);
        } else {
          expect(r.refus, isNotNull, reason: 'attendu refusé : ${a['code']}');
          expect(r.refus!.code, a['code']);
          expect(r.refus!.motif, a['motif']);
          expect(r.refus!.geste, a['geste']);
        }
      });
    }
  });

  group('les propositions de planning : contrôle d\'application', () {
    final personnel = {for (final a in liste(j['agents'])) '${a['id']}': a};
    for (final c in liste(j['propositions'])) {
      test(c['nom'] as String, () {
        final versions = liste(c['versions']);
        final r = controlerPropositionRh(
          proposition: m(c['proposition']),
          planningActif: liste(c['planning']),
          personnel: personnel,
          regimeDe: (agent, date) => regimeDe(agent, versions, date),
        );
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r, isNull, reason: 'attendu applicable');
        } else {
          expect(r, isNotNull, reason: 'attendu refusé : ${a['code']}');
          expect(r!.code, a['code']);
          expect(r.motif, a['motif']);
          expect(r.geste, a['geste']);
        }
      });
    }
  });

  group('la décision sur une proposition', () {
    for (final c in liste(j['decisions'])) {
      test(c['nom'] as String, () {
        final prop = c['absente'] == true
            ? null
            : {'id': 'PROP', 'statut': 'actif', 'etat': 'proposee', 'employeId': agentDe(j), 'type': 'retrait', 'vacationId': 'P1', 'motif': 'Vecteur', ...m(c['proposition'])};
        final r = peutTrancherPropositionRh(proposition: prop, role: c['role'] as String, decision: c['decision'] as String, motif: c['motif'] as String?, moiId: c['moiId'] as String?);
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull, reason: 'attendu refusé : ${a['code']}');
          expect(r!.code, a['code']);
          expect(r.motif, a['motif']);
          expect(r.geste, a['geste']);
        }
      });
    }
  });

  group('les gestes de l\'écran : réglages, pose et retrait, régularisation, avis, retrait d\'une proposition', () {
    void refusAttendu(RefusRh? r, Map<String, Object?> a) {
      if (a['ok'] == true) {
        expect(r, isNull, reason: 'attendu accepté');
      } else {
        expect(r, isNotNull, reason: 'attendu refusé : ${a['code']}');
        expect(r!.code, a['code']);
        expect(r.motif, a['motif']);
        expect(r.geste, a['geste']);
      }
    }

    for (final c in liste(j['reglages'])) {
      test('réglage, ${c['nom']}', () {
        refusAttendu(controlerReglageRh(role: c['role'] as String, genre: c['genre'] as String, valeur: c['valeur']), m(c['attendu']));
      });
    }
    for (final c in liste(j['poses'])) {
      test('planning, ${c['nom']}', () {
        final retrait = c['genre'] == 'retrait';
        final planning = liste(c['planning']);
        final vac = planning.where((p) => p['id'] == c['id']).firstOrNull;
        final r = retrait ? controlerRetraitVacationRh(role: c['role'] as String, vacation: vac, id: c['id']) : peutPoserPlanningRh(c['role'] as String);
        refusAttendu(r, m(c['attendu']));
      });
    }
    for (final c in liste(j['regularisations'])) {
      test('régularisation, ${c['nom']}', () {
        final rec = m(c['rec']);
        final introuvable = c['id'] != 'PIECE';
        final r = regulariserPresenceRh(
            rec: introuvable ? null : rec, role: c['role'] as String, acteur: c['acteur'] as String, aujourdhui: '2026-10-30', o: m(c['o']), moiId: c['moiId'] as String?);
        final a = m(c['attendu']);
        refusAttendu(r.refus, a);
        if (a['ok'] == true) {
          final attendu = m(a['patch']);
          for (final k in attendu.keys) {
            memes(r.patch![k], attendu[k], 'patch.$k');
          }
          // une clé écrite par le domaine mais absente du relevé de la maquette n'a pas changé la fiche
          for (final k in r.patch!.keys) {
            if (!attendu.containsKey(k)) expect(r.patch![k], rec[k], reason: 'patch.$k aurait dû changer la fiche');
          }
        }
      });
    }
    for (final c in liste(j['avis'])) {
      test('avis du chef, ${c['nom']}', () {
        final introuvable = c['id'] != 'PIECE';
        final r = avisMissionRh(rec: introuvable ? null : m(c['rec']), role: c['role'] as String, acteur: c['acteur'] as String, aujourdhui: '2026-10-30', o: m(c['o']));
        final a = m(c['attendu']);
        refusAttendu(r.refus, a);
        if (a['ok'] == true) memes(r.patch!['avisChefService'], a['avis'], 'avis');
      });
    }
    for (final c in liste(j['retraits'])) {
      test('retrait de proposition, ${c['nom']}', () {
        final prop = c['absente'] == true
            ? null
            : {'id': 'PROP', 'statut': 'actif', 'etat': 'proposee', 'employeId': agentDe(j), 'type': 'retrait', 'vacationId': 'P1', 'motif': 'Vecteur', ...m(c['proposition'])};
        final r = annulerPropositionRh(proposition: prop, aujourdhui: '2026-10-30', moiId: c['moiId'] as String?);
        final a = m(c['attendu']);
        refusAttendu(r.refus, a);
        if (a['ok'] == true) {
          expect(r.patch!['etat'], a['etat']);
          expect(r.patch!['annuleeLe'], a['annuleeLe']);
        }
      });
    }
  });

  group('les gardes de collection (REGIME_INDIVIDUEL_FIGE, PRESENCE_VALIDEE)', () {
    // Textes et conditions repris de `S.garder('regimesIndividuels', …)` et `S.garder('presences', …)` de la maquette (parcours.js).
    test('une version de régime individuel : l\'insertion passe, modifier et archiver sont refusés en nommant la garde', () {
      expect(gardeRegimeIndividuelRh('inserer'), isNull);
      expect(gardeRegimeIndividuelRh('modifier'), startsWith('REGIME_INDIVIDUEL_FIGE'));
      expect(gardeRegimeIndividuelRh('archiver'), startsWith('REGIME_INDIVIDUEL_FIGE'));
    });
    test('un pointage validé : un champ qui change est refusé, une régularisation passe, un pointage d\'avant le circuit reste éditable', () {
      final valide = {'id': 'P', 'validationEtat': 'valide', 'etat': 'retard', 'date': '2026-10-29', 'employeId': 'A', 'heureArrivee': '09:10', 'motifCode': null, 'regularisations': <Object?>[]};
      expect(gardePresenceValideeRh('modifier', valide, {...valide, 'etat': 'present'}), startsWith('PRESENCE_VALIDEE'));
      expect(gardePresenceValideeRh('modifier', valide, {...valide, 'motifCode': 'maladie'}), startsWith('PRESENCE_VALIDEE'));
      expect(gardePresenceValideeRh('modifier', valide, {...valide, 'etat': 'present', 'regularisations': [{'le': '2026-10-30'}]}), isNull);
      expect(gardePresenceValideeRh('modifier', valide, {...valide, 'justificatif': 'CERT'}), isNull, reason: 'un champ hors liste ne fige pas');
      expect(gardePresenceValideeRh('modifier', {...valide, 'validationEtat': 'a_valider'}, {...valide, 'etat': 'present'}), isNull);
      expect(gardePresenceValideeRh('modifier', {'id': 'P', 'etat': 'retard'}, {'id': 'P', 'etat': 'present'}), isNull);
      expect(gardePresenceValideeRh('inserer', null, valide), isNull);
      expect(gardePresenceValideeRh('archiver', valide, valide), isNull);
    });
  });

  group('ce que chacun voit des propositions (RG-13)', () {
    for (final c in liste(j['visibles'])) {
      test('rôle ${c['role']}', () {
        final actives = liste(c['actives']);
        final avec = propositionsVisiblesRh(actives, c['role'] as String, c['moiId'] as String?).map((x) => x['id']).toList();
        final sans = propositionsVisiblesRh(actives, c['role'] as String, null).map((x) => x['id']).toList();
        // la maquette lit aussi les archivées ; le domaine reçoit déjà les actives
        expect(avec, [for (final x in (c['avecAgent'] as List)) if (x != 'X3') x]);
        expect(sans, [for (final x in (c['sansAgent'] as List)) if (x != 'X3') x]);
      });
    }
  });

  group('les libellés du circuit', () {
    test('trois circuits, trois libellés, deux étapes au plus', () {
      expect(libellesCircuitsRh.keys.toSet(), circuitsRh.keys.toSet());
      expect(circuitsRh.values.every((e) => e.isNotEmpty && e.length <= 2), isTrue);
      expect(typesPropositionRh.map((t) => t.id), ['ajout', 'modification', 'retrait', 'echange']);
      expect(motifsAbsenceRh.map((x) => x.id), ['maladie', 'mission', 'conge']);
    });
  });
}

/// L'identifiant de l'agent A des vecteurs (le premier médecin) : l'agent concerné par les pièces de sonde.
String agentDe(Map<String, Object?> j) => '${liste(j['agents']).first['id']}';
