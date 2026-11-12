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

/// L'IMPORT DIRECT D'UN FILEUL CONTRE LA VRAIE MÈRE (lot IMP-D, décision N du 12/11/2026) : un fileul écrit chez lui ET la mère en est avertie par une demande automatique.
///  1. la mère APPLIQUE : mêmes identifiants, une seule fiche par code chez les deux fileuls, marquage levé, lot confirmé non annulable chez le fileul ;
///  2. la mère est INJOIGNABLE (arrêtée pour de vrai) : le fileul garde son écriture, la demande attend, rien n'est dit « appliqué » ; elle revient : DEUX fileuls ont importé le MÊME code,
///     la première demande est appliquée, la seconde refusée en nommant, le second fileul restitue ;
///  3. la mère REFUSE (résultat différent) : le fileul restitue, la fiche qu'une pièce émise utilise reste, marquée ; le verdict se lit sur sa demande ;
///  4. JAMAIS vers un téléphone (RG-13) : ni la demande, ni ses lignes, ni son verdict, ni la restitution.
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

/// Un poste fileul complet : moteur de synchronisation, magasin gardé « réglé sur la mère », applicateur de configuration, pont d'activité.
class Poste {
  Poste(this.nom, this.port, this.role, this.par) {
    moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    appl = ApplicateurConfiguration(m, moteur.liste)..poserGardes();
    pont = PontActivite(
        m, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: nom);
    imp = DemandesImportPoste(m, role: role, auteur: () => par, matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 12, 9), etiquette: nom);
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

  ({ResultatImport resultat, Fiche? demande}) importer(String jeu, String cas) {
    final profil = ProfilImport(role: role, libelleRole: role, matrice: donnees.matrice.matriceImport);
    final a = analyserLignes(jeuImportParId(jeu)!, lignesDuCas(cas), '$cas.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 12), nomAgent: par, profil: profil))..empreinte = 'e-$cas';
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
    return imp.importerEtDemander(jeuImportParId(jeu)!, a);
  }

  List<Fiche> actives(String col, String code) => [for (final f in m.collection(col).actives) if (f['code'] == code) f];
  Fiche? demande(Object? id) => m.collection(demandesImportCollection).parId(id);
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
    mere = await Mere.creer(ConfigMere(port: port, dbChemin: dbChemin, admin: 'secret-test', dossierSauvegardes: '${File(dbChemin).parent.path}/sauvegardes'));
    await mere.demarrer();
    console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
  }

  Future<void> demarrer() async {
    await demarrerMere();
    pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    service = ServiceDemandesImport(mm, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 12));
  }

  Future<Poste> fileul(String nom, String role, String par) async {
    final p = Poste(nom, port, role, par);
    final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
    await p.moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    p.moteur.demarrer();
    fileuls.add(p);
    return p;
  }

  /// Un tour de toute la clinique, MÈRE JOIGNABLE : configuration, ponts, service de la mère, puis chaque fileul suit son verdict.
  Future<void> tour() async {
    await pub.pousser();
    await pontM.cycle();
    await service.traiter();
    for (final f in fileuls) {
      await f.tour();
    }
  }

  Future<void> converger(bool Function() fini, String quoi) async {
    final fin = DateTime.now().add(const Duration(seconds: 60));
    while (!fini()) {
      await tour();
      if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, pontM ${pontM.erreur.value}, service ${service.derniereErreur}, fileuls ${[for (final f in fileuls) '${f.nom}: ${f.appl.erreur.value}/${f.pont.erreur.value}']})');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
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

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-imp-d-'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('CAS 1, LA MÈRE APPLIQUE : le fileul écrit chez lui, la mère rejoue et confirme avec les MÊMES identifiants ; une seule fiche par code chez les deux fileuls ; marquage levé ; lot confirmé non annulable chez le fileul', () async {
    final c = Clinique(9411, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r = f1.importer('fournisseurs', 'fo-valide');
      expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
      final id = '${r.demande!['id']}';
      expect(f1.actives('fournisseurs', 'CAME'), hasLength(1), reason: 'écrit chez le fileul tout de suite, sans attendre la mère');
      expect(f1.actives('fournisseurs', 'CAME').single[champEnAttenteMere], id);
      expect(f1.actives('fournisseurs', 'CAME').single['id'], 'FOU-$id-1');
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportAppliquee && f1.demande(id)?['marquageLeve'] == true, 'la mère confirme, le fileul lève le marquage');
      final v = f1.demande(id)!;
      expect([v['resultatEcrits'], v['traitePar'], v['lignes']], [2, 'Mère', isEmpty]);
      final surMere = c.mm.collection('fournisseurs').actives.where((f) => f['lotImport'] == v['resultatLot']).toList();
      expect({for (final f in surMere) '${f['id']}'}, {'FOU-$id-1', 'FOU-$id-2'}, reason: 'la mère rejoue avec les identifiants de la demande');
      expect(surMere.every((f) => f['validePar'] == 'GESTIONNAIRE UN'), isTrue, reason: 'au nom de l\'auteur (RG-12)');
      // Une identité de ligne : aucun doublon chez le fileul qui a écrit, ni chez l'autre qui a reçu la configuration.
      await c.converger(() => f2.actives('fournisseurs', 'CAME').isNotEmpty, 'la configuration de la mère arrive au second fileul');
      for (final f in [f1, f2]) {
        expect(f.actives('fournisseurs', 'CAME'), hasLength(1), reason: '${f.nom} : une fiche par code');
        expect(f.actives('fournisseurs', 'LOCAL'), hasLength(1));
        expect(f.m.collection('fournisseurs').actives.where((x) => x.containsKey(champEnAttenteMere)), isEmpty, reason: '${f.nom} : plus rien « en attente »');
      }
      expect(f1.actives('fournisseurs', 'CAME').single.containsKey('lotImport'), isTrue);
      expect(f1.actives('fournisseurs', 'CAME').single['lotImport'], v['resultatLot'], reason: 'la fiche de la mère a remplacé celle du fileul');
      final annul = f1.imp.annulerLotDuFileul(r.resultat.lot!['id']);
      expect([annul.ok, annul.code], [false, 'LOT_CONFIRME_PAR_LA_MERE']);
      // JAMAIS vers un téléphone (RG-13).
      expect(await _collectionsRecuesParUnMobile(c.port), isNot(contains(demandesImportCollection)));
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 3, LA MÈRE EST INJOIGNABLE puis revient : le fileul garde son écriture, rien n\'est « appliqué » ; DEUX fileuls importent le même code : la première demande est appliquée, la seconde refusée, le second fileul restitue', () async {
    final c = Clinique(9412, '${tmp.path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      final f2 = await c.fileul('F2', 'comptable', 'COMPTABLE DEUX');
      await c.tour();
      // La mère s'ARRÊTE pour de vrai (réseau coupé, processus arrêté).
      await c.mere.arreter();
      final r1 = f1.importer('assureurs', 'as-valide');
      final r2 = f2.importer('assureurs', 'as-valide');
      expect(r1.resultat.ok && r2.resultat.ok, isTrue, reason: 'chacun écrit chez lui, la mère n\'est pas consultée');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      for (var i = 0; i < 4; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      for (final (f, id) in [(f1, id1), (f2, id2)]) {
        expect(f.demande(id)!['etat'], demandeImportEnAttente, reason: '${f.nom} : la mère n\'a pas répondu, la demande attend dans sa file');
        expect(libelleEtatDemandeImport(f.demande(id)!).libelle, 'Écrit chez vous, en attente de la mère');
        expect(f.actives('assureurs', 'SUNU'), hasLength(1), reason: 'le fileul garde son écriture locale');
        expect(f.actives('assureurs', 'SUNU').single[champEnAttenteMere], id, reason: 'marquée « en attente de la mère »');
      }
      expect(c.mm.collection(demandesImportCollection).toutes, isEmpty, reason: 'la mère n\'a rien reçu');
      // Elle revient (même base, même port) : les deux demandes qui attendaient dans les files arrivent.
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] == restitutionFaite, 'la mère revient et tranche');
      final v2 = f2.demande(id2)!;
      expect(v2['resultatCode'], 'DOUBLON_MAGASIN', reason: 'le même code a été importé par un autre poste : refus nommé');
      expect(v2['resultatMotif'], contains('rejoué à la mère'));
      expect(v2['resultatGeste'], isNotEmpty);
      expect(libelleEtatDemandeImport(v2).libelle, 'Refusée par la mère, écriture restituée');
      await c.converger(() => f1.actives('assureurs', 'SUNU').length == 1 && f2.actives('assureurs', 'SUNU').length == 1 && f2.actives('assureurs', 'SUNU').single['lotImport'] != null, 'une fiche par code chez les deux');
      for (final f in [f1, f2]) {
        expect(f.actives('assureurs', 'SUNU'), hasLength(1), reason: f.nom);
        expect(f.actives('assureurs', 'OLEA'), hasLength(1));
        expect(f.actives('assureurs', 'SUNU').single['id'], 'ASS-$id1-1', reason: '${f.nom} : la fiche de la première demande, celle de la mère');
        expect(f.m.collection('assureurs').actives.where((x) => x.containsKey(champEnAttenteMere)), isEmpty);
      }
      expect(f2.m.collection('assureurs').toutes.where((x) => x['statut'] == 'archive'), hasLength(2), reason: 'la restitution archive (RG-14), elle ne supprime rien');
      expect(f2.m.collection(collectionLots).toutes.single['etat'], 'restitue');
      expect(f1.m.collection(collectionLots).toutes.single['etat'], 'applique');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 2, LA MÈRE REFUSE : résultat différent, le fileul restitue ; la fiche qu\'une pièce émise utilise reste, marquée ; le verdict se lit sur sa demande', () async {
    final c = Clinique(9413, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      // Entre-temps, la mère reçoit la fiche CAME d'ailleurs (un autre poste) : elle n'écrirait pas la même chose que le fileul.
      c.mm.collection('fournisseurs').inserer({'id': 'FOU-AILLEURS', 'code': 'CAME', 'nom': 'CAME (créé ailleurs)', 'statut': 'actif'});
      final r = f1.importer('fournisseurs', 'fo-valide');
      final id = '${r.demande!['id']}';
      // Une pièce émise s'appuie déjà sur la fiche écrite chez le fileul avant le refus.
      f1.m.collection('commandes').inserer({'numero': 'BC-12', 'fournisseurCode': 'CAME', 'statut': 'actif'});
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportRefusee && f1.demande(id)?['restitution'] != null, 'le refus de la mère revient, le fileul restitue');
      final v = f1.demande(id)!;
      expect(v['resultatCode'], 'RESULTAT_DIFFERENT');
      expect(v['resultatMotif'], allOf(contains('pas le même résultat'), contains('ligne 2')));
      expect(v['restitution'], restitutionPartielle);
      expect((v['restitutionGardees'] as List).single['code'], 'FOURNISSEUR_UTILISE');
      expect(libelleEtatDemandeImport(v).libelle, 'Refusée par la mère, restitution partielle');
      expect(f1.m.collection('fournisseurs').toutes.firstWhere((f) => f['id'] == 'FOU-$id-1')['statut'], isNot('archive'), reason: 'une pièce émise ne se réécrit jamais');
      expect('${f1.m.collection('fournisseurs').toutes.firstWhere((f) => f['id'] == 'FOU-$id-1')[champRefuseeParMere]}', contains('RESULTAT_DIFFERENT'));
      expect(f1.actives('fournisseurs', 'LOCAL'), isEmpty, reason: 'l\'autre fiche, que rien n\'utilise, est restituée');
      expect(c.mm.collection('fournisseurs').actives.where((f) => f['code'] == 'LOCAL'), isEmpty, reason: 'rien n\'a été écrit à la mère');
      expect(c.mm.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), hasLength(1), reason: 'la mère l\'emporte : sa fiche est la seule qu\'elle tient');
      expect(await _collectionsRecuesParUnMobile(c.port), isNot(contains(demandesImportCollection)));
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}

/// Les collections qu'un téléphone du profil soignant reçoit de la mère (RG-13) : lues pour de vrai, jamais déduites.
Future<List<String>> _collectionsRecuesParUnMobile(int port) async {
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
    final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-mobile-$port', 'plateforme': 'test'});
    final noms = <String>[];
    var depuis = 0;
    while (true) {
      final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
      if (pull['ops'] == null) fail('pull du mobile à $depuis : $pull');
      final ops = (pull['ops'] as List).cast<Map>();
      for (final o in ops) {
        noms.add('${o['collection']}');
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
