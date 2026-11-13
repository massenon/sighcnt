import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/demandes_import_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// OUTILS DES TESTS DU GRAND STOCK AU FILEUL (lot IMP-E, décision de la Direction du 13/11/2026) : la VRAIE mère Dart, de VRAIS moteurs de fileul, le câblage de `main.dart`
/// (le fileul ne publie JAMAIS le catalogue `produits`, il en reçoit la configuration, et ses stocks voyagent par leurs variations).
typedef M = Map<String, Object?>;
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin vide() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

List<List<Object?>> lignesDuCas(String id) {
  final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == id);
  return [
    for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
  ];
}

/// Le Grand Stock du vecteur `gs-valide` : MED1 (deux lots, 100 + 50) et GANT1 (40, sans lot). Total des entrées : 190, trois mouvements.
const stockMed1 = 150, stockGant1 = 40;

class Poste {
  Poste(this.nom, this.port, this.role, this.par) {
    moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    appl = ApplicateurConfiguration(m, moteur.liste)..poserGardes();
    pont = PontActivite(
        m, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: nom, enLectureSeule: collectionsDeLaMereSeule);
    imp = DemandesImportPoste(m, role: role, auteur: () => par, matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 13, 9), etiquette: nom);
  }
  final String nom, role, par;
  final int port;
  final Magasin m = vide();
  late final MoteurFileul moteur;
  late final ApplicateurConfiguration appl;
  late final PontActivite pont;
  late final DemandesImportPoste imp;

  Future<void> tour() async {
    try {
      await appl.tirer();
      await pont.cycle();
    } catch (_) {/* mère injoignable : le fileul garde sa file et réessaie */}
    imp.traiterVerdicts();
  }

  AnalyseImport analyser(String cas) {
    final profil = ProfilImport(role: role, libelleRole: role, matrice: donnees.matrice.matriceImport);
    final a = analyserLignes(jeuImportParId('grand-stock')!, lignesDuCas(cas), '$cas.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 13), nomAgent: par, profil: profil))
      ..empreinte = 'e-$cas';
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
    return a;
  }

  ({ResultatImport resultat, Fiche? demande}) importer(String cas) => imp.importerEtDemander(jeuImportParId('grand-stock')!, analyser(cas));

  /// Une SORTIE de stock du poste (dispensation) : le lot, le produit et un mouvement de sortie, comme le geste réel.
  void sortir(String code, String numeroLot, int q) {
    final p = m.collection('produits').actives.firstWhere((x) => x['code'] == code);
    final l = m.collection('lots').actives.firstWhere((x) => x['produitId'] == p['id'] && x['numeroLot'] == numeroLot);
    m.collection('lots').mettreAJour(l['id'], {'quantiteRestante': (l['quantiteRestante'] as num) - q});
    m.collection('produits').mettreAJour(p['id'], {'stockGros': (p['stockGros'] as num) - q, 'stock': (p['stock'] as num) - q});
    m.collection('mouvements').inserer({'reference': 'S-${m.collection('mouvements').toutes.length}', 'produitId': p['id'], 'produit': p['designation'], 'type': 'sortie', 'typeLabel': 'Sortie', 'quantite': q, 'stockType': 'gros', 'justificatif': 'ORD-test'});
  }

  Fiche? demande(Object? id) => m.collection(demandesImportCollection).parId(id);
  List<Fiche> produits(String code) => [for (final f in m.collection('produits').actives) if (f['code'] == code) f];

  /// Le stock de chaque article ACTIF par code, tel que ce poste le tient : somme du compteur, nombre de fiches, somme des lots, nombre de mouvements d'entrée de l'import.
  Map<String, Object?> etat(String code) {
    final ps = produits(code);
    final ids = {for (final p in ps) p['id']};
    final lots = [for (final l in m.collection('lots').actives) if (ids.contains(l['produitId'])) l];
    final mouvs = [for (final x in m.collection('mouvements').actives) if (ids.contains(x['produitId']) && x['type'] == 'entree' && '${x['justificatif']}'.startsWith('Import')) x];
    return {
      'fichesProduit': ps.length,
      'stockGros': ps.fold<num>(0, (t, p) => t + ((p['stockGros'] as num?) ?? 0)),
      'fichesLot': lots.length,
      'sommeLots': lots.fold<num>(0, (t, l) => t + ((l['quantiteRestante'] as num?) ?? 0)),
      'mouvementsEntree': mouvs.length,
      'sommeEntrees': mouvs.fold<num>(0, (t, x) => t + ((x['quantite'] as num?) ?? 0)),
    };
  }
}

class Clinique {
  Clinique(this.port, this.dbChemin);
  final int port;
  final String dbChemin;
  late Mere mere;
  late ClientMere console;
  final Magasin mm = vide();
  late final PublicateurConfiguration pub;
  late final PontActivite pontM;
  late final ServiceDemandesImport service;
  final fileuls = <Poste>[];

  Future<void> demarrerMere() async {
    mere = await Mere.creer(ConfigMere(port: port, dbChemin: dbChemin, admin: 'secret-test', dossierSauvegardes: '${Directory.systemTemp.path}/sauv-grand-stock-$port'));
    await mere.demarrer();
    console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
  }

  Future<void> demarrer() async {
    await demarrerMere();
    pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    service = ServiceDemandesImport(mm, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 13));
  }

  Future<Poste> fileul(String nom, String role, String par) async {
    final p = Poste(nom, port, role, par);
    final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
    await p.moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    p.moteur.demarrer();
    fileuls.add(p);
    return p;
  }

  /// Un tour de toute la clinique, MÈRE JOIGNABLE : configuration, pont de la mère, service des demandes, puis chaque fileul.
  Future<void> tour() async {
    await pub.pousser();
    await pontM.cycle();
    await service.traiter();
    for (final f in fileuls) {
      await f.tour();
    }
  }

  /// Des tours jusqu'à ce que [fini] soit vrai, puis [apres] tours de plus (pour laisser le temps à un doublon éventuel d'apparaître : une mesure qui s'arrête à la première
  /// convergence ne verrait jamais un compte doublé par un second passage).
  Future<void> converger(bool Function() fini, String quoi, {int apres = 3}) async {
    final fin = DateTime.now().add(const Duration(seconds: 60));
    while (!fini()) {
      await tour();
      if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, pontM ${pontM.erreur.value}, service ${service.derniereErreur}, fileuls ${[for (final f in fileuls) '${f.nom}: ${f.appl.erreur.value}/${f.pont.erreur.value}']})');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    for (var i = 0; i < apres; i++) {
      await tour();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// L'état d'un article à la MÈRE (mêmes comptes que [Poste.etat]).
  Map<String, Object?> etatMere(String code) {
    final ps = [for (final f in mm.collection('produits').actives) if (f['code'] == code) f];
    final ids = {for (final p in ps) p['id']};
    final lots = [for (final l in mm.collection('lots').actives) if (ids.contains(l['produitId'])) l];
    final mouvs = [for (final x in mm.collection('mouvements').actives) if (ids.contains(x['produitId']) && x['type'] == 'entree' && '${x['justificatif']}'.startsWith('Import')) x];
    return {
      'fichesProduit': ps.length,
      'stockGros': ps.fold<num>(0, (t, p) => t + ((p['stockGros'] as num?) ?? 0)),
      'fichesLot': lots.length,
      'sommeLots': lots.fold<num>(0, (t, l) => t + ((l['quantiteRestante'] as num?) ?? 0)),
      'mouvementsEntree': mouvs.length,
      'sommeEntrees': mouvs.fold<num>(0, (t, x) => t + ((x['quantite'] as num?) ?? 0)),
    };
  }

  Future<void> arreter() async {
    for (final f in fileuls) {
      f.appl.arreter();
    }
    pub.arreter();
    service.arreter();
    try {
      await mere.arreter();
    } catch (_) {}
  }
}

/// Les collections qu'un téléphone du profil soignant reçoit de la mère (RG-13) : lues pour de vrai, jamais déduites.
Future<List<({String collection, String fiche})>> collectionsRecuesParUnMobile(int port) async {
  final http0 = HttpClient();
  Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
    final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
    req.headers.contentType = ContentType.json;
    entetes.forEach(req.headers.set);
    if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
    final rep = await req.close();
    return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
  }

  try {
    final c = (await appel('POST', '/admin/code', corps: {'etiquette': 'mobile', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}, entetes: {'x-admin': 'secret-test'}))['code'];
    final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-mobile-$port-${DateTime.now().microsecondsSinceEpoch}', 'plateforme': 'test'});
    final noms = <({String collection, String fiche})>[];
    var depuis = 0;
    while (true) {
      final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
      if (pull['ops'] == null) fail('pull du mobile à $depuis : $pull');
      final ops = (pull['ops'] as List).cast<Map>();
      for (final o in ops) {
        noms.add((collection: '${o['collection']}', fiche: '${o['fiche']}'));
        depuis = (o['seq'] as num).toInt();
      }
      if (pull['fin'] == true || ops.isEmpty) break;
    }
    expect(noms, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence est une EXCLUSION, pas un journal vide');
    return noms;
  } finally {
    http0.close(force: true);
  }
}
