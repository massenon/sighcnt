import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

/// Lot RLS-SYNC : la liste blanche des indicateurs de synchronisation, rejouée sur les vecteurs partagés (`synchro_fileuls.json`, les mêmes que ceux du banc Node et du relais Laravel).
void main() {
  final v = lireVecteurs('synchro_fileuls');

  /// Les vecteurs écrivent « GENERER_201 » pour un tableau de 201 fileuls valides (un fichier JSON de 201 lignes n'apprendrait rien de plus).
  Object? developper(Object? x) => x == 'GENERER_201' ? [for (var i = 0; i < 201; i++) {'poste': 'F$i'}] : x;

  test('les cinq clés et la borne sont celles du vecteur', () {
    expect(synchroClesFileul, (v['cles']! as List).cast<String>());
    expect(synchroFileulsMax, v['max']);
  });

  group('nom technique du poste', () {
    final p = (v['poste']! as Map).cast<String, Object?>();
    test('valides', () {
      for (final s in (p['valides']! as List).cast<String>()) {
        expect(synchroPosteTechnique.hasMatch(s), isTrue, reason: s);
      }
    });
    test('invalides (dossier, adresse, ponctuation, saut de ligne, trop long)', () {
      for (final s in (p['invalides']! as List).cast<String>()) {
        expect(synchroPosteTechnique.hasMatch(s), isFalse, reason: s);
      }
    });
  });

  group('verifier : le même refus nommé que le relais', () {
    for (final c in liste(v['valider'])) {
      test(c['nom']! as String, () {
        final charge = (c['charge']! as Map).map((k, x) => MapEntry('$k', developper(x)));
        final refus = synchroVerifierIndicateurs(charge);
        if (c['ok'] == true) {
          expect(refus, isNull, reason: refus?.motif);
        } else {
          expect(refus, isNotNull);
          expect(refus!.code, c['code']);
          expect(refus.chemin, c['chemin']);
          expect(refus.motif, isNotEmpty);
          expect(refus.geste, isNotEmpty);
        }
      });
    }

    test('un refus ne recopie jamais la valeur ni une clé de forme douteuse', () {
      final r = synchroVerifierIndicateurs({
        'fileuls': [
          {'poste': 'F1', 'KOUASSI Awa': 1}
        ]
      })!;
      expect('${r.motif} ${r.chemin} ${r.geste}', isNot(contains('KOUASSI')));
      final r2 = synchroVerifierIndicateurs({
        'fileuls': [
          {'poste': 'CNT/12/26'}
        ]
      })!;
      expect('${r2.motif} ${r2.chemin} ${r2.geste}', isNot(contains('CNT/12')));
    });
  });

  group('construire : compteurs et horodatages, jamais zéro pour une valeur non calculable', () {
    for (final c in liste(v['construire'])) {
      test(c['nom']! as String, () {
        final e = (c['entree']! as Map).cast<String, Object?>();
        final s = synchroFileulPublie(
          etiquette: e['etiquette'] as String?,
          uuid: e['uuid']! as String,
          dernierContact: e['dernierContact'] as int?,
          dernierSeq: e['dernierSeq']! as int,
          seqMax: e['seqMax']! as int,
          conflitsOuverts: e['conflitsOuverts']! as int,
          demandesEnAttente: e['demandesEnAttente']! as int,
        );
        expect(s, (c['sortie']! as Map).cast<String, Object?>());
        // Ce que la mère construit est toujours permis par le relais.
        expect(synchroVerifierIndicateurs({'fileuls': [s]}), isNull);
        expect(s.keys.toList(), synchroClesFileul);
      });
    }
  });

  group('assainir : la mère omet ce qui sort de la liste', () {
    for (final c in liste(v['assainir'])) {
      test(c['nom']! as String, () {
        final r = synchroAssainirFileuls(developper(c['entree']));
        if (c.containsKey('longueur')) {
          expect(r.length, c['longueur']);
        } else {
          expect(r, (c['sortie']! as List).map((x) => (x as Map).cast<String, Object?>()).toList());
        }
        // Tout ce qui sort passe le contrôle du relais.
        expect(synchroVerifierIndicateurs({'fileuls': r}), isNull);
      });
    }
  });
}
