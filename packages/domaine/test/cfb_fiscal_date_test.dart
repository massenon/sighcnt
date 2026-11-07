// Rejoue `test/vecteurs/fiscal-date.json` (prototype_html/build/vecteurs-fiscal-date.js : le moteur RÉEL de la maquette, SIGH.configurationFiscale,
// S.identiteALaDate, D.obligationsALaDate, S.genEcheances, SIGH.paie.calculOrtb, horloge figée au 16/08/2026 10 h) sur les fonctions pures du
// domaine, dans l'ORDRE des gestes du script : la semence, une version 2 de l'identité au 01/09, CCIB-2 du 10 au 15 à effet du 01/06, la
// régénération (payée conservée, non payée régénérée), la génération complète de 2026 et 2027, le retrait de la TVM, le seuil télé relevé à
// 80 000 au 01/08, la validation refusée à la réception et acceptée à la DAF, puis « modifié depuis ».
//
// Trois MUTATIONS doivent faire tomber ces tests : ignorer la date dans le calcul ORTB (cas du 01/06 contre le 01/09), laisser la réception
// valider (VALIDATION_RESERVEE), toucher une échéance payée à la régénération (quittance ITS de juin et juillet).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();

/// L'horloge du script : 16/08/2026 10 h (UTC dans le navigateur du banc).
final maintenant = DateTime.utc(2026, 8, 16, 10);
final aujourdhui = DateTime(2026, 8, 16);
const acteur = 'BASSONGUI Chabi Séko';
DateTime d(String iso) => DateTime.parse(iso);

/// Applique une écriture d'obligation au magasin simulé : la copie va à l'historique, la fiche est remplacée (ou créée, ou archivée).
void appliquer(CfbEcritureObligation r, List<M> obligations, List<M> historique) {
  expect(r.ok, isTrue, reason: '${r.refus}');
  if (r.historique != null) historique.add({...r.historique!, 'id': 'HOB${historique.length + 1}'});
  if (r.creation) {
    obligations.add({...r.fiche!, 'id': 'OBL${obligations.length + 1}'});
  } else {
    final i = obligations.indexWhere((o) => '${o['id']}' == r.id);
    obligations[i] = r.fiche!;
  }
}

void main() {
  final v = lireVecteurs('fiscal-date');
  test('le vecteur est celui de l’horloge du 16/08/2026, sans erreur de page', () {
    expect(v['aujourdhui'], isoJour(aujourdhui));
    expect((v['erreurs'] as List), isEmpty, reason: 'le script a relevé des erreurs de page');
  });

  // --------------------------------------------------------------------------------------------------------------------------------------------
  group('identité légale à la date (versions)', () {
    final vi = obj(v['identiteALaDate']);
    final versions = <M>[cfbSemenceIdentite()];

    test('la semence est la version 1, depuis l’ouverture, non validée : les champs sont ceux de C.BRAND_ORIGINE', () {
      memes(versions.first, vi['semence'], 'semence', ignorer: {'id', 'creeLe', 'creePar'});
      expect(cfbIdentiteSemence().keys.toList(), champsIdentiteLegale);
      expect(cfbIdentiteALaDate(versions, aujourdhui)!['version'], 1);
      expect(cfbIdentiteALaDate(const [], aujourdhui), isNull);
    });

    test('une version 2 au 01/09/2026 (RCCM et adresse fiscale) : l’ancienne se ferme au 31/08 et reste, la nouvelle n’est pas en force aujourd’hui', () {
      final r = cfbNouvelleVersionIdentite(versions, {'rccm': 'RB/NAT/2026-B-999', 'bp': 'BP : 999 NATITINGOU (Rép. du Bénin)'},
          dateEffet: '2026-09-01', motif: 'Vecteur : nouveau RCCM et nouvelle adresse fiscale', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      final att = obj(vi['creation']);
      expect(r.ok, att['ok']);
      expect(r.version, att['version']);
      expect(r.enForceAujourdhui, att['enForceAujourdhui']);
      expect(r.mode, 'version');
      expect(r.precedenteId, 'IDL001');
      expect(r.patchPrecedente!['fin'], '2026-08-31');
      // le magasin écrit : la nouvelle fiche, et le patch de l'ancienne
      versions[0] = {...versions[0], ...r.patchPrecedente!};
      versions.add({...r.fiche!, 'id': 'IDL002'});
      final attVersions = liste(vi['versions']);
      final tri = [...versions]..sort((a, b) => (b['version'] as int).compareTo(a['version'] as int));
      for (var i = 0; i < attVersions.length; i++) {
        memes(tri[i], attVersions[i], 'versions[$i]', sousEnsemble: true);
      }
      expect(r.fiche!['ifu'], IdentiteClinique.ifu, reason: 'un champ non saisi est copié de la version couvrante');
      expect(r.fiche!['nom'], IdentiteClinique.nom);
    });

    test('cinq dates : avant toute version (v1), aujourd’hui, le 31/08 (v1), le 01/09 et le 31/12 (v2)', () {
      for (final c in liste(vi['dates'])) {
        final date = d('${c['date']}');
        final fiche = cfbIdentiteALaDate(versions, date)!;
        final i = cfbIdentiteImprimee(versions, date);
        expect(fiche['version'], c['version'], reason: '${c['date']}');
        expect([i.rccm, i.bp, i.ifu, i.nom], [c['rccm'], c['bp'], c['ifu'], c['nom']], reason: '${c['date']}');
      }
    });

    test('C.BRAND aujourd’hui reste la version 1 : une version à effet futur ne change pas ce que la caisse imprime ce matin', () {
      final b = obj(vi['brandAujourdhui']);
      final i = cfbIdentiteImprimee(versions, aujourdhui);
      expect([i.rccm, i.bp], [b['rccm'], b['bp']]);
      expect(i.version, 1);
      expect(cfbIdentiteImprimee(const [], aujourdhui).rccm, IdentiteClinique.rccm, reason: 'sans magasin : la semence');
    });

    test('le rouleau porte l’identité EN FORCE À LA DATE DE LA PIÈCE : hier l’ancien RCCM, après la date d’effet le nouveau', () {
      EntreeTicket entree(DateTime quand) => EntreeTicket(operateur: 'CAISSE', numero: 'FN-2026-00001', date: quand, partPatient: 1000, total: 1000);
      final hier = lignesTicket(entree(DateTime(2026, 8, 15, 9)), identite: cfbIdentiteImprimee(versions, DateTime(2026, 8, 15))).map((l) => l.brut).toList();
      final apres = lignesTicket(entree(DateTime(2026, 12, 31, 9)), identite: cfbIdentiteImprimee(versions, DateTime(2026, 12, 31))).map((l) => l.brut).toList();
      expect(hier, contains('RCCM RB/NAT/2016-B-268'));
      expect(apres, contains('RCCM RB/NAT/2026-B-999'));
      expect(apres, contains('BP : 999 NATITINGOU (Rép. du Bénin)'));
      expect(apres.first, 'CLINIQUE NASSIERA TOO', reason: 'le nom court se dérive du nom de la version');
      expect(lignesTicket(entree(DateTime(2026, 8, 15, 9))).map((l) => l.brut), hier, reason: 'sans identité passée : la semence, soit la version 1');
    });

    test('refus nommés : motif requis dès la version 2, exercice clos, IFU à 13 chiffres, une version par date d’effet', () {
      final att = obj(vi['refus']);
      String code(CfbEcritureIdentite r) => r.refus!.code;
      expect(code(cfbNouvelleVersionIdentite(versions, {'rccm': 'X'}, dateEffet: '2026-10-01', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), att['sansMotif']);
      expect(code(cfbNouvelleVersionIdentite(versions, {'rccm': 'X'}, dateEffet: '2025-10-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)),
          att['exerciceClos']);
      expect(code(cfbNouvelleVersionIdentite(versions, {'ifu': '123'}, dateEffet: '2026-10-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)),
          att['ifuFormat']);
      expect(code(cfbNouvelleVersionIdentite(versions, {'rccm': 'X'}, dateEffet: '2026-09-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)),
          att['memeDate']);
      expect(cfbNouvelleVersionIdentite(versions, {'rccm': 'X'}, dateEffet: '2026-08-20', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).ok, isTrue,
          reason: 'une date entre les deux versions est acceptée : v1 (debut nul) couvre, aucune version n’y prend déjà effet');
      expect(code(cfbNouvelleVersionIdentite(versions, {'rccm': 'X'}, dateEffet: '2026-10-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui, fileul: true)),
          'FILEUL_LECTURE_SEULE');
      expect(code(cfbNouvelleVersionIdentite(versions, {'telephones': ''}, dateEffet: '2026-10-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)),
          'TELEPHONE_REQUIS');
      expect(code(cfbNouvelleVersionIdentite(versions, {'nom': ' '}, dateEffet: '2026-10-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'NOM_REQUIS');
    });

    test('l’état : à valider, deux versions comptées (en force et à venir), dernière modification datée et attribuée', () {
      final e = cfbEtatIdentite(versions, aujourdhui);
      memes(e.fiche, vi['etat'], 'etat');
      expect(cfbTexteEtat(e, 'identité légale', (iso) => iso), startsWith('identité légale à valider (première configuration)'));
    });

    test('avant la première validation « Enregistrer » corrige la version en force ; après, il exige une version datée', () {
      final r = cfbEnregistrerIdentite(versions, {'slogan': ' Nouveau slogan '}, acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      expect(r.ok, isTrue);
      expect(r.mode, 'en_place');
      expect(r.id, 'IDL001');
      expect(r.fiche!['slogan'], 'Nouveau slogan');
      expect(r.fiche!['modifiePar'], acteur);
      final validees = [for (final x in versions) {...x, 'valideLe': '2026-08-16T11:00:00.000Z', 'validePar': 'TAKI Alimatou'}];
      expect(cfbEnregistrerIdentite(validees, {'slogan': 'X'}, acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'VERSION_REQUISE');
      expect(cfbEnregistrerIdentite(versions, {'ifu': '12'}, acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'IFU_FORMAT');
      expect(cfbEnregistrerIdentite(const [], {'slogan': 'X'}, acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'IDENTITE_ABSENTE');
    });
  });

  // --------------------------------------------------------------------------------------------------------------------------------------------
  // Le magasin simulé des obligations suit le script : il est partagé par les groupes qui suivent, dans l'ordre.
  final obligations = <M>[...cfbSemenceObligations()];
  final historique = <M>[];
  final echeances = <M>[];

  group('obligations à la date (CCIB-2 du 10 au 15 juin, à effet du 01/06/2026)', () {
    final vo = obj(v['obligationsALaDate']);

    test('la semence : 19 obligations du calendrier confirmé et la fiche ORTB-PARAMETRES, aucune validée', () {
      expect(obligations.length, 20);
      expect(obligations.where((o) => o['type'] == 'obligation').length, cfbCalendrierFiscal.length);
      expect(obligations.last['code'], 'ORTB-PARAMETRES');
      expect(obligations.every((o) => o['valideLe'] == null && o['dateEffet'] == null), isTrue);
      expect(obligations.first['id'], 'FIS01');
      expect(obligations.first['famille'], 'ITS');
      expect(obligations.where((o) => o['code'] == 'CCIB-1').single['famille'], 'CCIB');
      // sans magasin : la semence, et seulement les obligations
      expect(cfbObligationsALaDate(const [], const [], aujourdhui).length, cfbCalendrierFiscal.length);
    });

    test('avant la modification : CCIB-2 le 10 juin, version d’origine', () {
      final o = cfbObligationsALaDate(obligations, historique, d('2026-05-15')).where((x) => x['code'] == 'CCIB-2').single;
      memes({'code': o['code'], 'jour': o['jour'], 'mois': o['mois'], 'periodicite': o['periodicite'], 'part': o['part'], 'dateEffet': o['dateEffet']}, vo['avant'], 'avant');
    });

    test('refus nommés : exercice clos, motif requis, jour invalide, code existant (TVM)', () {
      final att = obj(vo['refus']);
      expect(cfbModifierObligation(obligations, code: 'CCIB-2', valeurs: {'jour': 15}, dateEffet: '2025-06-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code,
          att['exerciceClos']);
      expect(cfbModifierObligation(obligations, code: 'CCIB-2', valeurs: {'jour': 15}, dateEffet: '2026-06-01', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code,
          att['sansMotif']);
      expect(cfbModifierObligation(obligations, code: 'CCIB-2', valeurs: {'jour': 40}, dateEffet: '2026-06-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code,
          att['jourInvalide']);
      expect(
          cfbCreerObligation(obligations, historique,
                  valeurs: {'code': 'TVM', 'libelle': 'x', 'periodicite': 'annuelle', 'jour': 1, 'mois': 0}, dateEffet: '2026-06-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)
              .refus!
              .code,
          att['codeExistant']);
      expect(cfbModifierObligation(obligations, code: 'XXX', valeurs: {'jour': 1}, motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'OBLIGATION_INCONNUE');
      expect(cfbModifierObligation(obligations, code: 'IS-1', valeurs: {'mois': 12}, motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'MOIS_INVALIDE');
      expect(cfbModifierObligation(obligations, code: 'IS-1', valeurs: {'part': 120}, motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'PART_INVALIDE');
      expect(cfbCreerObligation(obligations, historique, valeurs: {'code': 'tps 1'}, motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui).refus!.code, 'CODE_INVALIDE');
    });

    test('la modification : la version sortante va à l’historique (jour 10, fin 31/05), la fiche porte jour 15, date d’effet 01/06, plus de validation', () {
      final r = cfbModifierObligation(obligations, code: 'CCIB-2', valeurs: {'jour': 15}, dateEffet: '2026-06-01', motif: 'Vecteur : la DGI reporte la 2e tranche au 15',
          acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      final att = obj(vo['modification']);
      expect(r.ok, att['ok']);
      expect([r.code, r.fiche!['jour'], r.dateEffet], [att['code'], att['jour'], att['dateEffet']]);
      appliquer(r, obligations, historique);
      final hist = [for (final h in cfbVersionsObligation(historique, 'CCIB-2')) {'jour': h['jour'], 'dateEffet': h['dateEffet'], 'dateFin': h['dateFin'], 'retiree': h['retiree']}];
      memes(hist, vo['historique'], 'historique');
      final fiche = obligations.where((o) => o['code'] == 'CCIB-2').single;
      memes({'jour': fiche['jour'], 'dateEffet': fiche['dateEffet'], 'valideLe': fiche['valideLe']}, vo['fiche'], 'fiche');
      expect(historique.single['obligationId'], fiche['id']);
      expect(historique.single['remplaceePar'], acteur);
    });

    test('trois dates : le 15/05 lit la version d’origine (le 10), le 01/06 et le 31/12 la nouvelle (le 15) ; les 19 codes restent, dans l’ordre', () {
      for (final c in liste(vo['dates'])) {
        final l = cfbObligationsALaDate(obligations, historique, d('${c['date']}'));
        final o = l.where((x) => x['code'] == 'CCIB-2').single;
        expect([o['jour'], o['dateEffet']], [c['jour'], c['dateEffet']], reason: '${c['date']}');
        expect(l.length, c['nombreObligations'], reason: '${c['date']}');
        expect(l.map((x) => x['code']).toList(), c['codes'], reason: '${c['date']}');
      }
    });
  });

  group('échéances d’un exercice depuis la version en vigueur, régénération sans toucher une payée', () {
    final ve = obj(v['echeancesVersion']);

    test('le magasin du jeu : 2026 engendré depuis la semence (CCIB-2 au 10/06 réputée payée : le script la remet due)', () {
      echeances.addAll(cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: aujourdhui));
      expect(echeances.length, 63, reason: '4 mensuelles sur 12 mois et 15 annuelles');
      final ccib2 = echeances.where((e) => e['code'] == 'CCIB-2').single;
      expect(ccib2['echeance'], '2026-06-10');
      expect(ccib2['paye'], isTrue, reason: 'le 10/06 est passé de plus de 25 jours au 16/08');
      ccib2['paye'] = false;
      ccib2['datePaiement'] = null;
      ccib2['reference'] = null;
      ccib2['valideePar'] = null;
    });

    test('régénération CCIB-2 au 01/06 : 0 conservée, 0 antérieure, 1 archivée, 1 créée ; CCIB-1 payée intacte ; magasin = celui de la maquette', () {
      final r = cfbRegenererEcheances(echeances, code: 'CCIB-2', dateEffet: '2026-06-01', auteur: acteur, maintenant: maintenant, obligations: obligations, historique: historique);
      memes(r.comptes, {...obj(ve['regeneration'])}, 'regeneration', sousEnsemble: true);
      echeances
        ..clear()
        ..addAll(r.echeances);
      final ccib = [
        for (final e in echeances)
          if (e['code'] == 'CCIB-1' || e['code'] == 'CCIB-2')
            {'code': e['code'], 'echeance': e['echeance'], 'statut': e['statut'], 'versionObligation': e['versionObligation'], 'paye': e['paye'] == true, 'reference': e['reference']}
      ]..sort((a, b) => '${a['code']}${a['echeance']}${a['statut']}'.compareTo('${b['code']}${b['echeance']}${b['statut']}'));
      memes(ccib, ve['magasinCcib'], 'magasinCcib');
      expect(r.avant, ['2026-06-10']);
      expect(r.apres, ['2026-06-15']);
      expect(r.creeesFiches.single['regenereePar'], acteur);
      expect(r.libelle, 'Échéances régénérées : CCIB-2, 1');
    });

    test('2026 engendré depuis la version en vigueur de chaque mois : 61 échéances, CCIB-2 au 15/06 avec sa version, dates, reports, périodes et règlements = maquette', () {
      final l = cfbGenEcheances(2026, obligations: obligations, historique: historique, aujourdhui: aujourdhui);
      final att = liste(ve['engendrees2026']);
      expect(l.length, att.length);
      for (var i = 0; i < att.length; i++) {
        memes({
          'code': l[i]['code'],
          'echeance': l[i]['echeance'],
          'echeanceTheorique': l[i]['echeanceTheorique'],
          'reportee': l[i]['reportee'],
          'versionObligation': l[i]['versionObligation'],
          'paye': l[i]['paye'],
          'periode': l[i]['periode'],
        }, att[i], 'engendrees2026[$i] ${att[i]['code']}');
      }
      // MUTATION « genEcheances lit la semence au lieu de la version en vigueur » : CCIB-2 retomberait au 10/06
      expect(cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations()).where((e) => e['code'] == 'CCIB-2').single['echeance'], '2026-06-10');
      expect(l.where((e) => e['code'] == 'CCIB-2').single['echeance'], '2026-06-15');
    });

    test('2027 (sans règlement) : la CCIB suit la version datée, les autres la version d’origine', () {
      final l = cfbGenEcheances(2027, obligations: obligations, historique: historique, aujourdhui: aujourdhui, sansReglement: true);
      expect(l.every((e) => e['paye'] == false), isTrue);
      final ccib = [for (final e in l) if (e['famille'] == 'CCIB') {'code': e['code'], 'echeance': e['echeance'], 'versionObligation': e['versionObligation']}];
      memes(ccib, ve['engendrees2027'], 'engendrees2027');
    });

    test('retrait de la TVM au 01/07 : la version va à l’historique marquée retirée, la TVM payée d’avril reste (antérieure), rien n’est créé', () {
      final att = obj(ve['retrait']);
      final r = cfbRetirerObligation(obligations, code: 'TVM', dateEffet: '2026-07-01', motif: 'Vecteur : TVM retirée', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      expect(r.ok, att['ok']);
      expect(r.archiver, isTrue);
      expect(r.fiche!['statut'], 'archive');
      appliquer(r, obligations, historique);
      final reg = cfbRegenererEcheances(echeances, code: 'TVM', dateEffet: '2026-07-01', auteur: acteur, maintenant: maintenant, obligations: obligations, historique: historique);
      memes(reg.comptes, obj(att['echeances']), 'retrait.echeances', sousEnsemble: true);
      echeances
        ..clear()
        ..addAll(reg.echeances);
      expect(cfbObligationsALaDate(obligations, historique, d('2026-08-01')).any((o) => o['code'] == 'TVM'), att['enVigueurApres']);
      expect(cfbObligationsALaDate(obligations, historique, d('2026-06-30')).any((o) => o['code'] == 'TVM'), att['enVigueurAvant']);
      memes([for (final h in cfbVersionsObligation(historique, 'TVM')) {'dateFin': h['dateFin'], 'retiree': h['retiree']}], att['historique'], 'retrait.historique');
      expect(cfbRetirerObligation(obligations, code: 'ITS', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui, droitAnnuler: false, libelleRole: 'Direction').refus!.code,
          'RETRAIT_RESERVE', reason: 'la Direction édite et valide, elle ne retire pas');
    });

    test('MUTATION « toucher une échéance payée » : ITS au 01/06 (le 12), juin et juillet PAYÉES conservées avec leur quittance, août à décembre régénérées', () {
      // Un magasin à part : ITS engendrée depuis la semence au 16/08 (janvier à juillet réputées payées).
      final magasin = cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: aujourdhui).where((e) => e['code'] == 'ITS').toList();
      expect(magasin.where((e) => e['paye'] == true).map((e) => e['echeance']), ['2026-01-12', '2026-02-10', '2026-03-10', '2026-04-10', '2026-05-11', '2026-06-10', '2026-07-10']);
      final obl = <M>[...cfbSemenceObligations()];
      final hist = <M>[];
      appliquer(cfbModifierObligation(obl, code: 'ITS', valeurs: {'jour': 12}, dateEffet: '2026-06-01', motif: 'test', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui), obl, hist);
      final r = cfbRegenererEcheances(magasin, code: 'ITS', dateEffet: '2026-06-01', auteur: acteur, maintenant: maintenant, obligations: obl, historique: hist);
      expect([r.anterieures, r.conservees, r.archivees, r.creees], [5, 2, 5, 5]);
      final payees = r.echeances.where((e) => e['paye'] == true).toList();
      expect(payees.length, 7, reason: 'aucune quittance ne disparaît');
      expect(payees.every((e) => e['statut'] == 'actif' && e['reference'] == 'QUIT-ITS-2026'), isTrue);
      expect(payees.where((e) => e['echeance'] == '2026-06-10').single['echeanceTheorique'], '2026-06-10', reason: 'juin garde sa date : la quittance ne se réécrit pas');
      final actives = r.echeances.where((e) => e['statut'] == 'actif').map((e) => e['echeance']).toList()..sort();
      expect(actives.where((e) => '$e'.startsWith('2026-06') || '$e'.startsWith('2026-07')).length, 2, reason: 'un mois couvert par une quittance n’est pas dû deux fois');
      expect(r.apres, ['2026-08-12', '2026-09-14', '2026-10-12', '2026-11-12', '2026-12-14'], reason: '12/09 et 12/12 tombent un week-end : reportés');
      expect(r.echeances.where((e) => e['statut'] == 'archive').map((e) => e['echeance']).toList(), ['2026-08-10', '2026-09-10', '2026-10-12', '2026-11-10', '2026-12-10']);
      expect(cfbRefusEcheancePayee(payees.first)!.code, 'ECHEANCE_PAYEE');
      expect(cfbRefusEcheancePayee(const {'paye': false}), isNull);
      final impact = cfbEcheancesImpactees(magasin, 'ITS', '2026-06-01');
      expect(impact, (payees: 2, nonPayees: 5, exercice: 2026));
      expect(cfbAnnoncePortee(impact), 'Exercice 2026 : 2 échéance(s) payée(s) CONSERVÉE(S), 5 échéance(s) non payée(s) RÉGÉNÉRÉE(S).');
    });
  });

  group('paramètres ORTB datés : le seuil télé passe à 80 000 au 01/08/2026', () {
    final vc = obj(v['calculOrtbDate']);
    const champsRedevance = ['id', 'code', 'categorie', 'libelle', 'montant', 'mois', 'moisLabel', 'seuilMin', 'seuilMax', 'assiette'];
    M red(Object? r) => {for (final k in champsRedevance) k: obj(r)[k]};

    test('la modification : la version sortante à l’historique (60 000, fin 31/07), la fiche à 80 000 (télé dès 80 001, assiette réécrite), cumul 4 000', () {
      final r = cfbModifierOrtb(obligations, valeurs: {'seuilTele': 80000}, dateEffet: '2026-08-01', motif: 'Vecteur : seuil relevé', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      final att = obj(vc['modification']);
      expect(r.ok, att['ok']);
      expect([r.fiche!['seuilTele'], r.dateEffet], [att['seuilTele'], att['dateEffet']]);
      appliquer(r, obligations, historique);
      final avant = cfbOrtbALaDate(obligations, historique, d('2026-07-31'));
      final attAvant = obj(vc['parametresAvant']);
      for (final k in const ['type', 'code', 'libelle', 'famille', 'seuilTele', 'cumulMaximum', 'source', 'dateEffet', 'motif', 'valideLe', 'obligationId', 'dateFin', 'remplaceeLe', 'remplaceePar', 'motifRemplacement', 'retiree']) {
        expect(avant[k], attAvant[k], reason: 'avant.$k');
      }
      expect([for (final x in avant['redevances'] as List) red(x)], [for (final x in attAvant['redevances'] as List) red(x)]);
      final apres = cfbOrtbALaDate(obligations, historique, d('2026-08-01'));
      final attApres = obj(vc['parametresApres']);
      for (final k in const ['id', 'type', 'code', 'seuilTele', 'cumulMaximum', 'dateEffet', 'modifieLe', 'modifiePar', 'motif', 'valideLe', 'validePar']) {
        expect(apres[k], attApres[k], reason: 'apres.$k');
      }
      expect([for (final x in apres['redevances'] as List) red(x)], [for (final x in attApres['redevances'] as List) red(x)]);
      memes([for (final h in cfbVersionsObligation(historique, 'ORTB-PARAMETRES')) {'seuilTele': h['seuilTele'], 'dateFin': h['dateFin'], 'cumulMaximum': h['cumulMaximum']}], vc['historique'],
          'historique');
    });

    test('onze bulletins : la version en vigueur à la DATE DU BULLETIN décide ; sans date, aujourd’hui (mutation « date ignorée » : le 01/06 à 70 000 perdrait sa télé)', () {
      for (final c in liste(vc['cas'])) {
        final date = c['date'] == null ? aujourdhui : d('${c['date']}');
        final r = paiCalculOrtbALaDate(c['brut'] as num, c['mois'] as int, date, obligations: obligations, historique: historique);
        final ctx = '${c['brut']} / mois ${c['mois']} / ${c['date']}';
        expect([r.montant, r.montantAnnuel, r.du], [c['montant'], c['montantAnnuel'], c['du']], reason: ctx);
        memes([for (final l in r.lignes) {'id': l.id, 'montant': l.montant, 'montantAnnuel': l.montantAnnuel, 'du': l.du}], c['lignes'], ctx);
      }
      expect(paiCalculOrtbALaDate(70000, 5, d('2026-06-01'), obligations: obligations, historique: historique).tele, isNotNull);
      expect(paiCalculOrtbALaDate(70000, 5, d('2026-09-01'), obligations: obligations, historique: historique).tele, isNull);
      expect(paiCalculOrtb(70000, 5).tele, isNotNull, reason: 'sans magasin : la semence (seuil 60 000)');
      expect(PaiParametresOrtb.aLaDate(d('2026-09-01'), obligations: obligations, historique: historique).seuilTele, 80000);
      expect(PaiParametresOrtb.aLaDate(d('2026-07-31'), obligations: obligations, historique: historique).dateEffet, isNull);
    });

    test('refus nommés : seuil négatif, mois hors calendrier, motif requis, date antérieure à la version en vigueur', () {
      String code(CfbEcritureObligation r) => r.refus!.code;
      expect(code(cfbModifierOrtb(obligations, valeurs: {'seuilTele': -1}, dateEffet: '2026-09-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'SEUIL_INVALIDE');
      expect(code(cfbModifierOrtb(obligations, valeurs: {'tele': {'mois': 12}}, dateEffet: '2026-09-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'MOIS_INVALIDE');
      expect(code(cfbModifierOrtb(obligations, valeurs: {'radio': {'montant': -5}}, dateEffet: '2026-09-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'MONTANT_INVALIDE');
      expect(code(cfbModifierOrtb(obligations, valeurs: {'seuilTele': 90000}, dateEffet: '2026-09-01', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'MOTIF_REQUIS');
      expect(code(cfbModifierOrtb(obligations, valeurs: {'seuilTele': 90000}, dateEffet: '2026-07-15', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'DATE_EFFET_ANTERIEURE');
      expect(code(cfbModifierOrtb(const [], valeurs: {'seuilTele': 90000}, motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui)), 'ORTB_ABSENT');
      final mois = cfbModifierOrtb(obligations, valeurs: {'tele': {'mois': 8, 'montant': 3500}}, dateEffet: '2026-09-01', motif: 'v', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      final tele = (mois.fiche!['redevances'] as List).cast<Map>().where((r) => r['id'] == 'tele').single;
      expect([tele['mois'], tele['moisLabel'], tele['montant'], mois.fiche!['cumulMaximum']], [8, 'septembre', 3500, 4500]);
      expect(cfbEspaceMilliers(80000), '80 000');
      expect(cfbEspaceMilliers(1234567), '1 234 567');
      expect(cfbEspaceMilliers(999), '999');
    });
  });

  group('validation réservée et état « modifié depuis »', () {
    final vv = obj(v['validation']);

    test('la réception ne valide pas (VALIDATION_RESERVEE, le profil est nommé) ; ni le comptable ; un fileul jamais', () {
      final r = cfbValiderIdentite(const [], role: 'reception', acteur: 'X', maintenant: maintenant, aujourdhui: aujourdhui, libelleRole: (r) => 'Réception');
      expect(r.refus!.code, vv['reception']);
      expect(r.refus!.motif, contains('Profil : Réception'));
      for (final role in ['comptable', 'aide_comptable', 'medecin', 'caissier', null]) {
        expect(cfbValiderObligations(obligations, role: role, acteur: 'X', maintenant: maintenant).refus?.code, 'VALIDATION_RESERVEE', reason: '$role');
      }
      expect(cfbValiderObligations(obligations, role: 'da', acteur: 'X', maintenant: maintenant, fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect(cfbRolesValidation, (v['roles'] as List).cast<String>());
      for (final role in cfbRolesValidation) {
        expect(cfbValiderObligations(obligations, role: role, acteur: 'X', maintenant: maintenant).ok, isTrue, reason: role);
      }
    });

    test('la DAF valide d’un coup les 19 fiches actives (18 obligations après le retrait de la TVM, plus les paramètres ORTB) : état « valide »', () {
      final r = cfbValiderObligations(obligations, role: 'da', acteur: 'TAKI Alimatou', maintenant: maintenant);
      final att = obj(vv['da']);
      expect([r.ok, r.nombre, r.validePar], [att['ok'], att['nombre'], att['validePar']]);
      for (var i = 0; i < obligations.length; i++) {
        if (r.ids.contains('${obligations[i]['id']}')) obligations[i] = {...obligations[i], ...r.patch};
      }
      final e = cfbEtatObligations(obligations, historique);
      expect(e.etat, vv['etatObligations']);
      expect(e.validePar, 'TAKI Alimatou');
      expect(cfbTexteEtat(e, 'liste des obligations', (iso) => iso), 'Validé le ${r.valideLe} par TAKI Alimatou.');
      expect(cfbEtatObligations(const [], const []).etat, 'a_valider');
    });

    test('une modification après validation (ITS le 12 au 01/09) : la fiche perd sa validation, l’état devient « modifié depuis », septembre à décembre régénérées', () {
      final r = cfbModifierObligation(obligations, code: 'ITS', valeurs: {'jour': 12}, dateEffet: '2026-09-01', motif: 'Vecteur : après validation', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      final att = obj(vv['apresModification']);
      expect(r.ok, att['ok']);
      appliquer(r, obligations, historique);
      final e = cfbEtatObligations(obligations, historique);
      expect(e.etat, att['etat']);
      expect(e.validationAnterieure!['validePar'], 'TAKI Alimatou');
      expect(e.modifiePar, acteur);
      expect(cfbTexteEtat(e, 'liste des obligations', (iso) => iso), startsWith('Modifié le ${e.modifieLe} par $acteur depuis la validation du '));
      final reg = cfbRegenererEcheances(echeances, code: 'ITS', dateEffet: '2026-09-01', auteur: acteur, maintenant: maintenant, obligations: obligations, historique: historique);
      memes(reg.comptes, obj(att['regeneration']), 'apresModification.regeneration', sousEnsemble: true);
      expect(reg.apres, ['2026-09-14', '2026-10-12', '2026-11-12', '2026-12-14']);
    });

    test('la date d’effet : requise, hors exercice clos (la liasse déposée : 2024 et 2025), jamais antérieure à la version en vigueur', () {
      expect(cfbControleDateEffet(null, exercices: const [], aujourdhui: aujourdhui)!.code, 'DATE_EFFET_REQUISE');
      expect(cfbControleDateEffet('2024-03-01', exercices: const [], aujourdhui: aujourdhui)!.code, 'EXERCICE_CLOS');
      expect(cfbControleDateEffet('2026-03-01', exercices: const [], aujourdhui: aujourdhui), isNull);
      expect(cfbControleDateEffet('2026-03-01', minimum: '2026-06-01', exercices: const [], aujourdhui: aujourdhui)!.code, 'DATE_EFFET_ANTERIEURE');
      expect(cfbControleDateEffet('2026-03-01', exercices: const [{'annee': 2026, 'etat': 'clos'}], aujourdhui: aujourdhui)!.code, 'EXERCICE_CLOS',
          reason: 'un exercice clos au magasin ferme sa date');
    });
  });

  group('version en vigueur : la règle commune des données de référence datées', () {
    test('courante sans date d’effet, puis historique couvrant, puis rien', () {
      final courante = {'code': 'X', 'dateEffet': '2026-06-01', 'jour': 15};
      final hist = [
        {'code': 'X', 'dateEffet': null, 'dateFin': '2026-02-28', 'jour': 5},
        {'code': 'X', 'dateEffet': '2026-03-01', 'dateFin': '2026-05-31', 'jour': 10},
      ];
      expect(versionEnVigueur(courante, hist, '2026-06-01')!['jour'], 15);
      expect(versionEnVigueur(courante, hist, '2026-05-31')!['jour'], 10);
      expect(versionEnVigueur(courante, hist, '2026-01-01')!['jour'], 5);
      expect(versionEnVigueur(null, hist, '2026-07-01'), isNull, reason: 'retirée : aucune version ne couvre');
      expect(versionEnVigueur({'dateEffet': null}, const [], '2000-01-01'), isNotNull);
      expect(isoJour(DateTime(2026, 9, 1, 23, 59)), '2026-09-01');
      expect(isoJour('2026-09-01T10:00:00.000Z'), '2026-09-01');
      expect(veilleIso('2026-03-01'), '2026-02-28');
      expect(veilleIso('2026-01-01'), '2025-12-31');
    });
  });
}
