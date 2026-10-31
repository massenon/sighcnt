// Règles de la console du poste mère (lot MERE c) : assistant en étapes, compatibilité de schéma, registre borné, import de migration tout ou rien.
// L'import est rejoué sur l'inventaire SAGE RÉEL du dépôt (184 articles, 12 080 unités), pas sur un échantillon écrit pour le test.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/donnees_sage.dart';
import 'package:test/test.dart';

String csvSage() {
  final j = (jsonDecode(donneesSageJson) as Map).cast<String, Object?>();
  final out = StringBuffer('reference;designation;quantite;pr_unitaire;categorie\n');
  for (final a in (j['articles'] as List)) {
    final m = (a as Map).cast<String, Object?>();
    final d = '${m['designation']}'.contains(';') ? '"${m['designation']}"' : '${m['designation']}';
    out.writeln('${m['code']};$d;${m['quantite']};${m['prUnitaire']};${m['categorie']}');
  }
  return out.toString();
}

void main() {
  group('assistant de mise en service', () {
    test('cinq étapes numérotées, dans l’ordre du document', () {
      expect(mrcEtapes.map((e) => e.numero), [1, 2, 3, 4, 5]);
      expect(mrcEtapes.map((e) => e.id), ['identite', 'administrateur', 'jeu_depart', 'activation', 'appairage']);
    });

    test('l’état se lit sur les constats : fait, à faire, non vérifié ; le premier appairage est bloqué tant que la mère n’est pas active', () {
      final e = mrcEtatsEtapes({'identite': null, 'administrateur': true, 'jeu_depart': false, 'activation': false, 'appairage': false});
      expect(e['identite'], MrcEtatEtape.nonVerifiee, reason: 'sans source, jamais « fait »');
      expect(e['administrateur'], MrcEtatEtape.fait);
      expect(e['jeu_depart'], MrcEtatEtape.aFaire);
      expect(e['appairage'], MrcEtatEtape.bloquee);
      expect(mrcEtapeOuvrable('appairage', e), isFalse);
      expect(mrcPrealablesManquants('appairage', e).map((x) => x.libelle), ['Activation du mode mère']);
      expect(mrcEtapeOuvrable('activation', e), isTrue);
    });

    test('reprenable : la progression ne dépend que des constats', () {
      final a = mrcEtatsEtapes({'identite': true, 'administrateur': true, 'jeu_depart': true, 'activation': true, 'appairage': false});
      expect(mrcProgression(a), (faites: 4, total: 5));
      expect(mrcEtatsEtapes({'identite': true, 'administrateur': true, 'jeu_depart': true, 'activation': true, 'appairage': false}), a);
      expect(mrcEtapeOuvrable('appairage', a), isTrue);
    });

    test('un constat « fait » prime sur un prérequis non fait (on ne contredit pas un fait constaté)', () {
      final e = mrcEtatsEtapes({'activation': false, 'appairage': true});
      expect(e['appairage'], MrcEtatEtape.fait);
    });

    test('la confirmation nommée est exacte ou refusée, jamais approchée', () {
      final jeu = mrcEtape('jeu_depart')!;
      expect(mrcConfirmationExacte(jeu, 'vider l’activité'), isTrue);
      expect(mrcConfirmationExacte(jeu, '  VIDER   L’ACTIVITÉ '), isTrue);
      expect(mrcConfirmationExacte(jeu, 'vider'), isFalse);
      expect(mrcConfirmationExacte(jeu, ''), isFalse);
      expect(mrcConfirmationExacte(mrcEtape('identite')!, ''), isTrue, reason: 'une étape sans phrase n’en exige pas');
    });
  });

  group('compatibilité de schéma', () {
    test('trop ancien : refusé ; égal : à jour ; plus récent : signalé ; inconnu : ne rassure pas', () {
      expect(mrcCompatibilite(schemaMere: 68, schemaAppareil: 67), MrcCompat.tropAncien);
      expect(mrcCompatibilite(schemaMere: 68, schemaAppareil: 68), MrcCompat.aJour);
      expect(mrcCompatibilite(schemaMere: 68, schemaAppareil: 69), MrcCompat.plusRecent);
      expect(mrcCompatibilite(schemaMere: 68, schemaAppareil: null), MrcCompat.inconnu);
      expect(mrcCompatibilite(schemaMere: null, schemaAppareil: 68), MrcCompat.inconnu);
    });

    test('le refus nomme le code du protocole, l’appareil et les deux versions', () {
      final m = mrcMotifRefusSchema('Caisse', 66, 68);
      expect(m, contains(CodeSync.schemaIncompatible));
      expect(m, allOf(contains('Caisse'), contains('66'), contains('68')));
    });
  });

  group('planificateur et alertes', () {
    test('le registre est borné à 500 et garde les plus récentes', () {
      final l = List.generate(620, (i) => i);
      final b = mrcBornerRegistre(l);
      expect(b.length, 500);
      expect(b.first, 0);
      expect(b.last, 499);
      expect(mrcBornerRegistre([1, 2, 3]), [1, 2, 3]);
    });

    test('alerte ouverte : attention et alerte ; inconnu est listé sans compter', () {
      expect(mrcAlerteOuverte('alerte'), isTrue);
      expect(mrcAlerteOuverte('attention'), isTrue);
      expect(mrcAlerteOuverte('ok'), isFalse);
      expect(mrcAlerteOuverte('inconnu'), isFalse);
      expect(mrcPrioriteAlerte('alerte'), 'Critique');
      expect(mrcPrioriteAlerte('attention'), 'À surveiller');
      expect(mrcPrioriteAlerte('inconnu'), 'Inconnue');
    });

    test('poste joignable : dernier contact dans la fenêtre, jamais vu = non', () {
      final n = DateTime(2026, 10, 31, 10);
      expect(mrcPosteJoignable(n.subtract(const Duration(minutes: 5)), n), isTrue);
      expect(mrcPosteJoignable(n.subtract(const Duration(minutes: 31)), n), isFalse);
      expect(mrcPosteJoignable(null, n), isFalse);
    });

    test('valeur sans source : « non disponible », jamais un zéro', () {
      const v = MrcValeur<int>.indisponible('aucune source');
      expect(v.disponible, isFalse);
      expect(v.texte(), 'non disponible');
      expect(const MrcValeur.de(0).texte(), '0');
    });
  });

  group('import de migration (inventaire SAGE réel)', () {
    test('le fichier SAGE complet est accepté : 184 articles, 12 080 unités, aucune ligne perdue', () {
      final a = mrcAnalyserImport(csvSage(), mrcProfilSage);
      expect(a.refus, isEmpty, reason: a.refus.join('\n'));
      expect(a.lignes.length, 184);
      expect(a.lignes.fold<int>(0, (s, l) => s + (l['quantite'] as int)), 12080);
    });

    test('les fiches portent source, lot et validateur ; le prix de vente est le prix d’achat (RG-02) ; aucun seuil inventé', () {
      final a = mrcAnalyserImport(csvSage(), mrcProfilSage);
      final f = mrcFichesProduits(a, lot: 'IMPORT-SAGE-20261031', date: '2026-10-31', validePar: 'TAKI Alimatou');
      expect(f.length, 184);
      for (final x in f) {
        expect(x['source'], 'SAGE_100_GESTION_COMMERCIALE_15.01');
        expect(x['lotImport'], 'IMPORT-SAGE-20261031');
        expect(x['validePar'], 'TAKI Alimatou');
        expect(x['prixVente'], x['prixAchat']);
        expect(x.containsKey('seuilAlerte'), isFalse);
      }
      final aba = f.firstWhere((x) => x['code'] == 'ABA');
      expect(aba['valoriseSage'], isFalse, reason: 'P.R. nul : article non valorisé, pas valorisé d’office');
    });

    test('une ligne fautive est NOMMÉE (numéro de fichier, colonne, valeur, motif) et rien n’est accepté', () {
      const t = 'reference;designation;quantite;pr_unitaire;categorie\nA1;GANTS;10;100;conso_medical\nA2;SERINGUE;-3;50;conso_medical\nA3;COTON;5;abc;conso_medical\n';
      final a = mrcAnalyserImport(t, mrcProfilSage);
      expect(a.accepte, isFalse);
      expect(a.lignes, isEmpty, reason: 'tout ou rien');
      expect(a.refus.map((r) => (r.ligne, r.colonne)), [(3, 'quantite'), (4, 'pr_unitaire')]);
      expect(a.refus.first.motif, contains('RG-03'));
      expect(a.refus.first.toString(), contains('Ligne 3'));
    });

    test('catégorie inconnue, référence en double, référence déjà au catalogue : refusées en les nommant', () {
      const t = 'reference;designation;quantite;pr_unitaire;categorie\nA1;GANTS;1;10;divers\nA2;X;1;1;medicament\nA2;Y;1;1;medicament\nPRD1;Z;1;1;medicament\n';
      final a = mrcAnalyserImport(t, mrcProfilSage, codesExistants: {'PRD1'});
      expect(a.refus.map((r) => '${r.ligne}:${r.colonne}'), ['2:categorie', '4:reference', '5:reference']);
      expect(a.refus[1].motif, contains('ligne 3'));
      expect(a.refus[2].motif, contains('rien n’est écrasé'));
    });

    test('en-tête : colonne absente ou inconnue refusée à la ligne 1 ; fichier vide refusé', () {
      expect(mrcAnalyserImport('reference;designation\nA;B\n', mrcProfilSage).refus.first.ligne, 1);
      expect(mrcAnalyserImport('reference;designation;quantite;pr_unitaire;categorie;prix_libre\nA;B;1;1;reactif;3\n', mrcProfilSage).refus.single.colonne, 'prix_libre');
      expect(mrcAnalyserImport('', mrcProfilSage).accepte, isFalse);
      expect(mrcAnalyserImport('reference;designation;quantite;pr_unitaire;categorie\n', mrcProfilSage).accepte, isFalse);
    });

    test('guillemets, séparateur dans un champ, fin de ligne Windows, BOM et colonne unité facultative', () {
      const t = '﻿reference;designation;quantite;pr_unitaire;categorie;unite\r\nA1;"GANTS; TAILLE ""M""";10;1 250,5;conso_medical;Boîte\r\n';
      final a = mrcAnalyserImport(t, mrcProfilSage);
      expect(a.refus, isEmpty, reason: a.refus.join());
      expect(a.lignes.single['designation'], 'GANTS; TAILLE "M"');
      expect(a.lignes.single['pr_unitaire'], 1250.5);
      expect(a.lignes.single['unite'], 'Boîte');
    });

    test('la référence du lot est datée et ne se répète pas', () {
      final d = DateTime(2026, 10, 31);
      expect(mrcReferenceLot(mrcProfilSage, d, const []), 'IMPORT-SAGE-20261031');
      expect(mrcReferenceLot(mrcProfilSage, d, const ['IMPORT-SAGE-20261031']), 'IMPORT-SAGE-20261031-2');
      expect(mrcReferenceLot(mrcProfilSage, d, const ['IMPORT-SAGE-20261031', 'IMPORT-SAGE-20261031-2']), 'IMPORT-SAGE-20261031-3');
    });
  });
}
