import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT TARIF-FIX : le prix d'une ligne de prescription, rejoué contre les vecteurs TIRÉS de la maquette en marche (`build/vecteurs-tarifs-ligne.js`).
/// Un montant strictement positif, ou « prix à définir » avec sa cause, son motif et son geste : jamais un zéro, jamais la colonne de l'autre.
typedef F = Map<String, Object?>;
List<F> liste(Object? x) => [for (final e in (x as List? ?? const [])) (e as Map).cast<String, Object?>()];

void main() {
  final v = (jsonDecode(File('test/vecteurs/tarifs_ligne.json').readAsStringSync()) as Map).cast<String, Object?>();
  final sonde = (v['sonde'] as Map).cast<String, Object?>();
  final h = ReferentielTarifs(liste(sonde['tarifs']), liste(sonde['versions']));

  Map<String, Object?> forme(LignePrix r) => {
        'ok': r.ok,
        if (r.montant != null) 'montant': r.montant,
        if (r.tarif != null) 'tarif': r.tarif,
        if (r.motif != null) 'motif': r.motif,
        'prestation': r.prestation,
        'libelle': r.libelle,
        if (r.version != null) 'version': r.version,
        if (r.cause != null) 'cause': r.cause,
        if (r.geste != null) 'geste': r.geste,
        if (r.effectifLe != null) 'effectifLe': r.effectifLe,
        if (r.colonne != null) 'colonne': r.colonne,
        if (!r.ok) 'code': 'PRIX_A_DEFINIR',
      };

  group('le prix d’une ligne de prescription (lot TARIF-FIX)', () {
    test('CHAQUE cas de sonde de la maquette (deux voies, trois jours, deux colonnes) est rejoué à l’identique : montant, cause, motif, geste, date d’effet', () {
      final cas = liste(sonde['cas']);
      expect(cas.length, greaterThan(150));
      var ecarts = 0;
      for (final c in cas) {
        final r = h.prixDeLigne(c['code'], c['jour'], c['assure'] == true, voie: '${c['voie']}', aujourdhui: '2026-08-16');
        final attendu = (c['attendu'] as Map).cast<String, Object?>();
        if (jsonEncode(forme(r)) != jsonEncode(attendu)) {
          ecarts++;
          if (ecarts < 4) fail('${c['voie']} ${c['code']} ${c['jour']} assuré=${c['assure']} : ${jsonEncode(forme(r))} au lieu de ${jsonEncode(attendu)}');
        }
      }
      expect(ecarts, 0);
    });

    test('JAMAIS un zéro : aucune ligne « ok » ne porte un montant nul ou négatif ; un prix nul en base est « prix à définir »', () {
      for (final c in liste(sonde['cas'])) {
        final r = h.prixDeLigne(c['code'], c['jour'], c['assure'] == true, voie: '${c['voie']}', aujourdhui: '2026-08-16');
        if (r.ok) expect(r.montant! > 0, isTrue, reason: '${c['code']}');
      }
      final nul = h.prixDeLigne('A9', '2026-08-16', false, aujourdhui: '2026-08-16');
      expect([nul.ok, nul.cause], [false, 'prix-non-assure-vide']);
    });

    test('LES DEUX PRIX : une colonne vide n’est jamais remplacée par l’autre', () {
      final a2 = h.prixDeLigne('A2', '2026-08-16', true, aujourdhui: '2026-08-16');
      expect([a2.ok, a2.cause, a2.colonne], [false, 'prix-assure-vide', 'assuré']);
      expect(h.prixDeLigne('A2', '2026-08-16', false, aujourdhui: '2026-08-16').montant, 4000);
      final a4 = h.prixDeLigne('A4', '2026-08-16', false, aujourdhui: '2026-08-16');
      expect([a4.ok, a4.cause, a4.colonne], [false, 'prix-non-assure-vide', 'non assuré']);
      expect(h.prixDeLigne('A4', '2026-08-16', true, aujourdhui: '2026-08-16').montant, 3000);
    });

    test('DATE D’EFFET FUTURE : « prix à définir, effectif le JJ/MM/AAAA » avant le jour dit, le nouveau prix ce jour-là, lu à chaque appel (aucune tâche de minuit)', () {
      final avant = h.prixDeLigne('A6', '2026-08-19', false, aujourdhui: '2026-08-19');
      expect([avant.ok, avant.cause, avant.effectifLe, avant.libelleCourt], [false, 'version-future', '2026-08-20', 'prix à définir, effectif le 20/08/2026']);
      expect(h.prixDeLigne('A6', '2026-08-20', false, aujourdhui: '2026-08-20').montant, 3500);
      expect(h.prixDeLigne('A6', '2026-09-01', false, aujourdhui: '2026-09-01').montant, 3700);
      expect(h.prixDeLigne('A8', '2026-08-19', false, aujourdhui: '2026-08-19').montant, 5000, reason: 'l’ancien prix reste lu jusqu’à la veille');
      expect(h.prixDeLigne('A8', '2026-08-20', false, aujourdhui: '2026-08-20').montant, 5500);
    });

    test('sans référentiel, la ligne est « prix à définir » (jamais un zéro)', () {
      final r = ReferentielTarifs(const [], const []).prixDeLigne('A1', '2026-08-16', false, aujourdhui: '2026-08-16');
      expect(jsonEncode(forme(r)), jsonEncode(sonde['sansReferentiel']));
    });
  });

  group('un code ne se réutilise pas (lot TARIF-FIX)', () {
    test('CHAQUE cas de la maquette : casse, espaces, alias, archivé', () {
      final cp = (v['codePris'] as Map).cast<String, Object?>();
      final tarifs = liste(cp['tarifs']);
      for (final c in liste(cp['cas'])) {
        expect(tarCodePris(tarifs, c['code'])?['code'], c['pris'], reason: '${c['code']}');
        expect(tarCodeNormalise(c['code']), c['normalise']);
      }
    });

    test('le moteur de proposition REFUSE la création d’un code déjà pris écrit autrement (CODE_EXISTANT, geste)', () {
      final ref = ReferentielTarifs([
        {'code': 'CERT-APT', 'codeGrille': 'CERT-APT', 'libelle': 'Certificat médical d’aptitude', 'famille': 'CERTIFICAT', 'statut': 'actif'},
        {'code': 'OLD1', 'codeActe': 'OLD1', 'libelle': 'Acte archivé', 'famille': 'ACTE', 'statut': 'archive'},
      ], [
        {'code': 'CERT-APT', 'version': 1, 'prixNonAssure': 7000, 'prixAssure': 7000, 'etatAssure': 'montant', 'statut': 'valide'},
      ]);
      for (final code in ['cert-apt', ' CERT-APT ', 'old1']) {
        final r = tarProposer(
            ContexteTarif(referentiel: ref, role: 'da', auteur: 'Test DAF', peutEditerEcran: true, aujourdhui: '2026-08-16'),
            DemandeProposition(code: code, prixNonAssure: 5000, etatAssure: 'unique', dateEffet: '2026-08-16', motif: 'Test', creation: const {'libelle': 'Certificat d’aptitude', 'famille': 'CERTIFICAT'}));
        expect(r.refus?.code, 'CODE_EXISTANT', reason: code);
        expect(r.refus!.motif, contains('déjà pris'));
        expect(r.refus!.geste, isNotEmpty);
      }
    });
  });
}
