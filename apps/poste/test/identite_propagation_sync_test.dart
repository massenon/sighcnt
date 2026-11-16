import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/demandes_identite_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/identite_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_identite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LOT IDENT : UNE MISE À JOUR DES INFORMATIONS DE LA CLINIQUE SE PROPAGE PARTOUT, contre la VRAIE mère et DEUX vrais moteurs de fileul.
///
/// MESURE D'ABORD (état de départ, constaté par ce même banc avant le lot) :
///  - `identiteLegale` voyageait de la mère aux fileuls, mais AUSSI aux téléphones ; `reglages` (où vivaient les options d'impression) ne voyageait pas ;
///  - un fileul ne pouvait poser aucune version ; aucun refus de droit au moteur.
/// ICI : un profil habilité d'un fileul SIGNE et DÉPOSE ; la mère revérifie sous le rôle de l'auteur et propage ; les options d'impression voyagent ; rien vers un téléphone.
typedef M = Map<String, Object?>;
const cleSqlite = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
final donnees = DonneesNavigation.depuisDossier();

Magasin poste() => Magasin({
      'identiteLegale': <M>[],
      'optionsImpression': <M>[],
      'demandesIdentite': <M>[],
      'exercices': <M>[],
      'reglages': <M>[],
      'audit': const [],
    });

void main() {
  test('MESURE : ce qui voyage de la clinique est dit par les listes, pas supposé', () {
    expect(collectionsConfiguration(), contains('identiteLegale'), reason: 'les versions de l’identité voyagent de la mère aux postes');
    expect(collectionsConfiguration(), contains(idCollectionOptions), reason: 'les options d’impression voyagent désormais avec l’identité');
    expect(collectionsConfiguration(), isNot(contains('reglages')), reason: 'les réglages locaux (où vivaient les options) ne voyagent PAS : c’est le défaut mesuré');
    expect(familles[idCollectionDemandes], 'A');
    expect(familles[idCollectionOptions], 'R');
    expect(familles['identiteLegale'], 'R');
    expect(collectionsActivite, contains(idCollectionDemandes));
    expect(collectionsIdentiteJamaisMobile, containsAll(['identiteLegale', idCollectionOptions, idCollectionDemandes]));
  });

  test('DROIT AU MOTEUR : la fiche RBAC décide (admin, direction, DA écrivent ; un caissier non), refus nommé, rien de déposé ni d’écrit', () {
    final mm = poste()..collection('identiteLegale').ajouterSansJournal(cfbSemenceIdentite());
    final mere = DemandesIdentitePoste(mm, matrice: donnees.matrice, horloge: () => DateTime(2026, 11, 16, 9));
    final r = mere.poser(fileul: false, role: 'caissier', acteur: 'X', champs: {'bp': 'BP : 1'}, dateEffet: '2026-12-01', motif: 'essai');
    expect(r.refus!.code, 'IDENTITE_DROIT_REQUIS');
    expect(r.refus!.motif, contains('Caissier'));
    expect(mm.collection('identiteLegale').toutes, hasLength(1), reason: 'rien n’est écrit sans le droit, même si la commande avait été masquée');
    final o = mere.poser(fileul: false, role: 'caissier', acteur: 'X', optionsImpression: {'doubleLogo': false});
    expect(o.refus!.code, 'IDENTITE_DROIT_REQUIS');
    expect(mm.collection(idCollectionOptions).toutes, isEmpty);
    for (final role in ['admin', 'direction', 'da']) {
      expect(idDroitEcriture(donnees.matrice, role), isTrue, reason: role);
    }
    for (final role in ['caissier', 'comptable', 'medecin', 'reception']) {
      expect(idDroitEcriture(donnees.matrice, role), isFalse, reason: role);
    }
    expect(idDroitEcriture(null, 'admin'), isFalse, reason: 'jamais un droit supposé sans matrice');
    // Un fileul sans droit n'ouvre pas de dépôt non plus.
    final mf = poste();
    final f = DemandesIdentitePoste(mf, matrice: donnees.matrice, horloge: () => DateTime(2026, 11, 16, 9)).poser(fileul: true, role: 'caissier', acteur: 'X', champs: {'bp': 'BP : 1'}, dateEffet: '2026-12-01', motif: 'essai');
    expect(f.refus!.code, 'IDENTITE_DROIT_REQUIS');
    expect(mf.collection('demandesIdentite').toutes, isEmpty);
  });

  test('BOUT EN BOUT : le profil habilité d’un fileul signe et dépose, la mère revérifie et propage aux DEUX fileuls, les options voyagent, rejeu sans doublon, rien vers un mobile', () async {
    const port = 19491;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-ident-1'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final mm = poste()..collection('identiteLegale').ajouterSansJournal(cfbSemenceIdentite());
    mm.collection('identiteLegale').ajouterSansJournal(cfbSemenceIdentiteV2());
    final mf1 = poste(), mf2 = poste();
    final moteur1 = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Fileul 1');
    final moteur2 = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Fileul 2');
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl1 = ApplicateurConfiguration(mf1, moteur1.liste), appl2 = ApplicateurConfiguration(mf2, moteur2.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    PontActivite pontDe(Magasin m, MoteurFileul mo, String e) =>
        PontActivite(m, TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs)), etiquette: e);
    final pontF1 = pontDe(mf1, moteur1, 'F1'), pontF2 = pontDe(mf2, moteur2, 'F2');
    final signe = DateTime(2026, 11, 16, 9, 30);
    final service = ServiceDemandesIdentite(mm, donnees: () async => donnees, horloge: () => DateTime.utc(2026, 11, 16, 12));
    final dem1 = DemandesIdentitePoste(mf1, matrice: donnees.matrice, horloge: () => signe, etiquette: 'F1');
    final dem2 = DemandesIdentitePoste(mf2, matrice: donnees.matrice, horloge: () => signe.add(const Duration(minutes: 5)), etiquette: 'F2');
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 45));
      while (!fini()) {
        await pub.pousser();
        await appl1.tirer();
        await appl2.tirer();
        await pontF1.cycle();
        await pontF2.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) {
          fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl1 ${appl1.erreur.value}, appl2 ${appl2.erreur.value}, pontF1 ${pontF1.erreur.value}, pontM ${pontM.erreur.value}, service ${service.derniereErreur})');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      final code1 = await console.codeAppareil('Fileul 1').timeout(const Duration(seconds: 20));
      await moteur1.rattacher('http://127.0.0.1:$port', code1).timeout(const Duration(seconds: 20));
      moteur1.demarrer();
      final code2 = await console.codeAppareil('Fileul 2').timeout(const Duration(seconds: 20));
      await moteur2.rattacher('http://127.0.0.1:$port', code2).timeout(const Duration(seconds: 20));
      moteur2.demarrer();
      // La mère seule écrit les options : un réglage LOCAL (`reglages`) reste là où il est posé (le défaut mesuré), et une écriture directe d'un fileul est refusée par la garde.
      mm.collection('reglages').ajouterSansJournal({'id': 'impression.doubleLogo', 'statut': 'actif', 'valeur': false});
      await converger(() => mf1.collection('identiteLegale').toutes.length == 2 && mf2.collection('identiteLegale').toutes.length == 2, 'les deux versions semées arrivent aux deux fileuls');
      expect(mf1.collection('reglages').toutes, isEmpty, reason: 'un réglage local ne voyage pas (mesuré)');
      appl1.poserGardes();
      expect(() => mf1.collection(idCollectionOptions).inserer({'id': 'OPT-x', 'valeur': true}), throwsA(isA<EcritureRefusee>()), reason: 'un fileul n’écrit pas directement la configuration de la clinique');

      // SANS DROIT : refus nommé, rien déposé.
      final sans = dem1.poser(fileul: true, role: 'caissier', acteur: 'DOSSOU Paul', champs: {'bp': 'BP : 1 X'}, dateEffet: '2026-12-01', motif: 'essai');
      expect(sans.refus!.code, 'IDENTITE_DROIT_REQUIS');
      expect(mf1.collection('demandesIdentite').toutes, isEmpty);

      // AVEC DROIT : la Direction d'un fileul signe une version datée (adresse fiscale) ET des options d'impression.
      final p = dem1.poser(
          fileul: true,
          role: 'direction',
          acteur: 'TAKI Alimatou',
          champs: {'bp': 'BP : 999 NATITINGOU (Rép. du Bénin)', 'telephones': '01 11 22 33 44 / 01 55 66 77 88'},
          dateEffet: '2026-12-01',
          motif: 'Nouvelle adresse postale et nouveaux numéros',
          optionsImpression: {'doubleLogo': false, 'filigrane': 'Confidentiel'});
      expect(p.refus, isNull, reason: '${p.refus}');
      expect(p.mode, 'deposee');
      expect(dem1.enAttente(), hasLength(1));
      expect(mf1.collection('identiteLegale').toutes, hasLength(2), reason: 'rien n’est écrit chez le fileul avant l’application par la mère');
      // Une seconde demande à la même date d'effet est refusée en nommant (jamais doublée) tant que la première attend.
      final doublon = dem1.poser(fileul: true, role: 'direction', acteur: 'TAKI Alimatou', champs: {'bp': 'BP : 999 NATITINGOU (Rép. du Bénin)'}, dateEffet: '2026-12-01', motif: 'encore');
      expect(doublon.refus!.code, 'DEMANDE_DEJA_DEPOSEE');

      await converger(
          () => mm.collection('identiteLegale').toutes.length == 3 &&
              mf1.collection('identiteLegale').toutes.length == 3 &&
              mf2.collection('identiteLegale').toutes.length == 3 &&
              mf2.collection(idCollectionOptions).toutes.length == 2 &&
              dem1.demandes.toutes.every((d) => d['etat'] == idEtatAppliquee),
          'la mère applique, la version et les options arrivent aux DEUX fileuls, le verdict revient');
      final v3 = mm.collection('identiteLegale').toutes.firstWhere((v) => v['version'] == 3);
      expect(v3['debut'], '2026-12-01');
      expect(v3['bp'], 'BP : 999 NATITINGOU (Rép. du Bénin)');
      expect(v3['telephones'], ['01 11 22 33 44', '01 55 66 77 88']);
      expect(v3['creePar'], 'TAKI Alimatou', reason: 'le NOM de l’auteur, pas celui de la mère');
      expect(v3['creeLe'], valInstant(signe), reason: 'la date de la SIGNATURE, pas celle de l’application par la mère');
      expect(v3['motif'], 'Nouvelle adresse postale et nouveaux numéros');
      expect(v3['rccm'], IdentiteClinique.rccm, reason: 'un champ non saisi est copié de la version couvrante');
      final v2 = mm.collection('identiteLegale').toutes.firstWhere((v) => v['version'] == 2);
      expect(v2['fin'], '2026-11-30', reason: 'la version précédente se clôt la veille, jamais réécrite');
      expect(v2['rccm'], IdentiteClinique.rccm);
      final v1 = mm.collection('identiteLegale').toutes.firstWhere((v) => v['version'] == 1);
      expect(v1['rccm'], IdentiteClinique.rccmVersion1, reason: 'la version 1 reste telle qu’elle a été semée');
      expect(v1['fin'], '2026-11-15');
      expect(dem1.demandes.toutes.single['traitePar'], 'Mère');
      // Propagation aux deux fileuls : la pièce garde l'identité de SA date.
      for (final mf in [mf1, mf2]) {
        expect(identiteImprimeeDe(mf, DateTime(2026, 8, 16)).rccm, IdentiteClinique.rccmVersion1, reason: 'une pièce émise avant le 16/11/2026 garde son numéro');
        expect(identiteImprimeeDe(mf, DateTime(2026, 11, 20)).rccm, IdentiteClinique.rccm);
        expect(identiteImprimeeDe(mf, DateTime(2026, 11, 20)).bp, 'BP : 507 NATITINGOU (Rép. du Bénin)');
        expect(identiteImprimeeDe(mf, DateTime(2026, 12, 15)).bp, 'BP : 999 NATITINGOU (Rép. du Bénin)');
        expect(identiteImprimeeDe(mf, DateTime(2026, 12, 15)).telephones, ['01 11 22 33 44', '01 55 66 77 88']);
      }
      // Les OPTIONS D'IMPRESSION ont voyagé (défaut mesuré : elles restaient sur le poste).
      expect(idOption(mf2.collection(idCollectionOptions).toutes, 'doubleLogo'), false);
      expect(idOption(mf2.collection(idCollectionOptions).toutes, 'filigrane'), 'Confidentiel');
      expect(idOption(mm.collection(idCollectionOptions).toutes, 'doubleLogo'), false);
      expect(mm.collection('audit').toutes.where((a) => a['action'] == 'Option d’impression modifiée'), hasLength(2), reason: 'RG-12 : une ligne par option');
      expect(mm.collection('audit').toutes.where((a) => a['action'] == 'Identité : demande d’un fileul appliquée'), hasLength(1));

      // REJEU SANS DOUBLON : des tours de plus ne créent rien.
      for (var i = 0; i < 4; i++) {
        await pub.pousser();
        await appl1.tirer();
        await appl2.tirer();
        await pontF1.cycle();
        await pontF2.cycle();
        await pontM.cycle();
        await service.traiter();
      }
      expect(mm.collection('identiteLegale').toutes, hasLength(3));
      expect(mm.collection(idCollectionDemandes).toutes, hasLength(1));
      expect(mm.collection('audit').toutes.where((a) => a['action'] == 'Identité : demande d’un fileul appliquée'), hasLength(1));

      // LE DEUXIÈME FILEUL (qui a déjà reçu la version) dépose la MÊME date d'effet : le refus est nommé dès le dépôt, rien n'est déposé. Une demande qui arriverait quand même à la mère
      // (mère coupée au moment du dépôt, version posée entre-temps) est refusée par la mère, en nommant, et aucune version n'est ajoutée.
      final seconde = dem2.poser(fileul: true, role: 'da', acteur: 'ADJOVI Koffi', champs: {'bp': 'BP : 777 NATITINGOU (Rép. du Bénin)'}, dateEffet: '2026-12-01', motif: 'Autre adresse');
      expect(seconde.refus!.code, 'VERSION_EXISTANTE');
      expect(mf2.collection('demandesIdentite').toutes.where((d) => d['demandePar'] == 'ADJOVI Koffi'), isEmpty, reason: 'rien de déposé par le refusé');
      mf2.collection('demandesIdentite').inserer({
        'id': 'DICONCURRENTE',
        'statut': 'actif',
        'etat': idEtatDeposee,
        'champs': {'bp': 'BP : 777 CONCURRENTE'},
        'dateEffet': '2026-12-01',
        'motif': 'concurrente',
        'demandePar': 'ADJOVI Koffi',
        'demandeRole': 'da',
        'demandeLe': valInstant(signe.add(const Duration(minutes: 5))),
      });
      await converger(() => mf2.collection('demandesIdentite').parId('DICONCURRENTE')!['etat'] == idEtatRefusee, 'la mère refuse la demande concurrente');
      expect(mf2.collection('demandesIdentite').parId('DICONCURRENTE')!['resultatCode'], 'VERSION_EXISTANTE');
      expect(mm.collection('identiteLegale').toutes.where((v) => v['debut'] == '2026-12-01'), hasLength(1), reason: 'jamais deux versions à la même date d’effet');
      expect(mm.collection('identiteLegale').toutes, hasLength(3));

      // LE MOTEUR DE LA MÈRE REFAIT LE CONTRÔLE : une demande FORGÉE (rôle sans droit, posée sans passer par le moteur du fileul) est refusée en nommant.
      mf2.collection('demandesIdentite').inserer({
        'id': 'DIFORGE1',
        'statut': 'actif',
        'etat': idEtatDeposee,
        'champs': {'bp': 'BP : 666 FORGÉE'},
        'dateEffet': '2027-01-01',
        'motif': 'forgée',
        'demandePar': 'DOSSOU Paul',
        'demandeRole': 'caissier',
        'demandeLe': valInstant(signe),
      });
      await converger(() => mf2.collection('demandesIdentite').parId('DIFORGE1')!['etat'] == idEtatRefusee, 'la mère refuse la demande forgée');
      final forgee = mf2.collection('demandesIdentite').parId('DIFORGE1')!;
      expect(forgee['resultatCode'], 'IDENTITE_DROIT_REQUIS');
      expect(forgee['resultatGeste'], isNotEmpty);
      expect(mm.collection('identiteLegale').toutes.where((v) => '${v['bp']}'.contains('FORGÉE')), isEmpty);

      // RIEN VERS UN TÉLÉPHONE (RG-13) : ni l'identité, ni les options, ni les demandes ; le téléphone lit bien le journal (l'absence est une EXCLUSION, pas un journal vide).
      final http0 = HttpClient();
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      Future<List<String>> recues(String role, Map<String, Object?> extra) async {
        final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
        final noms = <String>[];
        var depuis = 0;
        while (true) {
          final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
          if (pull['ops'] == null) fail('pull de $role à $depuis : $pull');
          final ops = (pull['ops'] as List).cast<Map>();
          for (final o in ops) {
            noms.add('${o['collection']}');
            depuis = (o['seq'] as num).toInt();
          }
          if (pull['fin'] == true || ops.isEmpty) break;
        }
        return noms;
      }

      final fileul = await recues('fileul', {});
      expect(fileul, containsAll(['identiteLegale', idCollectionOptions, idCollectionDemandes]), reason: 'un fileul reçoit l’identité, les options et le verdict des demandes');
      final mobile = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobile, isNotEmpty, reason: 'le téléphone lit bien le journal : l’absence est une EXCLUSION, pas un journal vide');
      for (final c in ['identiteLegale', idCollectionOptions, idCollectionDemandes]) {
        expect(mobile, isNot(contains(c)), reason: '« $c » ne part jamais vers un téléphone (RG-13)');
      }
      http0.close(force: true);
    } finally {
      appl1.arreter();
      appl2.arreter();
      pontF1.arreter();
      pontF2.arreter();
      pontM.arreter();
      service.arreter();
      await mere0.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('MÈRE COUPÉE : la demande du fileul s’empile au journal local, le fileul continue, et au retour elle se rejoue UNE seule fois', () async {
    const port = 19492;
    final d = Directory.systemTemp.createTempSync('ident');
    addTearDown(() => d.deleteSync(recursive: true));
    ConfigMere config() => ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes', cleStockage: cleSqlite);
    var mere = await Mere.creer(config());
    await mere.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: '${d.path}/f.db', mere: 'http://127.0.0.1:$port', nom: 'Fileul', cleStockage: cleSqlite);
    final mm = poste()..collection('identiteLegale').ajouterSansJournal(cfbSemenceIdentite());
    mm.collection('identiteLegale').ajouterSansJournal(cfbSemenceIdentiteV2());
    final mf = poste();
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(mf, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)), etiquette: 'F');
    final service = ServiceDemandesIdentite(mm, donnees: () async => donnees, horloge: () => DateTime.utc(2026, 11, 16, 20));
    final dem = DemandesIdentitePoste(mf, matrice: donnees.matrice, horloge: () => DateTime(2026, 11, 16, 8, 30), etiquette: 'F');
    try {
      final code = await console.codeAppareil('Fileul');
      await moteur.appairer(code);
      moteur.demarrer();
      final fin0 = DateTime.now().add(const Duration(seconds: 40));
      while (mf.collection('identiteLegale').toutes.length != 2) {
        await pub.pousser();
        await appl.tirer();
        if (DateTime.now().isAfter(fin0)) fail('l’identité n’arrive pas au fileul');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      // COUPURE : la mère s'arrête. Le fileul habilité signe, saisit autre chose, continue.
      await mere.arreter();
      final p = dem.poser(fileul: true, role: 'admin', acteur: 'BASSONGUI Chabi Séko', champs: {'email': 'contact@clinique.test'}, dateEffet: '2026-12-15', motif: 'Nouveau courriel');
      expect(p.refus, isNull, reason: 'déposer hors ligne est possible : le dépôt est local');
      mf.collection('exercices').inserer({'id': 'EXO-2027', 'annee': 2027, 'etat': 'ouvert'});
      await pontF.cycle();
      expect(dem.enAttente(), hasLength(1));
      expect((await moteur.instantane()).enAttente, greaterThan(0), reason: 'la demande attend dans la file persistée du moteur : rien n’est perdu');
      expect(mm.collection('identiteLegale').toutes, hasLength(2), reason: 'la mère coupée n’a encore rien reçu');
      // RETOUR.
      mere = await Mere.creer(config());
      await mere.demarrer();
      final fin = DateTime.now().add(const Duration(seconds: 60));
      while (!(mm.collection('identiteLegale').toutes.length == 3 && dem.demandes.toutes.every((x) => x['etat'] == idEtatAppliquee) && mf.collection('identiteLegale').toutes.length == 3)) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('pas de convergence au retour : ${[for (final x in dem.demandes.toutes) x['etat']]}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      for (var i = 0; i < 4; i++) {
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
      }
      expect(mm.collection('identiteLegale').toutes, hasLength(3), reason: 'rejouée UNE fois, jamais doublée');
      expect(mm.collection(idCollectionDemandes).toutes, hasLength(1));
      expect(mm.collection('identiteLegale').toutes.firstWhere((v) => v['version'] == 3)['creeLe'], valInstant(DateTime(2026, 11, 16, 8, 30)), reason: 'la date de la signature, pas celle du rejeu');
      expect(identiteImprimeeDe(mf, DateTime(2026, 12, 20)).email, 'contact@clinique.test');
    } finally {
      appl.arreter();
      pontF.arreter();
      pontM.arreter();
      service.arreter();
      await mere.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
