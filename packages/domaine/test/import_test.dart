// Le module d'importation rejoué sur les vecteurs de la maquette (prototype_html/build/vecteurs-import.js) :
// quarante-sept fichiers analysés sur un magasin contrôlé, dix lots appliqués puis annulés, un refus d'annulation sous un stock vivant (RG-03),
// l'atomicité d'une écriture refusée en cours de lot, les modèles téléchargeables et le CSV.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

/// La matrice d'import ENGENDRÉE par la maquette (`rbac.json`) : le moteur lit le droit, la sensibilité et le mode de doublon de la DÉCLARATION du manifeste, jamais d'un
/// nom de rôle ni d'une constante du port.
final MatriceImport matriceReelle =
    MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>()).matriceImport;

/// Le profil de la maquette au tirage des vecteurs : l'administrateur, qui détient tous les jeux.
ProfilImport profilDe(String role, {Map<String, int> bornes = const {}}) =>
    ProfilImport(role: role, libelleRole: role == 'admin' ? 'Administrateur' : role, matrice: matriceReelle, bornes: bornes);

/// Un magasin en mémoire qui se comporte comme celui de la maquette : insertion EN TÊTE, archivage logique, gardes d'écriture.
class MagasinMemoire extends PortImport {
  MagasinMemoire(Map<String, Object?> jeu, {this.jourFixe = '2026-11-01', this.utilisateurFixe = 'ADMIN TEST', ProfilImport? profil}) : profil = profil ?? profilDe('admin') {
    for (final e in jeu.entries) {
      _c[e.key] = [for (final f in (e.value as List).cast<Map>()) {...f.cast<String, Object?>()}];
    }
  }
  final String jourFixe;
  String utilisateurFixe;
  /// Le profil change d'un geste à l'autre (un fichier analysé par un profil, appliqué ou annulé par un autre), comme `enRole` du tirage des vecteurs.
  @override
  ProfilImport profil;
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
    for (final e in modeles.entries.where((e) => jeuImportParId(e.key) != null)) {
      test(e.key, () {
        final m = (e.value as Map).cast<String, Object?>();
        final jeu = jeuImportParId(e.key)!;
        expect(jeu.libelle, m['libelle']);
        expect(jeu.ecran, m['ecran']);
        expect(jeu.statut, m['statut']);
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
      final lot = consigner(jeuGrandStock, a, port)!;
      memes({for (final k in ['reference', 'etat', 'nbLignes', 'nbAvertissements', 'nbRefus', 'erreursTotal', 'jeu', 'fichier']) k: lot[k]}, V['lotRefus'], 'lotRefus');
      expect({for (final n in ['produits', 'lots', 'mouvements']) n: port.toutes(n).length}, avant);
    });

    final ordre = ['gs-valide', 'pa-valide', 'so-valide', 'pe-valide', 'fo-valide', 'as-valide', 'sc-valide', 'pc-valide', 'an-valide', 'na-valide', 'ce-valide', 'un-valide', 'ps-valide', 'em-valide', 'sd-valide', 'tl-valide', 'ic-valide'];
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
        // La version 1 du prix d'achat (`tarifs`, `versionsTarif`, lot T5 de la maquette) n'est pas portée au poste : le prix reste à plat sur l'article, comme à l'écran
        // « Référentiel produits » du poste (ECARTS E2470). On compare tout le reste, collection par collection.
        const horsPoste = {'tarifs', 'versionsTarif'};
        final attendues = {for (final e in (app['fiches'] as Map).entries) if (!horsPoste.contains(e.key)) '${e.key}': e.value};
        expect((lot['ecrits'] as List).length, attendues.values.fold<int>(0, (t, l) => t + (l as List).length));
        final idVersCode = {for (final p in port.toutes('produits')) p['id']: '${p['code']}'};
        final fiches = <String, List<Map<String, Object?>>>{};
        for (final e in (lot['ecrits'] as List).cast<Map>()) {
          (fiches['${e['collection']}'] ??= []).add(_net(port.parId('${e['collection']}', e['id'])!, idVersCode));
        }
        // Dans la maquette, l'ordre des fiches suit l'ordre d'écriture ; ici de même.
        memes(fiches, attendues, '${app['cas']}.fiches');
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
      final apps = {for (final a in liste(V['applications'])) '${a['cas']}': a};
      for (final id in ordre) {
        r = annulerLot(jeuImportParId, lots[id]!['id'], 'test', port);
        final att = annulations[k++];
        expect(att['cas'], id);
        expect(r.ok, att['ok'], reason: '$id : ${r.motif}');
        // La maquette archive aussi l'identité de prix (`tarifs`) que l'import du stock a créée avec l'article ; le poste n'en écrit pas (ECARTS E2470).
        final identites = ((apps[id]!['fiches'] as Map)['tarifs'] as List?)?.length ?? 0;
        expect(r.archives, (att['archives'] as int) - identites, reason: id);
        final ecrits = (lots[id]!['ecrits'] as List).cast<Map>();
        expect(ecrits.where((e) => port.parId('${e['collection']}', e['id'])!['statut'] == 'archive').length, (att['archivesVerifiees'] as int) - identites);
        expect(port.parId(collectionLots, lots[id]!['id'])!['etat'], att['etatLot']);
      }
      r = annulerLot(jeuImportParId, lots['gs-valide']!['id'], 'encore', port);
      expect(r.ok, isFalse);
      expect(r.code, 'LOT_NON_APPLIQUE');
    });

    Map<String, Object?> stocks(List<String> codes) => {
          for (final c in codes)
            c: {
              for (final k in ['stock', 'stockGros', 'stockDetail']) k: port.toutes('produits').firstWhere((p) => p['code'] == c)[k]
            }
        };
    Map<String, Object?> lu(String code) => port.toutes('produits').firstWhere((p) => p['code'] == code);
    Map<String, Object?> refusDe(ResultatImport r) => {'ok': r.ok, 'code': r.code, 'motif': r.motif, 'geste': r.geste};
    Map<String, Object?> poser(String id) {
      final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
      final r = appliquer(jeuImportParId('${c['jeu']}')!, analyseDuCas(id), port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      return r.lot!;
    }

    test('LOT 8, stock détail initial : posé, puis annulation refusée détail dispensé (RG-03), puis sous un mouvement postérieur, puis réussie', () {
      final S = (V['stock'] as Map).cast<String, Object?>();
      final lot = poser('sd-valide');
      memes(stocks(['DOLIP']), S['detailPose'], 'detailPose');
      final avant = lu('DOLIP')['stockDetail'] as num;
      port.mettreAJour('produits', lu('DOLIP')['id'], {'stockDetail': avant - 10});
      var r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      memes(refusDe(r), S['detailDejaDispense'], 'detailDejaDispense');
      port.mettreAJour('produits', lu('DOLIP')['id'], {'stockDetail': avant});
      final mvx = port.inserer('mouvements', {'reference': 'M000060', 'date': '2026-11-01', 'produitId': lu('DOLIP')['id'], 'produit': 'DOLIPRANE 1 G B/8', 'type': 'sortie', 'typeLabel': 'Sortie', 'quantite': 1});
      r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      memes(refusDe(r), S['detailMouvementPosterieur'], 'detailMouvementPosterieur');
      port.archiver('mouvements', mvx['id'], 'test');
      r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      final att = (S['detailAnnule'] as Map).cast<String, Object?>();
      expect(r.ok, att['ok']);
      expect(r.archives, att['archives']);
      memes(stocks(['DOLIP']), att['stocks'], 'detailAnnule.stocks');
    });

    test('LOT 8, bon de transfert : le bon et ses deux mouvements par ligne, annulation refusée si dispensé, puis restitue gros ET détail ; magasin qui bouge : MAGASIN_CHANGE', () {
      final S = (V['stock'] as Map).cast<String, Object?>();
      final lot = poser('tl-valide');
      memes(stocks(['AMOXI', 'COTON']), S['transfertPose'], 'transfertPose');
      final bon = port.toutes('transferts').firstWhere((b) => b['lotImport'] == lot['reference']);
      memes(_net(bon, {}), S['transfertBon'], 'transfertBon');
      final am = lu('AMOXI')['stockDetail'];
      port.mettreAJour('produits', lu('AMOXI')['id'], {'stockDetail': 3});
      var r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      memes(refusDe(r), S['transfertDejaDispense'], 'transfertDejaDispense');
      port.mettreAJour('produits', lu('AMOXI')['id'], {'stockDetail': am});
      r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      final att = (S['transfertAnnule'] as Map).cast<String, Object?>();
      expect(r.ok, att['ok']);
      expect(r.archives, att['archives']);
      memes(stocks(['AMOXI', 'COTON']), att['stocks'], 'transfertAnnule.stocks');
      final analyse = analyseDuCas('tl-valide');
      final g = lu('COTON')['stockGros'];
      port.mettreAJour('produits', lu('COTON')['id'], {'stockGros': 1});
      final m = appliquer(jeuTransfertLignes, analyse, port);
      port.mettreAJour('produits', lu('COTON')['id'], {'stockGros': g});
      final mc = (S['magasinChange'] as Map).cast<String, Object?>();
      expect(m.ok, mc['ok']);
      expect(m.code, mc['code']);
    });

    test('LOT 8, comptage : une feuille par magasin nommé, aucun stock touché ; annulation refusée une fois la feuille régularisée', () {
      final S = (V['stock'] as Map).cast<String, Object?>();
      final avantStocks = stocks(['AMOXI', 'COTON', 'SIROP']);
      final lot = poser('ic-valide');
      memes(stocks(['AMOXI', 'COTON', 'SIROP']), avantStocks, 'le comptage ne touche aucun stock');
      final feuilles = [for (final f in port.toutes('inventaires')) if (f['lotImport'] == lot['reference']) f];
      memes([for (final f in feuilles) _net(f, {})], S['feuilles'], 'feuilles');
      final gros = feuilles.firstWhere((f) => f['magasin'] == 'gros');
      gros['statutInv'] = 'valide';
      final r = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      memes(refusDe(r), S['inventaireRegularise'], 'inventaireRegularise');
      gros['statutInv'] = 'importe';
      final ok = annulerLot(jeuImportParId, lot['id'], 'essai', port);
      final att = (S['comptageAnnule'] as Map).cast<String, Object?>();
      expect(ok.ok, att['ok']);
      expect(ok.archives, att['archives']);
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

  group('le droit d\'import tenu par le moteur (lot IMP-C)', () {
    final D = (V['droits'] as Map).cast<String, Object?>();
    List<List<Object?>> lignesDuCas(String id) {
      final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
      return [
        for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
      ];
    }

    String sansRef(Object? m) => '$m'.replaceAll(RegExp(r'IMP-\d{4}-\d{3}'), 'IMP-REF');

    test('l\'analyse sans le droit d\'importer est REFUSÉE en nommant, et rien n\'est consigné', () {
      final att = (D['analyseSansDroit'] as Map).cast<String, Object?>();
      final port = MagasinMemoire(magasinInitial, profil: profilDe('${att['role']}'));
      final a = analyserLignes(jeuFournisseurs, lignesDuCas('fo-valide'), 'fo-valide.xlsx', port);
      expect(a.accepte, att['accepte']);
      expect(a.droitRefuse, att['droitRefuse']);
      expect([for (final p in a.problemes) p.code], att['codes']);
      expect(a.globaux.single.motif.replaceAll('Caissier — Dispensaire (Pharmacie)', 'caissier'), contains('ne détient pas le droit de importer le jeu « Importation des fournisseurs »'));
      expect(a.globaux.single.geste, att['geste']);
      final avant = port.toutes(collectionLots).length;
      expect(consigner(jeuFournisseurs, a, port), isNull, reason: 'rien n\'a été tenté par un détenteur du droit');
      expect(port.toutes(collectionLots).length - avant, att['lotsAjoutes']);
    });

    test('l\'application relit le droit AU MOMENT D\'ÉCRIRE : analysé par qui peut, appliqué par qui ne peut pas, rien n\'est écrit', () {
      final att = (D['applicationSansDroit'] as Map).cast<String, Object?>();
      final port = MagasinMemoire(magasinInitial);
      final a = analyserLignes(jeuPatients, lignesDuCas('pa-valide'), 'pa-valide.xlsx', port);
      expect(a.accepte, isTrue);
      final patients = port.toutes('patients').length, lots = port.toutes(collectionLots).length;
      port.profil = profilDe('${att['role']}');
      final r = appliquer(jeuPatients, a, port);
      expect(r.ok, att['ok']);
      expect(r.code, att['code']);
      expect(port.toutes('patients').length - patients, att['patientsAjoutes']);
      expect(port.toutes(collectionLots).length - lots, att['lotsAjoutes']);
    });

    test('l\'annulation : sans le droit d\'annuler, puis le lot d\'un AUTRE agent (LOT_D_UN_AUTRE) ; l\'auteur et la supervision le défont', () {
      final att = (D['annulation'] as Map).cast<String, Object?>();
      final port = MagasinMemoire(magasinInitial);
      final r0 = appliquer(jeuGrandStock, analyserLignes(jeuGrandStock, lignesDuCas('gs-valide'), 'gs-valide.xlsx', port), port);
      expect(r0.ok, isTrue, reason: '${r0.motif}');
      final lot = r0.lot!['id'];
      port
        ..profil = profilDe('caissier')
        ..utilisateurFixe = 'CAISSIER TEST';
      var r = annulerLot(jeuImportParId, lot, 'essai', port);
      expect(r.code, (att['sansDroit'] as Map)['code']);
      port
        ..profil = profilDe('stock')
        ..utilisateurFixe = 'STOCK TEST';
      r = annulerLot(jeuImportParId, lot, 'essai', port);
      expect(r.code, (att['dUnAutre'] as Map)['code']);
      expect(sansRef(r.motif), sansRef((att['dUnAutre'] as Map)['motif']));
      expect(r.geste, (att['dUnAutre'] as Map)['geste']);
      expect(port.parId(collectionLots, lot)!['etat'], att['etatLot'], reason: 'le lot reste appliqué');
      // La supervision (droit d'annuler sur CHAQUE jeu) lit les lots de tous.
      port
        ..profil = profilDe('da')
        ..utilisateurFixe = 'DA TEST';
      expect(matriceReelle.supervise('da'), isTrue);
      expect(annulerLot(jeuImportParId, lot, 'supervision', port).ok, isTrue);
    });

    test('la taille maximale d\'un fichier est un réglage en base par jeu : refus nommé au-delà', () {
      final att = (D['borne'] as Map).cast<String, Object?>();
      final port = MagasinMemoire(magasinInitial, profil: profilDe('admin', bornes: {'fournisseurs': att['borne'] as int}));
      final a = analyserLignes(jeuFournisseurs, lignesDuCas('fo-valide'), 'fo-valide.xlsx', port);
      expect(a.accepte, att['accepte']);
      expect([for (final p in a.problemes) p.code], att['codes']);
      expect(a.globaux.single.motif, att['motif']);
      expect(ProfilImport.borneParDefaut, 5000, reason: 'sans réglage, le défaut de la maquette');
    });

    test('régler la taille maximale : réservé à qui SUPERVISE, entier de 1 à 100 000, motivé, jeu connu (mesuré sur la maquette)', () {
      final att = (D['reglageBorne'] as Map).cast<String, Object?>();
      ResultatBorneImport regler(String role, String jeu, Object? n, String motif) =>
          definirBorneImport(jeu, n, motif, MagasinMemoire(magasinInitial, profil: profilDe(role)), jeu: jeuImportParId);
      final essais = <String, ResultatBorneImport>{
        'sansSupervision': regler('stock', 'fournisseurs', 100, 'essai'),
        'invalide': regler('da', 'fournisseurs', 'abc', 'essai'),
        'zero': regler('da', 'fournisseurs', 0, 'essai'),
        'trop': regler('da', 'fournisseurs', 100001, 'essai'),
        'decimal': regler('da', 'fournisseurs', 12.5, 'essai'),
        'sansMotif': regler('da', 'fournisseurs', 100, ' '),
        'inconnu': regler('da', 'nimporte-quoi', 100, 'essai'),
        'ok': regler('da', 'fournisseurs', 8000, 'Grosse reprise'),
      };
      for (final e in essais.entries) {
        final a = (att[e.key] as Map).cast<String, Object?>();
        expect([e.value.ok, e.value.code], [a['ok'], a['code']], reason: e.key);
      }
      final ok = essais['ok']!;
      expect([ok.avant, ok.lignes], [(att['ok'] as Map)['avant'], (att['ok'] as Map)['lignes']]);
      expect(ok.bornes, {for (final e in (att['lu'] as Map).entries) '${e.key}': (e.value as num).toInt()});
    });

    test('la capacité paie se lit de la matrice : un profil qui importe le personnel sans écrire dans la paie n\'a pas la colonne « Salaire de base »', () {
      final att = (D['capacitePaie'] as Map).cast<String, Object?>();
      final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
      final base = MatriceDroits.depuisJson(brut);
      final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
      final jeuRbac = [for (final f in jsonDecode(File('../../apps/poste/assets/donnees/jeu/rbac.json').readAsStringSync()) as List) (f as Map).cast<String, Object?>()];
      final m = superposerDroits(base, manifeste, rbac: [
        ...jeuRbac,
        {'role': 'agentadmin', 'statut': 'actif', 'droitsImport': {'personnel': {'voir': true, 'importer': true, 'annuler': false}}}
      ]);
      ProfilImport profil(String r) => ProfilImport(role: r, libelleRole: r == 'agentadmin' ? 'Agent Administratif' : 'Administrateur', matrice: m.matriceImport);
      expect(profil('admin').capacitePaie, isTrue);
      expect(profil('agentadmin').capacitePaie, isFalse);
      final tete = [for (final c in jeuPersonnel.colonnes) c.label];
      final base0 = {'matricule': '88', 'nom': 'NOUVEAU', 'prenom': 'Agent', 'sexe': 'F', 'fonction': 'infirmier', 'poste': 'Infirmière', 'service': 'Soins infirmiers'};
      List<Object?> ligne(Map<String, Object?> o) => [for (final c in jeuPersonnel.colonnes) o[c.cle] ?? ''];
      final avec = [tete, ligne({...base0, 'salaireBase': 150000})];
      final sans = [
        [for (final c in jeuPersonnel.colonnes) if (c.cle != 'salaireBase') c.label],
        [for (final c in jeuPersonnel.colonnes) if (c.cle != 'salaireBase') base0[c.cle] ?? '']
      ];
      List<String> noms(AnalyseImport a) => [for (final p in a.problemes) '${p.code}:${p.niveau}'];
      var port = MagasinMemoire(magasinInitial, profil: profil('admin'));
      var a = analyserLignes(jeuPersonnel, avec, 'x.xlsx', port);
      expect([a.accepte, noms(a)], [(att['avecSalaireAdmin'] as Map)['accepte'], (att['avecSalaireAdmin'] as Map)['codes']]);
      port = MagasinMemoire(magasinInitial, profil: profil('agentadmin'));
      a = analyserLignes(jeuPersonnel, avec, 'x.xlsx', port);
      expect([a.accepte, noms(a)], [(att['avecSalaireAgent'] as Map)['accepte'], (att['avecSalaireAgent'] as Map)['codes']]);
      expect(a.globaux.single.motif, (att['avecSalaireAgent'] as Map)['motif']);
      a = analyserLignes(jeuPersonnel, sans, 'x.xlsx', port);
      expect([a.accepte, noms(a)], [(att['sansSalaireAgent'] as Map)['accepte'], (att['sansSalaireAgent'] as Map)['codes']],
          reason: 'sans la colonne, pas d\'avertissement « salaire absent » : elle n\'est pas dans son modèle');
      expect([for (final x in modeleImport(jeuPersonnel, port).donnees.first) '$x'], att['modeleAgent']);
      port = MagasinMemoire(magasinInitial, profil: profil('admin'));
      expect([for (final x in modeleImport(jeuPersonnel, port).donnees.first) '$x'], att['modeleAdmin']);
    });

    test('UN JEU RESTREINT NE RECOPIE JAMAIS UNE VALEUR DE CELLULE : ce qui entre à l\'historique et au rapport est masqué, motif fixe par code', () {
      var restreints = 0, lisibles = 0;
      for (final c in liste(V['cas'])) {
        final jeu = jeuImportParId('${c['jeu']}')!;
        final port = MagasinMemoire(magasinInitial);
        final a = analyserLignes(jeu, lignesDuCas('${c['id']}'), '${c['id']}.xlsx', port);
        final att = liste((c['attendu'] as Map)['consignes']);
        final obtenus = [
          for (final p in problemesConsignes(jeu, a, port)) {'n': p.n, 'colonne': p.colonne, 'code': p.code, 'niveau': p.niveau, 'valeur': texteDe(p.valeur), 'motif': p.motif}
        ];
        memes(obtenus, att, '${c['id']}.consignes');
        if (port.profil.restreint(jeu.id)) {
          restreints++;
          for (final p in obtenus) {
            expect(p['valeur'], '', reason: '${c['id']} : ${p['code']} recopie une valeur');
          }
        } else {
          lisibles++;
        }
      }
      expect(restreints, greaterThan(10));
      expect(lisibles, greaterThan(10));
    });

    test('un fichier REFUSÉ d\'un jeu restreint est consigné sans aucune valeur de cellule ; le rapport n\'a plus de colonne « Valeur »', () {
      final port = MagasinMemoire(magasinInitial);
      final a = analyserLignes(jeuPatients, lignesDuCas('pa-code-existant'), 'pa-code-existant.xlsx', port);
      expect(a.accepte, isFalse);
      expect([for (final p in a.problemes) p.valeur].any((v) => '$v'.contains('CNT/1/25')), isTrue, reason: 'à l\'écran de la vérification, la valeur se lit');
      final lot = consigner(jeuPatients, a, port)!;
      final erreurs = (lot['erreurs'] as List).cast<Map>();
      expect(erreurs, isNotEmpty);
      expect(jsonEncode(erreurs), isNot(contains('CNT/1/25')), reason: 'l\'historique ne recopie aucun code patient');
      expect(jsonEncode(erreurs), isNot(contains('TCHANE')), reason: 'ni le nom du patient déjà tenu');
      final rap = rapportImport([for (final e in erreurs) e.cast<String, Object?>()], sansValeur: true);
      expect(rap.first, ['Ligne', 'Colonne', 'Niveau', 'Code', 'Motif', 'Geste de correction']);
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
