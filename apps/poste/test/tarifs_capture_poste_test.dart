import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// CAPTURE EXHAUSTIVE DES PRIX du poste, par code et par voie de tarification (lot T6, étape 3) : pour CHAQUE code des trois espaces (grille, actes, analyses) et pour les voies de
/// prescription d'actes et d'analyses, de soins, d'imagerie, de caisse manuelle et de certificats, relève le prix que la voie donne RÉELLEMENT, en appelant ses points d'entrée
/// publics (`csPrescrire`, `csPrescrireSoins`, `csCreerDemandesImagerie`, `csTarifPrix`). Les deux colonnes sont relevées (patient non assuré, patient assuré à carte valide).
/// Même méthode que `prototype_html/build/capture-prix.js` (maquette, lot T1) : le relevé d'AVANT le référentiel (`test/fixtures/tarifs/prix-avant-t6.json`, tiré de l'arbre du lot T6 étape 2 par ce même harnais) est comparé au relevé d'APRÈS.

typedef M = Map<String, Object?>;

void main() {
  test('capture des prix', () {
    final maintenant = DateTime(2026, 10, 30, 10);
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    final s = StockMagasin(m, () => maintenant);
    const session = SessionCs(role: 'admin', fonction: 'direction');
    final ref = (jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>();
    final grille = [for (final t in m.collection('catalogueTarifs').toutes) '${t['code']}'];
    final actes = [for (final a in m.collection('actes').toutes) '${a['code']}'];
    final analyses = [for (final a in (ref['analyses'] as List)) '${(a as Map)['code']}'];
    final codes = {...grille, ...actes, ...analyses}.toList()..sort();
    final pat = m.collection('patients').actives.where((p) => p['externe'] != true).toList();
    final ptNon = pat.firstWhere((p) => !csVrai(p['assureur']));
    final ptAss = pat.firstWhere((p) => csVrai(p['assureur']) && carteValide(p, m.collection('couverturesAssurance').toutes, maintenant.toIso8601String()) && ((p['tauxPriseEnCharge'] as num?) ?? 0) > 0);
    final voies = <String, Map<String, Object?>>{};
    Map<String, Object?> v(String n) => voies.putIfAbsent(n, () => {});
    Object? essai(Object? Function() f) {
      try {
        return f();
      } catch (e) {
        return 'ERREUR:${'$e'.length > 80 ? '$e'.substring(0, 80) : '$e'}';
      }
    }

    for (final c in codes) {
      for (final assure in [false, true]) {
        final pt = assure ? ptAss : ptNon;
        final col = assure ? 1 : 0;
        void poser(String voie, Object? x) {
          final l = (v(voie)[c] ??= <Object?>[null, null]) as List;
          l[col] = x;
        }

        final pr = csTarifPrix(s, c, assure);
        poser('accesseur.csTarifPrix', [pr.montant, pr.tarif, pr.motif]);
        poser('prescrire.acte', essai(() {
          final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'CAPTURE', 'diagnostic': 'capture', 'actes': [c]}, session);
          final l = ((r.facture['lignes'] as List?) ?? const []).cast<M>().where((x) => x['acteCode'] == c).firstOrNull;
          return l == null ? 'AUCUNE LIGNE' : [l['prixUnitaire'], l['montant'], l['partAssureur'], l['partPatient']];
        }));
        poser('prescrire.analyse', essai(() {
          final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'CAPTURE', 'diagnostic': 'capture', 'analyses': [c]}, session);
          final a = ((r.ordonnance['analyses'] as List?) ?? const []).cast<M>().where((x) => x['code'] == c).firstOrNull;
          final l = ((r.facture['lignes'] as List?) ?? const []).cast<M>().where((x) => x['demandeId'] != null || x['categorie'] == 'analyse').firstOrNull;
          return a == null ? 'AUCUNE ANALYSE' : [a['prix'], l?['prixUnitaire'], l?['partAssureur']];
        }));
        poser('soins', essai(() {
          final p = csPrescrireSoins(s, {'patientCode': pt['code'], 'prescripteurId': null, 'actes': [c], 'secteurDestinataire': 'salle_soins'});
          final l = ((p['lignes'] as List?) ?? const []).cast<M>().firstOrNull;
          return l == null ? 'AUCUNE LIGNE' : [l['prix'], l['tarif'], l['motifTarif'], l['prixAValider'], l['libelle'], l['famille']];
        }));
        poser('imagerie', essai(() {
          final r = csCreerDemandesImagerie(s, pt, [c], maintenant.toIso8601String(), {'prescripteur': 'CAPTURE', 'indication': 'capture'});
          return [r.demandes.first['prix'], r.demandes.first['motifTarif']];
        }));
      }
    }
        // APRÈS : les listes que les écrans lisent maintenant, par l'accesseur du référentiel (version en vigueur le jour de la pièce).
    voies['caisse.acte'] = {'liste': [for (final a in TarifsPoste.actes(m, aujourdhui: maintenant)) if (a['prix'] != null) [a['code'], a['libelle'], a['prix']]]};
    voies['caisse.analyse'] = {'liste': [for (final a in TarifsPoste.analyses(m, aujourdhui: maintenant)) if (a['prix'] != null) [a['code'], a['designation'], a['prix']]]};
    voies['caisse.hospitalisation'] = {'liste': [for (final t in TarifsPoste.typesChambre(m, aujourdhui: maintenant)) [t['id'], t['label'], t['tarif']]]};
    voies['certificats'] = {
      for (final t in m.collection('typesPiece').toutes)
        '${t['code'] ?? t['id']}': () {
          final e = TarifsPoste.entreeGrille(m, t['tarifCode'], aujourdhui: maintenant);
          return e == null ? [t['tarifCode'], null] : [t['tarifCode'], e['prixNonAssure'], e['assurable'], e['libelle']];
        }()
    };
    // --- La comparaison avec le relevé d'AVANT le référentiel (versionné : `test/fixtures/tarifs/prix-avant-t6.json`) -----------------------------------------------------------
    final avant = (jsonDecode(File('test/fixtures/tarifs/prix-avant-t6.json').readAsStringSync()) as Map).cast<String, Object?>();
    // LOT TARIF-FIX : un code de plus, CERT-CA « Certificat d’aptitude » (décision de la Direction du 15/11/2026, deux certificats distincts) ; le relevé d'avant ne le porte pas.
    expect(codes.length, (avant['codes'] as num) + 1, reason: 'mêmes codes, mêmes espaces (grille, actes, analyses), plus CERT-CA');
    expect(codes.contains('CERT-CA'), isTrue);
    final apres = jsonDecode(jsonEncode({for (final e in voies.entries) e.key: e.value})) as Map;
    // Les codes de GRILLE dont le prix lu change PAR CONSTRUCTION (décision T2 du 11/11) : la ligne LABO de la grille imprimée est fusionnée avec l'analyse de même libellé, dont le prix
    // FACTURÉ aujourd'hui est la version 1 ; le prix de la grille devient la version 2 PROPOSÉE. Aucune voie ne les adresse (les soins sont des actes AMI, l'imagerie des examens IMG).
    final attendus = {
      for (final x in m.collection('versionsTarif').toutes)
        if (x['origine'] == 'semence-grille') '${m.collection('tarifs').parId(x['code'])?['codeGrille']}'
    };
    expect(attendus.length, 39);
    final inattendus = <String>[];
    final attendusVus = <String, int>{};
    // LOT TARIF-FIX : la prescription d'actes et d'analyses ne rend plus JAMAIS un zéro silencieux. Sur ces deux voies, une ligne d'avant à 0 devient un prix strictement positif
    // (le référentiel unique est lu hors de l'espace de la voie : certificat, consultation…) ou un refus nommé « Prix à définir » ; toute ligne d'avant tarifée reste IDENTIQUE.
    final zerosLeves = <String, int>{};
    bool zero(Object? x) => x is List && x.isNotEmpty && x.first == 0;
    bool leve(Object? x) => (x is List && x.isNotEmpty && x.first is num && (x.first as num) > 0) || (x is String && x.startsWith('ERREUR:Prix à définir'));
    (avant['voies'] as Map).forEach((voie, anciennes) {
      for (final c in (anciennes as Map).keys) {
        final ancien = jsonEncode(anciennes[c]);
        final nouveau = jsonEncode((apres[voie] as Map)[c]);
        if (ancien == nouveau) continue;
        if ((voie == 'prescrire.acte' || voie == 'prescrire.analyse') && anciennes[c] is List && ((apres[voie] as Map)[c]) is List) {
          final a = anciennes[c] as List, n = (apres[voie] as Map)[c] as List;
          var toutLeve = true;
          for (var i = 0; i < a.length; i++) {
            if (jsonEncode(a[i]) == jsonEncode(n[i])) continue;
            if (!(zero(a[i]) && leve(n[i]))) toutLeve = false;
          }
          if (toutLeve) {
            zerosLeves[voie as String] = (zerosLeves[voie] ?? 0) + 1;
            continue;
          }
        }
        if (attendus.contains(c)) {
          attendusVus[voie as String] = (attendusVus[voie] ?? 0) + 1;
        } else {
          inattendus.add('$voie $c : $ancien -> $nouveau');
        }
      }
    });
    expect(inattendus, isEmpty, reason: '0 écart INATTENDU : chaque prix lu par chaque voie est celui d\'avant le référentiel');
    // Les écarts ATTENDUS ne touchent que les trois voies qui lisent l'espace des codes de grille.
    expect(attendusVus.keys.toSet(), {'accesseur.csTarifPrix', 'soins', 'imagerie'});
    expect(attendusVus.values.toSet(), {39}, reason: 'les 39 lignes LABO de la grille fusionnées avec leur analyse, sur chacune des trois voies');
    // La caisse manuelle et les certificats : IDENTIQUES au franc près. La prescription d'actes et d'analyses : identique partout où elle était tarifée ; ses zéros sont levés.
    for (final voie in ['caisse.acte', 'caisse.analyse', 'caisse.hospitalisation', 'certificats']) {
      expect(jsonEncode((avant['voies'] as Map)[voie]), jsonEncode(apres[voie]), reason: voie);
    }
    expect(zerosLeves['prescrire.acte'] ?? 0, greaterThan(150), reason: 'les codes qui donnaient 0 à la prescription d’actes ne le donnent plus');
    for (final voie in ['prescrire.acte', 'prescrire.analyse']) {
      for (final e in (apres[voie] as Map).entries) {
        for (final x in e.value as List) {
          expect(zero(x), isFalse, reason: '$voie ${e.key} : jamais une ligne à 0');
        }
      }
    }
    // Le détail d'un écart attendu : le prix lu est celui que la caisse facturait pour l'analyse (version 1), non plus le prix imprimé de la grille.
    final akop = (apres['accesseur.csTarifPrix'] as Map)['LAB-AKOP'] as List;
    expect([(akop[0] as List)[0], (akop[1] as List)[0]], [2000, 2000]);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
