// Rejoue les vecteurs des ÉTATS FINANCIERS de M12 (les cinq feuillets de la liasse déposée), tirés de l'écran réel de la maquette
// (prototype_html/build/vecteurs-m12-etats.js). Le jeu est celui du poste, l'horloge celle du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
F carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<F> actives(List<F> l) => [for (final x in l) if (x['statut'] != 'archive') x];
List<List<String>> lignes(Object? t) => [for (final l in (t as List)) [for (final c in (l as List)) nt(c)]];

/// La cellule d'un montant : vide pour un sous-total, « — » quand le journal ne porte rien, sinon le montant.
String cellule(double? v, {bool total = false}) => total ? '' : (v == null ? '—' : nt(money(v, avecDevise: false)));

void main() {
  final f = File('test/vecteurs/etats.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-m12-etats.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final L = cpcLiasseDonnees;
  final exos = jeu('exercices');
  final ecr = actives(jeu('ecritures'));
  final courant = cpcSourceExercice(exos, ecr, 2026);

  group('la liasse déposée est ENGENDRÉE depuis la maquette, jamais recopiée', () {
    test('six écarts internes, le dépôt du 15/05/2026 (BK505416), N = 2025 et N-1 = 2024', () {
      expect(L.ecarts.length, 6);
      expect(L.ecarts.map((e) => e['cle']), ['cafg', 'bf', 'zb', 'fluxOp', 'fluxFin', 'tresorerie']);
      expect([L.depot['code'], L.depot['dateDepot'], L.exerciceN, L.exerciceN1], ['BK505416', '2026-05-15', 2025, 2024]);
      expect(L.bilanActif.length, 29);
      expect(L.bilanPassif.length, 28);
      expect(L.resultat.length, 42);
      expect(L.flux.length, 30);
      expect(L.synthese.length, 56);
      expect(liste(v['ecarts']).map((e) => [e['cle'], e['titre'], e['constat'], e['lecture']]).toList(), L.ecarts.map((e) => [e['cle'], e['titre'], e['constat'], e['lecture']]).toList(), reason: 'la liasse engendrée est celle que lit la maquette');
    });
    test('le bilan déposé s\'équilibre : total actif = total passif ; le résultat et le CA déposés sont ceux des indicateurs', () {
      expect(L.ligne(L.bilanActif, 'BZ')!['net'], L.ligne(L.bilanPassif, 'DZ')!['net']);
      final k = liste(carte(v['jeu'])['entete'] is Map ? carte(carte(v['jeu'])['entete'])['kpis'] : []);
      expect(nt(money(L.ligne(L.resultat, 'XB')!['n'])), nt(k[0]['valeur']));
      expect(nt(money(L.ligne(L.resultat, 'XI')!['n'])), nt(k[1]['valeur']));
      expect(nt(money(L.ligne(L.bilanActif, 'BZ')!['net'])), nt(k[2]['valeur']));
      expect('${L.ecarts.length}', k[3]['valeur']);
    });
    test('la MARGE COMMERCIALE est NULLE au dépôt : la confirmation documentaire de RG-02 (médicaments au prix d\'achat, sans marge)', () {
      expect(L.ligne(L.resultat, 'XA')!['n'], 0);
      expect(L.ligne(L.resultat, 'XA')!['n1'], 0);
    });
  });

  group('l\'exercice en cours est CALCULÉ depuis le journal — et reste vide là où il ne porte rien', () {
    final jeuEcran = carte(v['jeu']);
    List<List<String>> table(String onglet, int i) => lignes(liste(carte(jeuEcran['onglets'])[onglet] is Map ? carte(carte(jeuEcran['onglets'])[onglet])['tables'] : [])[i]['lignes']);

    test('bilan, actif : la colonne « Exercice en cours » de chaque ligne (journal 2026, comptes de tiers du côté de leur sens)', () {
      final att = table('Bilan', 0);
      expect(att.length, L.bilanActif.length);
      for (var i = 0; i < att.length; i++) {
        final l = L.bilanActif[i];
        expect(att[i][0], l['ref']);
        expect(att[i][7], cellule(cpcCalculActif(l, courant), total: l['t'] != null), reason: '${l['ref']} ${l['libelle']}');
      }
    });
    test('bilan, passif', () {
      final att = table('Bilan', 1);
      expect(att.length, L.bilanPassif.length);
      for (var i = 0; i < att.length; i++) {
        final l = L.bilanPassif[i];
        expect(att[i][5], cellule(cpcCalculPassif(l, courant), total: l['t'] != null), reason: '${l['ref']} ${l['libelle']}');
      }
    });
    test('compte de résultat : les charges en NÉGATIF, convention du formulaire', () {
      final att = table('Compte de résultat', 0);
      for (var i = 0; i < att.length; i++) {
        final l = L.resultat[i];
        expect(att[i][6], cellule(cpcCalculResultat(l, courant), total: l['t'] != null), reason: '${l['ref']} ${l['libelle']}');
      }
      expect(cpcCalculResultat(L.ligne(L.resultat, 'RA')!, courant)! < 0, true);
    });
    test('note 11 « Disponibilités » : le solde au débit, négatif compris ; la variation en % se calcule sur |N-1|', () {
      final att = table('Disponibilités', 0);
      for (var i = 0; i < att.length; i++) {
        final l = L.dispoLignes[i];
        expect(att[i][4], cellule(cpcCalculDisponibilite(l, courant), total: l['t'] != null), reason: '${l['libelle']}');
        final p = cpcVariationDisponibilite(l);
        expect(att[i][3], p == null ? '' : nt(pourcent(p, 2)), reason: '${l['libelle']}');
      }
      expect(cpcCalculDisponibilite(L.dispoLignes.first, courant)! < 0, true);
    });
    test('« non amorcé » n\'est pas zéro : une ligne que le journal n\'alimente pas reste « — »', () {
      expect(cpcSoldeDesComptes(null, 'debit', courant), isNull);
      expect(cpcSoldeDesComptes(const [], 'debit', courant), isNull);
      expect(cpcSoldeDesComptes(['999'], 'debit', courant), isNull);
      expect(cpcSoldeDesComptes(['571'], 'debit', const []), isNull);
    });
  });

  group('un compte de tiers change de côté selon son sens', () {
    test('un client CRÉDITEUR sort du côté du passif, un fournisseur DÉBITEUR du côté de l\'actif — jamais en négatif', () {
      final src = [
        {'compte': '411000', 'debit': 0, 'credit': 123000},
        {'compte': '401000', 'debit': 55000, 'credit': 0},
      ];
      final clients = {'comptes': ['411']};
      final fournisseurs = {'comptes': ['401']};
      expect(cpcCalculActif(clients, src), isNull, reason: 'solde créditeur : pas à l\'actif');
      expect(cpcCalculPassif(clients, src), 123000);
      expect(cpcCalculActif(fournisseurs, src), 55000);
      expect(cpcCalculPassif(fournisseurs, src), isNull, reason: 'solde débiteur : pas au passif');
    });
    test('les lignes de la maquette avec un client créditeur et un fournisseur débiteur', () {
      final src = [
        ...courant,
        {'compte': '411000', 'debit': 0, 'credit': 123000},
        {'compte': '571000', 'debit': 123000, 'credit': 0},
        {'compte': '401000', 'debit': 55000, 'credit': 0},
        {'compte': '571000', 'debit': 0, 'credit': 55000},
      ];
      final t = (carte(v['tiers'])['tables'] as List);
      final actif = lignes(t[0]), passif = lignes(t[1]);
      for (var i = 0; i < actif.length; i++) {
        final l = L.bilanActif[i];
        expect(actif[i][7], cellule(cpcCalculActif(l, src), total: l['t'] != null), reason: 'actif ${l['ref']}');
      }
      for (var i = 0; i < passif.length; i++) {
        final l = L.bilanPassif[i];
        expect(passif[i][5], cellule(cpcCalculPassif(l, src), total: l['t'] != null), reason: 'passif ${l['ref']}');
      }
    });
  });

  group('l\'exercice précédent tiré du journal (colonne N-1) quand il n\'a pas été déposé', () {
    test('un journal qui porte 2025 : la colonne « Exercice 2025 (journal) » paraît, calculée comme celle de l\'exercice choisi', () {
      final n1 = [
        for (final x in [
          ['571000', 900000, 0],
          ['706000', 0, 900000],
          ['521000', 400000, 0],
          ['411000', 0, 400000],
          ['401000', 0, 250000],
          ['604100', 250000, 0]
        ])
          {'compte': x[0], 'debit': x[1], 'credit': x[2], 'statut': 'validee', 'date': '2025-03-01'}
      ];
      final att = (carte(v['avecN1'])['tables'] as List);
      final actif = lignes(att[0]), passif = lignes(att[1]);
      for (var i = 0; i < actif.length; i++) {
        final l = L.bilanActif[i];
        expect(actif[i][8], l['t'] != null ? '' : cellule(cpcCalculActif(l, n1)), reason: 'actif N-1 ${l['ref']}');
      }
      for (var i = 0; i < passif.length; i++) {
        final l = L.bilanPassif[i];
        expect(passif[i][6], l['t'] != null ? '' : cellule(cpcCalculPassif(l, n1)), reason: 'passif N-1 ${l['ref']}');
      }
      final entetes = (carte(v['avecN1'])['entetes'] as List);
      expect((entetes[0] as List).last, 'EXERCICE 2025 (JOURNAL)');
    });
    test('le jeu 2026 n\'a pas d\'exercice précédent au journal (2025 est clos par la liasse) : aucune colonne', () {
      expect(cpcSourceExercice(exos, ecr, 2025), isEmpty);
      expect((carte(carte(carte(v['jeu'])['onglets'])['Bilan'])['tables'] as List).first['entetes'], isNot(contains('EXERCICE 2025 (JOURNAL)')));
    });
  });

  group('les écarts internes du document sont CONSERVÉS, non arbitrés', () {
    test('trois écarts au tableau des flux, quatre à la fiche de synthèse — nommés comme à l\'écran', () {
      final fl = carte(carte(v['jeu'])['onglets'])['Tableau des flux de trésorerie'] as Map;
      final tabEcarts = lignes((fl['tables'] as List)[1]['lignes']);
      expect(tabEcarts.map((l) => l[0]), [for (final e in L.ecartsDe(['bf', 'zb', 'cafg'])) nt(e['titre'])]);
      expect(tabEcarts.map((l) => l[1]), [for (final e in L.ecartsDe(['bf', 'zb', 'cafg'])) nt(e['constat'])]);
      final sy = carte(carte(v['jeu'])['onglets'])['Fiche de synthèse'] as Map;
      final tabSy = lignes((sy['tables'] as List)[1]['lignes']);
      expect(tabSy.map((l) => l[2]), [for (final e in L.ecartsDe(['cafg', 'fluxOp', 'fluxFin', 'tresorerie'])) nt(e['lecture'])]);
    });
    test('les chiffres du document ne sont PAS corrigés : ZB porte −18 108 317 quoi qu\'en dise la somme de ses composantes', () {
      expect(L.ligne(L.flux, 'ZB')!['n'], -18108317);
      expect(L.ligne(L.flux, 'ZH')!['n'], 6300639);
      expect(L.ecart('tresorerie')!['constat'], contains('450 F d’écart'));
    });
  });
}
