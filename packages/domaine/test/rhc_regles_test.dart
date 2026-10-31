// Rejoue les vecteurs de M10 (C) engendrés par la maquette (prototype_html/build/vecteurs-rh-c.js) : badges du personnel, événements et participations,
// assurance du personnel, planning rotatif sécurité & entretien — écrans PILOTÉS dans Chrome sur le jeu du poste, à l'horloge du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef F = Map<String, Object?>;

const jeu = '../../apps/poste/assets/donnees/jeu';
List<F> dossier(String nom) => liste(jsonDecode(File('$jeu/$nom.json').readAsStringSync()));
List<F> actives(List<F> l) => [for (final f in l) if (f['statut'] != 'archive') f];
F f(Object? x) => (x as Map).cast<String, Object?>();
List<F> lf(Object? x) => [for (final e in (x as List)) f(e)];
String sans(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]'), '');

void main() {
  final v = lireVecteurs('rhc');
  final auj = DateTime(2026, 10, 30, 10);
  final badges = dossier('badges');
  final personnel = actives(dossier('personnel'));

  group('fabrique des badges (PR.numeroBadge, badgeQR, lireBadgeQR)', () {
    final fab = f(v['fabrique']);
    test('le numéro suit la série ANNUELLE : le rang est le plus grand de l’année, plus un', () {
      for (final n in lf2(fab['numeros'])) {
        expect(rhcNumeroBadge(badges, n[0], auj), n[1], reason: '${n[0]}');
      }
    });
    test('un badge ARCHIVÉ garde son numéro : le rang ne se réutilise pas', () {
      final avecArchive = [
        ...badges,
        {'numero': 'BDG-00099-2026', 'statut': 'archive'}
      ];
      expect(rhcNumeroBadge(avecArchive, '2026-10-30', auj), 'BDG-00100-2026');
    });
    test('sans date, c’est l’année de l’horloge', () {
      expect(rhcNumeroBadge(const [], null, auj), 'BDG-00001-2026');
      expect(rhcNumeroBadge(const [], 'pas une date', auj), 'BDG-00001-2026');
    });
    test('le QR ne porte QUE le matricule et le numéro de série', () {
      for (final q in lf2(fab['qr'])) {
        final b = badges.firstWhere((x) => x['numero'] == q[1]);
        expect(rhcBadgeQR(b), q[2]);
        for (final secret in [b['agent'], b['poste'], b['service'], 'http']) {
          expect(rhcBadgeQR(b).contains('$secret'), isFalse, reason: 'le QR ne doit pas porter « $secret »');
        }
      }
      expect(rhcBadgeQR({}), fab['qrSansChamps']);
    });
    test('le QR s’arrête à 106 octets (version 6) : un badge ordinaire tient largement, un code trop long est REFUSÉ', () {
      for (final b in badges) {
        expect(rhcQrAcceptable(rhcBadgeQR(b)), isTrue, reason: '${b['numero']}');
      }
      expect(rhcQrAcceptable(rhcBadgeQR({'matricule': 'M' * 60, 'numero': 'N' * 60})), isFalse);
      expect(rhcQrAcceptable('é' * 53), isTrue);
      expect(rhcQrAcceptable('é' * 54), isFalse, reason: 'les octets, pas les caractères');
    });
    test('la lecture accepte la charge utile du QR ET la saisie à la main', () {
      for (final l in lf2(fab['lecture'])) {
        final r = rhcLireBadgeQR(l[0]);
        final a = l[1];
        if (a == null) {
          expect(r, isNull, reason: '« ${l[0]} »');
        } else {
          final m = f(a);
          expect([r!.matricule, r.numero, r.source], [m['matricule'], m['numero'], m['source']], reason: '« ${l[0]} »');
        }
      }
    });
  });

  group('vérification : quatre réponses, le retrait prime', () {
    // La mutation que le vecteur applique au badge avant de le vérifier.
    F mute(F b, String nom) {
      final c = {...b};
      switch (nom) {
        case 'expiré':
          c['expireLe'] = '2026-10-29';
        case 'expire aujourd’hui : encore valide':
          c['expireLe'] = '2026-10-30';
        case 'retiré — perte':
          c..['etat'] = 'perdu'..['motifRetrait'] = 'Perte'..['retireLe'] = '2026-10-01';
        case 'retiré — sans motif ni date':
          c..['etat'] = 'retire'..remove('motifRetrait')..remove('retireLe');
        case 'retiré ET expiré : le retrait prime':
          c..['etat'] = 'retire'..['expireLe'] = '2020-01-01';
      }
      return c;
    }

    for (final c in lf(f(v['verification'])['cas'])) {
      final rep = c['reponse'];
      if (rep == null) continue;
      test('${c['nom']}', () {
        final lu = rhcLireBadgeQR(c['saisie'])!;
        var b = rhcBadgeDuNumero(badges, lu.numero);
        if (b != null) b = mute(b, '${c['nom']}');
        final verdict = rhcVerdictBadge(b, auj);
        final texte = sans(f(rep)['texte']);
        expect(texte.startsWith(sans('${verdict.label} ${verdict.message}')), isTrue, reason: '${verdict.label} ${verdict.message}');
        expect(verdict.ton, {'success': 'success', 'warning': 'warning', 'danger': 'danger'}[f(rep)['classe']]);
      });
    }

    test('inconnu n’est pas retiré : deux libellés, deux messages', () {
      final i = rhcVerdictBadge(null, auj), r = rhcVerdictBadge({'etat': 'retire', 'motifRetrait': 'Vol'}, auj);
      expect([i.code, r.code], ['inconnu', 'retire']);
      expect(i.message == r.message, isFalse);
    });
    test('un état inconnu se lit « actif » : le badge n’est pas retiré par défaut', () {
      expect(rhcEtatBadge('autre').actif, isTrue);
      expect(rhcVerdictBadge({'etat': 'autre', 'expireLe': '2030-01-01'}, auj).code, 'valide');
    });
  });

  group('validité', () {
    test('24 mois, déduits de l’émission ; le 29 février déborde sur le 1ᵉʳ mars (setMonth)', () {
      expect(rhcExpirationDepuis('2026-10-30'), '2028-10-30');
      expect(rhcExpirationDepuis('2024-02-29'), '2026-03-01');
      expect(rhcExpirationDepuis('2025-12-31'), '2027-12-31');
    });
    test('un badge expire strictement après sa date', () {
      expect(rhcExpire({'expireLe': '2026-10-30'}, auj), isFalse);
      expect(rhcExpire({'expireLe': '2026-10-29'}, auj), isTrue);
      expect(rhcExpire({}, auj), isFalse);
    });
    test('« expirent sous 60 jours » compte aussi les expirés', () {
      final l = [
        {'expireLe': '2026-12-29'},
        {'expireLe': '2026-12-31'},
        {'expireLe': '2026-09-01'},
        <String, Object?>{}
      ];
      expect(rhcBadgesExpirant(l, auj).length, 2);
    });
    test('les quatre décisions de la Direction restent MARQUÉES', () {
      expect(rhcDecisionsBadge.length, 4);
      expect(rhcDecisionsBadge.first.valeurAffichee, '24 mois');
      expect(rhcDecisionsBadge.map((d) => d.libelle).toList(), contains('Le badge sert-il de support de POINTAGE ?'));
    });
    test('perte et vol → perdu ; tout autre motif → retiré', () {
      expect({for (final m in rhcMotifsRetrait) m: rhcEtatDeRetrait(m)}, {
        'Perte': 'perdu', 'Vol': 'perdu', 'Détérioration': 'retire', 'Départ de l’agent': 'retire', 'Réédition — remplacement': 'retire', 'Erreur de saisie': 'retire'
      });
    });
  });

  group('un seul badge valide par agent', () {
    test('l’agent qui en porte un est refusé EN NOMMANT le premier', () {
      final b = rhcBadgeEnCours(actives(badges), 'EMP02');
      expect(b!['numero'], 'BDG-00002-2026');
      expect(rhcBadgeEnCours(actives(badges), 'EMP30'), isNull);
    });
    test('un badge retiré ne bloque plus l’émission : le remplacement est permis', () {
      final l = [for (final x in badges) x['personnelId'] == 'EMP13' ? {...x, 'etat': 'perdu'} : x];
      expect(rhcBadgeEnCours(l, 'EMP13'), isNull);
    });
    test('« agents sans badge » : l’effectif rapproché du registre', () {
      expect(rhcAgentsSansBadge(personnel, actives(badges)).length, 30);
    });
  });

  group('gabarit', () {
    final modeles = actives(dossier('modelesBadge'));
    test('le modèle par défaut, puis le premier', () {
      expect(rhcModeleParDefaut(modeles)!['id'], 'MDB001');
      expect(rhcModeleParDefaut([{'id': 'A'}, {'id': 'B'}])!['id'], 'A');
      expect(rhcModeleParDefaut(const []), isNull);
    });
    test('zones en objet, mentions du verso une par ligne, lignes vides écartées', () {
      final m = rhcModeleNormalise(modeles.first, modeles);
      expect(m.zones, {for (final z in rhcZonesBadge) z: true});
      expect(m.mentionsVerso.length, 5);
      final p = rhcModeleNormalise({'zones': ['nom', 'fonction'], 'orientation': 'portrait', 'mentionsVerso': 'Un.\n\n  Deux.  '}, modeles);
      expect(p.zones, {'photo': false, 'nom': true, 'fonction': true, 'service': false, 'qr': false});
      expect(p.mentionsVerso, ['Un.', 'Deux.']);
      expect(p.portrait, isTrue);
    });
  });

  group('événements et participations', () {
    final ev = f(v['evenements']);
    test('une participation par agent, HORS bénéficiaire, au montant de l’événement', () {
      final c = f(f(ev['creation'])['creee']);
      final e = {...f(c['fiche']), 'id': 'EVT-X'};
      final l = rhcParticipationsAEngendrer(e, personnel);
      expect(l.length, c['nbParticipations']);
      expect([for (final p in l.reversed) p['employeId']], c['agents'], reason: 'en tête de collection : le dernier engendré est le premier');
      expect(l.any((p) => p['employeId'] == 'EMP05'), isFalse);
      final p0 = f(c['premiere']);
      for (final k in ['evenementLibelle', 'nature', 'dateEvenement', 'employeId', 'agent', 'matricule', 'fonction', 'service', 'montant', 'mode', 'periodeRetenue', 'statutPaiement']) {
        expect(l.last[k], p0[k], reason: k);
      }
    });
    test('une sélection restreint la liste, le bénéficiaire en est exclu même choisi', () {
      final s = f(ev['selection']);
      final l = rhcParticipationsAEngendrer(f(s['fiche']), personnel);
      expect([for (final p in l) [p['employeId'], p['montant']]], [for (final x in (s['participants'] as List).reversed) x]);
    });
    test('une sélection VIDE retombe sur tout le personnel', () {
      final l = rhcParticipationsAEngendrer(f(f(ev['selectionVide'])['fiche']), personnel);
      expect(l.length, f(ev['selectionVide'])['participants']);
    });
    test('un montant vide OU nul retombe sur le montant standard (zéro n’est pas une participation)', () {
      expect(rhcMontantParAgent('0'), 1000);
      expect(rhcMontantParAgent(''), 1000);
      expect(rhcMontantParAgent('1500'), 1500);
      expect(rhcMontantParAgent('0', 1200), 1200);
    });
    test('le bilan : attendu, collecté, taux arrondi comme Math.round', () {
      final parts = [
        {'montant': 1500, 'statutPaiement': 'paye', 'mode': 'comptant'},
        {'montant': 1500, 'statutPaiement': 'paye', 'mode': 'salaire'},
        for (var i = 0; i < 41; i++) {'montant': 1500, 'statutPaiement': 'du', 'mode': 'comptant'},
      ];
      final b = rhcBilanEvenement(parts);
      expect([b.attendus, b.attendu, b.regles, b.collecte, b.reste, b.taux, b.salaire, b.comptant], [43, 64500, 2, 3000, 61500, 5, 1, 42]);
      final vide = rhcBilanEvenement(const []);
      expect([vide.taux, vide.reste], [0, 0]);
    });
    test('modifier un événement ne touche QUE les participations non réglées', () {
      final m = f(f(ev['modification'])['resultat']);
      final parts = [
        {'id': 'a', 'statutPaiement': 'paye', 'montant': 1500},
        {'id': 'b', 'statutPaiement': 'du', 'montant': 1500},
        {'id': 'c', 'statutPaiement': null, 'montant': 1500},
      ];
      final k = rhcCorrectifsParticipations(parts, f(m['fiche']));
      expect(k.keys.toList(), ['b', 'c']);
      expect(k['b'], {'montant': 2000, 'periodeRetenue': '2027-01', 'evenementLibelle': 'Mariage de KORA S.', 'nature': 'mariage'});
    });
    test('référentiels : sept natures, deux modes', () {
      expect(rhcNaturesEvenement.length, 7);
      expect(rhcNatureEvenement('deces'), 'Décès');
      expect(rhcNatureEvenement('inconnue'), 'inconnue');
      expect(rhcModesReglement.map((m) => m.label).toList(), ['Imputation sur salaire', 'Paiement au comptant']);
    });
  });

  group('assurance du personnel', () {
    final patients = actives(dossier('patients'));
    final consultations = actives(dossier('consultations'));
    final analyses = actives(dossier('demandesAnalyses'));
    final admissions = actives(dossier('admissions'));
    List<F> rows(String periode, [String fonction = '']) => rhcPrestations(
        patients: patients,
        consultations: consultations,
        analyses: analyses,
        admissions: admissions,
        min: rhcBorneMin(periode, auj),
        fonction: fonction);

    for (final e in f(f(v['assurance'])['periodes']).entries) {
      final p = e.key == 'toujours' ? '' : e.key;
      final cas = f(e.value);
      test('période « ${rhcLibellePeriodeAssurance(p)} » : les quatre indicateurs de la maquette', () {
        final r = rows(p);
        final k = {for (final x in lf(cas['kpis'])) x['libelle']: x['valeur']};
        expect('${r.length}', k['Prestations prises en charge']);
        expect(sans(money(rhcSomme(r, 'valeur'))), sans(k['Valeur de l’avantage']));
        expect('${r.map((x) => x['patientId']).toSet().length}', k['Agents effectivement soignés']);
      });
    }
    test('ordre du tableau : plus récent d’abord, les ex æquo comme la maquette', () {
      final r = rows('365');
      final tab = (f(f(f(v['assurance'])['ouverture'])['ecran'])['tableaux'] as List).first as Map;
      final att = lf2(tab['lignes']);
      // le tableau de la maquette est trié par date décroissante : la première page en rend vingt
      for (var i = 0; i < att.length; i++) {
        expect(dateFR(DateTime.parse('${r[i]['date']}')), att[i][0], reason: 'ligne $i');
      }
    });
    test('les analyses des agents comptent : la date se lit aussi sur `dateHeure` et le prix sur `prix`', () {
      final a = rows('').where((x) => x['nature'] == 'Analyse').toList();
      expect(a.length, 25);
      expect(a.every((x) => (x['valeur'] as num) > 0), isTrue);
    });
    test('un filtre de fonction ne garde que ses agents ; une fonction sans dossier est vide', () {
      for (final e in f(f(v['assurance'])['parFonction']).entries) {
        final k = {for (final x in lf(f(e.value)['kpis'])) x['libelle']: x['valeur']};
        expect('${rows('', e.key).length}', k['Prestations prises en charge'], reason: e.key);
      }
      expect(rows('', 'caissiere'), isEmpty);
    });
    test('les dix agents les plus pris en charge, par valeur décroissante', () {
      final d = rhcDixPremiersAgents(rows('365'));
      expect(d.length, 10);
      for (var i = 1; i < d.length; i++) {
        expect(d[i - 1].$2 >= d[i].$2, isTrue);
      }
    });
    test('une borne : « 30 jours » = trente jours calendaires avant aujourd’hui', () {
      expect(rhcBorneMin('30', auj), '2026-09-30');
      expect(rhcBorneMin('', auj), isNull);
    });
  });

  group('rotation sécurité & entretien', () {
    final plan = actives(dossier('planning'));
    final s = f(v['securite']);
    test('les types proposés suivent la fonction, dans l’ordre du référentiel', () {
      expect([for (final t in rhcTypesRotation('securite')) rhcLibelleRotation(t)], [for (final t in lf2(f(s['modaleSecurite'])['types'])) t[1]]);
      expect([for (final t in rhcTypesRotation('entretien')) rhcLibelleRotation(t)], [for (final t in lf2(f(s['modaleEntretien'])['types'])) t[1]]);
    });
    test('une garde la veille interdit la suivante — le jour de la garde en cause est rendu', () {
      final inc = f(s['incompatibilite']);
      final p = [
        {'employeId': 'EMP38', 'date': inc['veille'], 'type': 'garde'}
      ];
      expect(rhcIncompatibiliteRotation(p, employeId: 'EMP38', jour: DateTime.parse('${inc['jour']}'), type: 'garde'), inc['veille']);
      expect(rhcIncompatibiliteRotation(p, employeId: 'EMP38', jour: DateTime.parse('${inc['jour']}'), type: 'soiree'), isNull, reason: 'la soirée suit une garde sans refus');
      expect(rhcIncompatibiliteRotation(p, employeId: 'EMP39', jour: DateTime.parse('${inc['jour']}'), type: 'garde'), isNull, reason: 'un autre agent');
      expect(rhcIncompatibiliteRotation(p, employeId: 'EMP38', jour: DateTime.parse('2026-10-31'), type: 'garde'), isNull, reason: 'pas la veille');
    });
    test('les agents de rotation et les vacations tenues (repos exclus)', () {
      final ag = rhcAgentsRotation(personnel);
      expect(ag.length, 6);
      final k = {for (final x in lf(f(s['ecran'])['kpis'])) x['libelle']: x['valeur']};
      expect(ag.where((e) => e['fonction'] == 'securite').length, int.parse('${k['Agents de sécurité']}'));
      expect(sans(money(rhcSomme(ag, 'salaireBase'))), sans(k['Masse salariale']));
      final vac = rhcVacationsRotation(plan);
      expect(vac.any((x) => '${x['type']}'.startsWith('repos')), isFalse);
      final g = lf(s['graphes']);
      final parAgent = rhcGrouper(vac, (x) => '${x['employe']}');
      final noms = trierPar(parAgent.keys.toList(), (k) => parAgent[k]!.length, descendant: true);
      expect(noms, g[0]['etiquettes']);
      expect([for (final n in noms) parAgent[n]!.length], [for (final x in (f((g[0]['donnees'] as List).first)['data'] as List)) x]);
      final parType = rhcGrouper(vac, (x) => '${x['type']}');
      expect([for (final k in parType.keys) rhbTypePlanningLabel(k)], g[1]['etiquettes']);
      expect([for (final l in parType.values) l.length], g[1]['donnees']);
    });
  });
}

List<List<Object?>> lf2(Object? x) => [for (final e in (x as List)) (e as List).cast<Object?>()];
