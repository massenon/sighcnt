// Rejoue les vecteurs de m7-fournisseurs (prototype_html/build/vecteurs-m7-achats.js) : l'écran réel, ses modales « Nouveau » et « Modifier ».
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> liste(Object? v) => ((v ?? const []) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

void memes(Object? obtenu, Object? attendu, String chemin) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

List<List<String>> kpisTexte(KpisFournisseurs k) => [
      ['Fournisseurs référencés', nombre(k.references)],
      ['Habilités aux retours', nombre(k.habilites)],
      ['Volume d’achats', money(k.volumeAchats)],
      ['Délai moyen', '${k.delaiMoyen} j'],
    ];

List<List<String>> attendus(Object? kpis) => [
      for (final k in (kpis! as List)) [(k as List)[0] as String, '${k[1]}']
    ];

void main() {
  final f = File('test/vecteurs/fournisseurs_m7.json');
  if (!f.existsSync()) {
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-m7-achats.js`');
  }
  final doc = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  final etat = (doc['etat']! as Map).cast<String, Object?>();

  test('indicateurs du jeu = ceux de l\'écran réel', () {
    final k = kpisFournisseurs(liste(etat['fournisseurs']), liste(etat['commandes']));
    expect(kpisTexte(k), attendus((etat['jeu']! as Map)['kpis']));
  });

  test('le nombre de commandes de chaque ligne = recompte par CODE', () {
    final cmds = liste(etat['commandes']);
    for (final l in ((etat['jeu']! as Map)['lignes']! as List).map((x) => x as List)) {
      // colonnes : sélection, code, raison sociale, …, commandes (avant-dernière).
      expect('${commandesDuFournisseur('${l[1]}', cmds).length}', '${l[l.length - 2]}',
          reason: '${l[1]}');
    }
  });

  group('création et modification', () {
    for (final c in liste(doc['cas'])) {
      test('${c['nom']}', () {
        final saisie = {
          ...((c['valeursInitiales'] as Map?)?.cast<String, Object?>() ?? {}),
          ...(c['saisie']! as Map).cast<String, Object?>(),
        };
        final s = (c['sortie']! as Map).cast<String, Object?>();
        final attendue = s['nouvelle'] ?? s['modifiee'];
        if (attendue == null) {
          expect(() => valeursFournisseur(saisie),
              throwsA(isA<FormulaireInvalide>()));
          return;
        }
        final patch = valeursFournisseur(saisie);
        final avant = (c['avant'] as Map?)?.cast<String, Object?>() ?? {};
        memes({'statut': 'actif', ...avant, ...patch}, attendue, 'fiche');
        final k = kpisFournisseurs(liste((c['entree']! as Map)['fournisseurs']),
            liste((c['entree']! as Map)['commandes']));
        expect(kpisTexte(k), attendus((c['apres']! as Map)['kpis']));
      });
    }

    test('un code déjà pris est ACCEPTÉ : aucun contrôle d\'unicité (écart signalé)',
        () {
      final cas = liste(doc['cas']).firstWhere((c) => '${c['nom']}'.contains('DÉJÀ'));
      expect((cas['sortie']! as Map)['nouvelle'], isNotNull);
    });
  });

  group('tiroir et état imprimé', () {
    for (final d in liste(doc['detail'])) {
      test('historique de ${d['code']}', () {
        final cmds = commandesDuFournisseur('${d['code']}', liste(etat['commandes']));
        final texte = (d['tiroir']! as List).cast<String>();
        for (final c in historiqueDuTiroir(cmds)) {
          expect(texte, contains('${c['reference']}'));
        }
        expect(texte, contains(nombre(cmds.length)));
      });
    }
  });
}
