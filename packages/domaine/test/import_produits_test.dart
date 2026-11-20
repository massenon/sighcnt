// LOT TFIN-2, groupe PRODUITS : les prix d'achat par fichier et le référentiel produits, rejoués sur les vecteurs tirés de l'écran réel de la maquette (section `produits` de
// `prototype_html/build/vecteurs-import.js`). Les fichiers `tp-*` et `pf-*` sont analysés par `import_test.dart` ; ici le geste d'ÉCRIRE : qui décide valide d'emblée, qui ne décide pas propose, un lot
// validé ne s'annule plus, les propositions se retirent avec leur lot, un prix identique est « inchangé », la version 1 naît avec l'article, un article sans prestation de prix reçoit sa reprise.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire, profilDe;

void main() {
  final V = lireVecteurs('import');
  final P = (V['produits'] as Map).cast<String, Object?>();
  final initial = (V['magasin'] as Map).cast<String, Object?>();

  List<List<Object?>> lignesDe(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  AnalyseImport analyser(MagasinMemoire port, String id, [JeuImport? jeu]) => analyserLignes(jeu ?? jeuTarifsProduits, lignesDe(id), '$id.xlsx', port);

  T enRole<T>(MagasinMemoire port, String role, String utilisateur, T Function() f, {bool fileul = false}) {
    final p0 = port.profil, u0 = port.utilisateurFixe;
    final p = profilDe(role);
    port.profil = fileul
        ? ProfilImport(role: p.role, libelleRole: p.libelleRole, matrice: p.matrice, bornes: p.bornes, reservesALaMere: p.reservesALaMere, libellesRoles: p.libellesRoles, fileul: true, surFileul: true)
        : p;
    port.utilisateurFixe = utilisateur;
    try {
      return f();
    } finally {
      port.profil = p0;
      port.utilisateurFixe = u0;
    }
  }

  Map<String, Object?> resume(AnalyseImport a) => {
        'accepte': a.accepte,
        'compte': a.compte.versJson(),
        'problemes': [
          for (final p in a.problemes) {'n': p.n, 'colonne': p.colonne, 'code': p.code, 'niveau': p.niveau}
        ],
        'details': [
          for (final l in a.lignes) [l.n, l.etat, l.detail ?? '']
        ],
      };

  Object? masque(Object? o, Map<String, String> refs) {
    var t = jsonEncode(o);
    for (final e in refs.entries) {
      t = t.replaceAll(e.key, e.value);
    }
    return jsonDecode(t);
  }

  Map<String, Object?> fiche(MagasinMemoire port, Map e) {
    final c = {...port.parId('${e['collection']}', e['id'])!};
    for (final k in ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage', '_archivePar', '_archiveLe', '_motifArchivage']) {
      c.remove(k);
    }
    return c;
  }

  group('prix d\'achat : analyse sous deux profils (qui décide, qui ne décide pas)', () {
    test('l\'administrateur décide : le Oui vaut version validée, la reprise de l\'article sans prix et le Non sont comptés', () {
      final port = MagasinMemoire(initial);
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'tp-valide'));
      memes(resume(a), P['adminValide'], 'adminValide');
    });
    test('le gestionnaire de stock importe des prix d\'achat sans les décider : le Oui vaut proposition, et la ligne le DIT', () {
      final port = MagasinMemoire(initial);
      final a = enRole(port, 'stock', 'STOCK TEST', () => analyser(port, 'tp-valide'));
      memes(resume(a), P['stockValide'], 'stockValide');
    });
    test('qui ne décide pas ne dépose qu\'UNE proposition par article (deux dates : refus nommé) ; qui décide peut en poser deux', () {
      final port = MagasinMemoire(initial);
      memes(resume(enRole(port, 'stock', 'STOCK TEST', () => analyser(port, 'tp-deux-dates'))), P['stockDeuxDates'], 'stockDeuxDates');
      memes(resume(enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'tp-deux-dates'))), P['adminDeuxDates'], 'adminDeuxDates');
    });
  });

  group('prix d\'achat : écrire, annuler, rejouer', () {
    final port = MagasinMemoire(initial);
    late Map<String, Object?> lotA, lotB;
    final refs = <String, String>{};

    test('A. l\'administrateur applique : versions VALIDÉES d\'emblée, l\'article sans prestation reçoit sa reprise AVANT sa proposition, journal de chaque transition (RG-12)', () {
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuTarifsProduits, analyser(port, 'tp-valide'), port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      lotA = r.lot!;
      refs['${lotA['reference']}'] = '{A}';
      final att = (P['appliqueAdmin'] as Map).cast<String, Object?>();
      expect(masque({for (final k in ['reference', 'etat', 'nbLignes', 'nbInchanges', 'nbNon']) k: lotA[k]}, refs), {for (final k in ['reference', 'etat', 'nbLignes', 'nbInchanges', 'nbNon']) k: att[k]});
      expect([for (final e in (lotA['ecrits'] as List).cast<Map>()) e['collection']], att['ecrits']);
      memes(masque([for (final e in (lotA['ecrits'] as List).cast<Map>()) fiche(port, e)], refs), att['fiches'], 'fiches');
      expect(port.journal.where((j) => j.startsWith('Changement de prix : validation à l’import|prix|')).length, 3, reason: 'trois lignes validées, trois transitions au journal');
      // Les versions de DOLIP, AMOXI (v1 `manquant` puis v2) et ABA (rien écrit : Non) comme la maquette.
      final att2 = (P['versionsApresAdmin'] as Map).cast<String, Object?>();
      for (final code in ['DOLIP', 'AMOXI', 'ABA']) {
        final vs = [for (final v in (port.toutes('versionsTarif').where((v) => v['code'] == code).toList()..sort((a, b) => (a['version'] as num).compareTo(b['version'] as num)))) {...v}];
        for (final v in vs) {
          for (final k in ['_creePar', '_creeLe', '_modifiePar', '_modifieLe']) {
            v.remove(k);
          }
        }
        memes(masque(vs, refs), att2[code], 'versions $code');
      }
    });

    test('un lot qui a VALIDÉ des prix d\'achat ne s\'annule plus : refus nommé, code, motif et geste, rien ne bouge', () {
      final avant = port.toutes('versionsTarif').map((v) => '${v['id']}:${v['statut']}').toList();
      final r = enRole(port, 'admin', 'ADMIN TEST', () => annulerLot(jeuImportParId, lotA['id'], 'essai', port));
      expect({'ok': r.ok, 'code': r.code, 'motif': r.motif, 'geste': r.geste}, P['annulationValidee']);
      expect(port.toutes('versionsTarif').map((v) => '${v['id']}:${v['statut']}').toList(), avant);
    });

    test('le même fichier rejoué : chaque prix est celui en vigueur, rien à écrire (jamais un doublon de version)', () {
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'tp-valide'));
      memes(resume(a), P['rejeu'], 'rejeu');
      final avant = port.toutes('versionsTarif').length;
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuTarifsProduits, a, port));
      expect(r.ok, isFalse);
      expect(port.toutes('versionsTarif').length, avant);
    });

    test('B. qui ne décide pas PROPOSE, puis retire ses propositions avec son lot : elles restent lisibles, rien n\'est supprimé (RG-14)', () {
      final r = enRole(port, 'stock', 'STOCK TEST', () => appliquer(jeuTarifsProduits, analyser(port, 'tp-proposition'), port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      lotB = r.lot!;
      refs['${lotB['reference']}'] = '{B}';
      final att = (P['appliqueStock'] as Map).cast<String, Object?>();
      expect(masque({for (final k in ['reference', 'etat', 'nbAvertissements']) k: lotB[k]}, refs), {for (final k in ['reference', 'etat', 'nbAvertissements']) k: att[k]});
      memes(masque([for (final e in (lotB['ecrits'] as List).cast<Map>()) fiche(port, e)], refs), att['fiches'], 'fiches');
      final ra = enRole(port, 'stock', 'STOCK TEST', () => annulerLot(jeuImportParId, lotB['id'], 'essai', port));
      final ann = (P['annulationPropositions'] as Map).cast<String, Object?>();
      expect(ra.ok, ann['ok']);
      expect(ra.archives, ann['archives']);
      expect(port.parId(collectionLots, lotB['id'])!['etat'], ann['etatLot']);
      for (final v in liste(ann['versions'])) {
        final f = port.parId('versionsTarif', v['id'])!;
        expect({'statut': f['statut'], 'decidePar': f['decidePar'], 'roleDecision': f['roleDecision'], 'motifDecision': '${f['motifDecision']}'.replaceAll('${lotB['reference']}', '{B}')},
            {'statut': v['statut'], 'decidePar': v['decidePar'], 'roleDecision': v['roleDecision'], 'motifDecision': v['motifDecision']});
      }
      final deux = enRole(port, 'stock', 'STOCK TEST', () => annulerLot(jeuImportParId, lotB['id'], 'encore', port));
      expect({'ok': deux.ok, 'code': deux.code}, P['annulationDeuxFois']);
    });

    test('un profil sans le droit d\'importer les prix d\'achat : refus de l\'application, rien n\'est écrit', () {
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'tp-proposition'));
      final avant = port.toutes('versionsTarif').length;
      final r = enRole(port, 'caissier', 'CAISSIER TEST', () => appliquer(jeuTarifsProduits, a, port));
      expect({'ok': r.ok, 'code': r.code, 'versionsAjoutees': port.toutes('versionsTarif').length - avant}, P['sansDroit']);
    });
  });

  group('l\'article sans prestation de prix (reprise) et la voie d\'un fileul', () {
    test('un article que le référentiel de prix ne porte pas encore : la vérification le dit virtuellement (rien n\'est écrit), l\'écriture pose la version 1 de reprise AVANT la proposition', () {
      final port = MagasinMemoire(initial);
      // INCOH n'a aucune prestation de prix dans le magasin contrôlé.
      expect(port.toutes('tarifs').where((t) => t['code'] == 'INCOH'), isEmpty);
      final lignes = [
        ['Code article', 'Prix d’achat', 'Date d’effet', 'Valider (Oui/Non)', 'Motif', 'Source'],
        ['INCOH', 150, '2027-01-01', 'Oui', 'Premier prix', null],
      ];
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyserLignes(jeuTarifsProduits, lignes, 'incoh.xlsx', port));
      expect(a.accepte, isTrue, reason: '${a.problemes.map((p) => p.code)}');
      expect(port.toutes('tarifs').where((t) => t['code'] == 'INCOH'), isEmpty, reason: 'l\'analyse n\'écrit rien');
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuTarifsProduits, a, port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      final vs = port.toutes('versionsTarif').where((v) => v['code'] == 'INCOH').toList()..sort((a, b) => (a['version'] as num).compareTo(b['version'] as num));
      expect([for (final v in vs) [v['version'], v['origine'], v['statut'], v['prixNonAssure']]], [
        [1, 'reprise', 'valide', null],
        [2, 'import', 'valide', 150]
      ], reason: 'reprise (prix absent : manquant) puis la version de l\'import ; la reprise n\'est pas déclarée au lot');
      expect((r.lot!['ecrits'] as List).cast<Map>().map((e) => e['collection']).toSet(), {'versionsTarif'}, reason: 'seule la version de l\'import est déclarée au lot');
    });

    test('la création d\'articles par le référentiel produits pose la version 1 de chacun (valide, sans date d\'effet, origine import) ; sur un FILEUL, la fiche s\'écrit et la version est laissée à la mère', () {
      final port = MagasinMemoire(initial);
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'pf-valide', jeuProduitsReferentiel));
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuProduitsReferentiel, a, port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      final vs = port.toutes('versionsTarif').where((v) => '${v['code']}'.startsWith('NEW-')).toList();
      expect(vs.length, 3);
      expect([for (final v in vs) [v['version'], v['statut'], v['origine'], v['dateEffet']]], everyElement([1, 'valide', 'import', null]));

      final fileul = MagasinMemoire(initial);
      final b = enRole(fileul, 'admin', 'ADMIN TEST', () => analyser(fileul, 'pf-valide', jeuProduitsReferentiel), fileul: true);
      final rf = enRole(fileul, 'admin', 'ADMIN TEST', () => appliquer(jeuProduitsReferentiel, b, fileul), fileul: true);
      expect(rf.ok, isTrue, reason: '${rf.motif}');
      expect(fileul.toutes('produits').where((p) => '${p['code']}'.startsWith('NEW-')).length, 3, reason: 'les fiches s\'écrivent chez le fileul');
      expect(fileul.toutes('versionsTarif').where((v) => '${v['code']}'.startsWith('NEW-')), isEmpty, reason: 'une version ne s\'écrit JAMAIS chez un fileul (famille R)');
    });

    test('la mère qui REJOUE la demande d\'un fileul pose la version 1 (le profil agit pour un fileul, il n\'EST pas sur un fileul)', () {
      final port = MagasinMemoire(initial);
      final p = profilDe('admin');
      port.profil = ProfilImport(role: p.role, libelleRole: p.libelleRole, matrice: p.matrice, bornes: p.bornes, libellesRoles: p.libellesRoles, fileul: true);
      final a = analyser(port, 'pf-valide', jeuProduitsReferentiel);
      final r = appliquer(jeuProduitsReferentiel, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(port.toutes('versionsTarif').where((v) => '${v['code']}'.startsWith('NEW-')).length, 3);
    });
  });
}
