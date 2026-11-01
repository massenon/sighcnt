// Le module d'importation rejoué sur les vecteurs de la maquette (prototype_html/build/vecteurs-import.js) :
// quarante-sept fichiers analysés sur un magasin contrôlé, dix lots appliqués puis annulés, un refus d'annulation sous un stock vivant (RG-03),
// l'atomicité d'une écriture refusée en cours de lot, les modèles téléchargeables et le CSV.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

/// Un magasin en mémoire qui se comporte comme celui de la maquette : insertion EN TÊTE, archivage logique, gardes d'écriture.
class MagasinMemoire extends PortImport {
  MagasinMemoire(Map<String, Object?> jeu, {this.jourFixe = '2026-11-01', this.utilisateurFixe = 'ADMIN TEST'}) {
    for (final e in jeu.entries) {
      _c[e.key] = [for (final f in (e.value as List).cast<Map>()) {...f.cast<String, Object?>()}];
    }
  }
  final String jourFixe, utilisateurFixe;
  final Map<String, List<FicheImport>> _c = {};
  final Map<String, String? Function(String op, FicheImport f)> gardes = {};
  int _rang = 0;
  final journal = <String>[];

  @override
  List<FicheImport> toutes(String collection) => _c.putIfAbsent(collection, () => []);
  @override
  String get jour => jourFixe;
  @override
  String get utilisateur => utilisateurFixe;

  @override
  FicheImport inserer(String collection, FicheImport fiche) {
    final motif = gardes[collection]?.call('inserer', fiche);
    if (motif != null) throw StateError(motif);
    final f = {'statut': 'actif', ...fiche};
    f['id'] ??= 'X${++_rang}';
    toutes(collection).insert(0, f);
    return f;
  }

  @override
  void retirer(String collection, Object? id) => toutes(collection).removeWhere((f) => f['id'] == id);

  @override
  bool archiver(String collection, Object? id, String motif) {
    final f = parId(collection, id);
    if (f == null) return false;
    if (gardes[collection]?.call('archiver', f) != null) return false;
    f['statutAvantArchivage'] = f['statut'];
    f['statut'] = 'archive';
    f['_motifArchivage'] = motif;
    return true;
  }

  @override
  void restaurer(String collection, Object? id) {
    final f = parId(collection, id);
    if (f == null) return;
    f['statut'] = f.remove('statutAvantArchivage') ?? 'actif';
  }

  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => parId(collection, id)?.addAll(patch);

  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) => journal.add('$action|$entite|$reference');
}

Map<String, Object?> _net(Map<String, Object?> f, Map<Object?, String> idVersCode) {
  final c = {...f};
  for (final k in ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage', '_archivePar', '_archiveLe', '_motifArchivage']) {
    c.remove(k);
  }
  if (c['produitId'] != null && idVersCode.containsKey(c['produitId'])) c['produitId'] = 'code:${idVersCode[c['produitId']]}';
  return c;
}

void main() {
  final V = lireVecteurs('import');
  final magasinInitial = (V['magasin'] as Map).cast<String, Object?>();

  group('analyse : les fichiers de la maquette sur un magasin contrôlé', () {
    for (final c in liste(V['cas'])) {
      final attendu = (c['attendu'] as Map).cast<String, Object?>();
      test('${c['id']}', () {
        final port = MagasinMemoire(magasinInitial);
        final jeu = jeuImportParId('${c['jeu']}')!;
        final lignes = [
          for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
        ];
        final a = analyserLignes(jeu, lignes, '${c['id']}.xlsx', port);
        expect(a.accepte, attendu['accepte'], reason: 'accepté');
        expect(a.nbLignes, attendu['nbLignes'], reason: 'lignes lues');
        memes(a.compte.versJson(), attendu['compte'], '${c['id']}.compte');
        final obtenus = [
          for (final p in a.problemes) {'n': p.n, 'colonne': p.colonne, 'code': p.code, 'niveau': p.niveau, 'valeur': texteDe(p.valeur)}
        ];
        memes(obtenus, attendu['problemes'], '${c['id']}.problemes');
        expect([for (final l in a.lignes) [l.n, l.etat]], [for (final e in (attendu['etats'] as List)) e]);
        // Un refus se NOMME : motif et geste ne sont jamais vides.
        for (final p in a.problemes) {
          expect(p.motif, isNotEmpty, reason: '${p.code} sans motif');
          expect(p.geste, isNotEmpty, reason: '${p.code} sans geste');
        }
      });
    }
  });

  group('modèles téléchargeables', () {
    final modeles = (V['modeles'] as Map).cast<String, Object?>();
    for (final e in modeles.entries) {
      test(e.key, () {
        final m = (e.value as Map).cast<String, Object?>();
        final jeu = jeuImportParId(e.key)!;
        expect(jeu.libelle, m['libelle']);
        expect(jeu.ecran, m['ecran']);
        expect(jeu.statut, m['statut']);
        expect(jeu.roles, m['roles']);
        expect(jeu.cibles, m['cibles']);
        expect(jeu.fichierModele, m['fichier']);
        expect([for (final c in jeu.colonnes) c.label], m['entetes']);
        expect([for (final c in jeu.colonnes) c.cle], m['cles']);
        expect([for (final c in jeu.colonnes) c.obligatoire], m['obligatoires']);
        expect([for (final c in jeu.colonnes) c.type], m['types']);
        final mod = modeleImport(jeu, MagasinMemoire(magasinInitial));
        expect(mod.donnees.length, 2);
        expect([for (final x in mod.donnees.first) '$x'], m['entetes']);
        // Un classeur ne garde pas les cellules vides de queue : on compare sans elles.
        List<String> sansQueue(Iterable<Object?> l) {
          final t = [for (final x in l) texteDe(x)];
          while (t.isNotEmpty && t.last.isEmpty) {
            t.removeLast();
          }
          return t;
        }

        expect(sansQueue(mod.donnees[1]), sansQueue(m['exemple'] as List));
        expect(mod.instructions.length, m['instructions']);
        expect([for (final x in mod.listes.first) '$x'], m['listes']);
      });
    }
    test('Grand Stock : la ligne d\'exemple, restée telle quelle, est un fichier vide', () {
      final jeu = jeuGrandStock;
      final port = MagasinMemoire(magasinInitial);
      final mod = modeleImport(jeu, port);
      final a = analyserLignes(jeu, mod.donnees, 'modele.xlsx', port);
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FICHIER_VIDE');
    });
    test('le CSV du modèle se relit', () {
      final csv = V['csv'] as Map;
      expect(modeleCsvImport(jeuGrandStock), csv['grandStock']);
      expect(importLireCsv(csv['grandStock'] as String), [
        for (final l in (csv['lignes'] as List)) [for (final x in l as List) '$x']
      ]);
    });
    test('séries Excel (système 1900)', () {
      final s = (V['lienCellules'] as Map).cast<String, Object?>();
      expect(importVersDate(1), s['serie1']);
      expect(importVersDate(61), s['serie60']);
      expect(importVersDate(45000), s['serie45000']);
      expect(importVersDate(46023), s['serie46023']);
    });
  });

  group('lots : application, annulation, atomicité', () {
    final port = MagasinMemoire(magasinInitial);
    final lots = <String, Map<String, Object?>>{};
    Map<String, AnalyseImport> analyses = {};

    AnalyseImport analyseDuCas(String id) {
      final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
      final jeu = jeuImportParId('${c['jeu']}')!;
      return analyserLignes(jeu, [
        for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
      ], '$id.xlsx', port);
    }

    test('un fichier refusé est consigné et n\'écrit rien', () {
      final avant = {for (final n in ['produits', 'lots', 'mouvements']) n: port.toutes(n).length};
      final a = analyseDuCas('gs-quantite-negative');
      final lot = consigner(jeuGrandStock, a, port);
      memes({for (final k in ['reference', 'etat', 'nbLignes', 'nbAvertissements', 'nbRefus', 'erreursTotal', 'jeu', 'fichier']) k: lot[k]}, V['lotRefus'], 'lotRefus');
      expect({for (final n in ['produits', 'lots', 'mouvements']) n: port.toutes(n).length}, avant);
    });

    final ordre = ['gs-valide', 'pa-valide', 'so-valide', 'ac-valide', 'pe-valide', 'fo-valide', 'as-valide', 'sc-valide', 'pc-valide', 'an-valide'];
    for (final app in liste(V['applications'])) {
      test('application de ${app['cas']}', () {
        final id = '${app['cas']}';
        final jeu = jeuImportParId('${app['jeu']}')!;
        final a = analyseDuCas(id);
        analyses[id] = a;
        final r = appliquer(jeu, a, port);
        expect(r.ok, isTrue, reason: '${r.motif}');
        final lot = r.lot!;
        lots[id] = lot;
        expect(lot['reference'], app['reference']);
        expect((lot['ecrits'] as List).length, app['ecrits']);
        final idVersCode = {for (final p in port.toutes('produits')) p['id']: '${p['code']}'};
        final fiches = <String, List<Map<String, Object?>>>{};
        for (final e in (lot['ecrits'] as List).cast<Map>()) {
          (fiches['${e['collection']}'] ??= []).add(_net(port.parId('${e['collection']}', e['id'])!, idVersCode));
        }
        // Dans la maquette, l'ordre des fiches suit l'ordre d'écriture ; ici de même.
        memes(fiches, app['fiches'], '${app['cas']}.fiches');
        memes({for (final k in ['etat', 'nbLignes', 'nbAvertissements', 'jeu', 'fichier', 'validePar', 'date']) k: lot[k]}, app['lot'], '${app['cas']}.lot');
      });
    }

    test('le même fichier rejoué est refusé : les articles existent maintenant', () {
      final a = analyseDuCas('gs-valide');
      final rejeu = (V['rejeu'] as Map).cast<String, Object?>();
      expect(a.accepte, rejeu['accepte']);
      expect([for (final p in a.problemes.where((p) => p.estRefus)) p.code], rejeu['codes']);
    });

    test('annulation : refusée sous un mouvement de stock postérieur (RG-03), puis réussie par archivage (RG-14)', () {
      final annulations = liste(V['annulations']);
      final prod = port.toutes('produits').firstWhere((p) => p['code'] == 'MED1');
      port.inserer('mouvements', {'reference': 'M000050', 'date': '2026-11-01', 'produitId': prod['id'], 'produit': prod['designation'], 'type': 'sortie', 'typeLabel': 'Sortie', 'quantite': 3});
      var r = annulerLot(jeuImportParId, lots['gs-valide']!['id'], 'test', port);
      expect(r.ok, annulations[0]['ok']);
      expect(r.code, annulations[0]['code']);
      expect(r.motif, contains('mouvement de stock'));
      expect(port.toutes('produits').where((p) => p['lotImport'] == 'IMP-2026-002' && p['statut'] == 'archive'), isEmpty, reason: 'rien n\'est archivé');
      port.archiver('mouvements', port.toutes('mouvements').firstWhere((m) => m['reference'] == 'M000050')['id'], 'test');
      var k = 1;
      for (final id in ordre) {
        r = annulerLot(jeuImportParId, lots[id]!['id'], 'test', port);
        final att = annulations[k++];
        expect(att['cas'], id);
        expect(r.ok, att['ok'], reason: '$id : ${r.motif}');
        expect(r.archives, att['archives'], reason: id);
        final ecrits = (lots[id]!['ecrits'] as List).cast<Map>();
        expect(ecrits.where((e) => port.parId('${e['collection']}', e['id'])!['statut'] == 'archive').length, att['archivesVerifiees']);
        expect(port.parId(collectionLots, lots[id]!['id'])!['etat'], att['etatLot']);
      }
      r = annulerLot(jeuImportParId, lots['gs-valide']!['id'], 'encore', port);
      expect(r.ok, isFalse);
      expect(r.code, 'LOT_NON_APPLIQUE');
    });

    test('atomicité : une écriture refusée en cours de lot ne laisse rien, le fichier est consigné', () {
      final att = (V['atomicite'] as Map).cast<String, Object?>();
      final avantEcr = port.toutes('ecritures').length, avantLots = port.toutes(collectionLots).length;
      expect(avantEcr, att['ecrituresAvant']);
      port.gardes['ecritures'] = (op, f) => op == 'inserer' && port.toutes('ecritures').length >= avantEcr + 2 ? 'exercice clos (garde d\'essai)' : null;
      final r = appliquer(jeuSoldesOuverture, analyseDuCas('so-valide'), port);
      port.gardes.remove('ecritures');
      expect(r.ok, att['ok']);
      expect(r.code, att['code']);
      expect(port.toutes('ecritures').length, att['ecrituresApres']);
      expect(port.toutes(collectionLots).length - avantLots, att['lotsAjoutes']);
      expect(r.lot!['etat'], att['lotEtat']);
    });
  });

  test('rapport d\'erreurs : les sept colonnes du rapport téléchargeable', () {
    final r = (V['rapport'] as Map).cast<String, Object?>();
    final t = rapportImport([
      {'n': 2, 'colonne': 'Quantité', 'valeur': -5, 'niveau': 'refus', 'code': 'RG03_STOCK_NEGATIF', 'motif': 'm', 'geste': 'g'}
    ]);
    expect(t.first, r['entete']);
    expect(t.length, r['nbLignes']);
  });
}
