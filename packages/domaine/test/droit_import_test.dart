import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

List<Fiche> _lire(String chemin) => [for (final f in jsonDecode(File(chemin).readAsStringSync()) as List) (f as Map).cast<String, Object?>()];

/// LE DROIT D'IMPORT PAR JEU (lot IMP-C) : lu de la section `import` de `rbac.json` (engendrée par la maquette, `N.droitImport`), superposé à chaud par les fiches RBAC
/// (`droitsImport`), jamais déduit du droit d'éditer l'écran `imp-*` ni d'un nom de rôle.
void main() {
  final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final base = MatriceDroits.depuisJson(brut);
  final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
  final jeuRbac = _lire('../../apps/poste/assets/donnees/jeu/rbac.json');
  final fichierModules = _lire('../../apps/poste/assets/donnees/jeu/modulesActifs.json');
  final jeuModules = [for (final f in fichierModules) if (f['proprePoste'] != true) f];
  final imp = (brut['import'] as Map).cast<String, Object?>();
  final attendu = (imp['parRole'] as Map).cast<String, Object?>();

  MatriceDroits calc({List<Fiche>? rbac, List<Fiche>? modules}) =>
      superposerDroits(base, manifeste, rbac: rbac ?? jeuRbac, modulesActifs: modules ?? jeuModules, referenceRbac: jeuRbac, referenceModules: jeuModules);
  MatriceDroits recalcule({List<Fiche>? rbac, List<Fiche>? modules}) => superposerDroits(base, manifeste, rbac: rbac ?? jeuRbac, modulesActifs: modules ?? jeuModules);
  List<int> t(DroitImport d) => [d.voir ? 1 : 0, d.importer ? 1 : 0, d.annuler ? 1 : 0];
  String d3(MatriceDroits m, String role, String jeu) => t(m.droitImport(role, jeu)).join();
  Fiche fiche(String role, Map<String, Object?> droitsImport) => {'role': role, 'statut': 'actif', 'droitsImport': droitsImport};

  test('la section import de rbac.json porte 22 rôles et 26 jeux, chacun avec ses hôtes, sa sensibilité, son doublon et sa matrice d\'origine', () {
    final jeux = ((imp['jeux'] as List).cast<Map>());
    expect(jeux.length, 26);
    expect(attendu.length, 22);
    for (final j in jeux) {
      expect(j['defaut'], isA<Map>(), reason: '${j['id']} : la matrice d\'origine est exportée (la superposition à chaud en a besoin)');
      expect(['courante', 'restreinte'], contains(j['sensibilite']));
      expect(['refuser', 'ignorer', 'versionner'], contains(j['doublon']));
    }
    expect(base.matriceImport.declarations.map((d) => d.id), jeux.map((j) => j['id']));
  });

  test('PARITÉ EXHAUSTIVE : chaque couple rôle × jeu de la matrice extraite se relit à l\'identique (voir, importer, annuler)', () {
    var n = 0;
    attendu.forEach((role, jeux) {
      (jeux as Map).forEach((jeu, c) {
        final v = (c as List).cast<num>();
        // `importer` et `annuler` supposent `voir`, comme `N.droitImport`.
        expect(t(base.droitImport(role, '$jeu')), [v[0], v[0] == 0 ? 0 : v[1], v[0] == 0 ? 0 : v[2]], reason: '$role → $jeu');
        n++;
      });
    });
    expect(n, 22 * 26);
  });

  test('PARITÉ À CHAUD : recalculée depuis les fiches RBAC et les activités fermées, la matrice d\'import égale celle que la maquette a extraite (22 rôles, 26 jeux)', () {
    for (final m in [calc(), recalcule()]) {
      attendu.forEach((role, jeux) {
        (jeux as Map).forEach((jeu, c) {
          final v = (c as List).cast<num>();
          expect(t(m.droitImport(role, '$jeu')), [v[0], v[0] == 0 ? 0 : v[1], v[0] == 0 ? 0 : v[2]], reason: '$role → $jeu');
        });
      });
      expect({for (final r in m.matriceImport.roles) if (m.matriceImport.supervise(r)) r}, {for (final r in (imp['superviseurs'] as List)) '$r'},
          reason: 'les superviseurs se TIRENT du droit d\'annuler sur chaque jeu');
      expect({for (final r in attendu.keys) if (m.matriceImport.aLaCapacitePaie(r)) r}, {for (final r in (imp['capacitePaie'] as List)) '$r'});
    }
  });

  test('un jeu ou un rôle inconnu est FERMÉ ; un rôle archivé n\'importe rien', () {
    expect(base.droitImport('role-invente', 'patients'), DroitImport.ferme('patients'));
    expect(base.droitImport('admin', 'jeu-inexistant'), DroitImport.ferme('jeu-inexistant'));
    final m = calc(rbac: [...jeuRbac, {'role': 'stock', 'statut': 'archive'}]);
    for (final d in m.matriceImport.declarations) {
      expect(m.droitImport('stock', d.id), DroitImport.ferme(d.id), reason: d.id);
    }
    expect(d3(m, 'admin', 'patients'), '111');
  });

  test('DÉCISION I4/I7 : le gestionnaire de stock importe le stock, les fournisseurs et les prix, ni les patients ni le personnel ; l\'assistant comptable ne fait que VOIR', () {
    for (final j in ['grand-stock', 'fournisseurs', 'tarifs', 'tarifs-produits', 'produits-referentiel', 'emplacements', 'stock-detail-initial', 'transfert-lignes', 'inventaire-comptage']) {
      expect(base.droitImport('stock', j).importer, isTrue, reason: j);
    }
    for (final j in ['patients', 'personnel', 'soldes-ouverture', 'budgets']) {
      expect(base.droitImport('stock', j).importer, isFalse, reason: j);
    }
    for (final j in base.matriceImport.declarations) {
      final d = base.droitImport('aide_comptable', j.id);
      expect(d.importer || d.annuler, isFalse, reason: 'l\'assistant comptable n\'importe aucun jeu : ${j.id}');
    }
  });

  test('LE DROIT D\'IMPORT N\'EST PAS LE DROIT D\'ÉDITER L\'ÉCRAN : le gestionnaire édite le référentiel produits sans importer pour autant le répertoire patients', () {
    expect(base.peutEditer('stock', 'm6-produits'), isTrue);
    expect(base.droitImport('stock', 'patients').importer, isFalse);
    // Un rôle qui ÉDITE l'écran hôte d'un jeu sans en détenir le droit n'a pas le bouton : on en trouve dans la matrice réelle.
    var sansLeDroit = 0, avecLeDroitSansEditer = 0;
    for (final d in base.matriceImport.declarations) {
      for (final r in base.matriceImport.roles) {
        final edite = d.hotes.any((h) => base.peutEditer(r, h));
        final importe = base.droitImport(r, d.id).importer;
        if (edite && !importe) sansLeDroit++;
        if (!edite && importe) avecLeDroitSansEditer++;
      }
    }
    expect(sansLeDroit, greaterThan(0), reason: 'éditer l\'écran hôte ne donne pas le droit d\'importer');
    expect(avecLeDroitSansEditer + sansLeDroit, greaterThan(0));
  });

  test('UNE SURCHARGE ACCORDE AUTANT QU\'ELLE RESTREINT : la fiche RBAC ouvre un jeu à un rôle qui ne l\'avait pas et le ferme à celui qui l\'avait', () {
    expect(d3(base, 'caissier', 'natures-facture'), '000');
    final m = calc(rbac: [
      ...jeuRbac,
      fiche('caissier', {'natures-facture': {'voir': true, 'importer': true, 'annuler': false}}),
      fiche('stock', {'emplacements': {'importer': false}}),
    ]);
    expect(d3(m, 'caissier', 'natures-facture'), '110', reason: 'accorde');
    expect(d3(m, 'stock', 'emplacements'), '101', reason: 'restreint champ par champ : il garde voir et annuler');
    expect(d3(m, 'stock', 'produits-referentiel'), '111', reason: 'les autres jeux ne bougent pas');
    // Retirer la lecture ferme tout le jeu : `importer` et `annuler` supposent `voir`.
    final f = calc(rbac: [...jeuRbac, fiche('admin', {'patients': {'voir': false}})]);
    expect(d3(f, 'admin', 'patients'), '000');
    // Deux fiches du même rôle : fusion jeu par jeu, la dernière l'emporte sur ce qu'elle définit seulement.
    final deux = calc(rbac: [
      ...jeuRbac,
      fiche('caissier', {'natures-facture': {'voir': true, 'importer': true}}),
      fiche('caissier', {'centres-couts': {'voir': true}}),
    ]);
    expect(d3(deux, 'caissier', 'natures-facture'), '110');
    expect(d3(deux, 'caissier', 'centres-couts'), '100');
  });

  test('un rôle CRÉÉ en exploitation part de zéro sur tous les jeux et s\'ouvre par surcharge', () {
    final nouveau = {'role': 'role-neuf', 'statut': 'actif', 'nouveau': true, 'libelle': 'Rôle neuf'};
    final m = calc(rbac: [...jeuRbac, nouveau]);
    for (final d in m.matriceImport.declarations) {
      expect(m.droitImport('role-neuf', d.id), DroitImport.ferme(d.id), reason: d.id);
    }
    final ouvert = calc(rbac: [
      ...jeuRbac,
      nouveau,
      fiche('role-neuf', {'courriers': {'voir': true, 'importer': true}})
    ]);
    expect(d3(ouvert, 'role-neuf', 'courriers'), '110');
  });

  test('une activité fermée ferme le jeu pour TOUS les rôles, administrateur compris ; fermer le module d\'import ferme tous les jeux ; une fermeture archivée ne ferme plus rien', () {
    final jeu = base.matriceImport.declaration('emplacements')!;
    final fermeEcran = {'id': 'F1', 'module': jeu.module, 'ecrans': [jeu.ecran], 'actif': false, 'statut': 'actif'};
    final m = calc(modules: [...jeuModules, fermeEcran]);
    expect(d3(m, 'admin', 'emplacements'), '000');
    expect(d3(m, 'stock', 'emplacements'), '000');
    expect(d3(m, 'admin', 'produits-referentiel'), '111', reason: 'les autres jeux restent ouverts');
    final fermeModule = {'id': 'F2', 'module': 'IMP', 'actif': false, 'statut': 'actif'};
    final tous = calc(modules: [...jeuModules, fermeModule]);
    for (final d in tous.matriceImport.declarations) {
      expect(tous.droitImport('admin', d.id), DroitImport.ferme(d.id), reason: d.id);
    }
    final archivee = calc(modules: [
      ...jeuModules,
      {...fermeEcran, 'statut': 'archive'}
    ]);
    expect(d3(archivee, 'admin', 'emplacements'), '111');
  });

  test('chaque jeu déclare au moins un hôte parmi les écrans du manifeste, ou aucun (jeu sans bouton) ; chaque écran de jeu existe au manifeste', () {
    for (final d in base.matriceImport.declarations) {
      expect(manifeste.ecran(d.ecran), isNotNull, reason: '${d.id} : écran ${d.ecran}');
      for (final h in d.hotes) {
        expect(manifeste.ecran(h), isNotNull, reason: '${d.id} : hôte $h');
      }
    }
  });
}
