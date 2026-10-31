// Rejoue les vecteurs du MOTEUR D'EXERCICE de M12 (m12-cloture, m12-ouverture) tirés de `SIGH.exercice` et des écrans réels de la maquette
// (prototype_html/build/vecteurs-m12-exercice.js). Le jeu est celui du poste (apps/poste/assets/donnees/jeu), l'horloge celle du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
F carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Les champs qui ne dépendent ni d'un identifiant tiré au hasard ni de l'horloge d'écriture.
String _v(Object? x) => x is num && x == x.truncate() ? '${x.toInt()}' : '${x ?? ''}';
String cle(F e) => [for (final k in ['numero', 'date', 'journal', 'compte', 'compteLibelle', 'debit', 'credit', 'libelle', 'statut', 'origine', 'origineCloture', 'pieceOrigine']) _v(e[k])].join('|');

void main() {
  final f = File('test/vecteurs/exercice.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-m12-exercice.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final auj = DateTime(2026, 10, 30, 10);
  final ecr = jeu('ecritures');
  final exo = jeu('exercices');
  List<F> valides(List<F> l) => [for (final x in l) {...x, if (x['statut'] == 'brouillon') 'statut': 'validee'}];
  List<F> actives(List<F> l) => [for (final x in l) if (x['statut'] != 'archive') x];

  group('SHA-256 : la maquette et le poste calculent la même empreinte', () {
    test('quatre entrées, accents et longueur comprises', () {
      final s = carte(v['sha']);
      expect(cpcSha256('abc'), s['abc']);
      expect(cpcSha256(''), s['vide']);
      expect(cpcSha256('Résultat net — 12 345,6 €'), s['accents']);
      expect(cpcSha256('a' * 1000), s['long']);
    });
  });

  group('exercices : amorçage, liste, états', () {
    test('l\'amorçage dérive une fiche par année du journal, de l\'horloge et de la liasse (2024-2025 closes d\'office)', () {
      final a = cpcExercicesAAmorcer([], ecr, auj).reversed.toList(); // la maquette insère EN TÊTE
      final att = liste(carte(v['amorcage'])['exercices']);
      expect(a.length, att.length);
      for (var i = 0; i < a.length; i++) {
        for (final k in ['id', 'annee', 'debut', 'fin', 'statut', 'etat', 'source', 'valideLe', 'validePar', 'motif']) {
          expect(a[i][k], att[i][k], reason: '${att[i]['id']}.$k');
        }
      }
    });
    test('une année déjà portée par une fiche n\'est pas recréée ; une fiche ARCHIVÉE non plus', () {
      expect(cpcExercicesAAmorcer(exo, ecr, auj), isEmpty);
      final arch = [for (final x in exo) {...x, if (x['annee'] == 2026) 'statut': 'archive'}];
      expect(cpcExercicesAAmorcer(arch, ecr, auj), isEmpty);
    });
    test('la liste est du plus récent au plus ancien et ignore les archivés', () {
      final att = liste(v['liste']);
      expect([for (final x in cpcListeExercices(exo)) x['annee']], [for (final x in att) x['annee']]);
      expect(cpcListeExercices([for (final x in exo) {...x, if (x['annee'] == 2025) 'statut': 'archive'}]).map((x) => x['annee']), [2026, 2024]);
    });
    test('l\'état de chaque année est celui de la maquette ; une fiche archivée ne ferme rien (RG-14)', () {
      final e = carte(v['etats']);
      for (final k in e.keys) {
        expect(cpcEtatExercice(exo, int.parse(k)), e[k], reason: k);
        expect(cpcEtatExercice([], int.parse(k)), e[k], reason: '$k sans fiche : ce que l\'amorçage donnerait');
      }
      expect(cpcEtatExercice([for (final x in exo) {...x, if (x['annee'] == 2025) 'statut': 'archive'}], 2025), 'ouvert');
    });
  });

  group('la garde de lecture seule, posée sur la collection', () {
    test('les refus ont le motif de la maquette ; 2026 et une date absente passent', () {
      final g = carte(v['garde']);
      String? motif(String d) => cpcGardeEcritures(exo, d);
      expect(motif('2025-03-01'), (carte(g['inserer-2025'])['toast'] as List).first);
      expect(motif('2024-12-31'), (carte(g['inserer-2024'])['toast'] as List).first);
      expect(motif('2025-06-01'), (carte(g['modifier-date-vers-2025'])['toast'] as List).first);
      expect(motif('2026-03-01'), isNull);
      expect(cpcGardeEcritures(exo, null), isNull);
      expect(cpcGardeEcritures(exo, ''), isNull);
    });
    test('un exercice clos AU POSTE (deux gestes) refuse à son tour, avec la date de la validation', () {
      final clos = [for (final x in exo) if (x['annee'] == 2026) {...x, 'etat': 'clos', 'valideLe': '2026-10-30T10:00:00.407Z'} else x];
      expect(cpcGardeEcritures(clos, '2026-07-01'), (carte(carte(v['cloture'])['ecritureApresCloture'])['toast'] as List).first);
    });
  });

  group('pré-clôture : six contrôles nommés', () {
    void verifie(String nom, List<F> lignes, int annee) {
      final att = carte(carte(v['preCloture'])[nom]);
      final p = cpcPreCloture(lignes, annee);
      expect([for (final c in p.controles) [c.id, c.bloquant, c.ok, c.libelle, c.ecran, c.detail]],
          [for (final c in liste(att['controles'])) [c['id'], c['bloquant'], c['ok'], c['libelle'], c['ecran'], c['detail']]],
          reason: nom);
      expect(p.bloquants.length, att['nbBloquants'], reason: nom);
      expect(p.resultat, closeTo(att['resultat'] as num, 0.001), reason: nom);
      expect(p.nbEcritures, att['nbEcritures'], reason: nom);
    }

    test('le jeu 2026 : 92 brouillons BLOQUENT, le résultat provisoire est calculé sur les validées', () {
      verifie('jeu2026', actives(ecr), 2026);
      expect(cpcPreCloture(actives(ecr), 2026).bloquants.map((c) => c.id), ['brouillons']);
    });
    test('2025 : aucune écriture, donc le contrôle « écritures » bloque', () => verifie('jeu2025', actives(ecr), 2025));
    test('brouillons validés : plus aucun blocage', () {
      verifie('valide2026', valides(actives(ecr)), 2026);
    });
    test('une ligne validée sans contrepartie : journal ET pièce déséquilibrés (RG-10)', () {
      final l = [
        {'id': 'X-DESEQ', 'numero': 'ODX', 'date': '2026-05-05', 'journal': 'OD', 'compte': '661100', 'debit': 5000, 'credit': 0, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('desequilibre2026', l, 2026);
    });
    test('un à-nouveau déjà écrit sur N+1 BLOQUE : la clôture écrit les définitifs', () {
      final l = [
        {'id': 'X-AN', 'numero': 'AN-2027-00001', 'date': '2027-01-01', 'journal': 'AN', 'compte': '571000', 'debit': 100, 'credit': 0, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('anExistant2026', l, 2026);
    });
    test('un compte d\'attente non soldé INFORME sans bloquer', () {
      final l = [
        {'id': 'X-47A', 'numero': 'OD47', 'date': '2026-05-05', 'journal': 'OD', 'compte': '471000', 'debit': 7000, 'credit': 0, 'statut': 'validee'},
        {'id': 'X-47B', 'numero': 'OD47', 'date': '2026-05-05', 'journal': 'OD', 'compte': '571000', 'debit': 0, 'credit': 7000, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('compte47', l, 2026);
      expect(cpcPreCloture(l, 2026).bloquants, isEmpty);
    });
  });

  group('lectures d\'un exercice : soldes, résultat, à-nouveaux provisoires', () {
    final e26 = cpcEcrituresDe(valides(actives(ecr)), 2026);
    test('les écritures de l\'exercice : validées seulement par défaut', () {
      final n = carte(v['nbEcrituresBrut']);
      expect(cpcEcrituresDe(actives(ecr), 2026).length, n['validees'], reason: 'le jeu brut : 410 validées');
      expect(cpcEcrituresDe(actives(ecr), 2026, brouillons: true).length, n['avecBrouillons']);
      expect(n['validees'] != n['avecBrouillons'], true, reason: 'les brouillons ne sont pas des faits comptables');
      expect(cpcEcrituresDe(valides(actives(ecr)), 2026).length, carte(v['nbEcritures2026'])['validees']);
    });
    test('le résultat suit les classes 6, 7 et 8', () {
      expect(cpcResultatDe(cpcEcrituresDe(actives(ecr), 2026)), closeTo(carte(v['nbEcrituresBrut'])['resultat'] as num, 0.001));
      expect(cpcResultatDe(cpcEcrituresDe(valides(actives(ecr)), 2026)), closeTo(v['resultat2026'] as num, 0.001));
    });
    test('les soldes par compte, triés comme Object.keys().sort()', () {
      final att = liste(v['soldes2026']);
      final s = cpcSoldesParCompte(cpcEcrituresDe(valides(actives(ecr)), 2026));
      expect(s.length, att.length);
      for (var i = 0; i < s.length; i++) {
        expect([s[i]['compte'], s[i]['libelle'], s[i]['debit'], s[i]['credit'], s[i]['solde']], [att[i]['compte'], att[i]['libelle'], att[i]['debit'], att[i]['credit'], att[i]['solde']]);
      }
      expect(e26.isNotEmpty, true);
    });
    test('les à-nouveaux provisoires de 2027 sont calculés, jamais stockés ; 2026 n\'en a pas (2025 vient de la liasse)', () {
      final p = cpcANouveauxProvisoires(exo, valides(actives(ecr)), 2027);
      final att = liste(v['provisoires2027']);
      expect(p.length, att.length);
      for (var i = 0; i < p.length; i++) {
        expect([p[i]['compte'], p[i]['compteLibelle'], p[i]['debit'], p[i]['credit'], p[i]['lettrable'], p[i]['id'], p[i]['libelle']],
            [att[i]['compte'], att[i]['compteLibelle'], att[i]['debit'], att[i]['credit'], att[i]['lettrable'], att[i]['id'], att[i]['libelle']],
            reason: '$i');
      }
      expect(cpcANouveauxProvisoires(exo, actives(ecr), 2026), isEmpty);
      expect(liste(v['provisoires2026']), isEmpty);
    });
    test('un exercice précédent CLOS ne donne plus de provisoires (les définitifs existent)', () {
      final clos = [for (final x in exo) if (x['annee'] == 2026) {...x, 'etat': 'clos'} else x];
      expect(cpcANouveauxProvisoires(clos, actives(ecr), 2027), isEmpty);
    });
  });

  group('lettrage des tiers', () {
    final l = <F>[
      for (final x in [
        ['L1', '411100', 5000, 0],
        ['L2', '411100', 0, 5000],
        ['L3', '411100', 0, 3000],
        ['L4', '421000', 100, 0],
        ['L5', '411200', 0, 5000]
      ])
        {'id': x[0], 'numero': 'LT-${x[0]}', 'date': '2026-06-01', 'journal': 'OD', 'compte': x[1], 'debit': x[2], 'credit': x[3], 'statut': 'validee'}
    ];
    final r = carte(v['lettrage']);
    test('les refus sont nommés, comme à l\'écran', () {
      expect(cpcLettrer(l, '571000', ['L1', 'L2']).motif, carte(r['nonLettrable'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1']).motif, carte(r['uneLigne'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'L5']).motif, carte(r['autreCompte'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'L3']).motif, carte(r['nonNul'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'ZZZ']).motif, carte(r['inconnue'])['motif']);
    });
    test('un ensemble qui s\'annule se lettre ; le code suit le nombre de codes DISTINCTS déjà posés', () {
      final ok = cpcLettrer(l, '411100', ['L1', 'L2']);
      expect([ok.ok, ok.code, ok.ids], [true, carte(r['valide'])['code'], ['L1', 'L2']]);
      final posees = [for (final x in l) if (x['id'] == 'L1' || x['id'] == 'L2') {...x, 'lettrage': 'A'} else x];
      expect(cpcLettrer(posees, '411100', ['L1', 'L2']).motif, carte(r['dejaLettree'])['motif']);
      final avecA = [...posees, {'id': 'L8', 'compte': '411100', 'debit': 50, 'credit': 0}, {'id': 'L9', 'compte': '411100', 'debit': 0, 'credit': 50}];
      expect(cpcLettrer(avecA, '411100', ['L8', 'L9']).code, 'B');
      expect(carte(r['second'])['code'], 'B');
    });
    test('dé-lettrer EXIGE un motif et un code existant', () {
      final posees = [for (final x in l) if (x['id'] == 'L1' || x['id'] == 'L2') {...x, 'lettrage': 'A'} else x];
      expect(cpcDelettrer(posees, '411100', 'A', '').motif, carte(r['delettrerSansMotif'])['motif']);
      expect(cpcDelettrer(posees, '411100', 'A', 'ab').motif, carte(r['delettrerCourt'])['motif']);
      expect(cpcDelettrer(posees, '411100', 'Z', 'Erreur de saisie').motif, carte(r['delettrerInconnu'])['motif']);
      final ok = cpcDelettrer(posees, '411100', 'A', 'Erreur de saisie');
      expect([ok.ok, ok.ids.length], [true, carte(r['delettrer'])['lignes']]);
    });
  });

  group('la clôture en DEUX gestes', () {
    final c = carte(v['cloture']);
    final base = valides(actives(ecr));
    String motif(F x) => '${x['motif']}';
    test('geste 1 — refus nommés : exercice inconnu, déjà clos, contrôles bloquants (le brouillon est nommé)', () {
      expect(cpcDemanderCloture(exo, base, 2031, acteur: 'KASSA Augustin', maintenant: auj).motif, motif(carte(c['inconnue'])));
      expect(cpcDemanderCloture(exo, base, 2025, acteur: 'KASSA Augustin', maintenant: auj).motif, motif(carte(c['dejaClos'])));
      final br = [
        {'id': 'X-BR', 'numero': 'BR1', 'date': '2026-04-04', 'journal': 'OD', 'compte': '661100', 'debit': 10, 'credit': 0, 'statut': 'brouillon'},
        ...base
      ];
      expect(cpcDemanderCloture(exo, br, 2026, acteur: 'KASSA Augustin', maintenant: auj).motif, motif(carte(c['refusBrouillon'])));
    });
    test('geste 1 — la demande porte le patch de la maquette ; une seconde demande est refusée', () {
      final d = cpcDemanderCloture(exo, base, 2026, acteur: 'KASSA Augustin', maintenant: auj);
      expect(d.ok, true);
      final patch = carte(liste(carte(carte(c['ecartDemande'])['modifs'])['exercices']).first['patch']);
      expect({...d.patch!}..remove('demandeLe'), {...patch}..remove('demandeLe'));
      final attente = [for (final x in exo) if (x['annee'] == 2026) {...x, ...d.patch!} else x];
      expect(cpcDemanderCloture(attente, base, 2026, acteur: 'KASSA Augustin', maintenant: auj).motif, motif(carte(c['secondeDemande'])));
    });
    final attente = [
      for (final x in exo)
        if (x['annee'] == 2026) {...x, 'etat': 'en_attente_cloture', 'demandePar': 'KASSA Augustin', 'demandeLe': '2026-10-30T10:00:00.319Z'} else x
    ];
    test('geste 2 — refus : la Direction ou la DAF seules valident, avec un motif, et JAMAIS le demandeur', () {
      CpcValidation val(String role, String acteur, String m, {int annee = 2026}) =>
          cpcValiderCloture(attente, base, annee, motif: m, acteur: acteur, role: role, maintenant: auj);
      expect(val('comptable', 'KASSA Augustin', 'Conforme').motif, motif(carte(c['validerMemePersonne'])));
      expect(val('direction', 'KASSA Augustin', 'Conforme').motif, motif(carte(c['validerDemandeur'])));
      expect(val('direction', 'BASSONGUI Chabi Séko', '').motif, motif(carte(c['validerSansMotif'])));
      expect(val('direction', 'BASSONGUI Chabi Séko', 'ok').motif, motif(carte(c['validerMotifCourt'])));
      expect(val('direction', 'BASSONGUI Chabi Séko', 'Conforme', annee: 2030).motif, motif(carte(c['validerInconnue'])));
      expect(cpcValiderCloture(exo, base, 2026, motif: 'Conforme', acteur: 'X Y', role: 'direction', maintenant: auj).ok, false, reason: 'rien en attente');
    });
    test('geste 2 — la validation solde 6/7/8 vers 131/139, écrit les à-nouveaux définitifs et rend l\'EMPREINTE de la maquette', () {
      final r = cpcValiderCloture(attente, base, 2026, motif: '  Exercice 2026 conforme  ', acteur: 'BASSONGUI Chabi Séko', role: 'direction', maintenant: auj);
      expect(r.ok, true);
      final att = carte(c['valider']);
      expect(r.resultat, att['resultat']);
      expect(r.empreinte, att['empreinte'], reason: 'l\'empreinte du journal arrêté se rejoue à l\'identique');
      expect(r.lignesAN.length, att['lignesAN']);
      expect(r.nbArchivees, carte(c['fiche'])['nbEcrituresArchivees']);
      final ins = liste(carte(carte(c['ecartValidation'])['inserts'])['ecritures']);
      final attendues = ins.map(cle).toList()..sort();
      expect([...r.lignesOD, ...r.lignesAN].map(cle).toList()..sort(), attendues);
      // pièce de résultat équilibrée (RG-10) et à-nouveaux équilibrés
      double somme(List<F> l, String k) => l.fold(0.0, (a, x) => a + (x[k] as num));
      expect(somme(r.lignesOD, 'debit'), somme(r.lignesOD, 'credit'));
      expect(somme(r.lignesAN, 'debit'), somme(r.lignesAN, 'credit'));
      expect(r.lignesOD.every((l) => '${l['compte']}'.startsWith('6') || '${l['compte']}'.startsWith('7') || '${l['compte']}'.startsWith('8') || l['compte'] == '131000' || l['compte'] == '139000'), true);
      expect(r.lignesAN.every((l) => '12345'.contains('${l['compte']}'[0])), true, reason: 'seules les classes 1 à 5 se reportent');
      final fiche = carte(c['fiche']);
      expect(r.patch!['motif'], fiche['motif']);
      expect(r.patch!['validePar'], fiche['validePar']);
      expect(r.patch!['anNumero'], fiche['anNumero']);
      expect(r.exerciceSuivant!['id'], carte(c['fiche2027'])['id']);
      expect(r.exerciceSuivant!['etat'], 'ouvert');
    });
  });

  group('bilan d\'ouverture : seules les classes 1 à 5 se reportent', () {
    final o = carte(v['ecranOuverture']);
    final actif = actives(ecr);
    test('les comptes reportés, leurs soldes et le résultat qui équilibre — comme l\'écran', () {
      final s = cpcSoldesDeCloture(actif, 2026);
      final t = carte(liste(carte(o['initial'])['tables']).first);
      final lignes = liste(t['lignes']);
      final res = cpcLignesOuverture(s, 2026);
      expect(res.length, lignes.length);
      for (var i = 0; i < res.length; i++) {
        final cel = (lignes[i]['cellules'] as List).cast<String>();
        final solde = res[i]['solde'] as double;
        expect([res[i]['compte'], res[i]['libelle'], solde > 0 ? nt(money(solde, avecDevise: false)) : '', solde < 0 ? nt(money(-solde, avecDevise: false)) : ''], cel.map(nt).toList());
      }
      expect(s.comptes.length, 8);
      expect(s.equilibre, true);
      expect(nt(money(s.totalDebiteurs)), nt(carte(liste(carte(o['initial'])['kpis'])[1])['valeur']));
      expect(nt(money(s.totalCrediteurs)), nt(carte(liste(carte(o['initial'])['kpis'])[2])['valeur']));
      expect(nt(money(s.resultat)), nt(carte(liste(carte(o['initial'])['kpis'])[3])['valeur']));
    });
    test('le report écrit une pièce en BROUILLON, au journal AN, avec le résultat au compte 131000 (bénéfice) ou 139000 (perte), un seul compte de résultat (E813)', () {
      final s = cpcSoldesDeCloture(actif, 2026);
      final r = cpcReporterANouveaux(s, 2026, dejaEcrits: 0);
      expect(r.ok, true);
      expect(r.numero, 'AN-2027-00001');
      final ins = liste(carte(carte(o['ecart'])['inserts'])['ecritures']);
      expect(r.lignes.map(cle).toList()..sort(), ins.map(cle).toList()..sort());
      expect(r.lignes.every((l) => l['statut'] == 'brouillon' && l['journal'] == 'AN'), true);
      expect(r.lignes.last['compte'], s.resultat >= 0 ? '131000' : '139000');
      expect(cpcCompteResultat(-1), '139000');
      expect(cpcCompteResultat(0), '131000');
    });
    test('REFUSÉ s\'il ne s\'équilibre pas (RG-10), REFUSÉ une seconde fois (double report) — avec les mots de l\'écran', () {
      final deseq = [
        {'id': 'X-DESEQ', 'numero': 'ODX', 'date': '2026-05-05', 'journal': 'OD', 'compte': '571000', 'compteLibelle': 'Caisse', 'debit': 5000, 'credit': 0, 'statut': 'validee'},
        ...actif
      ];
      final s = cpcSoldesDeCloture(deseq, 2026);
      expect(s.equilibre, false);
      final r = cpcReporterANouveaux(s, 2026, dejaEcrits: 0);
      expect(r.ok, false);
      final att = liste(o['deseqRefus']).first;
      expect([r.message, r.detail], [att['message'], att['detail']]);
      final dbl = cpcReporterANouveaux(cpcSoldesDeCloture(actif, 2026), 2026, dejaEcrits: 9);
      expect(dbl.ok, false);
      expect([dbl.message, dbl.detail], [liste(o['secondReport']).first['message'], liste(o['secondReport']).first['detail']]);
    });
  });
}
