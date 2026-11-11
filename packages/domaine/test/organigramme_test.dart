// L'organigramme (lot ORG2, Direction, 11/11/2026, O1 à O5) et le verrou d'un poste de secours (P3) : rejoue les vecteurs engendrés par les moteurs de la maquette
// (prototype_html/build/vecteurs-organigramme.js) sur les MÊMES entrées : semence de la photo, arbre et titre de l'agent, réaffecter, renommer le titulaire, poser le titre,
// créer, archiver (refus nommés : cycle, parent archivé, poste qui porte des postes, agent introuvable, poste vacant, titre trop long, droit), reprise qui épargne ce que la
// clinique a modifié, mise en page de l'impression paysage, délai de verrou d'un poste de secours.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;
M m(Object? x) => (x as Map).cast<String, Object?>();
M copie(M x) => (jsonDecode(jsonEncode(x)) as Map).cast<String, Object?>();

/// Les rôles que connaît le manifeste (assez pour les cas du vecteur).
const rolesConnus = {'admin', 'da', 'direction', 'dm', 'medecin', 'caissier', 'infirmier', 'agentadmin', 'comptable', 'stock', 'pharmacien', 'laborantin', 'reception', 'ambulancier', 'aide_soignant'};

/// Les droits de l'écran « Organisation & organigramme » par rôle, tels que la matrice les donne (admin et DA : tout ; Direction : écrire sans annuler ; les autres : rien).
({bool editer, bool annuler}) droits(String role, {bool sansRole = false}) {
  if (sansRole) return (editer: false, annuler: false);
  return switch (role) {
    'admin' || 'da' => (editer: true, annuler: true),
    'direction' => (editer: true, annuler: false),
    _ => (editer: false, annuler: false),
  };
}

String tronque(Object? v) {
  final s = jsonEncode(v);
  return s.length > 100 ? s.substring(0, 100) : s;
}

void main() {
  final j = lireVecteurs('organigramme');

  group('la semence de la photo (O1) et celle d\'avant', () {
    test('quinze fiches de la semence, dans l\'ordre du parcours, identiques à la maquette', () {
      final v = liste(j['semence']);
      final d = orgSemence();
      expect(d.length, 16);
      expect(d.length, v.length);
      for (var i = 0; i < v.length; i++) {
        memes(d[i], v[i], 'semence[$i]');
      }
    });
    test('la semence d\'avant sert à reconnaître une fiche intacte, rien de plus', () {
      final v = liste(j['precedent']);
      final d = orgPrecedent();
      expect(d.length, v.length);
      for (var i = 0; i < v.length; i++) {
        memes(d[i], v[i], 'precedent[$i]');
      }
    });
    test('les six intitulés de la photo, aucune étoile, « SG » ne se lit pas sur le poste', () {
      final noms = [for (final p in orgSemence()) p['poste']];
      for (final x in ['Directrice Administrative (DA)', 'Echographiste', 'Aide-Soignante', 'Agents de Sécurités', 'Agents d’Entretiens', 'Assistant comptable']) {
        expect(noms, contains(x));
      }
      for (final p in orgSemence()) {
        expect(p.containsKey('etoile'), isFalse);
      }
      expect(orgSemence().firstWhere((p) => p['poste'] == 'Infirmiers')['chef'], isFalse);
    });
  });

  final monde = m(j['monde']);
  List<M> postesMonde() => [for (final p in liste(monde['postes'])) copie(p)];
  List<M> personnelMonde() => [for (final p in liste(monde['personnel'])) copie(p)];
  List<M> actifs(List<M> l) => [for (final p in l) if (p['statut'] != 'archive') p];

  group('l\'arbre et le titre de l\'agent (O3)', () {
    test('le titre est lu sur l\'agent rattaché par son nom, la mention d\'épouse ne gêne pas', () {
      final pers = actifs(personnelMonde());
      expect(orgTitreDuPoste({'titulaire': 'GARBA Yahouza'}, pers), 'SG');
      expect(orgTitreDuPoste({'titulaire': 'garba  yahouza'}, pers), 'SG');
      expect(orgTitreDuPoste({'titulaire': 'TAKI Alimatou épse BASSONGUI'}, pers), isNull);
      expect(orgAgentDuPoste({'titulaire': 'TAKI Alimatou épse BASSONGUI'}, pers)?['id'], 'E3');
      expect(orgAgentDuPoste({'titulaire': 'Aïssatou DIEYABIDI'}, pers)?['id'], 'E5');
      expect(orgAgentDuPoste({'titulaire': 'ARCHIVÉ Ancien'}, pers), isNull, reason: 'un agent archivé ne porte plus de titre');
      expect(orgAgentDuPoste({}, pers), isNull);
    });
    test('l\'arbre des postes actifs porte le titre de chaque titulaire, dans l\'ordre de la maquette', () {
      final racines = orgArbre(actifs(postesMonde()), actifs(personnelMonde()));
      final lus = <M>[];
      void parcourir(OrgNoeud n, int niveau) {
        lus.add({'id': n.id, 'poste': n.poste, 'parentId': n.fiche['parentId'], 'niveau': niveau, 'titreAgent': n.titreAgent, 'enfants': [for (final e in n.enfants) e.id]});
        for (final e in n.enfants) {
          parcourir(e, niveau + 1);
        }
      }

      for (final r in racines) {
        parcourir(r, 0);
      }
      final v = liste(j['arbre']);
      expect(lus.length, v.length);
      for (var i = 0; i < v.length; i++) {
        memes(lus[i], v[i], 'arbre[$i]');
      }
    });
  });

  /// Joue un cas du vecteur : planifie, applique le plan sur la copie du monde, et rend ce que l'écran verrait.
  M jouer(M cas) {
    final postes = postesMonde(), personnel = personnelMonde();
    final role = '${cas['role']}';
    final a = m(cas['appel']);
    final d = droits(role, sansRole: a['sansRole'] == true);
    final avant = [for (final p in postes) jsonEncode(p)];
    final journal = <M>[];
    void ligne(String action, String module, String entite, Object? av, Object? ap, {bool detail = true}) =>
        journal.add({'action': action, 'module': module, 'entite': entite, 'ancienne': detail ? tronque(av) : null, 'nouvelle': detail ? tronque(ap) : null});
    RefusRh? refus;
    var inchange = false;
    Object? titre;
    final fn = a['fn'];
    final actifsP = actifs(postes), actifsA = actifs(personnel);
    if (fn == 'creer') {
      final r = orgPlanifierCreation(m(a['champs']), droitEcriture: d.editer, postes: postes, personnelActif: actifsA, rolesConnus: rolesConnus);
      refus = r.refus;
      if (r.fiche != null) {
        postes.add({'id': 'NOUVEAU', ...r.fiche!});
        ligne('Création', 'CFG', 'poste', null, null, detail: false);
      }
    } else if (fn == 'archiver') {
      refus = orgControlerArchivage('${a['posteId']}', droitAnnulation: d.annuler, postes: postes);
      if (refus == null) {
        postes.firstWhere((p) => p['id'] == a['posteId'])['statut'] = 'archive';
        ligne('Archivage', 'CFG', 'poste', {'statut': 'actif'}, {'statut': 'archive'});
      }
    } else {
      final champs = switch (fn) {
        'reaffecter' => <String, Object?>{'parentId': a['parentId']},
        'renommerTitulaire' => <String, Object?>{'titulaire': a['nom']},
        'poserTitre' => <String, Object?>{'titreAgent': a['titre']},
        _ => m(a['champs']),
      };
      final plan = orgPlanifierModification('${a['posteId']}', champs, droitEcriture: d.editer, postes: postes, personnelActif: actifsA, rolesConnus: rolesConnus);
      refus = plan.refus;
      inchange = plan.inchange;
      if (plan.ok && !plan.inchange) {
        titre = plan.titre;
        if (plan.journalPoste != null) {
          final p = postes.firstWhere((x) => x['id'] == a['posteId']);
          plan.patch.forEach((k, v) => p[k] = v);
          final jp = plan.journalPoste!;
          ligne(jp.action, jp.module, jp.entite, jp.avant, jp.apres);
        }
        if (plan.agentId != null) {
          final ag = personnel.firstWhere((x) => x['id'] == plan.agentId);
          if (plan.titrePose == null) {
            ag['titreOrganigramme'] = null;
          } else {
            ag['titreOrganigramme'] = plan.titrePose;
          }
          final jt = plan.journalTitre!;
          ligne(jt.action, jt.module, jt.entite, jt.avant, jt.apres);
        }
      }
    }
    final defaut = <String, Object?>{'parentId': null, 'titulaire': null, 'chef': false};
    M champsPoste(M p) => {
          'id': p['id'],
          'statut': p['statut'],
          'parentId': p.containsKey('parentId') ? p['parentId'] : null,
          'poste': p['poste'],
          'effectif': p['effectif'],
          'titulaire': p.containsKey('titulaire') ? p['titulaire'] : defaut['titulaire'],
          'chef': p['chef'] == true,
          'role': p['role']
        };
    final apres = [for (final p in postes) champsPoste(p)];
    final avantParId = {for (final s in avant) '${(jsonDecode(s) as Map)['id']}': jsonEncode(champsPoste((jsonDecode(s) as Map).cast<String, Object?>()))};
    final changes = [for (final p in apres) if (avantParId.containsKey(p['id']) && avantParId[p['id']] != jsonEncode(p)) p['id']];
    final nouveaux = [for (final p in apres) if (!avantParId.containsKey(p['id'])) {...p, 'id': null}];
    final titres = [for (final p in personnel) if (p['titreOrganigramme'] != null) [p['id'], p['titreOrganigramme']]];
    return {
      'ok': refus == null,
      if (refus != null) ...{'code': refus.code, 'motif': refus.motif, 'geste': refus.geste} else ...{'inchange': inchange, 'titre': titre},
      'postesChanges': changes,
      'nouveaux': nouveaux,
      'titres': titres,
      'journal': journal,
      'nbPostes': postes.length,
    };
  }

  group('les gestes sur un poste : le même plan, les mêmes refus nommés, le même journal que la maquette', () {
    for (final c in liste(j['cas'])) {
      test(c['nom'] as String, () {
        final r = jouer(c);
        final a = m(c['attendu']);
        expect(r['ok'], a['ok'], reason: 'ok');
        if (a['ok'] == false) {
          expect(r['code'], a['code']);
          expect(r['motif'], a['motif']);
          expect(r['geste'], a['geste']);
        } else {
          expect(r['inchange'], a['inchange'], reason: 'inchangé');
          expect(r['titre'], a['titre'], reason: 'titre');
        }
        expect(r['postesChanges'], a['postesChanges'], reason: 'postes changés');
        expect(r['nouveaux'], a['nouveaux'], reason: 'postes créés');
        expect(r['titres'], a['titres'], reason: 'titres du personnel');
        expect(r['journal'], a['journal'], reason: 'journal');
        expect(r['nbPostes'], a['nbPostes']);
      });
    }
  });

  group('contrôle d\'une saisie sans rien écrire', () {
    for (final c in liste(j['controles'])) {
      test(c['nom'] as String, () {
        final r = orgControler(c['posteId'] as String?, m(c['champs']), postes: postesMonde(), personnelActif: actifs(personnelMonde()), rolesConnus: rolesConnus);
        final a = c['attendu'];
        if (a == null) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull);
          expect({'ok': false, 'code': r!.code, 'motif': r.motif, 'geste': r.geste}, m(a));
        }
      });
    }
  });

  group('la reprise (VERSION 78) : n\'écrase JAMAIS ce que la clinique a modifié', () {
    for (final c in liste(j['reprises'])) {
      test(c['nom'] as String, () {
        final postes = [for (final p in liste(c['entree'])) copie(p)];
        final bilan = orgMigrer(postes);
        final second = orgMigrer(postes);
        final a = m(c['attendu']);
        expect(bilan.toJson(), a['bilan']);
        expect(second.toJson(), a['second'], reason: 'idempotente');
        final att = liste(a['postes']);
        expect(postes.length, att.length);
        for (var i = 0; i < att.length; i++) {
          memes(postes[i], att[i], 'postes[$i]');
        }
      });
    }
  });

  group('la mise en page de l\'impression paysage', () {
    OrgNoeud noeud(M n) {
      final o = OrgNoeud(n, n['titreAgent'] as String?);
      for (final e in liste(n['enfants'])) {
        o.enfants.add(noeud(e));
      }
      return o;
    }

    List<double> nombres(String d) => [for (final x in RegExp(r'-?\d+(?:\.\d+)?').allMatches(d)) double.parse(x.group(0)!)];
    const tol = 0.0061;
    for (final c in liste(j['mises'])) {
      test(c['nom'] as String, () {
        final opt = c['options'] == null ? null : m(c['options']);
        final r = orgMiseEnPage([for (final n in liste(c['entree'])) noeud(n)],
            o: opt == null
                ? const OrgOptions()
                : OrgOptions(
                    largeur: (opt['largeur'] as num?)?.toDouble() ?? 273,
                    hauteurMax: (opt['hauteurMax'] as num?)?.toDouble() ?? 120));
        final a = m(c['attendu']);
        expect(r, isNotNull);
        expect(r!.largeur, closeTo(a['largeur'] as num, tol));
        expect(r.hauteur, closeTo(a['hauteur'] as num, tol));
        expect(r.niveaux, a['niveaux']);
        final b = liste(a['boites']);
        expect(r.boites.length, b.length);
        for (var i = 0; i < b.length; i++) {
          expect(r.boites[i].poste, b[i]['poste']);
          expect(r.boites[i].gauche, closeTo(b[i]['gauche'] as num, tol), reason: '${b[i]['poste']} gauche');
          expect(r.boites[i].haut, closeTo(b[i]['haut'] as num, tol), reason: '${b[i]['poste']} haut');
          expect(r.boites[i].largeur, closeTo(b[i]['largeur'] as num, tol), reason: '${b[i]['poste']} largeur');
          expect(r.boites[i].hauteur, closeTo(b[i]['hauteur'] as num, tol));
          expect(r.boites[i].lignes, [for (final l in b[i]['lignes'] as List) '$l'], reason: '${b[i]['poste']} lignes');
        }
        final t = (a['traits'] as List).cast<List>();
        expect(r.traits.length, t.length);
        for (var i = 0; i < t.length; i++) {
          final x = r.traits[i];
          expect([x.x1, x.y1, x.x2, x.y2].indexed.every((e) => (e.$2 - (t[i][e.$1] as num)).abs() < tol), isTrue, reason: 'trait $i : ${[x.x1, x.y1, x.x2, x.y2]} contre ${t[i]}');
        }
        final f = (a['fleches'] as List).cast<String>();
        expect(r.fleches.length, f.length);
        for (var i = 0; i < f.length; i++) {
          final att = nombres(f[i]);
          final obt = [for (final p in r.fleches[i].points) ...[p.$1, p.$2]];
          expect(obt.length, att.length);
          for (var k = 0; k < att.length; k++) {
            expect((obt[k] - att[k]).abs() < tol, isTrue, reason: 'flèche $i : $obt contre $att');
          }
        }
      });
    }
    test('aucun poste à représenter : la feuille le dit', () {
      expect(orgMiseEnPage([]), isNull);
      expect(orgTexteAucunPoste, m(j['miseVide'])['texte']);
    });
  });

  group('le verrou d\'un poste de secours (P3) : 5 minutes à valider, réglage en base, administrateur et DAF seuls', () {
    final s = m(j['secours']);
    test('défauts : 5 minutes (secours), 15 (ordinaire), poste ordinaire', () {
      final d = m(s['defauts']);
      expect(delaiVerrouSecoursMinutes(null), d['delaiSecours']);
      expect(delaiVerrouOrdinaireMinutes(null), d['ordinaire']);
      expect(delaiVerrouPosteMinutes(posteDeSecours: false, reglageSecours: null, politiqueInactiviteMin: null), d['delaiPoste']);
      expect(delaiVerrouSecoursDefautMin, d['defautMin']);
      expect([delaiVerrouSecoursMin, delaiVerrouSecoursMax], d['bornes']);
    });
    test('le paramètre est au registre, marqué à valider, branché, jamais envoyé au téléphone', () {
      final def = definitionDeParametre(cleDelaiVerrouSecours)!;
      expect(def.defaut, 5);
      expect(def.branche, isTrue);
      expect(def.mobile, isFalse);
      expect(def.source, contains('à valider'));
    });
    final cas = liste(s['cas']);
    for (var i = 0; i < cas.length; i++) {
      final c = cas[i];
      test('réglage : ${c['role']} règle ${jsonEncode(c['minutes'])} minute(s)', () {
        final r = controlerReglageDelaiSecours(role: '${c['role']}', minutes: c['minutes']);
        final a = m(c['attendu']);
        if (a['ok'] == true) {
          expect(r, isNull);
          expect(delaiVerrouSecoursMinutes(c['minutes']), a['minutes']);
        } else {
          expect(r, isNotNull);
          expect({'code': r!.code, 'motif': r.motif, 'geste': r.geste}, {'code': a['code'], 'motif': a['motif'], 'geste': a['geste']});
          expect(a['enBase'], isNull, reason: 'rien n\'est écrit');
        }
      });
    }
    final poste = liste(s['poste']);
    for (var i = 0; i < poste.length; i++) {
      final p = poste[i];
      test('désignation : ${p['role']}', () {
        final r = controlerDesignationPosteSecours(role: '${p['role']}');
        final a = m(p['attendu']);
        final reglage = m(cas[i]['attendu'])['ok'] == true ? 7 : null;
        if (a['ok'] == true) {
          expect(r, isNull);
          expect(delaiVerrouPosteMinutes(posteDeSecours: true, reglageSecours: reglage, politiqueInactiviteMin: null), a['delaiMinutes']);
          expect(a['drapeau'], '1');
        } else {
          expect({'code': r!.code, 'motif': r.motif, 'geste': r.geste}, {'code': a['code'], 'motif': a['motif'], 'geste': a['geste']});
          expect(a['drapeau'], isNull);
        }
      });
    }
    for (final c in liste(s['delais'])) {
      test('délai en force : politique ${c['politiqueInactiviteMin']}, secours ${c['reglageSecours']}, poste de secours ${c['posteDeSecours']}', () {
        final a = m(c['attendu']);
        final ord = delaiVerrouOrdinaireMinutes(c['politiqueInactiviteMin']);
        final sec = delaiVerrouSecoursMinutes(c['reglageSecours']);
        final poste = delaiVerrouPosteMinutes(posteDeSecours: c['posteDeSecours'] == true, reglageSecours: c['reglageSecours'], politiqueInactiviteMin: c['politiqueInactiviteMin']);
        expect([ord, sec, poste, poste * 60000], [a['ordinaire'], a['secours'], a['poste'], a['verrouMs']]);
      });
    }
  });
}
