// Rejoue les vecteurs du BFR et du coût à l'activité de M12, tirés du moteur `SIGH.bfr` et des écrans réels de la maquette
// (prototype_html/build/vecteurs-m12-bfr.js). Le jeu est celui du poste, l'horloge celle du 30/10/2026 10 h.
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

void main() {
  final f = File('test/vecteurs/bfr.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-m12-bfr.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final mo = carte(v['moteur']);
  final auj = DateTime(2026, 10, 30, 10);
  final factures = actives(jeu('factures'));
  final produits = actives(jeu('produits'));
  final fournisseurs = actives(jeu('facturesFournisseurs'));
  final objectifs = jeu('objectifsPilotage');

  CpcBfr bfr({Object? fin, int? jours, List<F>? ff, List<F>? pr}) => cpcBfr(
      factures: factures, produits: pr ?? produits, facturesFournisseurs: ff ?? fournisseurs, auj: auj, fin: fin, jours: jours);

  void verifie(String nom, CpcBfr b) {
    final a = carte(mo[nom]);
    expect(b.creancesAssureurs, a['creancesAssureurs'], reason: '$nom : part assureur');
    expect(b.restesACharge, a['restesACharge'], reason: '$nom : restes à charge');
    expect(b.creances, a['creances'], reason: '$nom : créances');
    expect(b.stocks, a['stocks'], reason: '$nom : stocks');
    expect(b.dettes, a['dettes'], reason: '$nom : dettes');
    expect(b.bfr, a['bfr'], reason: '$nom : BFR');
    expect(b.caPeriode, a['caPeriode'], reason: '$nom : CA de la période');
    expect(b.bfrJours, a['bfrJours'], reason: '$nom : jours');
    expect(b.nbFacturesAssurees, a['nbFacturesAssurees'], reason: nom);
    expect(b.nbDettes, a['nbDettes'], reason: nom);
    expect(b.incomplet, (a['incomplet'] as List).cast<String>(), reason: '$nom : composants non amorcés');
    final fe = carte(a['fenetre']);
    expect([b.fenetre.debut, b.fenetre.fin, b.fenetre.jours], [fe['debut'], fe['fin'], fe['jours']], reason: '$nom : fenêtre');
    expect(b.arrete, a['arrete'], reason: nom);
  }

  group('le BFR : créances + stocks − dettes fournisseurs, jamais saisi', () {
    test('la fenêtre par défaut (90 jours jusqu\'à aujourd\'hui) et les trois composantes de la maquette', () {
      verifie('defaut', bfr(fin: '2026-10-30', jours: 90));
      verifie('sansOptions', bfr());
      expect(bfr(fin: '2026-10-30', jours: 90).bfr, 5011584);
    });
    test('les quatre périodes du sélecteur : l\'encours ne bouge pas, seul le chiffre d\'affaires (donc le BFR en jours) suit la fenêtre', () {
      for (final (k, j) in [('j30', 30), ('j180', 180), ('j365', 365)]) {
        verifie(k, bfr(fin: '2026-10-30', jours: j));
      }
      expect(bfr(fin: '2026-10-30', jours: 30).bfr, bfr(fin: '2026-10-30', jours: 365).bfr, reason: 'un encours se lit à UNE DATE');
      expect(bfr(fin: '2026-10-30', jours: 30).bfrJours, isNull, reason: 'CA nul sur la période : « non calculable » n\'est pas zéro');
    });
    test('à une autre date : août, un futur sans activité, une période sans chiffre d\'affaires', () {
      verifie('aout', bfr(fin: '2026-08-16', jours: 90));
      verifie('futur', bfr(fin: '2027-03-01', jours: 90));
      verifie('sansCA', bfr(fin: '2024-01-01', jours: 30));
    });
    test('UN COMPOSANT NON AMORCÉ SE DIT : sans factures fournisseurs, le BFR est surestimé et le nomme', () {
      final b = bfr(ff: []);
      verifie('sansDettes', b);
      expect(b.incomplet, ['les factures fournisseurs']);
      expect(b.bfr, greaterThan(bfr().bfr), reason: 'amputé de ses dettes, il est SURESTIMÉ');
      verifie('sansRien', bfr(ff: [], pr: []));
      expect(bfr(ff: [], pr: []).incomplet, ['les produits du stock', 'les factures fournisseurs']);
    });
    test('« payée » et « soldée » désignent la même chose : aucune n\'est comptée comme dette', () {
      final ff = [
        {'montantFacture': 1000, 'statutPaiement': 'payee'},
        {'montantFacture': 2000, 'statutPaiement': 'soldee'},
        {'montantFacture': 4000, 'statutPaiement': 'en_attente'},
        {'montantFacture': 8000},
      ];
      final b = bfr(ff: ff);
      expect(b.dettes, 12000);
      expect(b.nbDettes, 2);
    });
    test('la valorisation du stock suit la méthode en vigueur (prix de vente ou CUMP)', () {
      final p = [
        {'stock': 10, 'prixVente': 100, 'cump': 60, 'prixAchat': 50}
      ];
      CpcBfr avec(MethodeValorisation m) =>
          cpcBfr(factures: const [], produits: p, facturesFournisseurs: const [{'montantFacture': 1}], auj: auj, methode: m);
      expect(avec(MethodeValorisation.prixVente).stocks, 1000);
      expect(avec(MethodeValorisation.cump).stocks, 600);
    });
  });

  group('l\'alerte de recouvrement ROUTE, elle ne décide pas du seuil', () {
    List<List<Object?>> vue(List<CpcAlerteRecouvrement> l) => [for (final a in l) [a.seuil, a.assureur, a.montant, a.nb, a.jours]];
    List<List<Object?>> att(String k) => [for (final a in liste(mo[k])) [a['seuil'], a['assureur'], a['montant'], a['nb'], a['jours']]];
    test('13 compagnies au-delà de 60 jours, du plus gros montant au plus petit', () {
      expect(vue(cpcAlertesRecouvrement(factures: factures, objectifs: objectifs, auj: auj, fin: '2026-10-30')), att('alertes'));
      expect(vue(cpcAlertesRecouvrement(factures: factures, objectifs: objectifs, auj: auj)), att('alertesSansFin'));
      expect(vue(cpcAlertesRecouvrement(factures: factures, objectifs: objectifs, auj: auj, fin: '2026-08-16')), att('alertesAout'));
    });
    test('le jour où la Direction passe de 60 à 45 ou 120 jours, le moteur n\'a rien à changer', () {
      List<F> avecCible(num c) => [for (final o in objectifs) if (o['id'] == 'creance_agee') {...o, 'cible': c} else o];
      expect(vue(cpcAlertesRecouvrement(factures: factures, objectifs: avecCible(45), auj: auj, fin: '2026-10-30')), att('alertesSeuil45'));
      expect(cpcAlertesRecouvrement(factures: factures, objectifs: avecCible(120), auj: auj, fin: '2026-10-30').length, (mo['alertesSeuil120'] as List).length);
    });
    test('une collection d\'objectifs vidée retombe sur la SEMENCE : l\'alerte lit son seuil sans cible arrêtée', () {
      expect(vue(cpcAlertesRecouvrement(factures: factures, objectifs: const [], auj: auj, fin: '2026-10-30')), att('alertesSemence'));
      expect(cpcObjectifsPilotage(const []).map((o) => o['id']).toList(), (mo['objectifsSemence'] as List).cast<String>());
      expect(carte(cpcObjectif(objectifs, 'creance_agee'))['cible'], carte(mo['creanceAgee'])['cible']);
    });
  });

  group('coût à l\'activité : marge sur consommables, jamais coût de revient', () {
    final mouvements = actives(jeu('mouvements'));
    final secteurs = secteursDesActes(jeu('actes'));
    final ecran = carte(v['ecranCout']);

    CpcCoutActivite calcul(String du, String au) =>
        cpcCoutActivite(factures: factures, mouvements: mouvements, produits: produits, du: du, au: au, secteurParCode: secteurs);

    List<String> lignes(CpcCoutActivite r) => [
          for (final g in r.lignes) '${g.groupe}:${nt(money(g.recette, avecDevise: false))}/${nt(money(g.cout, avecDevise: false))}'
        ];
    List<String> att(Object? groupes) => [for (final g in (groupes as List)) '${g[0]}:${nt(g[2])}/${nt(g[3])}'];

    test('la période par défaut (90 jours) : six groupes, lignes facturées, marge et taux de la maquette', () {
      final r = calcul('2026-08-01', '2026-10-30');
      final d = carte(ecran['defaut']);
      expect(lignes(r), att(d['groupes']));
      final k = (d['kpis'] as List).cast<List>();
      expect(nt(money(r.recette)), nt(k[0][1]));
      expect(nt(money(r.cout)), nt(k[1][1]));
      expect(nt(money(r.recette - r.cout)), nt(k[2][1]));
      expect(nt(pourcent((r.recette - r.cout) / r.recette * 100)), nt(k[3][1]));
      expect(k[3][2], 'hors personnel et charges de structure');
      for (final (i, g) in r.lignes.indexed) {
        final c = ((d['groupes'] as List)[i] as List);
        expect(nt(g.nbLignes), nt(c[1]));
        expect(nt(money(arrondiJs(g.marge), avecDevise: false)), nt(c[4]));
        expect(nt(pourcent(g.taux)), nt(c[5]));
      }
    });
    test('toutes les périodes de l\'écran, bornes absentes comprises', () {
      final p = carte(ecran['parPeriode']);
      for (final (k, du, au) in [
        ('aout', '2026-08-01', '2026-08-31'),
        ('tout', '', ''),
        ('futur', '2027-01-01', '2027-12-31'),
        ('sansDebut', '', '2026-08-31'),
        ('sansFin', '2026-09-01', ''),
        ('juillet', '2026-07-01', '2026-07-31')
      ]) {
        final r = calcul(du, au);
        // sans facture sur la période, l'écran n'a plus de tableau des groupes (état vide) : ses quatre indicateurs disent alors 0 et « — »
        if (r.lignes.isEmpty) {
          expect((carte(p[k])['kpis'] as List).map((x) => nt((x as List)[1])).toList(), ['0 FCFA', '0 FCFA', '0 FCFA', '—'], reason: k);
        } else {
          expect(lignes(r), att(carte(p[k])['groupes']), reason: k);
        }
      }
    });
    test('une période sans facture : « — » et non un taux de 0 ; le taux n\'existe que s\'il y a une recette', () {
      final r = calcul('2027-01-01', '2027-12-31');
      expect(r.lignes, isEmpty);
      expect(carte(carte(ecran['parPeriode'])['futur'])['kpis'], isNotEmpty);
      expect(CpcGroupeActivite('x', 'X').taux, isNull);
    });
    test('le consommable est valorisé au CUMP et rattaché au groupe par la catégorie de l\'article ; un article inconnu est ignoré', () {
      final fact = [
        {
          'date': '2026-09-01',
          'lignes': [
            {'categorie': 'medicament', 'montant': 1000},
            {'categorie': 'analyse', 'montant': 500},
          ]
        }
      ];
      final prods = [
        {'id': 'P1', 'categorie': 'medicament', 'cump': 40, 'prixAchat': 30},
        {'id': 'P2', 'categorie': 'reactif', 'prixAchat': 10},
        {'id': 'P3', 'categorie': 'consommable', 'cump': 5},
        {'id': 'P4', 'categorie': 'medicament', 'cump': 1}
      ];
      final mvt = [
        {'type': 'sortie', 'date': '2026-09-02', 'produitId': 'P1', 'quantite': 3},
        {'type': 'perte', 'date': '2026-09-02', 'produitId': 'P2', 'quantite': 2},
        {'type': 'casse', 'date': '2026-09-03', 'produitId': 'P3', 'quantite': 4},
        {'type': 'entree', 'date': '2026-09-03', 'produitId': 'P1', 'quantite': 99},
        {'type': 'sortie', 'date': '2026-09-04', 'produitId': 'INCONNU', 'quantite': 7},
        {'type': 'sortie', 'date': '2026-12-31', 'produitId': 'P4', 'quantite': 50},
      ];
      final r = cpcCoutActivite(factures: fact, mouvements: mvt, produits: prods, du: '2026-09-01', au: '2026-09-30');
      expect({for (final g in r.lignes) g.id: g.cout}, {'pharmacie': 120.0, 'laboratoire': 20.0});
      expect(r.horsGroupe, 20.0, reason: 'la casse d\'un consommable ne se rattache à aucun groupe facturé : comptée à part, non répartie');
      expect(r.recette, 1500);
    });
  });

  group('la prévision saisonnière : une projection, pas une prévision budgétaire', () {
    test('l\'indice des admissions du mois et le BFR projeté de la maquette', () {
      final adm = actives(jeu('admissions'));
      final b = bfr(fin: '2026-10-30');
      final p = cpcPrevisionSaisonniere(adm, b.bfr)!;
      final att = ((carte(carte(v['ecranCout'])['defaut'])['prevision'] as Map)['lignes'] as List);
      expect(p.length, att.length);
      for (var i = 0; i < p.length; i++) {
        final c = (att[i] as List);
        expect([p[i].mois, '${p[i].admissions}', nt(p[i].indice!.toStringAsFixed(2)), nt(money(p[i].bfrProjete, avecDevise: false))], [c[0], c[1], c[2], nt(c[3])], reason: '$i');
      }
    });
    test('moins de trois mois d\'admissions : aucune prévision (un indice sur deux mois serait une coïncidence)', () {
      expect(cpcPrevisionSaisonniere(actives(jeu('admissions')).take(2).toList(), 1000000), isNull);
      expect(cpcPrevisionSaisonniere(const [], 1), isNull);
      expect(nt(carte(carte(v['ecranCout'])['sansPrevision'])['texte']), contains('Moins de trois mois d’admissions renseignés'));
    });
  });

  group('les quatre lignes du cycle', () {
    test('la dette se DÉDUIT : montant négatif, comme la pièce imprimée', () {
      final l = cpcLignesBfr(bfr(fin: '2026-10-30', jours: 90));
      expect([for (final x in l) x['quoi']], ['Part assureur des factures', 'Restes à charge non soldés', 'Stock détenu', 'Dettes fournisseurs (à déduire)']);
      expect(l.fold<double>(0, (a, x) => a + (x['montant'] as num)), bfr(fin: '2026-10-30', jours: 90).bfr);
      expect(nt(carte(v['ecranBfr'])['piece'] != null ? 'ok' : ''), 'ok');
    });
  });
}
