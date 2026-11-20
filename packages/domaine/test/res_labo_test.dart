// Rejoue les vecteurs du résultat d'analyse engendrés par la maquette (prototype_html/build/vecteurs-resultats.js) :
// états, habilitations, deux verrous, rectification, plages par lot, écart, règlement, comparatif, statistiques.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) =>
    ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();

/// Compare récursivement ; les clés absentes d'un côté valent `null` de l'autre (JSON : l'indéfini JS n'est pas écrit).
void memes(Object? obtenu, Object? attendu, String chemin, {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k)) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer);
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

SessionLabo session(F s) => SessionLabo(
    role: s['role'] as String?,
    fonction: s['fonction'] as String?,
    secteur: s['secteur'] as String?,
    id: s['id'] as String?,
    nom: s['nom'] as String?);

void main() {
  final f = File('test/vecteurs/resultats.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-resultats.js`');
  }
  final v = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  final maintenant = DateTime(2026, 10, 30, 12);
  final t0 = DateTime.utc(2026, 10, 30, 12);

  group('états du résultat', () {
    final e = (v['etats'] as Map).cast<String, Object?>();
    test('les huit états, leur libellé, leur ton, leur ordre et leur aide', () {
      final att = liste(e['liste']);
      expect(etatsResultat.length, att.length);
      for (var i = 0; i < att.length; i++) {
        expect(etatsResultat[i].id, att[i]['id']);
        expect(etatsResultat[i].label, att[i]['label']);
        expect(etatsResultat[i].tone, att[i]['tone']);
        expect(etatsResultat[i].ordre, att[i]['ordre']);
        expect(etatsResultat[i].aide, att[i]['aide']);
      }
    });
    test('seuls « valide » et « rectifie » sont opposables au prescripteur', () {
      for (final en in (e['rendu'] as Map).entries) {
        expect(resultatRendu(en.key == 'null' ? null : en.key), en.value, reason: en.key);
      }
    });
    test('un état inconnu se nomme lui-même, il ne disparaît pas', () {
      expect(etatResultat('zz_inconnu').label, (e['inconnu'] as Map)['label']);
      expect(etatResultat(null).label, (e['vide'] as Map)['label']);
      expect(etatResultat('zz_inconnu').ordre, 0);
    });
  });

  group('capacités', () {
    test('la table transcrite est celle de la maquette (D.CAPACITES)', () {
      final toutes = (v['toutesCapacites'] as Map).cast<String, Object?>();
      expect(capacitesLabo.keys.toSet(), toutes.keys.toSet());
      for (final en in toutes.entries) {
        final a = (en.value as Map).cast<String, Object?>();
        final c = capacitesLabo[en.key]!;
        expect(c.label, a['label'], reason: en.key);
        expect(c.voirResultats, a['voirResultats'], reason: en.key);
        expect(c.validerTechnique, a['validerTechnique'] ?? false, reason: en.key);
        expect(c.validerBiologique, a['validerBiologique'], reason: en.key);
        expect(c.continuitePrelevement, a['continuitePrelevement'] ?? false, reason: en.key);
        expect(c.secteurs, ((a['secteurs'] as List?) ?? const []).cast<String>(), reason: en.key);
        expect(c.remettreResultats, a['remettreResultats'] ?? false, reason: en.key);
      }
    });
    test('la fonction déduite de chaque rôle du manifeste', () {
      final rf = (v['roleFonction'] as Map).cast<String, Object?>();
      for (final en in rf.entries) {
        expect(capacites(SessionLabo(role: en.key)).fonction, en.value, reason: en.key);
      }
    });
    for (final c in liste(v['capacites'])) {
      test('${c['nom']}', () {
        final r = capacites(session((c['session'] as Map).cast()));
        expect(r.fonction, c['fonction']);
        expect(r.fonctionInconnue, c['fonctionInconnue']);
        expect(r.label, c['label']);
        expect(r.voirResultats, c['voirResultats']);
        expect(r.validerTechnique, c['validerTechnique']);
        expect(r.validerBiologique, c['validerBiologique']);
        expect(r.continuitePrelevement, c['continuitePrelevement']);
      });
    }
  });

  group('visibilité d\'un résultat (RBAC métier)', () {
    final cas = liste(v['visibilite']);
    test('117 combinaisons profil × état × secteur', () => expect(cas.length, 117));
    for (final c in cas) {
      test('${c['session']} / ${c['demande']}', () {
        final r = peutVoirResultat(
            (c['demandeFiche'] as Map).cast(), session((c['sessionFiche'] as Map).cast()));
        expect(r.autorise, c['autorise']);
        expect(r.motif, c['motif']);
        expect(r.enAttenteValidation, c['enAttenteValidation']);
      });
    }
    test('un résultat non validé n\'existe pas pour le prescripteur, même habilité à tout', () {
      final r = peutVoirResultat({'etatAnalyse': 'valide_technique'}, const SessionLabo(fonction: 'medecin'));
      expect(r.autorise, isFalse);
      expect(r.enAttenteValidation, isTrue);
    });
  });

  group('continuité du prélèvement', () {
    for (final c in liste(v['continuite'])) {
      test('${c['nom']}', () {
        final ag = c['agent'];
        final r = continuiteRespectee(c['demande'] == null ? null : (c['demande'] as Map).cast(),
            agentId: ag is Map ? ag['id'] : ag, agentNom: ag is Map ? ag['nomComplet'] : null);
        expect(r.ok, c['ok']);
        expect(r.motif, c['motif']);
        expect(r.preleveur, c['preleveur']);
      });
    }
  });

  group('validations et rectification', () {
    for (final c in liste(v['verrous'])) {
      final nom = '${c['nom']}';
      test(nom, () {
        final entree = c['entree'] == null ? null : {...(c['entree'] as Map).cast<String, Object?>(), 'id': 'D1'};
        final introuvable = nom.contains('introuvable');
        final d = introuvable ? null : entree;
        final s = nom.startsWith('biologique : le TSL')
            ? const SessionLabo(role: 'laborantin', fonction: 'tsl')
            : nom.contains('médecin')
                ? const SessionLabo(role: 'medecin', fonction: 'medecin')
                : const SessionLabo(role: 'laborantin', fonction: 'biologiste');
        final utilisateur = nom.startsWith('biologique : le TSL') ? 'IMOROU Choucouratou' : (nom.contains('seconde') ? 'IMOROU Choucouratou' : 'KINNOU Ganiou');
        GesteResultat appeler() {
          if (nom.startsWith('technique')) {
            return validerTechnique(d, utilisateur: utilisateur, maintenant: t0);
          }
          if (nom.startsWith('biologique')) {
            return validerBiologique(d, session: s, utilisateur: utilisateur, maintenant: t0);
          }
          final nouv = nom.contains('seconde') ? <String, Object?>{'GB': 6.3} : <String, Object?>{'GB': 6.1, 'GR': 4.4, 'HB': 12.5};
          final motif = switch (nom) {
            String n when n.contains('première') => 'Erreur de transcription du GB',
            String n when n.contains('seconde') => 'Second contrôle',
            String n when n.contains('commentaire général non fourni') => 'Contre-expertise',
            String n when n.contains('sans motif') => null,
            _ => 'Erreur',
          };
          return rectifierResultat(d, nouv,
              motif: motif,
              commentaireGeneral: nom.contains('première') ? 'Corrigé' : null,
              utilisateur: utilisateur,
              maintenant: t0);
        }

        if (c['erreur'] != null) {
          expect(() => appeler(), throwsA(isA<RefusResultat>().having((e) => e.motif, 'motif', c['erreur'])));
          return;
        }
        final g = appeler();
        final apres = {...entree!, ...g.patch};
        memes(apres, c['apres'], 'apres', ignorer: {'id', 'valideLe', 'valideTechniqueLe', 'rectifieLe', 'remplaceeLe'});
        expect(g.interim, c['interim'] ?? false);
        expect(g.version, c['version']);
        final nots = liste(c['notifications']);
        if (nots.isEmpty) {
          expect(g.notification, isNull);
        } else {
          memes(g.notification, nots.first, 'notification', ignorer: {'demandeId'});
          expect(g.notification!['demandeId'], 'D1');
        }
      });
    }
    test('la version sortante est conservée AVANT d\'être remplacée, datée', () {
      final g = rectifierResultat({
        'id': 'D', 'etatAnalyse': 'valide', 'version': 1, 'valeurs': {'GB': 5}, 'analyse': 'NFS', 'patient': 'P', 'patientCode': 'C', 'valideLe': '2026-08-11T10:00:00.000Z'
      }, {'GB': 6}, motif: 'm', utilisateur: 'U', maintenant: t0);
      final vs = g.patch['versions'] as List;
      expect(vs.length, 1);
      expect((vs.first as Map)['valeurs'], {'GB': 5});
      expect((vs.first as Map)['remplaceeLe'], '2026-10-30T12:00:00.000Z');
    });
  });

  group('plages par lot et écart à la référence', () {
    final p = (v['plages'] as Map).cast<String, Object?>();
    final variable = (p['variable'] as Map).cast<String, Object?>();
    final actives = [for (final x in liste(p['pose'])) if (x['archive'] != true) {...x, 'id': 'P-${x['lot']}'}];
    test('les cas datés', () {
      for (final c in liste(p['cas'])) {
        final nom = '${c['nom']}';
        final varia = nom.contains('sans date')
            ? {...variable, 'id': 'VAR-NFS-GR'}
            : (nom.contains('sans plage') ? {...variable, 'id': 'VAR-NFS-HB', 'min': 11, 'max': 14} : variable);
        final pl = nom.contains('sans date')
            ? [for (final a in actives) {...a, 'variableId': a['variableId'], 'id': a['id']}]
            : actives;
        final plage = plagePour(varia, pl, c['date'], aujourdhui: maintenant);
        expect(plage?['lot'], c['lot'], reason: nom);
        final vd = variableALaDate(varia, pl, c['date'], aujourdhui: maintenant);
        expect(vd['min'], c['min'], reason: nom);
        expect(vd['max'], c['max'], reason: nom);
        expect(referenceALaDate(varia, pl, c['date'], aujourdhui: maintenant), c['reference'], reason: nom);
      }
    });
    test('${liste(p['ecarts']).length} écarts et références rejoués', () {
      for (final c in liste(p['ecarts'])) {
        final varia = c['variable'] == null ? null : (c['variable'] as Map).cast<String, Object?>();
        expect(ecart(varia, c['valeur']), c['ecart'], reason: '${c['variable']} / ${c['valeur']}');
        expect(libelleReference(varia), c['reference'], reason: '${c['variable']}');
      }
    });
  });

  group('saisie structurée : quel examen, quelles variables, quel résumé', () {
    final examens = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/examensLabo.json').readAsStringSync()));
    final variables = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/variablesLabo.json').readAsStringSync()));
    for (final c in liste(v['saisie'])) {
      test('${c['nom']}', () {
        final d = (c['demande'] as Map).cast<String, Object?>();
        final code = codeExamenSaisie(d, examens);
        final vars = [for (final x in variablesExamen(code, variables)) if (x['actif'] != false) x];
        if (c['ouverte'] != true) {
          expect(vars, isEmpty, reason: 'un examen sans variable paramétrée refuse la saisie');
          return;
        }
        expect(vars.length, liste(c['lignes']).length);
        for (final (i, l) in liste(c['lignes']).indexed) {
          final lib = '${vars[i]['parent'] != null ? '↳ ' : ''}${vars[i]['libelle']}';
          expect('${l['variable']}'.startsWith(lib), isTrue, reason: '$lib / ${l['variable']}');
        }
      });
    }
    test('les motifs du commentaire général et les issues imposées par le type sont ceux de la maquette', () {
      expect(motifsCommentaireGeneral, (v['motifs'] as List).cast<String>());
      for (final t in liste(v['types'])) {
        if (t['valeurs'] != null) {
          expect(valeursTypeVariable['${t['id']}'], (t['valeurs'] as List).cast<String>(), reason: '${t['id']}');
        } else {
          expect(valeursTypeVariable.containsKey('${t['id']}'), isFalse, reason: '${t['id']}');
        }
        expect(libellesTypeVariable['${t['id']}'], t['label'], reason: '${t['id']}');
      }
    });
    test('le résumé textuel : variables principales renseignées, unité de la clinique, accompagnement exclu', () {
      final nfs = variablesExamen('NFS', variables);
      final r = resumeResultat(nfs, {'GB': 5.5, 'GR': 0, 'HB': '12'}, (u) => u == 'g_l_hb' ? 'G/l' : '—');
      expect(r.startsWith('Globules blancs 5.5 G/l'), isTrue);
      expect(r.contains('Globules rouges'), isFalse, reason: 'zéro est falsy, comme dans la maquette');
    });
    test('l\'âge s\'écrit comme sur une pièce : exact, ou déclaré et vieilli depuis sa déclaration', () {
      final auj = DateTime(2026, 10, 30, 12);
      expect(ageTexte({'dateNaissance': '1990-05-01'}, auj), '36 ans');
      expect(ageTexte({'dateNaissance': '2026-01-01'}, auj), '0 an');
      expect(ageTexte({'age': 45}, auj), '45 ans (âge déclaré)');
      expect(ageTexte({'age': 45, 'ageReferenceLe': '2024-10-30'}, auj), '47 ans (âge déclaré)');
      expect(ageTexte({}, auj), '—');
      expect(ageTexte(null, auj), '—');
    });
  });

  group('règlement lu sur la ligne de facture (impression)', () {
    final imp = (v['impression'] as Map).cast<String, Object?>();
    final ent = (v['entrees'] as Map)['impression'] as Map;
    final demandes = liste(ent['demandes']);
    final idx = indexReglements(liste(ent['factures']));
    final lignes = liste((liste(imp['cas']).first)['lignes']);
    for (final p in liste(imp['poses'])) {
      final nom = '${p['nom']}';
      if (nom.startsWith('non rendu')) continue;
      test(nom, () {
        final d = demandes.firstWhere((x) => x['reference'] == p['reference']);
        final g = reglementDemande(d, idx);
        final cellule = ((lignes.firstWhere((l) => '${(l['cellules'] as List).first}'.startsWith('${p['reference']}'))['cellules'] as List)[5]) as String;
        expect('${g.libelle}${g.facture ?? ''}', cellule);
      });
    }
  });

  group('comparatif des antériorités', () {
    final ent = (v['entrees'] as Map)['comparatif'] as Map;
    final demandes = liste(ent['demandes']);
    final plages = liste(ent['plages']);
    final examens = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/examensLabo.json').readAsStringSync()));
    final variables = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/variablesLabo.json').readAsStringSync()));
    final unites = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/unitesLabo.json').readAsStringSync()));
    final cas = liste(v['comparatif']);
    final direction = const SessionLabo(role: 'direction', fonction: 'direction');
    test('les patients comparables, dans l\'ordre du registre', () {
      final c0 = cas.first;
      final att = liste((c0['options'] as Map)['patients']);
      final obtenu = parPatient(comparables(demandes, direction));
      expect([for (final p in obtenu) p.id], [for (final a in att) a['value']]);
      expect([for (final p in obtenu) p.libelle], [for (final a in att) a['libelle']]);
    });
    test('un profil sans accès aux résultats ne compare rien (et le dit)', () {
      expect(comparables(demandes, const SessionLabo(role: 'infirmier', fonction: 'infirmier')), isEmpty);
    });
    for (final c in cas.where((c) => c['lignes'] != null)) {
      test('${c['patient']} / ${c['examen']} (${(c['choisi'] as Map)['a']} → ${(c['choisi'] as Map)['b']})', () {
        final rows = comparables(demandes, direction).where((r) => r['patientId'] == c['patient']).toList();
        final exs = examensDuPatient(rows, examens);
        final ex = exs.firstWhere((e) => e.code == c['examen']);
        final att = liste(c['choixPossibles']);
        expect([for (final m in ex.mesures) libelleMesure(m)], [for (final a in att) a['libelle']]);
        final vars = [for (final x in variables) if (x['examen'] == c['examen']) x]
          ..sort((a, b) => ((a['ordre'] ?? 0) as num).compareTo((b['ordre'] ?? 0) as num));
        final a = ex.mesures[int.parse((c['choisi'] as Map)['a'] as String)];
        final b = ex.mesures[int.parse((c['choisi'] as Map)['b'] as String)];
        final lg = comparer(a, b, vars, plages, unites, aujourdhui: maintenant);
        final att2 = liste(c['lignes']);
        expect(lg.length, att2.length);
        for (var i = 0; i < lg.length; i++) {
          final cel = (att2[i]['cellules'] as List).cast<String>();
          final gras = (att2[i]['gras'] as List).cast<bool>();
          expect(lg[i].libelle, cel[0]);
          expect(lg[i].valeurA, cel[1]);
          expect(lg[i].valeurB, cel[2]);
          expect(lg[i].evolution ?? '—', cel[3]);
          expect(lg[i].reference, cel[4]);
          expect(lg[i].horsA, gras[0]);
          expect(lg[i].horsB, gras[1]);
        }
      });
    }
  });

  group('statistiques du laboratoire', () {
    final ent = (v['entrees'] as Map)['stats'] as Map;
    final demandes = liste(ent['demandes']);
    final patients = liste(ent['patients']);
    final examens = liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/examensLabo.json').readAsStringSync()));
    final aujourdhui = DateTime(2026, 10, 30, 12);
    for (final c in liste(v['stats'])) {
      final fl = (c['filtres'] as Map).cast<String, Object?>();
      test('${c['nom']}', () {
        var f = FiltresStatsLabo(
            du: '${fl['du'] ?? ''}', au: '${fl['au'] ?? ''}', section: '${fl['section'] ?? ''}',
            service: '${fl['service'] ?? ''}', origine: '${fl['origine'] ?? ''}', sexe: '${fl['sexe'] ?? ''}');
        if (fl['periode'] == 'semaine') {
          final b = bornesPeriodeLabo('semaine', aujourdhui)!;
          f = f.avec(du: b.du, au: b.au);
        }
        final rows = lignesStats(demandes, patients, f, examens);
        final s = calculerStatsLabo(rows, patients, examens, maintenant: aujourdhui);
        final k = liste(c['kpis']);
        expect(s.demandes.toString(), k[0]['valeur']);
        expect(s.rendus.toString(), k[1]['valeur']);
        expect(s.indiceRendus ?? '', k[1]['indice']);
        expect(s.urgents.toString(), k[2]['valeur']);
        expect(s.patientsDistincts.toString(), k[3]['valeur']);
        final tab = (c['tableau'] as List).map((l) => (l as List).cast<String>()).toList();
        expect([for (final d in s.detail) [d.examen, d.section, '${d.total}', '${d.rendus}', '${d.urgents}', '${d.externes}']], tab);
        final g = liste(c['graphiques']);
        if (s.demandes == 0) {
          expect(g, isEmpty);
          return;
        }
        List<Object?> arg(F j, int i) => (j['a'] as List)[i] as List;
        expect([for (final x in s.topExamens) {'label': x.$1, 'value': x.$2, 'tone': 'navy'}], arg(g[0], 0));
        expect([for (final x in s.parSection) x.$1], arg(g[1], 0));
        expect([for (final x in s.parSection) x.$2], arg(g[1], 1));
        expect([for (final x in s.parService) x.$1], arg(g[2], 0));
        expect([for (final x in s.parService) x.$2], (((g[2]['a'] as List)[1] as List).first as Map)['data']);
        expect([for (final x in s.parOrigine) x.$1], arg(g[3], 0));
        expect([for (final x in s.parOrigine) x.$2], arg(g[3], 1));
        expect([for (final x in s.parSexe) x.$1], arg(g[4], 0));
        expect([for (final x in s.parSexe) x.$2], arg(g[4], 1));
        expect(s.parAge, (((g[5]['a'] as List)[1] as List).first as Map)['data']);
        if (s.parJour.length > 1) {
          expect(g.length, 7);
          expect([for (final x in s.parJour) dateFR(DateTime.parse(x.$1))], arg(g[6], 0));
          expect([for (final x in s.parJour) x.$2], (((g[6]['a'] as List)[1] as List).first as Map)['data']);
        } else {
          expect(g.length, 6);
        }
      });
    }
    test('les bornes d\'une périodicité se terminent aujourd\'hui', () {
      final b = bornesPeriodeLabo('mois', DateTime(2026, 10, 30, 12))!;
      expect(b.au, '2026-10-30');
      expect(b.du, '2026-10-01');
      expect(bornesPeriodeLabo('libre', DateTime(2026, 10, 30)), isNull);
    });
  });
}
