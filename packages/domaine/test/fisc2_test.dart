// Rejoue `test/vecteurs/fisc2.json` (prototype_html/build/vecteurs-fisc2.js : le moteur RÉEL de la maquette piloté dans Chrome, horloge d'extraction au 30/10/2026 midi) sur les
// fonctions pures du lot FISC-2 : la confirmation d'une obligation « à confirmer par la CNSS » (`cfbConfirmerObligation`) et l'imputation de l'AIB opération par opération
// (`aibProposerImputation`, `aibImputer`), plus la séparation des deux barèmes de l'AIB (situation de l'acheteur, retenue sur la facture d'un tiers).
//
// Mutations rouges (voir le compte rendu du lot) : confirmation sans droit acceptée, confirmation qui réécrit sans historique, référence absente acceptée, imputation sans décision
// du comptable acceptée, taux imposé à la place de celui du comptable, barème lu à une autre date.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

void main() {
  final v = obj(jsonDecode(File('test/vecteurs/fisc2.json').readAsStringSync()));
  final auj = DateTime.parse('${v['aujourdhui']}T12:00:00');
  final maintenant = DateTime.utc(2026, 10, 30, 12);
  final obligations = liste(v['obligations']);
  final exercices = liste(v['exercices']);

  group('confirmer une obligation « à confirmer par la CNSS »', () {
    for (final c in liste(v['confirmations'])) {
      test('${c['nom']}', () {
        final e = obj(c['entree']);
        final s = obj(c['sortie']);
        final r = cfbConfirmerObligation(obligations,
            code: e['code'] as String?,
            reference: e['reference'] as String?,
            dateEffet: e['dateEffet'],
            droit: c['droit'] == true,
            acteur: 'Acteur ${c['role']}',
            maintenant: maintenant,
            aujourdhui: auj,
            exercices: exercices,
            fileul: c['fileul'] == true);
        if (s['ok'] != true) {
          expect(r.ok, isFalse, reason: 'refus attendu');
          expect(r.refus!.code, s['code']);
          if (s['code'] != 'CONFIRMATION_RESERVEE') {
            expect(r.refus!.motif, s['motif']);
            expect(r.refus!.geste, s['geste']);
          }
          expect(r.fiche, isNull, reason: 'un refus n’écrit rien');
          return;
        }
        expect(r.ok, isTrue);
        final f = obj(s['fiche']);
        for (final k in ['aConfirmer', 'confirmationReference', 'confirmeePar', 'dateEffet', 'note', 'source', 'motif', 'code', 'jour']) {
          expect(r.fiche![k], f[k], reason: 'fiche après : $k');
        }
        expect(r.dateEffet, s['dateEffet']);
        // La version « à confirmer » est GARDÉE à l'historique, avec sa fin à la veille ; elle n'est pas réécrite.
        final h = obj(s['historique']);
        expect(r.historique!['aConfirmer'], h['aConfirmer']);
        expect(r.historique!['aConfirmer'], isTrue);
        expect(r.historique!['dateFin'], h['dateFin']);
        expect(r.historique!['obligationId'], isNotNull);
        expect(r.archiver, isFalse);
      });
    }
  });

  group('le motif est obligatoire pour TOUTE modification faite par le validateur (PRD M13 Q4)', () {
    for (final c in liste(v['motifs'])) {
      test('${c['nom']}', () {
        final avant = c['avant'] == null ? null : obj(c['avant']);
        final valeurs = obj(c['valeurs']);
        final famille = '${c['famille']}';
        final chiffres = valChiffresModifies(famille, avant, valeurs);
        expect(chiffres, (c['chiffres'] as List).cast<String>());
        final r = valControlerEnregistrement(famille,
            role: '${c['role']}',
            chiffres: chiffres,
            motif: c['motif'] as String?,
            fileul: c['fileul'] == true,
            avant: avant,
            valeurs: valeurs,
            modifie: c['modifie'] as bool?);
        final s = c['sortie'] == null ? null : obj(c['sortie']);
        if (s == null) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull, reason: 'refus attendu');
          expect([r!.code, r.motif, r.geste], [s['code'], s['motif'], s['geste']]);
        }
      });
    }
  });

  group('les paramètres du calendrier fiscal, datés (délais d’alerte, montant de la CCIB)', () {
    final pf = obj(v['parametresFiscaux']);
    test('la semence est celle de la maquette (10 et 30 jours, 300 000 FCFA en deux tranches), « à valider »', () {
      expect(jsonEncode(cfbSemenceParametresFiscaux()), jsonEncode(pf['depart']));
    });
    final fiches = liste(pf['fiches']);
    for (final c in liste(pf['delais'])) {
      test('délais d’alerte au ${c['date']}', () {
        final r = cfbDelaisFiscauxALaDate(fiches, '${c['date']}');
        expect([r.delaiAPayer, r.delaiDeclaration], [c['delaiAPayer'], c['delaiDeclaration']]);
      });
    }
    for (final c in liste(pf['ccib'])) {
      test('CCIB au ${c['date']}', () {
        final r = cfbMontantCcibALaDate(fiches, '${c['date']}');
        expect([r.total, r.tranches, r.tranche], [c['total'], c['tranches'], c['tranche']]);
      });
    }
    test('sans fiche, la semence répond ; le seuil « à payer » du suivi suit le paramètre à la date', () {
      expect(cfbDelaisFiscauxALaDate(const [], '2026-10-30').delaiAPayer, 10);
      final e = {'echeance': '2026-11-20', 'paye': false, 'declaration': null};
      expect(cpcCalculerEtat(e, DateTime(2026, 11, 8)), 'a_venir');
      expect(cpcCalculerEtat(e, DateTime(2026, 11, 8), delaiAPayer: 15), 'a_payer', reason: 'un délai plus long classe l’échéance plus tôt');
    });
  });

  final d = AibDonnees(
    situations: liste(v['situations']),
    bareme: liste(v['bareme']),
    comptes: liste(v['comptes']),
  );

  group('deux barèmes de l’AIB : situation de l’acheteur, retenue sur la facture d’un tiers', () {
    test('situations par famille', () {
      final p = obj(v['situationsParFamille']);
      expect([for (final s in aibSituationsActives(d)) s['code']], p['acheteur']);
      expect([for (final s in aibSituationsActives(d, famille: 'retenue_tiers')) s['code']], p['retenue']);
      expect([for (final s in aibSituationsActives(d, famille: 'tous')) s['code']], p['tous']);
    });
    for (final c in liste(v['propositions'])) {
      test('proposition ${c['situation']} au ${c['date']}', () {
        final r = aibProposerImputation(d, situation: c['situation'], date: '${c['date']}');
        final s = obj(c['sortie']);
        expect(r['ok'], s['ok']);
        if (s['ok'] == true) {
          for (final k in ['taux', 'situation', 'versionId', 'arrete', 'famille', 'dateEffet', 'dateFin', 'date']) {
            expect(r[k], s[k], reason: k);
          }
        } else {
          expect(r['code'], s['code']);
        }
      });
    }
  });

  group('imputer l’AIB opération par opération (le comptable décide, le logiciel propose)', () {
    for (final c in liste(v['imputations'])) {
      test('${c['nom']}', () {
        final s = obj(c['sortie']);
        final r = aibImputer(d, liste(c['existantes']),
            droit: c['droit'] == true,
            saisie: obj(c['entree']),
            acteur: 'Acteur ${c['role']}',
            libelleRole: '${c['role']}',
            maintenant: maintenant,
            aujourdhui: auj,
            exercices: exercices);
        if (s['ok'] != true) {
          expect(r['ok'], isFalse, reason: 'refus attendu');
          expect(r['code'], s['code']);
          expect(c['nb'], 0, reason: 'un refus n’écrit rien');
          return;
        }
        expect(r['ok'], isTrue);
        final fiche = obj(r['fiche']);
        final att = obj(s['fiche']);
        // La signature porte le compte et le rôle ; l'instant et le libellé du rôle sont ceux de l'appelant (hors vecteur).
        for (final k in att.keys) {
          if (k == 'signeePar' || k == 'signeeRole') continue;
          expect(fiche[k], att[k], reason: 'champ $k');
        }
        expect(fiche.keys.toSet().difference(att.keys.toSet()).difference({'signeeLe', 'signeePar', 'signeeRole'}), isEmpty, reason: 'aucun champ en trop');
        expect(fiche['signeePar'], 'Acteur ${c['role']}');
        expect(fiche['signeeLe'], isNotEmpty);
        if (fiche['appliquer'] == false) {
          expect(fiche.containsKey('taux'), isFalse);
          expect(fiche.containsKey('montant'), isFalse);
        }
      });
    }
  });
}
