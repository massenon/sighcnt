import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_propositions_tarif.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LE SERVICE DE LA MÈRE QUI APPLIQUE LES DEMANDES DE PRIX (lot TFIN, étape 0), contre la VRAIE mère Dart et un VRAI moteur de fileul, SANS appeler `appliquerDemandes` à la main :
/// seul le service de l'application applique (avant ce lot, aucun service ne le faisait : la demande restait « déposée » pour toujours).
///  1. un fileul (Direction) propose un prix : la mère l'applique SOUS SON NOM ET SON RÔLE, le verdict revient au fileul ;
///  2. rejeu : un second tour du service n'applique rien de plus (idempotence) ;
///  3. un fileul qui dépose une décision sous un rôle SANS le droit de décider : REFUS NOMMÉ (code, motif, geste) écrit sur la demande, aucune version décidée ;
///  4. le Oui de la Direction (fileul) devient, sur la mère, une décision appliquée sous le rôle `direction` ;
///  5. le câblage de `main.dart` démarre bien ce service à la mère ;
///  6. JAMAIS vers un téléphone (RG-13).
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));
final donnees = DonneesNavigation.depuisDossier();

TarifsPoste poste(Magasin m, String role, String nom, {bool fileul = false, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: true,
    peutEditerPour: (r) => const ['admin', 'da', 'direction'].contains(r),
    horloge: () => auj,
    etiquette: etiquette);

DemandeProposition prop(String code, num prix, {int jours = 3}) =>
    DemandeProposition(code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: plus(jours), motif: 'Test du service TFIN');

void main() {
  test('LE SERVICE DE LA MÈRE applique la proposition d\'un fileul, une seule fois, refuse en nommant, et rien ne part vers un téléphone', () async {
    const port = 19473;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-tfin'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Direction');
    final mm = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    final mf = Magasin({'actes': <M>[], 'notifications': <M>[]});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(
        mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)),
        etiquette: 'F');
    final service = ServicePropositionsTarif(mm, donnees: () async => donnees, horloge: () => auj);
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        await pub.pousser();
        await appl.tirer();
        await pontF.cycle();
        await pontM.cycle();
        await service.traiter();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (service ${service.derniereErreur}, pub ${pub.erreur.value}, appl ${appl.erreur.value}, pontF ${pontF.erreur.value}, pontM ${pontM.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    TarifsPoste.assurerProduits(mm);
    try {
      await pub.pousser();
      final code = await console.codeAppareil('Direction').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      await converger(() => mf.collection('versionsTarif').toutes.length >= 240 && mf.collection('tarifs').toutes.length >= 201, 'réception du référentiel par le fileul');

      // 1. Proposition du fileul : la mère l'applique par son SERVICE.
      final f = poste(mf, 'direction', 'La Direction', fileul: true, etiquette: 'F');
      final avant = mm.collection('versionsTarif').toutes.length;
      final dem = f.proposer(prop('MG01', 5300));
      expect(dem.ok && dem.depose, isTrue, reason: '${dem.refus}');
      expect(mm.collection('versionsTarif').toutes.length, avant, reason: 'rien n\'est écrit tant que la mère n\'a pas traité');
      await converger(() => mf.collection('propositionsTarif').toutes.any((d) => d['etat'] == 'appliquee'), 'le verdict de la mère revient au fileul');
      final v = mm.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == 'MG01' && x['statut'] == 'propose');
      expect([v['proposePar'], v['proposeRole']], ['La Direction', 'direction'], reason: 'appliquée sous le NOM et le RÔLE de l\'auteur (RG-12)');
      expect(service.traitees, greaterThanOrEqualTo(1));

      // 2. Rejeu : un tour de plus n'applique rien (idempotence), aucune seconde version.
      final apres = mm.collection('versionsTarif').toutes.length;
      expect(apres, avant + 1);
      expect(await service.traiter(), 0);
      expect(await service.traiter(), 0);
      expect(mm.collection('versionsTarif').toutes.length, apres);

      // 3. Refus NOMMÉ : une décision déposée sous un rôle sans le droit de décider. Le fileul (boîte forgée, peutEditerEcran vrai) la dépose ; la mère refait le contrôle.
      final caissier = poste(mf, 'caissier', 'Un caissier', fileul: true, etiquette: 'C');
      expect(caissier.decider('${v['id']}', 'oui').refus?.code, 'VALIDATION_RESERVEE', reason: 'le poste du fileul refuse déjà, nommé');
      // Un poste modifié contourne ce refus et dépose la demande tout de même : la mère REFAIT le contrôle (masquer ou refuser au fileul ne protège rien).
      mf.collection('propositionsTarif').inserer({
        'id': 'DTFORGEE1',
        'statut': 'actif',
        'genre': 'decision',
        'etat': 'deposee',
        'versionId': v['id'],
        'decision': 'oui',
        'demandePar': 'Un caissier',
        'demandeRole': 'caissier',
        'demandeLe': tarIso(auj),
      });
      await converger(() => mf.collection('propositionsTarif').toutes.any((d) => d['demandeRole'] == 'caissier' && d['etat'] == 'refusee'), 'la mère refuse la décision du caissier');
      final refus = mf.collection('propositionsTarif').toutes.firstWhere((d) => d['demandeRole'] == 'caissier');
      expect('${refus['resultatCode']}'.isNotEmpty && '${refus['resultatMotif']}'.isNotEmpty && '${refus['resultatGeste']}'.isNotEmpty, isTrue, reason: 'un refus se nomme : code, motif, geste ($refus)');
      expect(mm.collection('versionsTarif').parId(v['id'])?['statut'], 'propose', reason: 'aucune décision écrite par le refus');

      // 4. Le Oui de la Direction (fileul) : décision appliquée sur la mère sous le rôle `direction`.
      expect(f.decider('${v['id']}', 'oui').depose, isTrue);
      await converger(() => mm.collection('versionsTarif').parId(v['id'])?['statut'] == 'valide', 'le Oui de la Direction est appliqué par la mère');
      expect(mm.collection('versionsTarif').parId(v['id'])?['roleDecision'], 'direction');
      await converger(() => mf.collection('versionsTarif').parId(v['id'])?['statut'] == 'valide', 'la décision revient au fileul par le journal de configuration');
      expect(TarifsPoste.prixActe(mf, 'MG01', aujourdhui: auj, date: plus(3)), 5300);
      final traitees = service.traitees;
      expect(await service.traiter(), 0, reason: 'rejeu sans effet après la décision');
      expect(service.traitees, traitees);

      // 5. LES PRODUITS (lot TFIN) : le gestionnaire de stock d'un fileul propose le prix d'achat d'un article ; la mère l'applique par le même service, sous son rôle ; une seule version AJOUTÉE.
      await converger(() => mf.collection('versionsTarif').toutes.where((x) => x['origine'] == 'reprise').length >= 184, 'les prix d\'achat repris arrivent au fileul');
      final art = mm.collection('produits').actives.firstWhere((x) => x['categorie'] == 'medicament' && (x['prixAchat'] as num? ?? 0) > 0);
      final prixArt = art['prixAchat'] as num;
      final gest = TarifsPoste(mf, role: 'stock', auteur: () => 'Gestionnaire fileul', fileul: true, peutProposerPrixAchat: true, horloge: () => auj, etiquette: 'G');
      final nVers = mm.collection('versionsTarif').toutes.length;
      final dp = gest.proposerPrixAchat(DemandeProduit(code: '${art['code']}', prixAchat: prixArt + 30, dateEffet: plus(5), motif: 'Test du service TFIN'));
      expect(dp.ok && dp.depose, isTrue, reason: '${dp.refus?.code} ${dp.refus?.motif}');
      await converger(() => mf.collection('propositionsTarif').toutes.any((d) => d['genre'] == 'propositionProduit' && d['etat'] == 'appliquee'), 'la mère applique la proposition du prix d\'achat');
      expect(mm.collection('versionsTarif').toutes.length, nVers + 1, reason: 'une version AJOUTÉE à la mère');
      final vp = mm.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == art['code'] && x['statut'] == 'propose');
      expect([vp['proposePar'], vp['proposeRole'], vp['statut'], vp['prixNonAssure']], ['Gestionnaire fileul', 'stock', 'propose', prixArt + 30]);
      expect(mm.collection('produits').parId(art['id'])!['prixAchat'], prixArt, reason: 'une proposition ne change rien');
      expect(await service.traiter(), 0, reason: 'rejeu sans effet');

      // 6. JAMAIS vers un téléphone (RG-13).
      final http0 = HttpClient();
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      final c = (await appel('POST', '/admin/code', corps: {'etiquette': 'mobile', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}, entetes: {'x-admin': 'secret-test'}))['code'];
      final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-mobile', 'plateforme': 'test'});
      final noms = <String>[];
      var depuis = 0;
      while (true) {
        final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
        final ops = (pull['ops'] as List).cast<Map>();
        for (final o in ops) {
          noms.add('${o['collection']}');
          depuis = (o['seq'] as num).toInt();
        }
        if (pull['fin'] == true || ops.isEmpty) break;
      }
      expect(noms, isNotEmpty);
      expect(noms, isNot(contains('propositionsTarif')));
      expect(noms, isNot(contains('versionsTarif')));
      http0.close(force: true);
    } finally {
      service.arreter();
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CÂBLAGE : main.dart démarre le service des demandes de prix à la mère, à côté de celui des demandes d\'import', () {
    final src = File('lib/main.dart').readAsStringSync();
    final mere = src.substring(src.indexOf('void demarrerPontMere()'), src.indexOf('PontActivite creerPontFileul()'));
    expect(mere, contains('ServicePropositionsTarif(magasin'), reason: 'sans ce démarrage, une proposition de prix d\'un fileul n\'est jamais appliquée');
    expect(mere, contains('ServiceDemandesImport(magasin'));
    expect(mere, contains('.demarrer()'));
    expect(src.substring(src.indexOf('void demarrerApplication()'), src.indexOf('void demarrerApplicationEtPont()')), isNot(contains('ServicePropositionsTarif')), reason: 'un fileul ne traite rien, il dépose');
  });
}
