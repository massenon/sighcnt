import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LES PRIX D'ACHAT DES PRODUITS (PRD-TARIFS lot T5, porté par le lot TFIN) : chaque cas est TIRÉ de la maquette en marche (`prototype_html/build/vecteurs-tarifs-produits.js`, les articles
/// réels du jeu, l'horloge du banc le 16/08/2026) et rejoué contre le domaine Dart : refus NOMMÉS (code, motif, geste, texte identique), version écrite champ par champ, accesseur daté,
/// création de la version 1, migration d'une fiche, correctif de la fiche. RG-02 : un médicament se facture au prix d'achat, sans marge.
typedef M = Map<String, Object?>;
final V = (jsonDecode(File('test/vecteurs/tarifs_produits.json').readAsStringSync()) as Map).cast<String, Object?>();
List<M> liste(Object? x) => [for (final e in (x as List? ?? const [])) (e as Map).cast<String, Object?>()];

/// Une fiche telle que le magasin la tient : sans clé nulle ni métadonnée de la maquette (`_creePar`…).
M propre(Map<dynamic, dynamic> m) => {
      for (final e in m.entries)
        if (e.value != null && !'${e.key}'.startsWith('_')) '${e.key}': e.value is Map ? propre(e.value as Map) : e.value
    };

/// Le référentiel de la clinique n'est jamais vide : le vecteur ne porte que les prestations du code éprouvé, une SENTINELLE (sans rapport) tient la place du reste.
ReferentielTarifs ref(M etat) => ReferentielTarifs([
      {'id': 'SENTINELLE', 'code': 'SENTINELLE', 'famille': 'ACTE', 'statut': 'actif'},
      ...liste(etat['tarifs']).map(propre)
    ], liste(etat['versions']).map(propre));

/// Les libellés de rôle du manifeste, que les refus de date passée NOMMENT.
const libelles = {'da': 'Directrice de l’Administration et des Finances (DAF)', 'direction': 'Direction / Gérance'};

ContexteTarif contexte(M etat, {bool proposer = true, String? role, bool fileul = false}) => ContexteTarif(
    libelles: libelles,
    referentiel: ref(etat),
    aujourdhui: '${V['aujourdhui']}',
    role: role ?? '${V['role']}',
    auteur: '${V['auteur']}',
    peutEditerEcran: true,
    peutProposerProduit: proposer,
    fileul: fileul,
    pieces: PiecesTarif(factures: liste(etat['factures'])));

DemandeProduit demande(M o) => DemandeProduit(
      code: '${o['code']}',
      prixAchat: o['prixNonAssure'],
      prixVente: o['prixVente'],
      dateEffet: o['dateEffet'] as String?,
      motif: o['motif'] as String?,
      datePassee: o['datePassee'] == true,
      valider: o['valider'] == true,
      source: o['source'] as String?,
      creation: o['creation'] != null,
      libelle: (o['creation'] as Map?)?['libelle'] as String?,
    );

void main() {
  final cas = liste(V['cas']);
  group('les cas de la maquette (refus nommés et versions écrites)', () {
    for (final c in cas) {
      test('${c['nom']}', () {
        final etat = (c['avant'] as Map).cast<String, Object?>();
        final o = (c['demande'] as Map).cast<String, Object?>(), cx = contexte(etat);
        // `evaluerProposition` : un code qui n'est pas un produit (et pas une création d'article) suit la voie des prestations.
        final r = tarEstProduit(cx.referentiel, '${o['code']}', creation: o['creation'] != null)
            ? tarProposerProduit(cx, demande(o), produits: liste(etat['produits']))
            : tarProposer(cx, DemandeProposition(code: '${o['code']}', prixNonAssure: o['prixNonAssure'], etatAssure: 'unique', dateEffet: o['dateEffet'] as String?, motif: o['motif'] as String?));
        if (c['ok'] != true) {
          final attendu = (c['refus'] as Map).cast<String, Object?>();
          expect(r.ok, isFalse, reason: '${c['nom']} devait être refusé');
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [attendu['code'], attendu['motif'], attendu['geste']], reason: 'un refus se nomme : code, motif et geste comme la maquette');
        } else if (c['ecrit'] != true) {
          expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
        } else {
          expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
          expect(propre(r.valeur!.version), propre((c['version'] as Map).cast<String, Object?>()), reason: 'la version écrite, champ par champ');
          expect(r.valeur!.valideeEnUnGeste, c['valideeEnUnGeste']);
        }
      });
    }
  });

  test('RG-02 : un médicament ne se vend ni au-dessus NI au-dessous de son prix d\'achat ; égal, c\'est accepté ; hors médicament le prix de vente propre est libre', () {
    final med = cas.firstWhere((c) => c['nom'] == 'RG-02 : un médicament avec un prix de vente différent');
    final etat = (med['avant'] as Map).cast<String, Object?>(), code = '${med['code']}';
    final achat = (liste(etat['produits']).first['prixAchat'] as num).toInt() + 10;
    DemandeProduit d(int? vente) => DemandeProduit(code: code, prixAchat: achat, prixVente: vente, dateEffet: '2026-08-20', motif: 'x');
    for (final vente in [achat + 30, achat - 10, achat + 1, achat - 1]) {
      final r = tarProposerProduit(contexte(etat), d(vente), produits: liste(etat['produits']));
      expect([r.ok, r.refus?.code], [false, 'RG02_MARGE'], reason: 'vente $vente pour un achat de $achat');
    }
    expect(tarProposerProduit(contexte(etat), d(achat), produits: liste(etat['produits'])).ok, isTrue, reason: 'vente égale à l\'achat : pas de marge');
    expect(tarProposerProduit(contexte(etat), d(null), produits: liste(etat['produits'])).ok, isTrue, reason: 'vente vide : elle se dérive');
    final autre = cas.firstWhere((c) => c['nom'] == 'hors médicament : prix de vente propre');
    final ea = (autre['avant'] as Map).cast<String, Object?>();
    final libre = tarProposerProduit(contexte(ea), DemandeProduit(code: '${autre['code']}', prixAchat: 5000, prixVente: 4000, dateEffet: '2026-08-20', motif: 'x'), produits: liste(ea['produits']));
    expect(libre.ok, isTrue, reason: 'hors médicament, le prix de vente propre est libre : ${libre.refus?.code}');
  });

  test('le droit : sans le droit de proposer un prix d\'achat, refus nommé ; valider sans le droit de décider ; un fileul ne valide pas', () {
    final c = cas.firstWhere((x) => x['ok'] == true && x['ecrit'] == true);
    final etat = (c['avant'] as Map).cast<String, Object?>(), d = demande((c['demande'] as Map).cast<String, Object?>());
    final sans = tarProposerProduit(contexte(etat, proposer: false), d, produits: liste(etat['produits']));
    expect([sans.ok, sans.refus!.code], [false, 'PROPOSITION_RESERVEE']);
    final dv = DemandeProduit(code: d.code, prixAchat: d.prixAchat, dateEffet: d.dateEffet, motif: d.motif, valider: true);
    final res = tarProposerProduit(contexte(etat, role: 'stock'), dv, produits: liste(etat['produits']));
    expect([res.ok, res.refus!.code], [false, 'VALIDATION_RESERVEE']);
    final fil = tarProposerProduit(contexte(etat, role: 'da', fileul: true), dv, produits: liste(etat['produits']));
    expect([fil.ok, fil.refus!.code], [false, 'CONFIGURATION_DE_LA_MERE']);
    final da = tarProposerProduit(contexte(etat, role: 'da'), dv, produits: liste(etat['produits']));
    expect(da.ok, isTrue, reason: 'la DAF valide en un geste');
    expect(da.valeur!.version['statut'], 'valide');
  });

  group('l\'accesseur daté du prix d\'achat (prixProduitALaDate)', () {
    for (final l in liste(V['lectures'])) {
      test('${l['code']} au ${l['date'] ?? 'jour'}', () {
        final etat = (l['etat'] as Map).cast<String, Object?>();
        final produits = liste(etat['produits']);
        final pr = produits.isEmpty ? <String, Object?>{'code': l['code'], 'designation': 'X'} : produits.first;
        final r = tarPrixProduit(ref(etat), pr, l['date'], aujourdhui: '${V['aujourdhui']}');
        final a = (l['attendu'] as Map).cast<String, Object?>();
        expect([r.absent, r.achat, r.vente, r.version, r.dateEffet], [a['absent'], a['achat'], a['vente'], a['version'], a['dateEffet']]);
        if (a['motif'] != null) expect(r.motif, a['motif']);
      });
    }
  });

  group('la proposition née d\'une réception d\'achat (tarProposerPrixReception), tirée de la maquette', () {
    final receptions = liste(V['receptions']);
    test('le jeu de vecteurs porte les onze cas', () => expect(receptions.length, greaterThanOrEqualTo(11)));
    for (final c in receptions) {
      test('${c['nom']}', () {
        final etat = (c['avant'] as Map).cast<String, Object?>(), e = (c['entree'] as Map).cast<String, Object?>(), att = (c['resultat'] as Map).cast<String, Object?>();
        final cx = contexte(etat, role: '${c['role']}', proposer: c['droit'] == true);
        final fiche = liste(etat['produits']).firstWhere((x) => x['code'] == e['code']);
        final r = tarProposerPrixReception(cx, produit: fiche, prixRecu: e['prixRecu'], date: e['date'], reference: '${e['reference']}', produits: liste(etat['produits']));
        expect(r.etat, att['etat'], reason: 'l\'état de la proposition, comme la maquette');
        expect(r.code, att['code']);
        expect(r.prix, att['prix']);
        expect(r.ancien, att['ancien']);
        expect(r.dateEffet, att['dateEffet']);
        if (att['refus'] != null) {
          final a = (att['refus'] as Map).cast<String, Object?>();
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [a['code'], a['motif'], a['geste']], reason: 'un refus se nomme : code, motif et geste comme la maquette');
        } else {
          expect(r.refus, isNull);
        }
        if (att['etat'] == 'ouverte') {
          final v = propre(r.proposition!.version), a = propre((att['version'] as Map).cast<String, Object?>());
          for (final k in ['code', 'version', 'prixNonAssure', 'prixVente', 'dateEffet', 'motif', 'source', 'statut', 'origine', 'datePassee', 'proposeRole', 'etatAssure']) {
            expect(v[k], a[k], reason: 'la version écrite, champ $k');
          }
        } else {
          expect(r.proposition, isNull, reason: 'rien n\'est à écrire hors de l\'état ouverte');
        }
      });
    }
  });

  test('un article créé sans prix d\'achat est refusé en nommant (PRIX_ACHAT_ABSENT : code, motif, geste comme la maquette)', () {
    final l = liste(V['refusPrixAbsent']);
    expect(l.length, 3);
    for (final c in l) {
      final a = (c['refus'] as Map).cast<String, Object?>(), r = tarRefusPrixAchatAbsent(c['code'], c['designation']);
      expect([r.code, r.motif, r.geste], [a['code'], a['motif'], a['geste']]);
    }
  });

  group('la création d\'une fiche pose la version 1 (valide, sans date d\'effet) ; sans prix d\'achat, manquant', () {
    for (final c in liste(V['creations'])) {
      test('${c['code']}', () {
        final avant = (c['avant'] as Map).cast<String, Object?>();
        final fiche = propre((c['fiche'] as Map));
        final etat = {'tarifs': avant['tarifs'], 'versions': avant['versions'], 'produits': [fiche], 'factures': const []};
        final r = tarProposerProduit(contexte(etat), tarDemandeCreationProduit(fiche), produits: [fiche]);
        if (c['reutilise'] == true) {
          expect(r.refus!.code, 'PRIX_DEJA_VERSIONNE');
          return;
        }
        expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
        expect(propre(r.valeur!.version), propre((c['version'] as Map).cast<String, Object?>()));
        expect(propre(r.valeur!.identite!), propre((c['identite'] as Map).cast<String, Object?>()));
      });
    }
  });

  test('la migration d\'une fiche (reprise) : version 1, prix absent ou nul = manquant, archivé jamais repris', () {
    final m = (V['migration'] as Map).cast<String, Object?>();
    final r = tarMigrerProduits(liste(m['entree']).map(propre), origine: 'reprise');
    expect(r.tarifs.map(propre).toList(), liste(m['tarifs']).map(propre).toList());
    expect(r.versions.map(propre).toList(), liste(m['versions']).map(propre).toList());
  });

  test('le correctif de la fiche : la fiche suit la version en vigueur, un prix absent ne corrige rien', () {
    for (final c in liste(V['correctifs'])) {
      final s = (c['s'] as Map).cast<String, Object?>(), vrs = ((s['vrs'] as Map).cast<String, Object?>());
      final inst = InstantaneTarif(
          na: s['na'] as num?, pa: null, etatNonAssure: '${vrs['etatNonAssure'] ?? 'montant'}', etatAssure: 'unique', nc: false, version: 1, dateEffet: null, provisoire: false, vrs: vrs);
      final r = tarCorrectifProduit(propre((c['doc'] as Map)), inst);
      expect(r, c['attendu'] == null ? isNull : propre((c['attendu'] as Map)), reason: '${c['doc']}');
    }
  });

  test('à valoriser : un article sans prix d\'achat en vigueur ; une proposition en attente ne le sort PAS ; seul un prix décidé le fait', () {
    final fiches = [
      {'id': 'P1', 'code': 'AV-1', 'designation': 'Sans prix', 'categorie': 'consommable', 'statut': 'actif'},
      {'id': 'P2', 'code': 'AV-2', 'designation': 'Avec prix', 'categorie': 'consommable', 'prixAchat': 100, 'statut': 'actif'},
      {'id': 'P3', 'code': 'AV-3', 'designation': 'Sans identité de prix', 'categorie': 'consommable', 'statut': 'actif'},
    ];
    final m = tarMigrerProduits(fiches.take(2));
    var h = ReferentielTarifs(m.tarifs, m.versions);
    var av = tarProduitsAValoriser(h, fiches, '2026-08-16');
    expect(av.map((x) => x.produit['code']), ['AV-1'], reason: 'AV-3 n\'a pas encore sa prestation de prix : il reçoit la sienne à l\'ouverture d\'un écran');
    expect(av.single.enAttente, isFalse);
    final cx = ContexteTarif(referentiel: h, aujourdhui: '2026-08-16', role: 'stock', auteur: 'S', peutProposerProduit: true);
    final prop = tarProposerProduit(cx, const DemandeProduit(code: 'AV-1', prixAchat: 250, dateEffet: '2026-08-20', motif: 'premier prix'), produits: fiches);
    expect(prop.ok, isTrue, reason: '${prop.refus?.code}');
    h = ReferentielTarifs(m.tarifs, [...m.versions, prop.valeur!.version]);
    av = tarProduitsAValoriser(h, fiches, '2026-08-16');
    expect(av.single.enAttente, isTrue, reason: 'la proposition attend son Oui : l\'article reste à valoriser');
    final oui = {...prop.valeur!.version, 'statut': 'valide'};
    h = ReferentielTarifs(m.tarifs, [...m.versions, oui]);
    expect(tarProduitsAValoriser(h, fiches, '2026-08-16').single.produit['code'], 'AV-1', reason: 'avant la date d\'effet il n\'y a toujours aucun prix en vigueur');
    expect(tarProduitsAValoriser(h, fiches, '2026-08-20'), isEmpty, reason: 'le jour dit, le prix est en vigueur');
  });
}
