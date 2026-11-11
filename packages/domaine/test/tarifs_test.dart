// Le référentiel de prix unique (lot T6) : les vecteurs de `test/vecteurs/tarifs.json` sont tirés de l'écran réel « Tarifs et prix » de la maquette, piloté dans Chrome
// (`prototype_html/build/vecteurs-tarifs.js`). Ce test les REJOUE contre le domaine Dart : la résolution à une date, la proposition, la décision, les refus nommés, le
// contrôle d'usage, la date passée, « Valider » en un geste, « Oui à tout » encadré et la pro-forma.
//
// Le monde du test est celui des vecteurs : les 11 prestations de `migration.exemples` (fiche et versions telles que la maquette les porte), plus quelques prestations
// SYNTHÉTIQUES (mêmes codes que le tirage, prix tirés des vecteurs quand ils s'y lisent) et des pièces portant les numéros que le tirage a relevés. Les pièces du jeu de
// démonstration que le tirage a croisées sont remplacées par des pièces synthétiques de même effet (dit en clair à chaque endroit).

import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef F = Map<String, Object?>;

class Monde {
  Monde(this.jour, List<F> tarifs, List<F> versions, this.libelles, this.matrice)
      : tarifs = [for (final t in tarifs) {...t}],
        versions = [for (final v in versions) {...v}];
  final String jour;
  final List<F> tarifs, versions;
  final List<F> factures = [];
  final List<F> demandesAnalyses = [];
  final List<F> demandesImagerie = [];
  final Map<String, String> libelles;
  final MatriceDroits matrice;
  final List<String> journal = [];

  ReferentielTarifs get h => ReferentielTarifs(tarifs, versions);

  ContexteTarif cx(String role, {String? nom, bool? editer, bool fileul = false}) => ContexteTarif(
        referentiel: h,
        aujourdhui: jour,
        role: role,
        auteur: nom ?? 'V $role',
        peutEditerEcran: editer ?? matrice.peutEditer(role, 'cfg-tarifs'),
        fileul: fileul,
        libelles: libelles,
        pieces: PiecesTarif(factures: factures, demandesAnalyses: demandesAnalyses, demandesImagerie: demandesImagerie),
      );

  /// Propose ET écrit ce qu'une proposition recevable donne à écrire (comme le service du poste).
  ResultatTarif<PropositionTarif> proposer(String role, DemandeProposition d, {String? nom, bool? editer}) {
    final r = tarProposer(cx(role, nom: nom, editer: editer), d);
    if (r.ok) {
      final p = r.valeur!;
      if (p.identite != null) tarifs.add(p.identite!);
      versions.add(p.version);
    }
    return r;
  }

  ResultatTarif<DecisionTarif> decider(String role, String id, String decision, {String? motif, String? date, String? nom}) {
    final r = tarDecider(cx(role, nom: nom), id, decision, motif: motif, dateEffet: date);
    if (r.ok) appliquer(r.valeur!);
    return r;
  }

  void appliquer(DecisionTarif d) {
    final i = versions.indexWhere((v) => v['id'] == d.versionId);
    versions[i] = {...versions[i], ...d.patch};
  }

  void piece(String numero, String code, String date) => factures.add({
        'id': numero,
        'numero': numero,
        'date': date,
        'statut': 'actif',
        'lignes': [
          {'id': 'L001', 'acteCode': code, 'prixUnitaire': 1000, 'quantite': 1}
        ],
      });

  num na(String code, [String? date]) => h.aLaDate(code, date, false, aujourdhui: jour).montant!;
}

String plus(String jour, int n) => tarIso(DateTime.parse('${jour}T12:00:00').add(Duration(days: n)));

F prestation(String code, num prix, {String famille = 'ACTE'}) => {'id': code, 'code': code, 'codeActe': code, 'libelle': 'Prestation $code', 'famille': famille, 'statut': 'actif'};
F version1(String code, num prix, {String etatAssure = 'unique'}) => {
      'id': '$code@origine@1',
      'code': code,
      'version': 1,
      'prixNonAssure': prix,
      'prixAssure': prix,
      'etatAssure': etatAssure,
      'origine': 'migration',
      'statut': 'valide'
    };

void main() {
  final v = lireVecteurs('tarifs');
  final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final matrice = MatriceDroits.depuisJson(brut);
  final libelles = {for (final r in liste(brut['roles'])) '${r['id']}': '${r['label']}'};
  final exemples = (v['exemples'] as Map).cast<String, Object?>();
  final jour = '${(v['moteur'] as Map)['aujourdhui']}';

  Monde monde() {
    final tarifs = <F>[], versions = <F>[];
    exemples.forEach((code, x) {
      final m = (x as Map).cast<String, Object?>();
      tarifs.add((m['tarif'] as Map).cast<String, Object?>());
      versions.addAll(liste(m['versions']));
    });
    return Monde(jour, tarifs, versions, libelles, matrice);
  }

  void egalRefus(RefusTarif? r, Map<String, Object?> att, String nom) {
    expect(r, isNotNull, reason: nom);
    expect([r!.code, r.motif, r.geste], [att['code'], att['motif'], att['geste']], reason: nom);
  }

  group('résolution à la date (RG-09, trois états de la colonne assurée plus le prix unique)', () {
    test('les voies lisent la MÊME version : prix non assuré, assuré, NON COUVERT, SOS', () {
      final m = monde();
      final voies = (((v['moteur'] as Map)['voies']) as Map).cast<String, Object?>();
      var lus = 0;
      for (final code in ['SO02', 'SIV', 'IMG-ECHO-PEL', 'CERT-DEC', 'L01']) {
        final att = (voies[code] as Map).cast<String, Object?>();
        for (final c in [(false, 'nonAssure'), (true, 'assure')]) {
          final r = m.h.aLaDate(code, null, c.$1, aujourdhui: jour);
          final a = (att[c.$2] as Map).cast<String, Object?>();
          expect(r.toJson(), a, reason: '$code ${c.$2}');
          lus++;
        }
      }
      // « SIV » est l'alias de grille de SO02 : un code, une prestation, même version.
      expect(m.h.parCode['SIV']!['code'], 'SO02');
      expect(lus, 10);
    });

    test('une prestation absente et une date sans version valide se NOMMENT, jamais un zéro', () {
      final m = monde();
      final inconnue = m.h.aLaDate('NEXISTE', null, false, aujourdhui: jour);
      expect(inconnue.absent, isTrue);
      expect(inconnue.montant, isNull);
      expect(inconnue.motif, contains('NEXISTE'));
      // L05 n'a aucune ligne de grille : une seule version, `null` = depuis toujours ; une prestation sans version valide à la date est absente.
      final sans = ReferentielTarifs([prestation('X1', 100)], [
        {...version1('X1', 100), 'dateEffet': '2026-09-01'}
      ]);
      final r = sans.aLaDate('X1', '2026-08-31', false, aujourdhui: jour);
      expect(r.absent, isTrue);
      expect(r.facturable, isFalse);
      expect(sans.aLaDate('X1', '2026-09-01', false, aujourdhui: jour).montant, 100);
    });

    test('une version proposée, refusée ou retirée n\'est JAMAIS lue (mutation (c) du PRD)', () {
      final m = monde();
      for (final statut in ['propose', 'refuse', 'retire']) {
        final h = ReferentielTarifs([prestation('Y1', 100)], [
          version1('Y1', 100),
          {...version1('Y1', 999), 'id': 'Y1@2026-08-01@2', 'version': 2, 'dateEffet': '2026-08-01', 'statut': statut},
        ]);
        expect(h.aLaDate('Y1', jour, false, aujourdhui: jour).montant, 100, reason: statut);
      }
      expect(m.h.enVigueur('SO02', jour)!['version'], 1);
    });

    test('la date est celle de la PIÈCE : un instant se ramène au jour, une date vide vaut le jour du geste fourni (jamais l\'horloge)', () {
      expect(tarJourDe('2026-08-17T10:00:00', '2026-01-01'), '2026-08-17');
      expect(tarJourDe(null, '2026-01-01'), '2026-01-01');
      expect(tarJourDe('', '2026-01-01'), '2026-01-01');
      expect(tarJourDe('2026-08-17', '2026-01-01'), '2026-08-17');
      final h = ReferentielTarifs([prestation('Z1', 1)], [
        version1('Z1', 1000),
        {...version1('Z1', 1300), 'id': 'Z1@2026-08-20@2', 'version': 2, 'dateEffet': '2026-08-20'},
      ]);
      // Une pièce du 19 garde l'ancien prix, même lue le 25 : le prix se résout à la date de la PIÈCE.
      expect(h.aLaDate('Z1', '2026-08-19', false, aujourdhui: '2026-08-25').montant, 1000);
      expect(h.aLaDate('Z1', '2026-08-20', false, aujourdhui: '2026-08-25').montant, 1300);
      expect(h.aLaDate(null, null, false, aujourdhui: '2026-08-25').absent, isTrue);
      expect(h.aLaDate('Z1', null, false, aujourdhui: '2026-08-25').montant, 1300);
    });

    test('le prix unique : la colonne assurée vaut la colonne non assurée (L01) ; un état « manquant » ne se facture pas', () {
      final m = monde();
      final r = m.h.aLaDate('L01', null, true, aujourdhui: jour);
      expect([r.montant, r.tarif], [2000, 'assuré']);
      final h = ReferentielTarifs([prestation('M1', 1)], [
        {...version1('M1', 100), 'prixAssure': null, 'etatAssure': 'manquant'}
      ]);
      final a = h.aLaDate('M1', null, true, aujourdhui: jour);
      expect(a.montant, isNull);
      expect(a.facturable, isFalse);
      expect(h.aLaDate('M1', null, false, aujourdhui: jour).montant, 100);
    });

    test('les espaces de codes : un lecteur historique garde le sien (acte, grille, analyse)', () {
      final m = monde();
      expect(m.h.prixActe('SO02', null, true, aujourdhui: jour), (connu: true, montant: 800));
      expect(m.h.prixActe('SIV', null, true, aujourdhui: jour).connu, isFalse, reason: 'SIV est un code de grille, pas d\'acte');
      expect(m.h.prixGrille('SIV', null, true, aujourdhui: jour).montant, 800);
      expect(m.h.prixAnalyse('L01', null, true, aujourdhui: jour), (connu: true, montant: 2000));
      expect(m.h.prixAnalyse('SO02', null, true, aujourdhui: jour).connu, isFalse);
      expect(m.h.prixGrille('INCONNU', null, false, aujourdhui: jour).absent, isTrue);
    });
  });

  group('la proposition et la décision (moteur)', () {
    test('les refus nommés de la proposition, mot pour mot', () {
      final m = monde();
      final cas = liste(((v['moteur'] as Map)['cas']));
      final att = {for (final c in cas) '${c['nom']}': c};
      final base = m.na('SO02').toInt(), baseA = m.h.aLaDate('SO02', null, true, aujourdhui: jour).montant!.toInt();
      DemandeProposition d(String code, {Object? na, String etat = 'unique', Object? pa, String? date, String motif = 'x', Map<String, Object?>? creation}) =>
          DemandeProposition(code: code, prixNonAssure: na, etatAssure: etat, prixAssure: pa, dateEffet: date, motif: motif, creation: creation);
      void refus(String nom, DemandeProposition dem) => egalRefus(m.proposer('admin', dem).refus, att[nom]!, nom);
      refus('prix zéro', d('SO02', na: 0, date: plus(jour, 1)));
      refus('prix décimal', d('SO02', na: 1250.5, date: plus(jour, 1)));
      refus('prix absent', d('SO02', na: null, date: plus(jour, 1)));
      refus('colonne assurée annoncée sans montant', d('SO02', na: base + 1, etat: 'montant', pa: null, date: plus(jour, 1)));
      refus('sans motif', d('SO02', na: base + 1, date: plus(jour, 1), motif: ''));
      refus('sans date d’effet', d('SO02', na: base + 1, date: ''));
      refus('date passée', d('SO02', na: base + 1, date: plus(jour, -1)));
      refus('prix inchangé', d('SO02', na: base, etat: 'montant', pa: baseA, date: plus(jour, 1)));
      refus('prestation introuvable', d('NEXISTE', na: 100, date: plus(jour, 1)));
      refus('code existant (alias)', d('SIV', na: 100, date: plus(jour, 1), creation: {'libelle': 'Doublon', 'famille': 'AMI'}));
    });

    test('un changement futur : la proposition ne change RIEN, le Oui prend effet à sa date, un second changement attend (mutation (c) du PRD)', () {
      final m = monde();
      final f = ((v['moteur'] as Map)['futur'] as Map).cast<String, Object?>();
      final base = m.na('SO02').toInt(), baseA = m.h.aLaDate('SO02', null, true, aujourdhui: jour).montant!.toInt();
      final p1 = m.proposer('admin',
          DemandeProposition(code: 'SO02', prixNonAssure: base + 200, etatAssure: 'montant', prixAssure: baseA + 100, dateEffet: plus(jour, 3), motif: 'Vecteur : changement futur'));
      expect(p1.ok, isTrue);
      expect(p1.valeur!.version['id'], ((f['proposee'] as Map)['id']));
      expect(p1.valeur!.version['statut'], 'propose');
      final avant = (f['avantOui'] as Map).cast<String, Object?>();
      expect(m.h.aLaDate('SO02', null, false, aujourdhui: jour).toJson(), avant['aujourdhui']);
      expect(m.h.aLaDate('SO02', plus(jour, 3), false, aujourdhui: jour).toJson(), avant['dansTroisJours'], reason: 'une proposition en attente ne change pas le prix, même à sa date');
      final att = {for (final c in liste((v['moteur'] as Map)['cas'])) '${c['nom']}': c};
      egalRefus(m.proposer('admin', DemandeProposition(code: 'SO02', prixNonAssure: base + 300, etatAssure: 'unique', dateEffet: plus(jour, 4), motif: 'x')).refus, att['un seul changement en attente']!,
          'un seul changement en attente');
      final oui = m.decider('admin', p1.valeur!.version['id'] as String, 'oui');
      expect(oui.ok, isTrue);
      expect([oui.valeur!.version['statut'], oui.valeur!.version['roleDecision']], [(f['decision'] as Map)['statut'], (f['decision'] as Map)['role']]);
      final ap = (f['apresOui'] as Map).cast<String, Object?>();
      expect(m.h.aLaDate('SO02', null, false, aujourdhui: jour).toJson(), ap['aujourdhui']);
      expect(m.h.aLaDate('SO02', plus(jour, 2), false, aujourdhui: jour).toJson(), ap['veille']);
      expect(m.h.aLaDate('SO02', plus(jour, 3), false, aujourdhui: jour).toJson(), ap['jourDit'], reason: 'le prix bascule le jour dit, sans horloge ni connexion');
      expect(m.h.aLaDate('SO02', plus(jour, 3), true, aujourdhui: jour).toJson(), ap['jourDitAssure']);
      expect(m.h.aLaDate('SO02', plus(jour, 10), false, aujourdhui: jour).toJson(), ap['lendemain']);
      final g = (ap['grilleSIV'] as Map).cast<String, Object?>();
      expect(m.h.prixGrille('SIV', null, false, aujourdhui: jour).toJson()..remove('absent'), {...(g['nonAssure'] as Map).cast<String, Object?>()}..remove('absent'));
      egalRefus(m.decider('admin', p1.valeur!.version['id'] as String, 'oui').refus, att['décision rejouée']!, 'décision rejouée');
      // Le retour à l'auteur : rien quand l'auteur décide lui-même.
      expect(oui.valeur!.notification, isNull);
    });

    test('un Non : motif exigé, rien ne change, la proposition reste lisible', () {
      final m = monde();
      m.tarifs.add(prestation('SO12', 5000));
      m.versions.add(version1('SO12', 5000));
      final att = {for (final c in liste((v['moteur'] as Map)['cas'])) '${c['nom']}': c};
      final p2 = m.proposer('admin', DemandeProposition(code: 'SO12', prixNonAssure: 5050, etatAssure: 'unique', dateEffet: plus(jour, 1), motif: 'Vecteur : à refuser'));
      final id = p2.valeur!.version['id'] as String;
      egalRefus(m.decider('admin', id, 'non', motif: '').refus, att['refus sans motif']!, 'refus sans motif');
      final non = m.decider('admin', id, 'non', motif: 'Vecteur : hors grille');
      final r = ((v['moteur'] as Map)['refus'] as Map).cast<String, Object?>();
      expect([non.valeur!.version['statut'], non.valeur!.version['motifDecision']], [r['statut'], r['motif']]);
      expect(m.h.aLaDate('SO12', plus(jour, 1), false, aujourdhui: jour).montant, m.h.aLaDate('SO12', null, false, aujourdhui: jour).montant);
      expect(m.versions.where((x) => x['code'] == 'SO12').length, 2, reason: 'RG-14 : une version refusée reste à l\'historique');
    });

    test('une proposition « à dater » : la décision fixe la date (L01 : grille imprimée en version 2)', () {
      final m = monde();
      final ad = ((v['moteur'] as Map)['aDater'] as Map).cast<String, Object?>();
      final att = {for (final c in liste((v['moteur'] as Map)['cas'])) '${c['nom']}': c};
      final id = '${ad['id']}';
      expect(m.versions.where((x) => x['id'] == id).length, 1);
      expect(m.h.aLaDate('${ad['code']}', null, false, aujourdhui: jour).toJson(), ad['avant']);
      egalRefus(m.decider('admin', id, 'oui').refus, att['Oui sans date d’effet à une proposition à dater']!, 'sans date');
      egalRefus(m.decider('admin', id, 'oui', date: plus(jour, -1)).refus, att['Oui avec une date passée']!, 'date passée');
      final ok = m.decider('admin', id, 'oui', date: plus(jour, 5));
      final ap = (ad['apresOui'] as Map).cast<String, Object?>();
      expect([ok.ok, ok.valeur!.version['dateEffet']], [ap['ok'], ap['dateEffet']]);
      expect(m.h.aLaDate('${ad['code']}', null, false, aujourdhui: jour).toJson(), ap['aujourdhui']);
      expect(m.h.aLaDate('${ad['code']}', plus(jour, 5), false, aujourdhui: jour).toJson(), ap['ledit']);
    });

    test('les droits : la liste de rôles DÉCIDE, jamais « éditer » (mutation (g) du PRD)', () {
      final m = monde();
      final dr = ((v['moteur'] as Map)['droits'] as Map).cast<String, Object?>();
      dr.forEach((role, x) {
        final att = (x as Map).cast<String, Object?>();
        expect(tarPeutDecider(role), att['decider'], reason: '$role décide');
        expect(matrice.peutEditer(role, 'cfg-tarifs'), att['proposer'], reason: '$role propose (fiches RBAC lues de rbac.json)');
        if (att['decider'] != true) {
          expect(m.decider(role, 'X@x@1', 'oui').refus!.code, att['refusDecision'], reason: role);
        }
      });
      // Un profil qui ÉDITE sans décider (droit accordé à la main) ne décide toujours pas.
      final r = tarDecider(m.cx('comptable', editer: true), 'X@x@1', 'oui');
      expect(r.refus!.code, 'VALIDATION_RESERVEE');
      // Un fileul ne décide pas, quel que soit son rôle : la mère seule écrit (T11 : la DAF EST la mère).
      final f = tarDecider(m.cx('da', fileul: true), 'X@x@1', 'oui');
      expect(f.refus!.code, 'CONFIGURATION_DE_LA_MERE');
      expect(f.refus!.geste, contains('poste principal'));
    });

    test('la projection de compatibilité : actes, analyses et grille portent le prix en vigueur (parité 0 écart)', () {
      final m = monde();
      final pr = ((v['moteur'] as Map)['projection'] as Map).cast<String, Object?>();
      final acte = (pr['actes'] as List).first as List;
      final docActe = {'id': 'ACT1', 'code': acte[0], 'prix': acte[1], 'prixNonAssure': acte[2], 'prixAssure': acte[3], 'nonCouvert': false, 'assurable': true, 'codeTarif': 'SIV'};
      final cat = (pr['catalogue'] as List).first as List;
      final docCat = {'id': 'TAR1', 'code': cat[0], 'prixNonAssure': cat[1], 'prixAssure': cat[2], 'nonCouvert': false, 'prixAValider': false, 'assurable': true};
      expect(tarProjection(m.h, jour, actes: [docActe], analyses: const [], catalogue: [docCat]), isEmpty);
      // Un écart est un correctif NOMMÉ : seuls les champs de prix sont touchés.
      final faux = {...docActe, 'prix': 1};
      final c = tarProjection(m.h, jour, actes: [faux], analyses: const [], catalogue: const []);
      expect(c.length, 1);
      expect([c.first.collection, c.first.id, c.first.patch], ['actes', 'ACT1', {'prix': 1200}]);
    });
  });

  group('le circuit complet (lot T3) : contrôle d\'usage, date passée, Valider en un geste, Oui à tout, pro-forma', () {
    final circuit = (v['circuit'] as Map).cast<String, Object?>();
    final att = {for (final c in liste(circuit['cas'])) '${c['nom']}': c};

    Monde mondeCircuit() {
      final m = monde();
      // Prestations synthétiques : les prix qui se LISENT dans les vecteurs (MG02 8 000, MG04 30 000, CH03 150 000, SO17 7 000) ; les autres sont sans effet sur le relevé.
      for (final c in {'MG02': 8000, 'MG03': 10000, 'MG04': 30000, 'CH01': 10000, 'CH02': 10000, 'CH03': 150000, 'CH04': 10000, 'CH05': 10000, 'CH06': 10000, 'SO17': 7000}.entries) {
        m.tarifs.add(prestation(c.key, c.value));
        m.versions.add(version1(c.key, c.value));
      }
      return m;
    }

    DemandeProposition prop(String code, Object? na, {String? date, bool passee = false, bool valider = false, String etat = 'unique'}) =>
        DemandeProposition(code: code, prixNonAssure: na, etatAssure: etat, dateEffet: date, motif: 'Vecteur T3', datePassee: passee, valider: valider);

    test('contrôle d\'usage : une pièce du jour, rejoué au Oui, deux changements, la pièce du jour ferme la date (mutation (a) du PRD)', () {
      final m = mondeCircuit();
      m.piece('FP-2026-00123', 'MG01', '${jour}T09:00:00');
      final a1 = m.proposer('da', prop('MG01', m.na('MG01') + 100, date: jour));
      egalRefus(a1.refus, att['usage : une pièce du jour porte la prestation']!, 'pièce du jour');
      expect(a1.refus!.nbPieces, att['usage : une pièce du jour porte la prestation']!['nbPieces']);
      expect(a1.refus!.motif, contains('FP-2026-00123'));
      final a2 = m.proposer('da', prop('MG01', m.na('MG01') + 100, date: plus(jour, 1)));
      expect(a2.ok, isTrue, reason: att['usage : le même changement à effet de demain']!['ok'].toString());
      m.piece('FP-2026-00124', 'MG01', '${plus(jour, 1)}T10:00:00');
      final a3 = m.decider('da', a2.valeur!.version['id'] as String, 'oui');
      egalRefus(a3.refus, att['usage : rejoué au Oui (pièce émise pendant l’attente)']!, 'rejoué au Oui');
      expect(m.versions.firstWhere((x) => x['id'] == a2.valeur!.version['id'])['statut'], 'propose');
      final non = m.decider('da', a2.valeur!.version['id'] as String, 'non', motif: 'Vecteur : une pièce de demain');
      expect(non.ok, isTrue);
      expect(m.versions.where((x) => x['code'] == 'MG01').length, att['Non avec motif (aucune version nouvelle)']!['versions']);
      // Deux changements le même jour.
      final b0 = m.na('MG02').toInt();
      final b1 = m.proposer('da', prop('MG02', b0 + 100, date: plus(jour, 2)));
      egalRefus(m.proposer('da', prop('MG02', b0 + 150, date: plus(jour, 2))).refus, att['deux changements : un seul en attente']!, 'un seul en attente');
      expect(m.decider('da', b1.valeur!.version['id'] as String, 'oui').ok, isTrue);
      final b3 = m.proposer('da', prop('MG02', b0 + 200, date: plus(jour, 2)));
      expect(b3.ok, isTrue);
      expect(m.decider('da', b3.valeur!.version['id'] as String, 'oui').ok, isTrue);
      final mj = (circuit['memeJour'] as Map).cast<String, Object?>();
      expect(m.na('MG02', plus(jour, 2)), mj['vigueur']);
      expect([for (final x in m.h.versionsDe('MG02')) '${x['version']}:${x['statut']}'], mj['versions'], reason: 'les deux restent lisibles, la plus grande version l\'emporte');
      m.piece('FP-2026-00125', 'MG02', '${plus(jour, 2)}T10:00:00');
      egalRefus(m.proposer('da', prop('MG02', b0 + 300, date: plus(jour, 2))).refus, att['deux changements : la pièce du jour ferme la date']!, 'la pièce du jour ferme la date');
    });

    test('date passée : permise à la DAF et à la Direction avec la case et le motif, refusée aux autres (T6)', () {
      final m = mondeCircuit();
      // Le tirage croisait trois pièces du jeu de démonstration (13/08 et deux autres depuis) : trois pièces synthétiques de même effet.
      m.piece('FP-2026-00126', 'MG03', '2026-08-13T10:00:00');
      m.piece('FP-2026-00200', 'MG03', '2026-08-14T10:00:00');
      m.piece('FP-2026-00201', 'MG03', '2026-08-15T10:00:00');
      egalRefus(m.proposer('da', prop('MG03', m.na('MG03') + 100, date: plus(jour, -5), passee: true)).refus, att['date passée déjà utilisée (DAF, case cochée)']!, 'passée utilisée');
      egalRefus(m.proposer('da', prop('MG04', m.na('MG04') + 100, date: plus(jour, -1))).refus, att['date passée sans la case (DAF)']!, 'sans la case DAF');
      final pa = m.proposer('da', prop('MG04', m.na('MG04') + 100, date: plus(jour, -1), passee: true));
      expect([pa.ok, pa.valeur!.version['datePassee']], [true, att['date passée avec la case (DAF)']!['marquee']]);
      egalRefus(m.proposer('admin', prop('CH01', m.na('CH01') + 100, date: plus(jour, -1))).refus, att['date passée sans la case (administrateur)']!, 'sans la case admin');
      egalRefus(m.proposer('admin', prop('CH01', m.na('CH01') + 100, date: plus(jour, -1), passee: true)).refus, att['date passée avec la case (administrateur)']!, 'avec la case admin');
      final id = pa.valeur!.version['id'] as String;
      egalRefus(m.decider('admin', id, 'oui').refus, att['décision d’une date passée par l’administrateur']!, 'décision admin');
      final d = m.decider('direction', id, 'oui');
      expect(d.ok, isTrue);
      final x = att['décision d’une date passée par la Direction']!;
      expect(m.na('MG04', plus(jour, -1)), x['prixHier']);
      expect(m.na('MG04', plus(jour, -2)), x['prixAvantHier']);
    });

    test('cas limites : zéro, vide, identique, tiret de la colonne assurée', () {
      final m = mondeCircuit();
      egalRefus(m.proposer('da', prop('CH02', 0, date: plus(jour, 1))).refus, att['prix zéro']!, 'zéro');
      egalRefus(m.proposer('da', prop('CH02', '', date: plus(jour, 1))).refus, att['prix vide']!, 'vide');
      egalRefus(m.proposer('da', const DemandeProposition(code: 'CH02')).refus, att['proposition vide']!, 'proposition vide');
      egalRefus(m.proposer('da', prop('CH02', m.na('CH02'), date: plus(jour, 1))).refus, att['ligne identique']!, 'identique');
      final d4 = m.proposer('da',
          DemandeProposition(code: 'CH02', prixNonAssure: m.na('CH02') + 10, etatAssure: 'manquant', dateEffet: plus(jour, 1), motif: 'Vecteur : tiret assuré'));
      expect([d4.ok, d4.valeur!.version['etatAssure']], [true, att['tiret de la colonne assurée']!['etatAssure']]);
      // Un tiret n'est ni un zéro ni une exclusion : la proposition se décide (le prix non assuré est chiffré), la colonne assurée ne se facture pas.
      expect(m.decider('da', d4.valeur!.version['id'] as String, 'non', motif: 'Vecteur : libère la ligne').ok, isTrue);
    });

    test('« Valider » en un geste : née valide avec le rôle de l\'auteur ; un profil qui édite sans décider est refusé', () {
      final m = mondeCircuit();
      final v0 = m.na('CH03');
      final vg = m.proposer('da', prop('CH03', v0 + 250, date: jour, valider: true));
      final x = att['valider en un geste (DAF)']!;
      expect([vg.ok, vg.valeur!.version['statut'], vg.valeur!.version['roleDecision']], [true, x['statut'], x['roleDecision']]);
      expect(vg.valeur!.valideeEnUnGeste, isTrue);
      expect(vg.valeur!.journalAction, 'validation en un geste');
      expect(m.na('CH03'), x['prixApres']);
      expect(m.na('CH03'), x['prixAttendu']);
      egalRefus(m.proposer('comptable', prop('CH04', m.na('CH04') + 100, date: jour, valider: true), editer: true).refus, att['valider par un profil qui édite sans décider']!, 'valider sans décider');
      final pe = m.proposer('comptable', prop('CH04', m.na('CH04') + 100, date: jour), editer: true);
      expect([pe.ok, pe.valeur!.version['proposeRole']], [true, att['proposer par un profil qui édite sans décider']!['proposeRole']]);
      expect(pe.valeur!.version['id'], circuit['idEditeur']);
      // Un fileul ne valide pas en un geste : la mère seule écrit (DAF = la mère, T11).
      final f = m.proposer('da', prop('CH05', m.na('CH05') + 100, date: jour, valider: true), editer: true);
      expect(f.ok, isTrue);
      final fileul = tarProposer(m.cx('da', fileul: true), prop('CH05', m.na('CH05') + 200, date: plus(jour, 3), valider: true));
      expect(fileul.refus!.code, 'CONFIGURATION_DE_LA_MERE');
      // Le retour à l'auteur : le comptable apprend le refus de sa proposition, avec le motif.
      final non = m.decider('da', pe.valeur!.version['id'] as String, 'non', motif: 'Prix hors grille de la clinique', nom: 'Vecteur DAF');
      final n = non.valeur!.notification!;
      expect([n['poste'], n['type'], n['priorite'], n['libelle']], ['comptable', 'prix_decide', 'haute', 'Votre changement de prix CH04 a été refusé']);
      expect(n['detail'], 'Motif : Prix hors grille de la clinique. Décidé par Vecteur DAF.');
    });

    test('« Oui à tout » : jamais sans la comparaison ni sans le droit, chaque ligne passe par la décision ordinaire', () {
      final m = mondeCircuit();
      final o = (circuit['ouiATout'] as Map).cast<String, Object?>();
      ResultatTarif<DecisionEnBloc> tous(String role, {required bool comparaison, List<String>? ids}) =>
          tarDeciderTous(() => m.cx(role), comparaisonAffichee: comparaison, appliquer: m.appliquer, ids: ids);
      expect(tous('da', comparaison: false, ids: const []).refus!.code, o['sansComparaison']);
      expect(tous('caissier', comparaison: true, ids: const []).refus!.code, o['sansDroit']);
      final t1 = m.proposer('da', prop('CH05', m.na('CH05') + 100, date: plus(jour, 1)));
      final t2 = m.proposer('da', prop('CH06', m.na('CH06') + 100, date: plus(jour, 1)));
      m.piece('FP-2026-00300', 'CH06', '${plus(jour, 1)}T10:00:00');
      final r = tous('da', comparaison: true, ids: [t1.valeur!.version['id'] as String, t2.valeur!.version['id'] as String]).valeur!;
      final att2 = (o['resultat'] as Map).cast<String, Object?>();
      expect([for (final x in r.acceptees) x['code']], att2['acceptees']);
      expect([for (final x in r.refusees) '${x['code']}:${x['refus']}'], att2['refusees']);
      expect(r.exclues.length, att2['exclues']);
      // Au-delà du seuil de variation signalée, une ligne n'est jamais acceptée en bloc.
      final t3 = m.proposer('da', prop('CH01', m.na('CH01') * 2, date: plus(jour, 1)));
      final s = tarDeciderTous(() => m.cx('da'), comparaisonAffichee: true, appliquer: m.appliquer, ids: [t3.valeur!.version['id'] as String], seuil: 50).valeur!;
      expect(s.exclues.length, 1);
      expect(s.exclues.first['variation'], 100.0);
      expect(m.versions.firstWhere((x) => x['id'] == t3.valeur!.version['id'])['statut'], 'propose');
    });

    test('la pro-forma à la conversion : prix de la pro-forma tenu dans la durée de validité, prix du jour au-delà', () {
      final m = mondeCircuit();
      final pf = (circuit['proforma'] as Map).cast<String, Object?>();
      expect(tarValiditeProformaJours(null), pf['defaut']);
      expect(tarValiditeProformaDefaut, pf['propose']);
      final P = m.na('SO17');
      F mk(int n, String num) => {
            'id': 'PF$num',
            'numero': 'PRO-2026-8$num',
            'date': '${plus(jour, -n)}T09:00:00',
            'proforma': true,
            'statut': 'actif',
            'lignes': [
              {'id': 'L001', 'categorie': 'acte', 'designation': 'Vecteur : estimation', 'quantite': 1, 'prixUnitaire': P, 'montant': P, 'acteCode': 'SO17'}
            ]
          };
      final pa = mk(10, '0001'), pb = mk(40, '0002');
      expect(m.proposer('da', prop('SO17', P + 300, date: jour, valider: true)).ok, isTrue);
      Map<String, Object?> ec(F f, int validite) {
        final r = tarEcartProforma(f, referentiel: m.h, pieces: m.cx('da').pieces, aujourdhui: jour, validiteJours: validite, assureA: (_) => false);
        final e = r.valeur!;
        final l = (e['lignes'] as List).first as Map;
        return {'regle': e['regle'], 'age': e['ageJours'], 'validite': e['validiteJours'], 'ancien': l['ancien'], 'nouveau': l['nouveau'], 'retenu': l['retenu'], 'ecart': e['ecartTotal']};
      }

      expect(ec(pa, 30), pf['dixJours']);
      expect(ec(pb, 30), pf['quaranteJours']);
      final regle = tarDefinirValiditeProforma(m.cx('da'), 5, reglageActuel: null);
      expect([regle.ok, regle.valeur!.jours, regle.valeur!.avant], [(pf['regle'] as Map)['ok'], (pf['regle'] as Map)['jours'], (pf['regle'] as Map)['avant']]);
      expect(ec(pa, regle.valeur!.jours), pf['dixJoursApres']);
      expect([for (final j in ['abc', '', '2.5', '-1', '400']) tarDefinirValiditeProforma(m.cx('da'), j, reglageActuel: null).refus!.code], pf['invalides']);
      expect(tarDefinirValiditeProforma(m.cx('caissier'), 99, reglageActuel: null).refus!.code, pf['reserve']);
      final vente = {...pa, 'proforma': false};
      expect(tarEcartProforma(vente, referentiel: m.h, pieces: const PiecesTarif(), aujourdhui: jour, validiteJours: 30, assureA: (_) => false).refus!.code, pf['venteNonProforma']);
      // Une durée illisible en base retombe sur le défaut : jamais une valeur inventée.
      expect(tarValiditeProformaJours('abc'), tarValiditeProformaDefaut);
      expect(tarValiditeProformaJours(400), tarValiditeProformaDefaut);
      expect(tarValiditeProformaJours(0), 0);
    });

    test('un retrait : l\'auteur, ou un profil qui décide ; une version décidée ne se retire pas', () {
      final m = mondeCircuit();
      final p = m.proposer('comptable', prop('CH02', m.na('CH02') + 10, date: plus(jour, 1)), editer: true, nom: 'Aude').valeur!;
      final id = p.version['id'] as String;
      expect(tarRetirer(m.cx('comptable', nom: 'Autre', editer: true), id, 'x').refus!.code, 'RETRAIT_RESERVE');
      final r = tarRetirer(m.cx('comptable', nom: 'Aude', editer: true), id, null);
      expect(r.ok, isTrue);
      expect(r.valeur!.patch['statut'], 'retire');
      expect(r.valeur!.patch['motifDecision'], 'Retirée par son auteur');
      m.appliquer(r.valeur!);
      expect(tarRetirer(m.cx('da'), id, 'x').refus!.code, 'DEJA_DECIDEE');
    });
  });

  group('la migration des listes d\'avant', () {
    test('MIGRATION RÉELLE : les listes d\'avant du jeu du poste redonnent EXACTEMENT les 201 prestations et 240 versions que la maquette sème', () {
      List<F> jeu(String n) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$n.json').readAsStringSync()));
      final ref = (jsonDecode(File('../../apps/poste/assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>();
      final mg = tarMigrer(actes: jeu('actes'), grille: jeu('catalogueTarifs'), analyses: liste(ref['analyses']));
      final t = jeu('tarifs'), vs = jeu('versionsTarif');
      expect([mg.tarifs.length, mg.versions.length], [201, 240]);
      expect([for (final x in mg.tarifs) jsonEncode(x)], [for (final x in t) jsonEncode(x)]);
      expect([for (final x in mg.versions) jsonEncode(x)], [for (final x in vs) jsonEncode(x)]);
      // Les chiffres que les vecteurs relèvent de l\'écran : 201 versions 1, 39 propositions de la grille des analyses (à dater), 0 écart de parité de projection.
      final mig = (v['migration'] as Map).cast<String, Object?>();
      expect(mg.versions.where((x) => x['version'] == 1).length, mig['versions1']);
      expect(mg.versions.where((x) => x['origine'] == 'semence-grille').length, mig['propositionsGrille']);
      expect({for (final x in mg.tarifs) '${x['famille']}': mg.tarifs.where((y) => y['famille'] == x['famille']).length}, mig['parFamille']);
      final h = ReferentielTarifs(mg.tarifs, mg.versions);
      final projection = tarProjection(h, '2026-10-30', actes: jeu('actes'), analyses: jeu('analyses'), catalogue: jeu('catalogueTarifs'));
      // Les 73 actes et les 48 analyses portent déjà le prix en vigueur ; seules les 39 lignes LABO de la grille imprimée, fusionnées avec leur analyse, portent encore le prix
      // IMPRIMÉ (la maquette ne les projette qu'à l'ouverture d'un écran) : le poste les projette au démarrage, sans ligne de journal.
      expect({for (final c in projection) c.collection}, {'catalogueTarifs'});
      expect(projection.length, 39);
      final ecarts = (v['ecarts'] as Map).cast<String, Object?>();
      expect([for (final e in mg.ecarts.where((e) => e['type'] == 'analyse-sans-grille')) e['code']]..sort(), ecarts['analysesSansGrille']);
      expect([for (final e in mg.ecarts.where((e) => e['type'] == 'grille-sans-analyse')) e['code']], ecarts['grilleSansAnalyse']);
    });

    test('le prix facturé aujourd\'hui est la version 1 ; la grille imprimée des analyses arrive en version 2 PROPOSÉE', () {
      final actes = [
        {'id': 'ACT1', 'code': 'SO02', 'libelle': 'Soins intraveineux (SIV)', 'secteur': 'Soins', 'prix': 1200, 'prixNonAssure': 1200, 'prixAssure': 800, 'assurable': true, 'codeTarif': 'SIV'},
        {'id': 'ACT2', 'code': 'HO01', 'libelle': 'Journée', 'prix': 5000},
      ];
      final grille = [
        {'code': 'SIV', 'libelle': 'Soin, injection intraveineuse', 'famille': 'AMI', 'prixNonAssure': 1200, 'prixAssure': 800, 'assurable': true},
        {'code': 'LAB-AKOP', 'libelle': 'AKOP (grille imprimée)', 'famille': 'LABO', 'prixNonAssure': 1500, 'prixAssure': 2500, 'assurable': true},
      ];
      final analyses = [
        {'code': 'L01', 'designation': 'AKOP', 'prix': 2000, 'tarifProvisoire': true},
        {'code': 'L99', 'designation': 'Sans ligne', 'prix': 3000},
      ];
      final mg = tarMigrer(actes: actes, grille: grille, analyses: analyses);
      expect(mg.tarifs.map((t) => t['code']), ['SO02', 'HO01', 'L01', 'L99']);
      final siv = mg.tarifs.first;
      expect([siv['codeGrille'], siv['codesAlias'], siv['libelleGrille']], ['SIV', ['SIV'], 'Soin, injection intraveineuse']);
      expect(mg.tarifs[1]['famille'], 'HOSPITALISATION');
      // L01 : le prix facturé reste la version 1 ; la ligne de grille (LAB-AKOP, libellé normalisé identique) devient alias, prix en version 2 proposée à dater.
      final v1 = mg.versions.firstWhere((x) => x['id'] == 'L01@origine@1');
      expect([v1['prixNonAssure'], v1['statut'], v1['provisoire']], [2000, 'valide', true]);
      final v2 = mg.versions.firstWhere((x) => x['id'] == 'L01@a-dater@2');
      expect([v2['statut'], v2['aDater'], v2['prixNonAssure'], v2['origine']], ['propose', true, 1500, 'semence-grille']);
      expect(mg.versions.where((x) => x['code'] == 'L99').length, 1);
      expect(mg.ecarts.map((e) => e['type']), ['analyse-grille', 'analyse-sans-grille']);
      // Un état « prix unique » n'est jamais un tiret : l'acte sans grille garde sa colonne assurée égale à la colonne non assurée.
      final h = ReferentielTarifs(mg.tarifs, mg.versions);
      expect(h.aLaDate('HO01', null, true, aujourdhui: jour).montant, 5000);
      expect(h.aLaDate('SIV', null, true, aujourdhui: jour).montant, 800);
      expect(h.aLaDate('L01', null, false, aujourdhui: jour).montant, 2000, reason: 'la version 2 est proposée : elle ne change rien');
    });
  });
}
