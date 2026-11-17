// Rejoue `test/vecteurs/tiers.json` (prototype_html/build/vecteurs-tiers.js : le moteur RÉEL SIGH.tiers de la maquette piloté dans Chrome, horloge d'extraction au 30/10/2026 midi) sur les
// fonctions pures du lot TIERS : l'acheteur (IFU de 13 chiffres et nom obligatoires), les champs d'un tiers payeur, la DÉCISION du comptable sur l'AIB (le logiciel propose, ne décide
// jamais), le contrôle d'émission, le numéro FT-AAAA-nnnn (année de la date de la pièce), la créance (dû moins lettrages), le lettrage et la balance âgée (tranches lues en base).
//
// Mutations rouges (voir le compte rendu du lot) : IFU invalide accepté, AIB imposé sans décision, créance non calculée, numéro d'une autre année, droit ignoré.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];

/// Une fiche sans ses champs nuls (le magasin de la maquette n'écrit pas un champ nul).
M sansNuls(M m) => {for (final e in m.entries) if (e.value != null) e.key: e.value};

void main() {
  final v = obj(jsonDecode(File('test/vecteurs/tiers.json').readAsStringSync()));
  final maintenant = DateTime.utc(2026, 10, 30, 12);
  final donnees = AibDonnees(situations: liste(v['situations']), bareme: liste(v['bareme']));

  group('l’acheteur d’une facture à un tiers : IFU de 13 chiffres et nom obligatoires', () {
    for (final c in liste(v['acheteurs'])) {
      test('${c['nom']}', () {
        final s = obj(c['sortie']);
        final r = tiersValiderAcheteur(ifu: c['ifu'], nom: c['acheteur']);
        expect(r['ok'] == true, s['ok'] == true, reason: '${r['code']}');
        if (s['ok'] == true) {
          expect(r['ifu'], s['ifu']);
          expect(r['nom'], s['nom']);
        } else {
          expect(r['code'], s['code']);
        }
      });
    }
  });

  group('les champs d’un tiers payeur', () {
    for (final c in liste(v['champs'])) {
      test('${c['nom']}', () {
        final s = obj(c['sortie']);
        final r = tiersLireChamps(obj(c['entree']));
        expect(r['ok'] == true, s['ok'] == true, reason: '${r['code']}');
        if (s['ok'] == true) {
          final champs = obj(r['champs']);
          expect(champs['ifu'], s['ifu']);
          expect(champs['delaiPaiementJours'], s['delai']);
        } else {
          expect(r['code'], s['code']);
          expect(c['ecrits'], 0, reason: 'un refus n’écrit rien');
        }
      });
    }
  });

  group('la décision du comptable sur l’AIB : le logiciel propose, il ne décide jamais', () {
    for (final c in liste(v['decisions'])) {
      test('${c['nom']}', () {
        final s = obj(c['sortie']);
        final r = tiersDeciderAib(donnees,
            droit: c['droit'] == true,
            facture: obj(c['facture']),
            saisie: obj(c['saisie']),
            acteur: 'Acteur ${c['role']}',
            libelleRole: '${c['role']}',
            maintenant: maintenant);
        expect(r['ok'] == true, s['ok'] == true, reason: '${r['code']} ${r['motif']}');
        if (s['ok'] == true) {
          final d = Map<String, Object?>.from(obj(r['decision']))..removeWhere((k, _) => ['decideLe', 'decidePar', 'decideRole'].contains(k));
          expect(sansNuls(d), sansNuls(obj(obj(s)['decision'])));
        } else {
          expect(r['code'], s['code']);
        }
      });
    }
    test('sans décision posée, le taux effectif est 0 : le logiciel n’impose jamais l’AIB', () {
      expect(tiersTauxEffectif({'aibDecision': null}), 0);
      expect(tiersTauxEffectif({}), 0);
      expect(tiersTauxEffectif({'aibDecision': {'appliquer': false}}), 0);
      expect(tiersTauxEffectif({'aibDecision': {'appliquer': true, 'taux': 1}}), 1);
    });
  });

  group('le contrôle d’émission', () {
    for (final c in liste(v['emissions'])) {
      test('${c['nom']}', () {
        final s = obj(c['sortie']);
        final r = tiersControleEmission(droit: c['droit'] == true, libelleRole: '${c['role']}', facture: obj(c['facture']));
        if (s['ok'] == true) {
          expect(r, isNull, reason: '${r?['code']}');
          final taux = tiersTauxEffectif(obj(c['facture']));
          expect(aibDivArrondi(100000 * taux, 100), s['aib']);
          expect(100000 + aibDivArrondi(100000 * taux, 100), s['net']);
        } else {
          expect(r?['code'], s['code']);
        }
      });
    }
    test('un IFU invalide ou un nom absent est refusé avant toute émission (acheteur contrôlé deux fois)', () {
      final b = {'statut': 'brouillon', 'aibDecision': {'appliquer': false}};
      expect(tiersControleEmission(droit: true, libelleRole: 'x', facture: {...b, 'ifuAcheteur': '12345', 'nomAcheteur': 'X'})?['code'], 'IFU_INVALIDE');
      expect(tiersControleEmission(droit: true, libelleRole: 'x', facture: {...b, 'ifuAcheteur': '', 'nomAcheteur': 'X'})?['code'], 'TIERS_IFU_ABSENT');
      expect(tiersControleEmission(droit: true, libelleRole: 'x', facture: {...b, 'ifuAcheteur': '3201642748214', 'nomAcheteur': ' '})?['code'], 'NOM_ACHETEUR_ABSENT');
      expect(tiersControleEmission(droit: true, libelleRole: 'x', facture: {...b, 'ifuAcheteur': '3201642748214', 'nomAcheteur': 'X'}), isNull);
    });
  });

  group('le numéro FT-AAAA-nnnn : l’année est celle de la date de la pièce', () {
    final pieces = liste(obj(v['numeros'])['pieces']);
    for (final c in liste(obj(v['numeros'])['cas'])) {
      test('date « ${c['date']} »', () => expect(tiersNumeroFacture(c['date'] == '' ? null : c['date'], pieces, maintenant: maintenant), c['numero']));
    }
  });

  group('la créance, le lettrage et la balance âgée', () {
    final cr = obj(v['creances']);
    final ids = obj(cr['ids']);
    final tranches = pcTranches(const [], '${cr['jour']}');
    M balance(M etat) => tiersCreances(
        date: '${cr['jour']}', factures: liste(etat['factures']), lettrages: liste(etat['lettrages']), avoirs: liste(etat['avoirs']), reglements: liste(etat['reglements']), tranches: tranches);
    test('les tranches viennent des paramètres de clinique (30 et 90 jours semés)', () => expect([tranches.courte, tranches.longue], [30, 90]));
    test('la balance de départ', () {
      final b = balance(obj(cr['depart']));
      final e = obj(cr['balanceDepart']);
      expect(b['total'], e['lignes'] == null ? 0 : liste(e['lignes']).fold<int>(0, (n, l) => n + (l['du'] as int)));
      for (final l in liste(e['lignes'])) {
        final m = liste(b['lignes']).firstWhere((x) => x['code'] == l['code']);
        for (final k in ['factures', 'facture', 'du', 'moins30', 'de30a90', 'plus90', 'enRetard', 'echeanceIncalculable']) {
          expect(m[k], l[k], reason: '${l['code']} $k');
        }
      }
    });
    for (final e in liste(cr['etapes'])) {
      test('${e['nom']}', () {
        final avant = obj(e['etatAvant']);
        final saisie = obj(e['entree']);
        final reglement = liste(avant['reglements']).where((r) => r['id'] == saisie['reglementId']).firstOrNull;
        final r = tiersLettrer(
            droit: e['droit'] == true,
            libelleRole: '${e['role']}',
            reglement: reglement,
            affectations: liste(saisie['affectations']),
            factures: liste(avant['factures']),
            lettrages: liste(avant['lettrages']),
            avoirs: liste(avant['avoirs']));
        final s = obj(e['sortie']);
        expect(r['ok'] == true, s['ok'] == true, reason: '${r['code']} ${r['motif']}');
        if (s['ok'] == true) {
          expect(r['lettre'], s['lettre']);
          expect(r['resteNonLettre'], s['resteNonLettre']);
        } else {
          expect(r['code'], s['code']);
        }
        /* la créance de chaque facture et la balance, sur l'état APRÈS (la créance n'est jamais « non calculée ») */
        final apres = obj(e['etatApres']);
        final cs = obj(e['creances']);
        for (final k in ['f1', 'f2', 'f3', 'f4']) {
          final f = liste(apres['factures']).firstWhere((x) => x['id'] == ids[k]);
          expect(tiersCreanceFacture(f, liste(apres['lettrages']), liste(apres['avoirs'])), cs[k], reason: 'créance $k');
        }
        final b = balance(apres);
        final eb = obj(e['balance']);
        expect(b['total'], liste(eb['lignes']).fold<int>(0, (n, l) => n + (l['du'] as int)));
        expect(b['nonLettre'], liste(apres['reglements']).fold<int>(0, (n, rg) => n + tiersResteNonLettre(rg, liste(apres['lettrages']))));
      });
    }
    test('un règlement non lettré ne diminue aucune créance', () {
      final d = obj(cr['depart']);
      final b = balance(d);
      final avecRegl = {...d, 'reglements': liste(d['reglements'])};
      expect(balance(avecRegl)['total'], b['total']);
    });
  });

  group('la synchronisation : famille A, identité par le contenu, jamais vers un téléphone, une pièce émise ne se réécrit pas au rejeu', () {
    test('les cinq collections du lot voyagent et ne vont JAMAIS vers un téléphone (RG-13)', () {
      expect(collectionsTiersSynchronisees, {'tiersPayeurs', 'facturesTiers', 'avoirsTiers', 'reglementsTiers', 'lettragesTiers'});
      expect(collectionsGestionSynchronisees, containsAll(collectionsTiersSynchronisees));
      expect(collectionsGestionJamaisMobile, containsAll(collectionsTiersSynchronisees));
      expect(v['collections'], unorderedEquals(collectionsTiersSynchronisees.toList()), reason: 'les collections que le moteur de la maquette écrit sont exactement celles qui voyagent');
    });
    test('l\'identité tirée du contenu : la même facture saisie à deux postes est la même, une autre prestation est une autre', () {
      M f(String src, [String date = '2026-11-16']) => {'tiersCode': 'TP-001', 'date': date, 'sourcesCle': src};
      final a = identiteSyncGestion('facturesTiers', f('FAC-1#L001:100000'));
      expect(a, startsWith('FTP-'));
      expect(identiteSyncGestion('facturesTiers', {...f('FAC-1#L001:100000'), 'numero': 'FT-2026-0009'}), a, reason: 'le numéro affiché n\'entre pas dans l\'identité');
      expect(identiteSyncGestion('facturesTiers', f('FAC-1#L001:50000')), isNot(a));
      expect(identiteSyncGestion('facturesTiers', f('FAC-1#L001:100000', '2026-11-17')), isNot(a));
      expect(identiteSyncGestion('facturesTiers', {'tiersCode': 'TP-001', 'date': '2026-11-16'}), isNull, reason: 'sans prestation rattachée, identité propre au poste');
      expect(identiteSyncGestion('tiersPayeurs', {'code': 'TP-001', 'dateEffet': '2026-01-05'}), identiteSyncGestion('tiersPayeurs', {'code': ' tp-001 ', 'dateEffet': '2026-01-05T00:00:00'}));
      expect(identiteSyncGestion('tiersPayeurs', {'code': 'TP-001', 'dateEffet': '2026-02-01'}), isNot(identiteSyncGestion('tiersPayeurs', {'code': 'TP-001', 'dateEffet': '2026-01-05'})), reason: 'une version datée est une autre fiche');
      expect(identiteSyncGestion('avoirsTiers', {'sourcesCle': 'FT-2026-0001'}), startsWith('ATP-'));
      final r = {'tiersCode': 'TP-001', 'date': '2026-11-17', 'montant': 100000, 'referencePaiement': 'VIR-1'};
      expect(identiteSyncGestion('reglementsTiers', r), identiteSyncGestion('reglementsTiers', {...r, 'numero': 'RGT-2026-0007'}));
      expect(identiteSyncGestion('reglementsTiers', {...r, 'referencePaiement': 'VIR-2'}), isNot(identiteSyncGestion('reglementsTiers', r)));
      final l = {'tiersCode': 'TP-001', 'reglementRef': 'VIR-1', 'factureNumero': 'FT-2026-0001', 'montant': 100000};
      expect(identiteSyncGestion('lettragesTiers', l), startsWith('LTP-'));
      expect(identiteSyncGestion('lettragesTiers', {...l, 'factureNumero': 'FT-2026-0002'}), isNot(identiteSyncGestion('lettragesTiers', l)));
    });
    test('une pièce émise ne se réécrit jamais au rejeu (FACTURE_TIERS_FIGEE), une trace MECeF nouvelle passe, un numéro MECeF posé ne change pas', () {
      final emise = {'statut': 'emise', 'numero': 'FT-2026-0001', 'base': 100000, 'ifuAcheteur': '3201642748214', 'lignes': [{'ligneId': 'L001', 'montant': 100000}], 'aibDecision': {'appliquer': true, 'taux': 1}};
      expect(refusRejeuFactureTiers(null, emise), isNull, reason: 'une création n\'est pas une réécriture');
      expect(refusRejeuFactureTiers({...emise, 'statut': 'brouillon'}, {...emise, 'base': 5}), isNull, reason: 'un brouillon se complète');
      expect(refusRejeuFactureTiers(emise, {...emise, 'base': 1})?['code'], 'FACTURE_TIERS_FIGEE');
      expect(refusRejeuFactureTiers(emise, {...emise, 'ifuAcheteur': '0000000000000'})?['code'], 'FACTURE_TIERS_FIGEE');
      expect(refusRejeuFactureTiers(emise, {...emise, 'aibDecision': {'appliquer': false}})?['code'], 'FACTURE_TIERS_FIGEE');
      expect(refusRejeuFactureTiers(emise, {...emise, 'lignes': [{'ligneId': 'L001', 'montant': 1}]})?['code'], 'FACTURE_TIERS_FIGEE');
      expect(refusRejeuFactureTiers(emise, {...emise, 'statutMecef': 'valide', 'numeroMecef': 'MECEF1', 'codeRetour': 'OK-200'}), isNull);
      final certifiee = {...emise, 'numeroMecef': 'MECEF1'};
      expect(refusRejeuFactureTiers(certifiee, {...certifiee, 'numeroMecef': 'MECEF2'})?['code'], 'FACTURE_TIERS_NUMERO_MECEF_FIGE');
      expect(refusRejeuFactureTiers(certifiee, {...certifiee, 'statutMecef': 'valide'}), isNull);
    });
  });
}
