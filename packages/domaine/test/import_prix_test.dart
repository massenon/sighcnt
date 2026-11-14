// LOT 8B, groupe PRIX : le changement de prix versionné par date et le catalogue de l'imagerie, rejoués sur les vecteurs tirés de l'écran réel de la maquette
// (`prototype_html/build/vecteurs-import.js`, section `prix`). Les fichiers `ta-*` et `ci-*` sont analysés par `import_test.dart` ; ici le geste d'ÉCRIRE : qui décide valide
// d'emblée, qui ne décide pas propose, un lot validé ne s'annule plus, les propositions se retirent avec leur lot, un prix identique est « inchangé ».
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire, profilDe;

void main() {
  final V = lireVecteurs('import');
  final P = (V['prix'] as Map).cast<String, Object?>();
  final initial = (V['magasin'] as Map).cast<String, Object?>();

  List<List<Object?>> lignesDe(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  AnalyseImport analyser(MagasinMemoire port, String id) => analyserLignes(jeuTarifs, lignesDe(id), '$id.xlsx', port);

  T enRole<T>(MagasinMemoire port, String role, String utilisateur, T Function() f) {
    final p0 = port.profil, u0 = port.utilisateurFixe;
    port.profil = profilDe(role);
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

  /// Les références de lot se disent {A} et {B} (elles dépendent de ce qui précède dans chaque magasin).
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

  group('prix : analyse sous deux profils (qui décide, qui ne décide pas)', () {
    test('l\'administrateur décide : le Oui vaut version validée, l\'inchangé et le Non sont comptés', () {
      final port = MagasinMemoire(initial);
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'ta-valide'));
      memes(resume(a), P['adminValide'], 'adminValide');
    });
    test('le gestionnaire de stock importe des prix sans les décider : le Oui vaut proposition, et la ligne le DIT', () {
      final port = MagasinMemoire(initial);
      final a = enRole(port, 'stock', 'STOCK TEST', () => analyser(port, 'ta-valide'));
      memes(resume(a), P['stockValide'], 'stockValide');
      final b = enRole(port, 'stock', 'STOCK TEST', () => analyser(port, 'ta-proposition'));
      memes(resume(b), P['stockProposition'], 'stockProposition');
    });
  });

  group('prix : écrire, annuler, rejouer', () {
    final port = MagasinMemoire(initial);
    late Map<String, Object?> lotA, lotB;
    final refs = <String, String>{};

    test('A. l\'administrateur applique : versions VALIDÉES d\'emblée, identité de la prestation créée, journal de chaque transition (RG-12)', () {
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuTarifs, analyser(port, 'ta-valide'), port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      lotA = r.lot!;
      refs['${lotA['reference']}'] = '{A}';
      final att = (P['appliqueAdmin'] as Map).cast<String, Object?>();
      expect(masque({for (final k in ['reference', 'etat', 'nbLignes', 'nbInchanges', 'nbNon']) k: lotA[k]}, refs), {for (final k in ['reference', 'etat', 'nbLignes', 'nbInchanges', 'nbNon']) k: att[k]});
      expect([for (final e in (lotA['ecrits'] as List).cast<Map>()) e['collection']], att['ecrits']);
      memes(masque([for (final e in (lotA['ecrits'] as List).cast<Map>()) fiche(port, e)], refs), att['fiches'], 'fiches');
      expect(port.journal.where((j) => j.startsWith('Changement de prix : validation à l’import|prix|')).length, 3, reason: 'trois lignes validées, trois transitions au journal');
    });

    test('un lot qui a VALIDÉ des prix ne s\'annule plus : refus nommé, code, motif et geste, rien ne bouge', () {
      final avant = port.toutes('versionsTarif').map((v) => '${v['id']}:${v['statut']}').toList();
      final r = enRole(port, 'admin', 'ADMIN TEST', () => annulerLot(jeuImportParId, lotA['id'], 'essai', port));
      final att = (P['annulationValidee'] as Map).cast<String, Object?>();
      expect({'ok': r.ok, 'code': r.code, 'motif': r.motif, 'geste': r.geste}, att);
      expect(port.toutes('versionsTarif').map((v) => '${v['id']}:${v['statut']}').toList(), avant);
      expect(port.parId(collectionLots, lotA['id'])!['etat'], 'applique');
    });

    test('le même fichier rejoué : chaque prix est celui en vigueur, rien à écrire (jamais un doublon de version)', () {
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'ta-valide'));
      memes(resume(a), P['rejeu'], 'rejeu');
      final avant = port.toutes('versionsTarif').length;
      final r = enRole(port, 'admin', 'ADMIN TEST', () => appliquer(jeuTarifs, a, port));
      expect(r.ok, isFalse);
      expect(port.toutes('versionsTarif').length, avant);
    });

    test('B. qui ne décide pas PROPOSE (le Oui vaut proposition), puis retire ses propositions avec son lot : elles restent lisibles, rien n\'est supprimé (RG-14)', () {
      final r = enRole(port, 'stock', 'STOCK TEST', () => appliquer(jeuTarifs, analyser(port, 'ta-proposition'), port));
      expect(r.ok, isTrue, reason: '${r.motif}');
      lotB = r.lot!;
      refs['${lotB['reference']}'] = '{B}';
      final att = (P['appliqueStock'] as Map).cast<String, Object?>();
      expect(masque({for (final k in ['reference', 'etat', 'nbAvertissements']) k: lotB[k]}, refs), {for (final k in ['reference', 'etat', 'nbAvertissements']) k: att[k]});
      memes(masque([for (final e in (lotB['ecrits'] as List).cast<Map>()) fiche(port, e)], refs), att['fiches'], 'fiches');
      expect(port.journal.where((j) => j.startsWith('Changement de prix : proposition à l’import|prix|')).length, 2);
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

    test('un profil qui n\'a pas le droit d\'importer les prix : refus de l\'application, rien n\'est écrit', () {
      final a = enRole(port, 'admin', 'ADMIN TEST', () => analyser(port, 'ta-proposition'));
      final avant = port.toutes('versionsTarif').length;
      final r = enRole(port, 'caissier', 'CAISSIER TEST', () => appliquer(jeuTarifs, a, port));
      expect({'ok': r.ok, 'code': r.code, 'versionsAjoutees': port.toutes('versionsTarif').length - avant}, P['sansDroit']);
    });
  });

  group('catalogue de l\'imagerie', () {
    test('un examen importé naît « à valider », porte l\'icône de sa modalité, et s\'annule par archivage (RG-14) tant qu\'aucune demande ne s\'appuie sur lui', () {
      final port = MagasinMemoire(initial);
      final jeu = jeuCatalogueImagerie;
      final a = analyserLignes(jeu, lignesDe('ci-valide'), 'ci-valide.xlsx', port);
      final r = appliquer(jeu, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      final fiches = [for (final e in (r.lot!['ecrits'] as List).cast<Map>()) port.parId('${e['collection']}', e['id'])!];
      expect(fiches.map((f) => f['aValider']), [true, true]);
      expect(fiches.map((f) => f['icone']), ['bone', 'scan-line']);
      final d = port.inserer('demandesImagerie', {'reference': 'DI-1', 'examenCode': 'IMG-RAD-THO'});
      final refus = annulerLot(jeuImportParId, r.lot!['id'], 'essai', port);
      expect(refus.code, 'EXAMEN_DEMANDE');
      expect(refus.motif, contains('DI-1'));
      port.archiver('demandesImagerie', d['id'], 'test');
      final ok = annulerLot(jeuImportParId, r.lot!['id'], 'essai', port);
      expect(ok.ok, isTrue);
      expect(ok.archives, 2);
    });
  });
}
