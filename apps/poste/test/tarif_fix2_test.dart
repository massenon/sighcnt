import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'dart:convert';
import 'dart:io';

import 'm14_aide.dart' show donneesNav;

/// LOT TARIF-FIX-2 (Direction, 16/11/2026, section AL point 2) : le médecin prescrit TOUJOURS ; seule la caisse attend le prix. Au poste : prescription acceptée,
/// ligne sans prix nommée, total non calculable ; encaissement refusé nommé (la pièce entière par défaut, le reste si le paramètre de clinique le permet) ; alerte
/// UNE par code vers qui fixe le prix (fiche RBAC), qui retombe ; le prix décidé, la ligne se valorise à la date de la pièce et l'encaissement passe, sur la mère
/// ET sur un fileul synchronisé contre la vraie mère.
typedef M = Map<String, Object?>;
var horloge = DateTime(2026, 10, 30, 10);
String jourPlus(int n) => tarIso(horloge.add(Duration(days: n)));
const session = SessionCs(role: 'admin', fonction: 'direction');

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

TarifsPoste poste(Magasin m, String role, String nom, {bool fileul = false, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: true,
    peutEditerPour: (r) => const ['admin', 'da', 'direction'].contains(r),
    horloge: () => horloge,
    etiquette: etiquette);

DemandeProposition creation(String code, num prix, String dateEffet, {String famille = 'ACTE'}) => DemandeProposition(
    code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: dateEffet, motif: 'Test TARIF-FIX-2', creation: {'libelle': 'Prestation $code', 'famille': famille, 'secteur': 'Soins'});

Fiche patientNonAssure(Magasin m) => m.collection('patients').actives.firstWhere((p) => p['externe'] != true && !csVrai(p['assureur']) && !csVrai(p['personnelId']));

ResultatPrescription prescrire(Magasin m, List<String> actes, {DateTime? date}) => csPrescrire(StockMagasin(m, () => horloge),
    {'patientCode': patientNonAssure(m)['code'], 'medecin': 'TEST', 'diagnostic': 'test', 'date': (date ?? horloge).toIso8601String(), 'actes': actes}, session);

void main() {
  setUp(() => horloge = DateTime(2026, 10, 30, 10));

  test('DÉCIDER un prix est le geste réservé `decider_prix` de la fiche RBAC (Direction, 16/11/2026 : pas de rôle en dur) : défaut d’origine = les trois rôles d’hier ; retiré à la Directrice Administrative par sa fiche, la décision lui est REFUSÉE nommée et l’alerte « à valider » ne la vise plus ; la fiche restaurée, tout revient', () {
    final rbac = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map)['gestes'] as Map;
    final decl = (rbac['jeux'] as List).cast<Map>().firstWhere((g) => g['id'] == tarGesteDecider);
    expect(decl['rolesDefaut'], tarRolesValidation, reason: 'le défaut d’origine du domaine est celui du manifeste de la maquette');
    final m = jeu();
    tarInstallerDroitDecider((r) => donneesNav.aChaud(m).matrice.droitGeste(r, tarGesteDecider));
    try {
      expect([for (final r in ['admin', 'da', 'direction', 'caissier', 'stock']) tarPeutDecider(r)], [true, true, true, false, false], reason: 'aucun changement par défaut');
      final da = poste(m, 'da', 'Yvette DAF');
      final p = da.proposer(creation('TF2G', 2200, jourPlus(0)));
      List<String> alertes(String role) => [
            for (final n in CentreNotifications(magasin: m, donnees: () => donneesNav.aChaud(m), role: () => role, horloge: () => horloge).collecter(detaille: true))
              if (n.source == 'prix_a_valider') n.cle
          ];
      expect(alertes('da'), isNotEmpty);
      // La fiche RBAC de la Directrice Administrative retire le geste (`droitsGestes.decider_prix = false`).
      final fiche = m.collection('rbac').toutes.firstWhere((f) => f['role'] == 'da');
      final annule = m.collection('rbac').mettreAJour(fiche['id'], {
        'droitsGestes': {...((fiche['droitsGestes'] as Map?) ?? const {}).cast<String, Object?>(), tarGesteDecider: false}
      });
      expect(tarPeutDecider('da'), isFalse);
      expect(tarPeutDecider('admin'), isTrue, reason: 'les autres rôles gardent le droit');
      final refus = poste(m, 'da', 'Yvette DAF').decider('${p.version!['id']}', 'oui').refus;
      expect([refus?.code, refus?.motif], ['VALIDATION_RESERVEE', contains('« Décider un changement de prix » (fiche RBAC)')]);
      expect(alertes('da'), isEmpty, reason: 'l’alerte des changements à valider suit le geste');
      annule();
      expect(tarPeutDecider('da'), isTrue, reason: 'fiche restaurée');
      expect(poste(m, 'da', 'Yvette DAF').decider('${p.version!['id']}', 'oui').refus, isNull);
    } finally {
      tarInstallerDroitDecider(null);
    }
  });

  test('sur la mère : prescription ACCEPTÉE (ligne « prix à définir », total nul), encaissement REFUSÉ nommé, la pièce entière par défaut ; le Oui valorise à la date de la pièce et l’encaissement passe', () {
    final m = jeu();
    final da = poste(m, 'da', 'Yvette DAF');
    final p = da.proposer(creation('TF2A', 3100, jourPlus(0)));
    expect(p.refus, isNull);
    final r = prescrire(m, ['TF2A', 'CERT-APT']);
    final fac = r.facture;
    final ls = (fac['lignes'] as List).cast<Map>();
    expect(ls.first['prixManquant'], isNotNull);
    expect([ls.first['prixUnitaire'], ls.first['montant'], fac['montantTTC'], fac['reliquat'], fac['enAttentePrix']], [null, null, null, null, true], reason: 'jamais 0');
    expect(ls[1]['prixUnitaire'], 7000, reason: 'la ligne tarifée garde son prix');
    expect(r.sansPrix.single['code'], 'TF2A');
    // Le paramètre de clinique : défaut semé « non ».
    expect(encaissementPartielPoste(m, horloge), isFalse);
    // La caisse : refus nommé, rien n'est écrit, la commande sera absente (état de caisse).
    final avant = '${m.collection('factures').parId(fac['id'])}';
    for (final opts in [
      () => encaisserFacture(m, '${fac['id']}', lignes: ['${ls[1]['id']}'], maintenant: horloge),
      () => encaisserFacture(m, '${fac['id']}', montant: 7000, maintenant: horloge),
    ]) {
      expect(opts, throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', 'ENCAISSEMENT_PRIX_MANQUANT').having((e) => e.motif, 'motif', allOf(contains('TF2A'), contains('prix à définir'), contains('la pièce entière attend le prix')))));
    }
    expect('${m.collection('factures').parId(fac['id'])}', avant, reason: 'un refus n’écrit rien');
    final ep = etatCaissePrix(m, m.collection('factures').parId(fac['id'])!, horloge);
    expect([ep.encaissable, ep.refus?.code], [false, 'ENCAISSEMENT_PRIX_MANQUANT']);
    expect(titreSansPrix(ep.refus!), 'En attente de prix : « TF2A » prix à définir');
    expect(ep.refus!.geste, contains('date d’effet du 30/10/2026 au plus tard'));
    // Le Oui : la décision n'est PAS bloquée par la pièce en attente ; la ligne se valorise aussitôt, à la date de la pièce.
    expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
    final f2 = m.collection('factures').parId(fac['id'])!;
    expect([((f2['lignes'] as List).first as Map)['prixUnitaire'], f2['montantTTC'], f2['enAttentePrix']], [3100, 10100, false]);
    final res = encaisserFacture(m, '${fac['id']}', maintenant: horloge);
    expect(res.facture['statutPaiement'], 'soldee');
  });

  test('le paramètre de clinique « oui » (versionné par date) : la ligne tarifée s’encaisse seule, la ligne sans prix reste refusée, la pièce partielle a un reste non calculable', () {
    final m = jeu();
    final sp = serviceParametres(m, auteur: () => 'Direction', horloge: () => horloge)..semerDefauts();
    expect(sp.valeur(cleEncaissementPartielSansPrix, iso(horloge)), 'non', reason: 'défaut semé');
    final pose = sp.regler(cleEncaissementPartielSansPrix, 'oui', jourPlus(0), motif: 'Test TARIF-FIX-2');
    expect(pose.refus, isNull, reason: '${pose.refus}');
    expect(encaissementPartielPoste(m, horloge), isTrue);
    expect(encaissementPartielPoste(m, horloge.subtract(const Duration(days: 1))), isFalse, reason: 'versionné par date : la veille, la version semée');
    poste(m, 'da', 'Yvette DAF').proposer(creation('TF2B', 2000, jourPlus(0)));
    final fac = prescrire(m, ['TF2B', 'CERT-APT']).facture;
    final ls = (fac['lignes'] as List).cast<Map>();
    expect(() => encaisserFacture(m, '${fac['id']}', lignes: ['${ls.first['id']}'], maintenant: horloge),
        throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', 'ENCAISSEMENT_PRIX_MANQUANT')));
    expect(etatCaissePrix(m, fac, horloge).encaissable, isTrue, reason: 'il reste une ligne tarifée');
    final r = encaisserFacture(m, '${fac['id']}', lignes: ['${ls[1]['id']}'], maintenant: horloge);
    expect([r.montantRegle, r.facture['statutPaiement'], r.facture['reliquat']], [7000, 'partielle', null]);
    expect(r.normalisation, isNull, reason: 'rien au MECeF tant que la pièce n’est pas soldée');
  });

  test('l’ALERTE : une par code (deux prescriptions), vers les rôles qui peuvent MODIFIER « Tarifs et prix » (fiche RBAC), sans donnée de santé ; elle retombe au Oui', () {
    final m = jeu();
    final da = poste(m, 'da', 'Yvette DAF');
    final p = da.proposer(creation('TF2C', 1500, jourPlus(0)));
    prescrire(m, ['TF2C']);
    prescrire(m, ['TF2C']);
    List<AlerteNotif> pour(String role) => CentreNotifications(magasin: m, donnees: () => donneesNav, role: () => role, horloge: () => horloge)
        .collecter(detaille: true)
        .where((n) => n.source == 'prix_manquant')
        .toList();
    final avecDroit = [for (final r in ['admin', 'da', 'direction', 'caissier', 'laborantin', 'medecin']) if (donneesNav.matrice.droit(r, 'cfg-tarifs').editer) r];
    final sansDroit = [for (final r in ['caissier', 'laborantin', 'medecin', 'infirmier']) if (!donneesNav.matrice.droit(r, 'cfg-tarifs').editer) r];
    expect(avecDroit, isNotEmpty);
    expect(sansDroit, isNotEmpty);
    final a = pour(avecDroit.first);
    expect(a, hasLength(1), reason: 'une alerte par code, jamais une par prescription');
    expect(a.single.titre, 'Prix à définir : « TF2C » Prestation TF2C');
    expect(a.single.detail, startsWith('2 pièce(s) en attente à la caisse.'));
    final pt = patientNonAssure(m);
    for (final x in [pt['nom'], pt['prenom'], pt['code']]) {
      expect('${a.single.titre} ${a.single.detail}', isNot(contains('$x')), reason: 'aucune donnée de santé, aucun patient');
    }
    for (final r in sansDroit) {
      expect(pour(r), isEmpty, reason: '$r ne fixe pas les prix');
    }
    expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
    expect(pour(avecDroit.first), isEmpty, reason: 'retombe au Oui');
    // Sur un FILEUL, la version validée arrive par la synchronisation, sans valorisation écrite : l'alerte DÉRIVÉE retombe quand même (elle lit le prix à la
    // date de la pièce), la pièce garde sa ligne sans prix jusqu'à l'encaissement qui la valorise.
    final q = da.proposer(creation('TF2F', 1800, jourPlus(0)));
    final fq = prescrire(m, ['TF2F']).facture;
    expect(pour(avecDroit.first).map((n) => n.cle), ['prix:tarif:TF2F']);
    m.collection('versionsTarif').mettreAJour(q.version!['id'], {'statut': 'valide', 'decidePar': 'Direction (mère)'});
    expect(((m.collection('factures').parId(fq['id'])!['lignes'] as List).first as Map)['prixManquant'], isNotNull, reason: 'aucune valorisation écrite par la réception');
    expect(pour(avecDroit.first), isEmpty, reason: 'retombe dès que le prix est en vigueur à la date de la pièce, sans tâche');
  });

  test('le prix lu À LA DATE DE LA PIÈCE : une pièce de la veille n’est pas valorisée par un prix d’aujourd’hui', () {
    final m = jeu();
    final da = poste(m, 'da', 'Yvette DAF');
    final p = da.proposer(creation('TF2D', 2700, jourPlus(0)));
    final fac = prescrire(m, ['TF2D'], date: horloge.subtract(const Duration(days: 1))).facture;
    expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
    final f = m.collection('factures').parId(fac['id'])!;
    final l = ((f['lignes'] as List).first as Map).cast<String, Object?>();
    expect([l['prixUnitaire'], (l['prixManquant'] as Map)['cause']], [null, 'version-future']);
    expect(() => encaisserFacture(m, '${fac['id']}', maintenant: horloge), throwsA(isA<RefusCaisse>().having((e) => e.motif, 'motif', contains('date d’effet du 29/10/2026 au plus tard'))));
  });

  test('SUR UN FILEUL APRÈS SYNCHRONISATION : prescription sans prix sur le fileul, caisse du fileul refusée ; la Direction décide le prix sur la mère ; le fileul reçoit la version et l’encaissement passe, valorisé à la date de la pièce', () async {
    const port = 19489;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-tf2'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Fileul');
    final mm = jeu();
    final mf = Magasin({'actes': <M>[], 'notifications': <M>[], 'factures': <M>[], 'ecritures': <M>[], 'taches': <M>[], 'ordonnances': <M>[], 'patients': mm.collection('patients').toutes, 'couverturesAssurance': mm.collection('couverturesAssurance').toutes});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final da = poste(mm, 'direction', 'Direction', etiquette: 'M');
    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (!fini()) {
        await pub.pousser();
        await appl.tirer();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, appl ${appl.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      await pub.pousser();
      final code = await console.codeAppareil('Fileul').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      final p = da.proposer(creation('TF2S', 3900, jourPlus(0)));
      await converger(() => mf.collection('tarifs').toutes.any((t) => t['code'] == 'TF2S'), 'la prestation proposée arrive au fileul');
      final fac = prescrire(mf, ['TF2S']).facture;
      expect([fac['montantTTC'], fac['enAttentePrix']], [null, true], reason: 'sur le fileul : prescrite, total non calculable, jamais 0');
      expect(() => encaisserFacture(mf, '${fac['id']}', maintenant: horloge), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', 'ENCAISSEMENT_PRIX_MANQUANT')));
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      await converger(() => mf.collection('versionsTarif').parId(p.version!['id'])?['statut'] == 'valide', 'la décision arrive au fileul');
      expect(etatCaissePrix(mf, mf.collection('factures').parId(fac['id'])!, horloge).encaissable, isTrue, reason: 'la commande « Encaisser » revient sur le fileul');
      final res = encaisserFacture(mf, '${fac['id']}', maintenant: horloge);
      expect([((res.facture['lignes'] as List).first as Map)['prixUnitaire'], res.facture['statutPaiement']], [3900, 'soldee'], reason: 'valorisée à la date de la pièce puis encaissée, sans redémarrage');
    } finally {
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
