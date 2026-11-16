import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LOT TARIF-FIX (16/11/2026), exigence de la Direction du 15/11/2026 : une fois le prix décidé, la prescription ne dit PLUS « prix à définir », sur la mère ET sur un
/// fileul après synchronisation, sans redémarrage ; une date d'effet future est lue le jour dit (lecture à la date de la pièce à chaque lecture) ; une pièce émise garde
/// son prix ; les deux colonnes ne se remplacent jamais ; la projection de lecture est remise au pas à la décision. Et les deux certificats d'aptitude.
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

DemandeProposition creation(String code, num prix, String dateEffet, {String famille = 'ACTE', String etatAssure = 'unique', num? prixAssure, bool? assurable}) => DemandeProposition(
    code: code,
    prixNonAssure: prix,
    etatAssure: etatAssure,
    prixAssure: prixAssure,
    dateEffet: dateEffet,
    motif: 'Test TARIF-FIX',
    assurable: assurable,
    creation: {'libelle': 'Prestation $code', 'famille': famille, 'secteur': 'Soins'});

/// La prescription d'un acte par le moteur du domaine : le prix de la ligne de facture, ou le refus nommé.
({num? prix, String? refus, String? texte}) prescrire(Magasin m, String code, {bool assure = false, String voie = 'actes'}) {
  final s = StockMagasin(m, () => horloge);
  final pat = m.collection('patients').actives.where((p) => p['externe'] != true).toList();
  final pt = assure
      ? pat.firstWhere((p) => csVrai(p['assureur']) && carteValide(p, m.collection('couverturesAssurance').toutes, horloge.toIso8601String()) && ((p['tauxPriseEnCharge'] as num?) ?? 0) > 0)
      : pat.firstWhere((p) => !csVrai(p['assureur']));
  try {
    final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'test', 'date': horloge.toIso8601String(), voie: [code]}, session);
    return (prix: ((r.facture['lignes'] as List).first as Map)['prixUnitaire'] as num?, refus: null, texte: null);
  } on RefusCs catch (e) {
    return (prix: null, refus: e.code, texte: e.message);
  }
}

void main() {
  setUp(() => horloge = DateTime(2026, 10, 30, 10));

  group('sur la mère, sans redémarrage', () {
    test('(a) un code sans prix dit « prix à définir » ; après le Oui à effet d’AUJOURD’HUI, la prescription suivante lit CE prix, la projection suit à la décision', () {
      final m = jeu();
      final da = poste(m, 'da', 'Yvette DAF');
      final p = da.proposer(creation('TFA1', 4200, jourPlus(0)));
      expect(p.refus, isNull);
      final avant = prescrire(m, 'TFA1');
      expect([avant.prix, avant.refus], [null, 'PRIX_A_DEFINIR']);
      expect(avant.texte, contains('prix à définir'));
      expect(TarifsPoste.ligne(m, 'TFA1', aujourdhui: horloge).cause, 'proposition-en-attente');
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      expect(prescrire(m, 'TFA1').prix, 4200, reason: 'la même instance du magasin, aucun redémarrage');
      expect(m.collection('actes').toutes.where((a) => a['code'] == 'TFA1').single['prix'], 4200, reason: 'projection remise au pas à la décision');
      expect(TarifsPoste.parites(m, horloge), isEmpty);
    });

    test('(b) date d’effet FUTURE : « prix à définir, effectif le JJ/MM/AAAA » jusqu’au jour dit, puis le prix ce jour-là SANS redémarrage ni tâche ; la projection du jour suit à l’ouverture d’un écran', () {
      final m = jeu();
      final da = poste(m, 'da', 'Yvette DAF');
      final p = da.proposer(creation('TFB1', 6100, jourPlus(1)));
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      final l = TarifsPoste.ligne(m, 'TFB1', aujourdhui: horloge);
      expect([l.ok, l.cause, l.effectifLe, l.libelleCourt], [false, 'version-future', jourPlus(1), 'prix à définir, effectif le 31/10/2026']);
      expect(prescrire(m, 'TFB1').texte, contains('prix à définir, effectif le 31/10/2026'));
      horloge = horloge.add(const Duration(days: 1));
      expect(prescrire(m, 'TFB1').prix, 6100, reason: 'le jour dit, la lecture à la date de la pièce donne le prix, AVANT toute projection');
      expect(m.collection('actes').toutes.where((a) => a['code'] == 'TFB1'), isEmpty, reason: 'la liste de lecture n’est pas encore projetée');
      expect(TarifsPoste.projeterSiNouveauJour(m, horloge), greaterThan(0), reason: 'le changement de jour branché à l’ouverture d’un écran');
      expect(m.collection('actes').toutes.where((a) => a['code'] == 'TFB1').single['prix'], 6100);
      expect(TarifsPoste.projeterSiNouveauJour(m, horloge), 0, reason: 'une fois par jour');
    });

    test('(c) un prix modifié pour un code qui en avait un : la pièce émise garde son prix, la prochaine lit le nouveau le jour dit', () {
      final m = jeu();
      final da = poste(m, 'da', 'Yvette DAF');
      final avant = TarifsPoste.ligne(m, 'MG01', aujourdhui: horloge).montant!;
      prescrire(m, 'MG01');
      final emise = m.collection('factures').toutes.first;
      final figee = '${emise['lignes']}';
      final p = da.proposer(DemandeProposition(code: 'MG01', prixNonAssure: avant + 700, etatAssure: 'unique', dateEffet: jourPlus(1), motif: 'Test TARIF-FIX (c)'));
      expect(p.refus, isNull);
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      expect(prescrire(m, 'MG01').prix, avant);
      horloge = horloge.add(const Duration(days: 1));
      expect(prescrire(m, 'MG01').prix, avant + 700);
      expect('${m.collection('factures').parId(emise['id'])!['lignes']}', figee, reason: 'une pièce émise ne se réécrit jamais');
    });

    test('(d) les DEUX prix : colonne assurée vide, le non assuré lit son prix et l’assuré « prix assuré à définir », jamais l’autre colonne ; le geste (une version au prix assuré) le rend tarifable', () {
      final m = jeu();
      final da = poste(m, 'da', 'Yvette DAF');
      final p = da.proposer(creation('TFD1', 5000, jourPlus(0), etatAssure: 'manquant', assurable: true));
      expect(p.refus, isNull, reason: '${p.refus}');
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      expect(prescrire(m, 'TFD1').prix, 5000);
      final ass = prescrire(m, 'TFD1', assure: true);
      expect([ass.prix, ass.refus], [null, 'PRIX_A_DEFINIR']);
      expect(ass.texte, contains('prix assuré à définir'));
      horloge = horloge.add(const Duration(days: 1));
      final p2 = da.proposer(DemandeProposition(code: 'TFD1', prixNonAssure: 5000, etatAssure: 'montant', prixAssure: 3500, dateEffet: jourPlus(0), motif: 'Prix assuré'));
      expect(p2.refus, isNull, reason: '${p2.refus}');
      expect(da.decider('${p2.version!['id']}', 'oui').refus, isNull);
      expect(prescrire(m, 'TFD1', assure: true).prix, 3500);
    });

    test('(e) une analyse absente du référentiel : « Nouvelle prestation, famille Analyses, même code » puis Oui la rend tarifable', () {
      final m = jeu();
      final da = poste(m, 'da', 'Yvette DAF');
      final avant = prescrire(m, 'TFL1', voie: 'analyses');
      expect(avant.refus, 'PRIX_A_DEFINIR');
      expect(TarifsPoste.ligne(m, 'TFL1', aujourdhui: horloge, voie: 'analyse').geste, contains('famille Analyses de laboratoire, MÊME code'));
      final p = da.proposer(creation('TFL1', 2700, jourPlus(0), famille: 'LABO'));
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      expect(prescrire(m, 'TFL1', voie: 'analyses').prix, 2700);
    });
  });

  group('les deux certificats d’aptitude', () {
    test('CERT-APT « Certificat médical d’aptitude » 7 000 (que la caisse lit) et CERT-CA « Certificat d’aptitude » 5 000 : deux prestations, deux codes ; un second code identique écrit autrement est REFUSÉ', () {
      final m = jeu();
      final h = TarifsPoste.lire(m);
      expect(h.tarifs.where((t) => tarCodeNormalise(t['code']) == 'CERT-APT').map((t) => t['libelle']), ['Certificat médical d’aptitude']);
      expect(h.tarifs.where((t) => t['code'] == 'CERT-CA').map((t) => t['libelle']), ['Certificat d’aptitude']);
      expect(TarifsPoste.prixGrille(m, 'CERT-APT', aujourdhui: horloge).montant, 7000);
      expect(TarifsPoste.prixGrille(m, 'CERT-CA', aujourdhui: horloge).montant, 5000);
      expect(prescrire(m, 'CERT-APT').prix, 7000, reason: 'la prescription d’actes lit le certificat hors de l’espace des actes');
      final da = poste(m, 'da', 'Yvette DAF');
      for (final c in ['cert-apt', ' CERT-APT ', 'Cert-Ca']) {
        final r = da.proposer(creation(c, 5000, jourPlus(0), famille: 'CERTIFICAT'));
        expect(r.refus?.code, 'CODE_EXISTANT', reason: c);
      }
    });
  });

  test('SUR UN FILEUL APRÈS SYNCHRONISATION : la Directrice Administrative (mère) décide un prix à effet d’aujourd’hui, puis un à effet de demain ; le fileul reçoit les versions et sa prescription lit le prix, sans redémarrage, le jour dit', () async {
    const port = 19487;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-tariffix'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Fileul');
    final mm = jeu();
    final mf = Magasin({'actes': <M>[], 'notifications': <M>[], 'patients': mm.collection('patients').toutes, 'couverturesAssurance': mm.collection('couverturesAssurance').toutes});
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero, collections: {...collectionsConfiguration()});
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final da = poste(mm, 'da', 'Yvette DAF', etiquette: 'M');
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
      await converger(() => mf.collection('tarifs').toutes.any((t) => t['code'] == 'CERT-CA'), 'réception du référentiel par le fileul');
      expect(prescrire(mf, 'CERT-CA').prix, 5000, reason: 'le fileul reçoit le second certificat');
      // Un code sans prix, puis décidé AUJOURD'HUI.
      final p = da.proposer(creation('TFS1', 3900, jourPlus(0)));
      await converger(() => mf.collection('tarifs').toutes.any((t) => t['code'] == 'TFS1'), 'la prestation proposée arrive au fileul');
      expect(prescrire(mf, 'TFS1').refus, 'PRIX_A_DEFINIR', reason: 'avant la décision : « prix à définir », jamais 0');
      expect(da.decider('${p.version!['id']}', 'oui').refus, isNull);
      await converger(() => mf.collection('versionsTarif').parId(p.version!['id'])?['statut'] == 'valide', 'la décision arrive au fileul');
      expect(prescrire(mf, 'TFS1').prix, 3900, reason: 'le fileul lit le prix décidé, sans redémarrage');
      // Une date d'effet FUTURE : « prix à définir, effectif le … » chez le fileul jusqu'au jour dit.
      final f = da.proposer(creation('TFS2', 4400, jourPlus(1)));
      expect(da.decider('${f.version!['id']}', 'oui').refus, isNull);
      await converger(() => mf.collection('versionsTarif').parId(f.version!['id'])?['statut'] == 'valide', 'la décision à effet futur arrive au fileul');
      expect(prescrire(mf, 'TFS2').texte, contains('prix à définir, effectif le 31/10/2026'));
      horloge = horloge.add(const Duration(days: 1));
      expect(prescrire(mf, 'TFS2').prix, 4400, reason: 'le jour dit, sans connexion, sans redémarrage ni tâche');
    } finally {
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
