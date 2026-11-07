// Rejoue les vecteurs de m7-factures-fournisseurs (prototype_html/build/vecteurs-m7-achats.js) : l'écran réel, sa modale « Modifier » et le
// moteur du BFR (`SIGH.bfr.calculer`) qui lit la même colonne.
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

List<List<String>> kpisTexte(KpisFacturesFournisseurs k) => [
      ['Factures fournisseurs', nombre(k.total)],
      ['Rapprochées', nombre(k.rapprochees)],
      ['Anomalies', nombre(k.anomalies)],
      ['Impayées', money(k.impayees)],
    ];

List<List<String>> attendus(Object? kpis) => [
      for (final k in (kpis! as List)) [(k as List)[0] as String, '${k[1]}']
    ];

void main() {
  final f = File('test/vecteurs/factures_fournisseurs.json');
  if (!f.existsSync()) {
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-m7-achats.js`');
  }
  final doc = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();

  test('le jeu : indicateurs et bandeau d\'anomalie = ceux de l\'écran réel', () {
    final j = (doc['jeu']! as Map).cast<String, Object?>();
    final rendu = ((j['rendu']! as Map)['etat']! as Map).cast<String, Object?>();
    final rows = liste(j['factures']);
    expect(kpisTexte(kpisFacturesFournisseurs(rows)), attendus(rendu['kpis']));
    expect(noteAnomalies(rows), rendu['noteTexte']);
  });

  group('indicateurs et poids sur le BFR', () {
    for (final c in liste(doc['cas'])) {
      test('${c['nom']}', () {
        final rows = liste(c['factures']);
        final rendu = (c['rendu']! as Map).cast<String, Object?>();
        final bfr = (c['bfr']! as Map).cast<String, Object?>();
        // La dette que lit le BFR : montant facturé de toute pièce ni payée ni soldée.
        expect(detteFournisseurs(rows), (bfr['dettes']! as num).toDouble());
        expect(nbDettesFournisseurs(rows), bfr['nbDettes']);
        if (rendu['erreur'] != null) {
          // Pièce « soldee » : la maquette ne sait pas peindre le tableau (E21). Le Dart l'affiche tel quel ; l'indicateur de l'écran compte
          // la pièce comme impayée alors que le BFR ne la compte pas.
          expect(rows.any((r) => r['statutPaiement'] == 'soldee'), isTrue);
          expect(kpisFacturesFournisseurs(rows).impayees,
              isNot(detteFournisseurs(rows)));
          return;
        }
        final etat = (rendu['etat']! as Map).cast<String, Object?>();
        expect(kpisTexte(kpisFacturesFournisseurs(rows)), attendus(etat['kpis']));
        expect(noteAnomalies(rows), etat['noteTexte']);
        // Hors « soldee », écran et BFR comptent la même chose.
        expect(kpisFacturesFournisseurs(rows).impayees, detteFournisseurs(rows));
      });
    }
    test('« payée » sort des impayées ; « partielle » compte pour son montant entier',
        () {
      final rows = [
        {'statutPaiement': 'payee', 'montantFacture': 1000},
        {'statutPaiement': 'partielle', 'montantFacture': 3000},
        {'statutPaiement': 'impayee', 'montantFacture': 500},
      ];
      expect(kpisFacturesFournisseurs(rows).impayees, 3500);
      expect(detteFournisseurs(rows), 3500);
    });
  });

  group('modifier une facture', () {
    for (final c in liste(doc['editions'])) {
      test('${c['nom']}', () {
        final saisie = {
          ...(c['valeursInitiales']! as Map).cast<String, Object?>(),
          ...(c['saisie']! as Map).cast<String, Object?>(),
        };
        final diff = (c['diff']! as Map).cast<String, Object?>();
        final messages = liste(c['messages']);
        if (messages.isNotEmpty && messages.first['type'] == 'error') {
          expect(diff, isEmpty);
          expect(() => patchEditionFacture(saisie),
              throwsA(isA<FormulaireInvalide>()));
          return;
        }
        final avant = (c['avant']! as Map).cast<String, Object?>();
        final patch = patchEditionFacture(saisie);
        memes({...avant, ...patch}, {...avant, ...diff}, 'fiche');
        // Les champs « montant » et « numero » ne sont pas ceux de la fiche : le montant facturé NE BOUGE PAS.
        expect(patch.containsKey('montantFacture'), isFalse);
        expect(patch.containsKey('numeroFournisseur'), isFalse);
      });
    }
  });

  test('le formulaire de la maquette propose « Sélectionner », Impayée, Partielle, Payée', () {
    final e = liste(doc['editions']).first;
    expect(e['optionsReglement'], ['— Sélectionner —', 'Impayée', 'Partielle', 'Payée']);
    expect(e['actionsLigne'], ['Modifier', 'Archiver']);
  });
}
