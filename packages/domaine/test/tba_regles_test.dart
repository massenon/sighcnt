// Tableaux de bord par poste (DASH) : les règles du domaine rejouées sur les relevés ENGENDRÉS en pilotant les dix écrans réels de la maquette
// (prototype_html/build/vecteurs-dash.js → test/vecteurs/tba_dash.json), sur le jeu du poste et l'horloge du 16/08/2026 midi.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M ecrans() => obj(obj(jsonDecode(File('test/vecteurs/tba_dash.json').readAsStringSync()))['ecrans']);
List<M> jeu(String nom) =>
    [for (final f in liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()))) if (f['statut'] != 'archive') f];
String n(String s) => s.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
final auj = DateTime(2026, 8, 16, 12);

List<M> blocs(M e) => liste(e['blocs']);
M? premierRegard(M e) => [for (final b in blocs(e)) if (b['premierRegard'] != null) obj(b['premierRegard'])].firstOrNull;
List<M> kpisDe(M e) => [for (final b in blocs(e)) if (b['kpis'] != null) ...liste(b['kpis'])];
M carte(M e, String titre) => [
      for (final b in blocs(e)) for (final c in liste(b['cartes'] ?? const [])) if (c['titre'] == titre || '${c['titre']}'.startsWith(titre)) c
    ].first;

void kpis(List<TbaKpi> obtenus, M e) {
  final attendus = kpisDe(e);
  expect(obtenus.length, attendus.length);
  for (var i = 0; i < attendus.length; i++) {
    expect(n(obtenus[i].libelle), attendus[i]['label']);
    expect(n(obtenus[i].valeur), attendus[i]['valeur'], reason: obtenus[i].libelle);
    expect(obtenus[i].indice == null ? null : n(obtenus[i].indice!), attendus[i]['indice'], reason: '${obtenus[i].libelle} : indice');
  }
}

void premier(TbaPremierRegard p, M e) {
  final a = premierRegard(e)!;
  // La ligne du bandeau : le compte (span à part) puis « unité — question », ou la phrase positive quand il n'y a rien.
  final lue = n('${a['ligne']}');
  expect(n(p.ligne), lue, reason: 'ligne du premier regard');
  expect(n(p.note), a['note']);
  final lien = a['lien'] == null ? null : obj(a['lien']);
  if (p.valeur == 0) {
    // À zéro le bandeau n'offre aucun lien.
    expect(lien, isNull);
  } else {
    expect(p.ecran, lien!['ecran']);
    expect(p.lienLabel, lien['libelle']);
  }
}

void classement(List<(String, int)> obtenu, M c) {
  // Le classement est lu en paires [libellé, valeur].
  final lignes = (c['classement'] as List).cast<List>();
  expect(obtenu.length, lignes.length, reason: 'classement : longueur');
  for (var i = 0; i < lignes.length; i++) {
    expect(n(obtenu[i].$1), n('${lignes[i][0]}'), reason: 'classement[$i] libellé');
    expect(n('${obtenu[i].$2}'), n('${lignes[i][1]}'), reason: 'classement[$i] valeur');
  }
}

void graphique(TbaGraphique g, M c, {int serie = 0}) {
  final att = liste(c['graphiques']).first;
  expect(g.etiquettes.map(n).toList(), (att['etiquettes'] as List).map((x) => n('$x')).toList(), reason: 'étiquettes');
  final series = liste(att['series']);
  expect(g.series.length, series.length);
  for (var i = 0; i < series.length; i++) {
    expect(g.series[i].donnees.map((x) => x.toDouble()).toList(), (series[i]['donnees'] as List).map((x) => (x as num).toDouble()).toList(), reason: 'série ${g.series[i].libelle}');
  }
}

void main() {
  final e = ecrans();

  test('dash-medecin — premier regard, indicateurs, file du praticien, motifs et diagnostics', () {
    for (final cle in ['dash-medecin', 'dash-medecin#nomme']) {
      final v = obj(e[cle]);
      final d = tbaMedecin(
        demandesAnalyses: jeu('demandesAnalyses'),
        fileAttente: jeu('fileAttente'),
        consultations: jeu('consultations'),
        admissions: jeu('admissions'),
        nom: cle.endsWith('nomme') ? '${v['nom']}' : 'BASSONGUI Chabi Séko',
        auj: auj,
      );
      premier(d.premier, v);
      kpis(d.kpis, v);
      classement(d.motifs, carte(v, 'Motifs de consultation'));
      final g = carte(v, 'Diagnostics posés');
      graphique(TbaGraphique([for (final x in d.diagnostics) x.$1], [TbaSerie('Cas', [for (final x in d.diagnostics) x.$2])]), g);
      final rec = liste(carte(v, 'File d’attente et consultations récentes')['tables'])[0]['lignes'] as List;
      expect(d.recentes.length, rec.length);
      for (var i = 0; i < rec.length; i++) {
        expect('${d.recentes[i]['patient']}', (rec[i] as List)[2], reason: 'consultation récente $i');
      }
      final texte = n('${carte(v, 'Vos patients en attente')['texte']}');
      if (d.file.miens.isNotEmpty) {
        expect(texte, contains('${d.file.miens.length} patient(s) vous attendent nommément'));
      } else {
        expect(texte, contains('Aucun patient ne vous est adressé nommément.'));
      }
      expect(texte, contains('${d.file.communs.length} patient(s)'));
      if (d.file.autres.isNotEmpty) expect(texte, contains('${d.file.autres.length} patient(s) attendent un autre praticien'));
    }
    // La file « miens » existe VRAIMENT sous le nom d'un praticien auquel un ticket est adressé.
    final d = tbaMedecin(
        demandesAnalyses: const [], fileAttente: jeu('fileAttente'), consultations: const [], admissions: const [], nom: '${obj(e['dash-medecin#nomme'])['nom']}', auj: auj);
    expect(d.file.miens, isNotEmpty);
  });

  test('dash-infirmier — hospitalisés, lits libres, sorties à préparer', () {
    final v = obj(e['dash-infirmier']);
    final due = int.parse(RegExp(r'^\d+').firstMatch('${premierRegard(v)!['ligne']}')!.group(0)!);
    final d = tbaInfirmier(admissions: jeu('admissions'), administrationsDues: due, auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    final lignes = liste(carte(v, 'Patients hospitalisés')['tables'])[0]['lignes'] as List;
    expect(d.hospitalises.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.hospitalises[i]['patient']}', (lignes[i] as List)[1]);
      expect('${joursEntre(DateTime.parse('${d.hospitalises[i]['dateEntree']}'), auj)}', (lignes[i] as List)[4]);
    }
    expect(tbaTotalLits(), 19);
  });

  test('dash-pharmacien — compte fermé dit, indicateurs, réapprovisionnement, mouvements et péremptions', () {
    final v = obj(e['dash-pharmacien']);
    final mois = (List<FicheTba> r) => _parMois(r, 'date', 'quantite', auj);
    final d = tbaPharmacien(produits: jeu('produits'), lots: jeu('lots'), mouvements: jeu('mouvements'), parMoisQuantite: mois);
    premier(d.premier, v);
    kpis(d.kpis, v);
    final lignes = liste(carte(v, 'Produits à réapprovisionner')['tables'])[0]['lignes'] as List;
    expect(d.aReapprovisionner.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.aReapprovisionner[i]['code']}', (lignes[i] as List)[0]);
    }
    final g = carte(v, 'Mouvements de stock');
    final att = liste(g['graphiques']).first;
    expect(d.entrees, liste(att['series'])[0]['donnees']);
    expect(d.sorties, liste(att['series'])[1]['donnees']);
    expect(d.peremptions, liste(liste(carte(v, 'Péremptions à venir')['graphiques']).first['series'])[0]['donnees']);
  });

  test('dash-laborantin — validation biologique, indicateurs, séries tirées au hasard, rappel du matin', () {
    final v = obj(e['dash-laborantin']);
    final d = tbaLaborantin(demandes: jeu('demandesAnalyses'), produits: jeu('produits'), analyses: _analyses());
    premier(d.premier, v);
    kpis(d.kpis, v);
    classement([for (final x in d.analysesDemandees) (x.$1, x.$2)], carte(v, 'Analyses les plus demandées'));
    final ligne = liste(carte(v, 'Analyses réalisées')['graphiques']).first;
    expect(d.analysesRealisees, liste(ligne['series'])[0]['donnees']);
    graphique(d.categories, carte(v, 'Répartition par catégorie'));
    // Le rappel du matin.
    final r = tbaRappelBiologiste(jeu('demandesAnalyses'))!;
    final modale = n('${(v['dialogue'] as List).first}');
    expect(modale, contains('${r.aPrelever} analyse(s) réglée(s) à la caisse'));
    expect(modale, contains('${r.aSaisir} échantillon(s) reçu(s)'));
    expect(tbaRappelBiologiste(const []), isNull, reason: 'rien à faire : aucune modale');
    expect(obj(e['dash-laborantin#secondPassage'])['dialogue'], isEmpty, reason: 'une fois par jour');
  });

  test('dash-stock — alertes, premier regard, valeur au CUMP, mouvements et catégories', () {
    final v = obj(e['dash-stock']);
    final cats = {for (final c in categoriesProduit) c.id: c.label};
    final d = tbaStock(produits: jeu('produits'), lots: jeu('lots'), mouvements: jeu('mouvements'), categories: cats, auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    final al = liste(blocs(v).firstWhere((b) => b['alertes'] != null && (b['alertes'] as List).length > 1)['alertes']);
    expect(d.alertes.map((a) => n(a.texte)).toList(), al.map((a) => a['texte']).toList());
    expect(d.alertes.map((a) => a.ecran).toList(), al.map((a) => a['ecran']).toList());
    final lignes = liste(carte(v, 'Derniers mouvements')['tables'])[0]['lignes'] as List;
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.derniers[i]['produit']}', (lignes[i] as List)[1]);
    }
    graphique(d.valeurParCategorie, carte(v, 'Valeur du stock par catégorie'));
    graphique(d.repartitionMouvements, carte(v, 'Répartition des mouvements'));
  });

  test('dash-caissier — prescriptions à encaisser, indicateurs, modes de paiement, recettes du mois', () {
    final v = obj(e['dash-caissier']);
    final d = tbaCaissier(taches: jeu('taches'), factures: jeu('factures'), auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    graphique(d.parMode, carte(v, 'Encaissements par mode de paiement'));
    graphique(d.recettesQuotidiennes, carte(v, 'Recettes quotidiennes du mois'));
    final lignes = liste(carte(v, 'Dernières factures')['tables'])[0]['lignes'] as List;
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.dernieres[i]['numero']}', (lignes[i] as List)[0]);
    }
  });

  test('dash-comptable — brouillons, équilibre RG-10, écritures par journal et charges par centre', () {
    final v = obj(e['dash-comptable']);
    final d = tbaComptable(ecritures: jeu('ecritures'));
    premier(d.premier, v);
    kpis(d.kpis, v);
    graphique(d.parJournal, carte(v, 'Écritures par journal'));
    graphique(d.chargesParCentre, carte(v, 'Charges par centre de coûts'));
    final lignes = liste(carte(v, 'Dernières écritures')['tables'])[0]['lignes'] as List;
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.dernieres[i]['numero']}', (lignes[i] as List)[0]);
    }
    // Une pièce déséquilibrée se DIT : l'écart remplace « Équilibré ».
    final bancal = tbaComptable(ecritures: [
      {'debit': 100, 'credit': 0},
      {'debit': 0, 'credit': 40}
    ]);
    expect(n(bancal.kpis[3].valeur), '60 FCFA');
    expect(bancal.kpis[3].indice, 'Écart à régulariser');
  });

  test('dash-rh — compte fermé dit, effectif par fonction, gardes du jour', () {
    final v = obj(e['dash-rh']);
    final d = tbaRh(personnel: jeu('personnel'), planning: jeu('planning'), auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    classement(d.parFonction, carte(v, 'Effectif par fonction'));
    graphique(d.parService, carte(v, 'Répartition du personnel par service'));
    graphique(d.planningDuJour, carte(v, 'Planning du jour'));
  });

  test('dash-receptionniste — file en attente, indicateurs, rendez-vous du jour', () {
    final v = obj(e['dash-receptionniste']);
    final d = tbaReception(fileAttente: jeu('fileAttente'), patients: jeu('patients'), consultations: jeu('consultations'), auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    final lignes = liste(carte(v, 'Rendez-vous et consultations du jour')['tables'])[0]['lignes'] as List;
    expect(d.rendezVousDuJour.length, lignes.length);
    for (var i = 0; i < lignes.length; i++) {
      expect('${d.rendezVousDuJour[i]['patient']}', (lignes[i] as List)[2]);
    }
  });

  test('dash-admin-agent — courriers à traiter, indicateurs comptés, notes de service', () {
    final v = obj(e['dash-admin-agent']);
    final d = tbaAgentAdmin(courriers: jeu('courriers'), reunions: jeu('reunions'), documents: jeu('documents'), auj: auj);
    premier(d.premier, v);
    kpis(d.kpis, v);
    final lignes = liste(carte(v, 'Notes de service en vigueur')['tables'])[0]['lignes'] as List;
    expect(d.notes.map((x) => x.reference).toList(), [for (final l in lignes) (l as List)[0]]);
    expect(d.notes.map((x) => x.objet).toList(), [for (final l in lignes) (l as List)[1]]);
  });

  test('les briques communes : un seuil ABSENT ne déclenche rien, un seuil NUL compte', () {
    expect(tbaSousSeuil({'stock': 0}), isFalse, reason: 'seuil absent : undefined, jamais « en rupture »');
    expect(tbaSousSeuil({'stock': 0, 'seuilAlerte': null}), isTrue, reason: 'seuil nul = zéro, comme en JavaScript');
    expect(tbaSousSeuil({'stock': 5, 'seuilAlerte': 5}), isTrue);
    expect(tbaSousSeuil({'stock': 6, 'seuilAlerte': 5}), isFalse);
    final g = tbaGrouper([{'k': 'a'}, {}, {'k': 'a'}], (x) => x['k']);
    expect(g.keys.toList(), ['a', 'undefined']);
    expect(const TbaPremierRegard(valeur: 0, unite: 'x', question: 'y', vide: 'Rien.', ton: 'info', icone: 'i', note: '').ligne, 'Rien.');
  });
}

List<M> _analyses() => [
      for (final f in liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/analyses.json').readAsStringSync()))) f
    ];

/// L'équivalent de `parMois(rows, date, valeur)` du kit sur 12 mois, ancré au mois de [ref].
List<num> _parMois(List<M> rows, String cleDate, String cleValeur, DateTime ref) {
  final b = List<num>.filled(12, 0);
  for (final r in rows) {
    final d = DateTime.tryParse('${r[cleDate]}');
    if (d == null) continue;
    final diff = (ref.year - d.year) * 12 + (ref.month - d.month);
    final idx = 11 - diff;
    if (idx >= 0 && idx < 12) b[idx] += nombreOuZero(r[cleValeur]);
  }
  return b;
}
