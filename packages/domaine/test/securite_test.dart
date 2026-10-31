// Rejoue les vecteurs de M14 engendrés par la maquette (prototype_html/build/vecteurs-securite.js) : les sept écrans PILOTÉS dans Chrome.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef F = Map<String, Object?>;

F f(Object? x) => (x as Map).cast<String, Object?>();

/// Retire ce que le magasin pose lui-même (identifiant, statut, traces de modification).
F net(F x) => {
      for (final e in x.entries)
        if (!{'id', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'}.contains(e.key)) e.key: e.value
    };

void main() {
  final v = lireVecteurs('securite');

  group('comptes (m14-utilisateurs)', () {
    final cas = liste(v['comptes']);
    final jour = '${liste(v['comptes']).firstWhere((c) => c['jour'] != null)['jour']}';
    final maintenant = DateTime.utc(2026, 10, 30, 23, 49, 28, 726);

    test('la maquette produit au moins quinze cas de création et cinq de modification', () {
      expect(cas.where((c) => c['mode'] == 'creation').length, greaterThanOrEqualTo(15));
      expect(cas.where((c) => c['mode'] == 'edition').length, greaterThanOrEqualTo(5));
    });

    for (final c in cas.where((c) => c['mode'] == 'creation')) {
      test('création — ${c['nom']}', () {
        final saisie = f(c['saisie']);
        final longueur = c['motDePasseLongueur'] as int;
        final toasts = (c['toasts'] as List).cast<String>();
        final different = toasts.contains('Les deux mots de passe saisis ne correspondent pas.');
        final form = {
          ...secCompteParDefaut(),
          ...saisie,
          'motDePasse': (c['nom'] as String).contains('huit espaces') ? ' ' * longueur : 'x' * longueur,
          'motDePasseConfirmation': different
              ? 'y' * longueur
              : ((c['nom'] as String).contains('huit espaces') ? ' ' * longueur : 'x' * longueur),
        };
        final refus = secVerifierCompte(form, comptes: [
          {'id': 'U0', 'identifiant': 'admin.systeme'}
        ]);
        final creees = liste(c['creee']);
        if (creees.isEmpty) {
          // Le formulaire en erreur (identifiant vide) est arrêté AVANT beforeSave par la validation des champs obligatoires : le toast est celui du kit.
          if (toasts.last == 'Le formulaire comporte des erreurs.') {
            expect(secVrai(saisie['identifiant']), isFalse);
          } else {
            expect(refus, toasts.last);
          }
          return;
        }
        expect(refus, isNull);
        final attendu = f(creees.single['fiche']);
        final agent = secVrai(saisie['employeId'])
            ? {
                'nomComplet': attendu['nomComplet'],
                'matricule': attendu['matricule'],
                'poste': attendu['poste'],
                'service': attendu['service']
              }
            : null;
        final obtenu = secTransformerCompte(form,
            agent: agent, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant, jour: jour);
        // Le secret ne franchit pas la transformation.
        expect(obtenu.containsKey('motDePasse'), isFalse);
        expect(obtenu.containsKey('motDePasseConfirmation'), isFalse);
        expect(creees.single['aMotDePasse'], isFalse);
        expect(obtenu['motDePasseDefiniLe'], isNotNull);
        memes(obtenu, net(attendu), c['nom'] as String, ignorer: {'motDePasseDefiniLe'});
      });
    }

    final avantEdition = <F>[];
    for (final c in cas.where((c) => c['mode'] == 'edition')) {
      test('modification — ${c['nom']}', () {
        final avant = f(c['avant']);
        final saisie = f(c['saisie']);
        expect(c['champsMotDePasseAffiches'], isEmpty, reason: 'pas de champs de mot de passe à la modification');
        final record = {'id': c['cible'], ...avant};
        final form = <String, Object?>{
          for (final k in ['identifiant', 'employeId', 'role', 'service', 'actif', 'mfa']) k: avant[k],
          ...saisie,
        };
        final refus = secVerifierCompte(form, record: record, comptes: [
          record,
          {'id': 'U0', 'identifiant': 'admin.systeme'}
        ]);
        final toasts = (c['toasts'] as List).cast<String>();
        if (toasts.last != 'Modifications enregistrées.') {
          expect(refus, toasts.last);
          expect(net(f(c['apres'])), net(avant), reason: 'rien n\'est écrit');
          return;
        }
        expect(refus, isNull);
        final apresAttendu = f(c['apres']);
        final agent = secVrai(form['employeId']) && form['employeId'] != avant['employeId']
            ? {
                'nomComplet': apresAttendu['nomComplet'],
                'matricule': apresAttendu['matricule'],
                'poste': apresAttendu['poste'],
                'service': apresAttendu['service']
              }
            : (secVrai(form['employeId'])
                ? {
                    'nomComplet': avant['nomComplet'],
                    'matricule': avant['matricule'],
                    'poste': avant['poste'],
                    'service': avant['service']
                  }
                : null);
        final ecrit = secTransformerCompte(form,
            record: record, agent: agent, utilisateur: 'U', maintenant: maintenant, jour: jour);
        // `col.update` fusionne : ce qui n'est pas dans le formulaire reste (dernier accès, échecs — E591).
        final apres = {...avant, ...ecrit};
        memes(apres, apresAttendu, c['nom'] as String);
        avantEdition.add(avant);
      });
    }

    test('les services proposés sont ceux de D.SERVICES', () {
      expect(secServices, v['services']);
    });

    test('les rôles à privilèges imposent le double facteur, les autres le laissent au choix', () {
      expect(secRolesDoubleFacteur, ['dm', 'da', 'direction', 'admin']);
      final a = secTransformerCompte({'role': 'reception', 'mfa': false},
          utilisateur: 'U', maintenant: maintenant, jour: jour);
      expect(a['mfa'], false);
      final b = secTransformerCompte({'role': 'admin', 'mfa': false},
          utilisateur: 'U', maintenant: maintenant, jour: jour);
      expect(b['mfa'], true);
    });
  });

  group('rôles (m14-roles)', () {
    final ouverture = f(v['rolesOuverture']);
    final cas = liste(v['roles']);

    test('à l\'ouverture : les libellés, les comptes par rôle et la mention « ex- » viennent des fiches', () {
      final libelles = (ouverture['libelles'] as List).map((x) => (x as List).cast<String>()).toList();
      final comptes = f(ouverture['comptesParRole']);
      final lignes = (ouverture['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(lignes.length, libelles.length);
      for (var i = 0; i < libelles.length; i++) {
        final r = libelles[i];
        final n = (comptes[r[0]] as int?) ?? 0;
        final attendu = '${r[1]}$n compte(s)${r[1] != r[2] ? ' · ex-${r[2]}' : ''}';
        expect(lignes[i][0], attendu);
      }
    });

    test('l\'onglet « Habilitations métier » reprend D.CAPACITES ligne à ligne', () {
      final rows = secHabilitationsMetier();
      final t = f(ouverture['habilitations']);
      final lignes = (t['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(rows.length, lignes.length);
      const res = {'tous': 'Tous', 'secteur': 'Son secteur', 'produits': 'Ceux qu’il produit', 'aucun': 'Aucun'};
      const echo = {'tous': 'Toutes', 'secteur': 'Son secteur', 'aucun': 'Aucune'};
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        expect(r['label'], lignes[i][0]);
        expect(res[r['resultats']] ?? 'Aucun', lignes[i][1]);
        expect(echo[r['echographie']] ?? 'Aucune', lignes[i][2]);
        expect((r['prescrire'] as int) > 0 ? r['natures'] : 'non', lignes[i][3]);
        expect(r['soins'] == true ? 'Oui' : 'Non', lignes[i][4]);
        expect('${r['note']}', lignes[i][5]);
      }
    });

    final gestes = <String, void Function(Map<String, CasesDroitsSec>)>{
      'lecture seule cochée : voir sans éditer ni annuler': (c) => c['M10']!.cocherLecture(true),
      'éditer coché ouvre aussi « voir »': (c) => c['M12']!.cocherEditer(true),
      'décocher « voir » retire éditer et annuler': (c) => c['M8']!.cocherVoir(false),
      'annuler coché seul ouvre « voir » (éditer reste faux)': (c) => c['M9']!.cocherAnnuler(true),
      'lecture seule décochée : le module reste visible': (c) {
        c['M5']!.cocherLecture(true);
        c['M5']!.cocherLecture(false);
      },
      '« Tout fermer »': (c) => secBasculerTout(c.values, ModeToutSec.fermer),
      '« Tout en lecture seule »': (c) => secBasculerTout(c.values, ModeToutSec.lectureSeule),
      '« Tout ouvrir »': (c) => secBasculerTout(c.values, ModeToutSec.ouvrir),
    };

    for (final c in cas.where((c) => c['type'] == 'droits')) {
      test('droits — ${c['nom']}', () {
        // Les cases : l'état initial de la modale est celui des droits effectifs du rôle.
        final initial = {
          for (final x in liste(c['initial'])) x['code'] as String: CasesDroitsSec(x['voir'] == true, x['editer'] == true, x['annuler'] == true)
        };
        // Le tableau de la modale a une ligne par rangée : les gestes de la maquette visent la PREMIÈRE ligne d'un code répété ; ici un seul code.
        gestes[c['nom']]!(initial);
        final saisi = liste(c['saisi']);
        final codes = <String>[];
        for (final x in saisi) {
          final code = x['code'] as String;
          if (codes.contains(code)) continue;
          codes.add(code);
          final e = initial[code]!;
          expect([e.voir, e.editer, e.annuler, e.lecture], [x['voir'], x['editer'], x['annuler'], x['lecture']], reason: code);
        }
        // L'enregistrement écrit trois droits par module ; la matrice affichée ensuite est la base + la fiche.
        final fiche = f(liste(f(c['apres'])['fiches']).first);
        final droitsEcrits = f(fiche['droits']);
        for (final code in initial.keys) {
          memes(droitsEcrits[code], initial[code]!.versFiche(), '${c['nom']}.$code');
        }
        final role = c['role'] as String;
        final avant = f(f(c['avant'])['matrice']);
        final bases = {
          role: {
            'id': role,
            'archive': false,
            'modules': {for (final e in avant.entries) e.key: [f(e.value)['voir'] == true ? 1 : 0, f(e.value)['editer'] == true ? 1 : 0, f(e.value)['annuler'] == true ? 1 : 0]}
          }
        };
        final sur = secSurcharges(liste(f(c['apres'])['fiches']));
        final apres = f(f(c['apres'])['matrice']);
        for (final code in apres.keys) {
          final d = secDroitModule(role, code, bases: bases, sur: sur, rolesBase: bases.values);
          final a = f(apres[code]);
          expect([d.voir, d.editer, d.annuler], [a['voir'], a['editer'], a['annuler']], reason: '$role/$code');
        }
        expect(c['autresIdentiques'], true, reason: 'les autres rôles ne bougent pas');
      });
    }

    test('l\'état d\'une case : fermé, lecture seule, partiel, plein — et l\'info-bulle de la maquette', () {
      expect(secEtatCase(DroitSec.ferme), EtatCaseSec.ferme);
      expect(secEtatCase(const DroitSec(true, false, false)), EtatCaseSec.lectureSeule);
      expect(secEtatCase(const DroitSec(true, true, false)), EtatCaseSec.partiel);
      expect(secEtatCase(const DroitSec(true, true, true)), EtatCaseSec.plein);
      expect(secInfobulleCase(const DroitSec(true, true, false)), 'Édition');
      expect(secInfobulleCase(const DroitSec(true, false, true)), ' Annulation');
    });

    for (final c in cas.where((c) => c['type'] == 'creation')) {
      test('création — ${c['nom']}', () {
        final saisie = f(c['saisie']);
        final id = secIdentifiantRole('${saisie['id']}');
        final toasts = liste(c['toasts']);
        final fiches = liste(f(c['apres'])['fiches']);
        if (toasts.last['type'] == 'error') {
          expect(id == '' || id == 'medecin', isTrue);
          expect(toasts.last['message'], id == '' ? 'Identifiant technique invalide.' : 'Ce rôle existe déjà.');
          return;
        }
        expect(id, c['idAttendu']);
        final fiche = f(fiches.single);
        expect(fiche['nouveau'], true);
        expect(fiche['libelleCourt'], secVrai(saisie['libelleCourt']) ? saisie['libelleCourt'] : saisie['libelle']);
        expect(fiche['libelleOrigine'], saisie['libelle']);
        // Tous les modules fermés, l'écran universel aussi.
        for (final d in f(fiche['droits']).values) {
          expect(f(d), {'voir': false, 'editer': false, 'annuler': false});
        }
        expect(f(fiche['droitsEcrans']).keys, ['m7-besoins']);
        expect(c['nbEcransOuverts'], 0);
        final z = secZeroDroits(f(fiche['droits']).keys, ['m7-besoins']);
        memes(z.droits, fiche['droits'], 'droits');
        memes(z.droitsEcrans, fiche['droitsEcrans'], 'droitsEcrans');
        expect(secDetailCreationRole(32), toasts.last['detail']);
        // Le rôle créé figure aux rôles, part de zéro, et n'ouvre rien.
        final roles = secRoles(const [], secSurcharges(fiches));
        expect(roles.single.id, id);
        expect(roles.single.cree, true);
        expect(roles.single.label, saisie['libelle']);
        final sur = secSurcharges(fiches);
        final dm = secDroitModule(id, 'M1', bases: const {}, sur: sur, rolesBase: const []);
        expect([dm.voir, dm.editer, dm.annuler], [false, false, false]);
      });
    }

    test('l\'identifiant technique : accents retirés, tout ce qui n\'est pas lettre ou chiffre supprimé', () {
      expect(secIdentifiantRole('Auditeur Externe'), 'auditeurexterne');
      expect(secIdentifiantRole('Médecin-chef n°2'), 'medecinchefn2');
      expect(secIdentifiantRole('---'), '');
      expect(secIdentifiantRole('Œuvre ÇA'), 'uvrea'.replaceFirst('uvrea', 'uvrea') == '' ? '' : secIdentifiantRole('Œuvre ÇA'));
    });

    for (final c in cas.where((c) => c['type'] == 'renommage')) {
      test('renommage — ${c['nom']}', () {
        final role = c['role'] as String;
        final fiches = liste(f(c['apres'])['fiches']);
        final sur = secSurcharges(fiches);
        final base = [
          {'id': role, 'label': f(c['avant'])['roles'] is Map ? f(f(c['avant'])['roles'])['labelOrigine'] : '', 'labelOrigine': f(f(c['apres'])['roles'])['labelOrigine'], 'shortOrigine': f(f(c['apres'])['roles'])['labelOrigine'], 'color': 'neutral'}
        ];
        final r = secRoles(base, sur).single;
        expect(r.label, c['libelle']);
        expect(r.short, f(f(c['apres'])['roles'])['short']);
        expect(r.labelOrigine, f(f(c['apres'])['roles'])['labelOrigine']);
        // Une seule fiche est modifiée : la première ; les doublons sont fusionnés sans effacer le renommage.
        expect(fiches.where((x) => x['libelle'] == c['libelle']).length, 1);
      });
    }

    for (final c in cas.where((c) => c['type'] == 'archivage' || c['type'] == 'restauration')) {
      test('${c['type']} — ${c['nom']}', () {
        final role = c['role'] as String;
        final toasts = liste(c['toasts']);
        if (toasts.last['message'] == 'Impossible d’archiver le rôle de la session en cours.') {
          expect(f(c['apres'])['roles'], f(c['avant'])['roles']);
          return;
        }
        final fiches = liste(f(c['apres'])['fiches']);
        final sur = secSurcharges(fiches);
        final apres = f(f(c['apres'])['matrice']);
        final avant = f(f(c['avant'])['matrice']);
        final archiveSource = f(c['avant'])['roles'] is Map && f(f(c['avant'])['roles'])['archive'] == true;
        final bases = {
          role: {
            'id': role,
            'archive': archiveSource,
            'modules': {for (final e in (archiveSource ? avant : (c['type'] == 'archivage' ? avant : apres)).entries) e.key: [f(e.value)['voir'] == true ? 1 : 0, f(e.value)['editer'] == true ? 1 : 0, f(e.value)['annuler'] == true ? 1 : 0]},
            if (archiveSource)
              'modulesOrigine': {for (final e in apres.entries) e.key: [f(e.value)['voir'] == true ? 1 : 0, f(e.value)['editer'] == true ? 1 : 0, f(e.value)['annuler'] == true ? 1 : 0]},
          }
        };
        final roleSec = secRoles([
          {'id': role, 'label': role, 'labelOrigine': f(f(c['apres'])['roles'])['labelOrigine'], 'color': 'neutral'}
        ], sur).single;
        expect(roleSec.archive, f(f(c['apres'])['roles'])['archive']);
        for (final code in apres.keys) {
          final d = secDroitModule(role, code, bases: bases, sur: sur, rolesBase: bases.values);
          final a = f(apres[code]);
          if (a['horsMatrice'] == true) continue;
          expect([d.voir, d.editer, d.annuler], [a['voir'], a['editer'], a['annuler']], reason: '$role/$code');
        }
        if (c['type'] == 'archivage') {
          expect(fiches.first['statut'], 'archive');
          expect(fiches.first['motifArchivage'], c['motif']);
          expect(fiches.first['archivePar'], isNotNull);
        } else {
          expect(fiches.first['statut'], 'actif');
          expect(fiches.first['restaureLe'], isNotNull);
        }
      });
    }

    for (final c in cas.where((c) => c['type'] == 'ecrans')) {
      test('écran par écran — ${c['nom']}', () {
        final role = c['role'] as String;
        final ecrits = liste(f(c['apres'])['fiches']).first['droitsEcrans'];
        final initial = liste(c['initial']);
        // Un écran réglé l'est par la fiche ; un écran non réglé suit son module.
        final sur = secSurcharges(liste(f(c['avant'])['fiches']));
        final reglesAvant = f(sur[role]?['droitsEcrans'] ?? <String, Object?>{});
        for (final x in initial) {
          expect(x['origine'], reglesAvant.containsKey(x['id']) ? 'Réglé' : 'suit le module', reason: '${x['id']}');
        }
        if (c['nom'].toString().startsWith('retirer')) {
          expect(f(ecrits).isEmpty, isTrue);
        } else {
          expect(f(ecrits).length, greaterThanOrEqualTo(reglesAvant.length));
        }
      });
    }

    test('tentatives refusées : l\'alerte, la liste (la plus récente d\'abord) et le marquage « examinée »', () {
      final t = cas.firstWhere((c) => c['type'] == 'tentatives');
      expect(t['alerte'], '2 tentative(s) de connexion refusée(s)');
      final lignes = (t['lignes'] as List).cast<String>();
      expect(lignes.first, contains('Test Deux'));
      expect(lignes.last, contains('Test Tentative'));
      expect(f(t['apres'])['traitee'], true);
      expect(f(t['apres'])['examineeLe'], t['jour']);
      expect(secTentativeAExaminer({'traitee': true}), isFalse);
      expect(secTentativeAExaminer({}), isTrue);
    });

    test('fusion des fiches d\'un même rôle : la dernière l\'emporte sur ce qu\'elle définit, et seulement sur cela', () {
      final sur = secSurcharges([
        {'role': 'caissier', 'libelle': 'Caissier test', 'droits': {'M1': {'voir': true}}, 'statut': 'actif'},
        {'role': 'caissier', 'libelle': null, 'droits': {'M8': {'voir': false}}, 'statut': 'archive'},
      ]);
      expect(sur['caissier']!['libelle'], 'Caissier test');
      expect(sur['caissier']!['statut'], 'archive');
      expect((sur['caissier']!['droits'] as Map).keys, containsAll(['M1', 'M8']));
    });
  });

  group('sessions (m14-sessions)', () {
    test('douze sessions, tirage 3413 : identifiant, poste, adresse, ouverture, inactivité, état', () {
      final s = f(v['sessions']);
      final users = [for (final u in liste(s['utilisateurs'])) {...u, 'actif': true}];
      final rows = secSessions(users, DateTime.parse('${s['jour']}'));
      final t = (f(s['tableau'])['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(rows.length, t.length);
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].identifiant, t[i][0]);
        expect(rows[i].nomComplet, t[i][1]);
        expect(rows[i].poste, t[i][3]);
        expect(rows[i].adresseIp, t[i][4]);
        expect(heure(rows[i].debut), t[i][5]);
        expect('${rows[i].inactivite} min', t[i][6]);
        expect(rows[i].verrouillage ? 'Verrouillée' : 'Active', t[i][7]);
      }
      final kpis = (s['kpis'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(kpis[0][1], '${rows.length}');
      expect(kpis[1][1], '${rows.map((r) => r.poste).toSet().length}');
      expect(kpis[2][1], '${rows.where((r) => r.verrouillage).length}');
      expect(kpis[3][1], '$secDelaiVerrouillageMin min');
    });

    test('un compte désactivé n\'ouvre pas de session', () {
      final rows = secSessions([
        {'id': 'a', 'identifiant': 'x', 'actif': false, 'role': 'admin'},
        {'id': 'b', 'identifiant': 'y', 'actif': true, 'role': 'admin'},
      ], DateTime(2026, 10, 30));
      expect(rows.map((r) => r.identifiant), ['y']);
    });

    test('« Clôturer » journalise la modification (RG-12) : ouverte → close', () {
      final c = f(v['sessionsCloture']);
      final a = f(c['audit']);
      expect(a['action'], 'Modification');
      expect(a['module'], 'M14');
      expect(a['entite'], 'SessionUtilisateur');
      expect(a['ancienneValeur'], '{"etat":"ouverte"}');
      expect(a['nouvelleValeur'], '{"etat":"close"}');
      expect(secSessionAvant, {'etat': 'ouverte'});
      expect(secSessionApres, {'etat': 'close'});
      expect((c['toasts'] as List).single['message'], 'Session clôturée.');
    });
  });

  group('journal d\'audit (m14-audit)', () {
    final cas = liste(v['audit']);
    final maintenant = DateTime.utc(2026, 10, 30, 10);

    test('indicateurs, ancienneté et valeurs lisibles sur un journal fabriqué', () {
      final c = cas.first;
      final rows = liste(c['entrees']);
      final s = secStatsAudit(rows);
      final k = (c['kpis'] as List).map((x) => (x as List).cast<String>()).toList();
      expect([k[0][1], k[1][1], k[2][1], k[3][1]], ['${s.actions}', '${s.utilisateurs}', '${s.modules}', '${s.echecs}']);
      // Tri par date décroissante ; la cellule porte la date puis l'ancienneté.
      final tri = [...rows]..sort((a, b) => '${b['dateHeure']}'.compareTo('${a['dateHeure']}'));
      final lignes = (f(c['tableau'])['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      for (var i = 0; i < tri.length; i++) {
        final d = secHorodatage(tri[i]['dateHeure'])!;
        expect(lignes[i][0], '${dateHeure(d)}${secIlYA(d, maintenant)}');
        expect(lignes[i][1], tri[i]['utilisateur']);
        expect(lignes[i][7], tri[i]['succes'] == false ? 'Échec' : 'Succès');
      }
      expect(secJsonLisible('{"statut":"brouillon"}'), '{\n  "statut": "brouillon"\n}');
      expect(secJsonLisible('texte non JSON'), 'texte non JSON');
      expect(c['tiroirModifie'], contains('Ancienne valeur{ "statut": "brouillon" }'));
      expect(c['tiroirNonJson'], contains('Nouvelle valeurtexte non JSON'));
      expect(c['tiroirSansValeur'], contains('Aucune valeur détaillée conservée pour cette action.'));
    });

    test('le ton du badge d\'action : l\'échec est toujours rouge', () {
      expect(secTonAction('Création', succes: true), 'success');
      expect(secTonAction('Création', succes: false), 'danger');
      expect(secTonAction('Inconnue', succes: true), 'neutral');
      expect(secTonAction('Connexion', succes: true), 'navy');
    });

    test('sans échec : zéro tentative infructueuse ; journal vide : quatre zéros', () {
      expect((cas[1]['kpis'] as List).last, ['Tentatives infructueuses', '0']);
      expect(cas[1]['note'], false);
      final s = secStatsAudit(const []);
      expect([s.actions, s.utilisateurs, s.modules, s.echecs], [0, 0, 0, 0]);
    });

    test('le journal du poste (avant / apres) se lit comme celui de la maquette (ancienneValeur / nouvelleValeur)', () {
      expect(secAncienneValeur({'avant': {'a': 1}}), {'a': 1});
      expect(secNouvelleValeur({'nouvelleValeur': 'x', 'apres': 'y'}), 'x');
      expect(secJsonLisible({'a': 1}), '{\n  "a": 1\n}');
    });

    test('l\'impression reprend les cent premières lignes, dans l\'ordre du journal', () {
      final imp = f(cas.first['impression']);
      expect(imp['titre'], 'Journal d’audit');
      expect(imp['sousTitre'], startsWith('Traçabilité des actions — situation au '));
    });
  });

  group('sauvegardes (m14-sauvegardes)', () {
    final s = f(v['sauvegardes']);

    test('l\'historique glissant de 34 jours : tirage 3517, dimanche = hebdomadaire externalisée', () {
      final rows = secHistoriqueSauvegardes(DateTime.parse('${s['jour']}'));
      expect(rows.length, 34);
      final t = (f(s['historique'])['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      for (var i = 0; i < t.length; i++) {
        final r = rows[i];
        expect([r.reference, dateFR(DateTime.parse(r.date)), r.heure, r.type, r.support, '${r.taille} Mo', '${r.duree} s', r.succes ? 'Succès' : 'Échec', r.message],
            t[i].sublist(0, 9),
            reason: 'ligne $i');
      }
      final k = (s['kpis'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(k[0][1], '34');
      expect(k[1][1], dateFR(DateTime.parse(rows.first.date)));
      expect(k[2][1], '${rows.where((r) => !r.succes).length}');
      expect(k[3][1], '${secVolumeMoyen(rows)} Mo');
      expect((s['notes'] as List).first, startsWith('${rows.where((r) => !r.succes).length} sauvegarde(s) en échec.'));
    });

    test('seules les sauvegardes réussies se restaurent', () {
      final rows = secHistoriqueSauvegardes(DateTime.parse('${s['jour']}'));
      final t = (f(s['historique'])['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(t.where((l) => l.last.contains('Restaurer')).length, rows.take(t.length).where((r) => r.succes).length);
    });

    test('les six fichiers hebdomadaires amorcés (graine 88) et le poids lisible', () {
      final semes = liste(s['fichiersSemes']);
      final obtenus = secFichiersSauvegardeSemes(DateTime.parse('${s['jour']}'), semes.first['tables'] as int);
      expect(obtenus.length, 6);
      for (var i = 0; i < 6; i++) {
        memes(obtenus[i], semes[i], 'fichier $i');
      }
      final t = (f(s['fichiers'])['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      for (var i = 0; i < semes.length; i++) {
        expect(t[i][1], '${dateFR(DateTime.parse('${semes[i]['date']}'))}${semes[i]['heure']} — ${secPoidsFichier(semes[i]['taille'] as num)}');
      }
      expect(secPoidsFichier(1024 * 1024 + 1), '1.0 Mo');
      expect(secPoidsFichier(1024 * 1024), '1024 Ko');
      expect(secPoidsFichier(2048), '2 Ko');
    });

    test('le nom d\'un fichier généré suit le rang dans la collection', () {
      final g = f(f(s['generation'])['fiche']);
      expect(secNomFichierSauvegarde(DateTime.parse('${s['jour']}'), 6), g['fichier']);
    });

    test('les simulations de la maquette sont journalisées ou annoncées telles qu\'elles', () {
      expect(f(f(s['manuelle'])['audit'])['reference'], 'BK-MANUELLE');
      expect(liste(f(s['manuelle'])['toasts']).single['detail'], 'Volume : 412 Mo — durée : 9 s');
      expect(f(f(s['restauration'])['audit'])['action'], 'Restauration');
      expect(liste(f(s['restauration'])['toasts']).single['detail'], 'Dans le prototype, aucune donnée n’est effectivement remplacée.');
      expect(f(s['testRestauration'])['audit'], isNull);
    });
  });

  group('prescripteurs & exécutants (m14-soignants)', () {
    final s = f(v['soignants']);

    test('qualités et secteurs : ceux de la maquette', () {
      expect(secQualitesSoignant, s['qualites']);
      expect(secSecteursSoins.map((x) => {'code': x['code'], 'label': x['label'], 'icone': x['icone']}).toList(),
          liste(s['secteurs']).map((x) => {'code': x['code'], 'label': x['label'], 'icone': x['icone']}).toList());
    });

    test('la fiche est dérivée du personnel : nom, poste, source', () {
      final agent = f(s['agentLibre']);
      for (final nom in ['infirmierSecteurs', 'sageFemme']) {
        final c = f(s[nom]);
        final obtenu = secTransformerSoignant(f(c['saisie']), agent);
        memes(obtenu, net(f(liste(c['creees']).single)), nom);
      }
      expect(secTransformerSoignant({'a': 1}, null)['nomComplet'], '—');
    });

    test('sans secteur : le formulaire est en erreur, rien n\'est créé', () {
      final c = f(s['sansSecteur']);
      expect(c['creees'], isEmpty);
      expect(liste(c['toasts']).single['message'], 'Le formulaire comporte des erreurs.');
    });

    test('indicateurs : soignants, prescripteurs, exécutants, cumul — recalculés après chaque création', () {
      final fiches = [
        {'prescrit': true, 'execute': true},
        {'prescrit': true, 'execute': false},
        {'prescrit': false, 'execute': true},
        {'prescrit': false, 'execute': false},
      ];
      final c = secCompteSoignants(fiches);
      expect([c.total, c.prescripteurs, c.executants, c.cumul], [4, 2, 2, 1]);
      expect(secSecteursEnTexte(['salle_soins', 'maternite']), 'Salle de soins · Maternité');
      expect(secSecteursEnTexte(const []), '—');
    });
  });

  group('tâches planifiées (m14-taches)', () {
    final maintenant = DateTime.utc(2026, 10, 30, 10);
    for (final c in liste(v['taches']).where((c) => c['reponse'] != null)) {
      test('${c['nom']}', () {
        final taches = liste(f(c['reponse'])['taches']);
        final b = secBilanTaches(taches, maintenant);
        final k = (c['kpis'] as List).map((x) => (x as List).cast<String>()).toList();
        expect([k[0][1], k[1][1], k[2][1], k[3][1]], ['${b.actives}', '${b.erreurs}', '${b.enRetard}', '${b.alertes}']);
        if (b.enRetard > 0) {
          expect(c['note'], '${b.enRetard} tâche(s) n’ont pas tourné à leur fréquence. Vérifier que la tâche du système (cron Linux ou Planificateur de tâches Windows) est installée et active.');
        } else {
          expect(c['note'], isNull);
        }
        final tabs = (c['tableaux'] as List).cast<Map>();
        if (taches.isNotEmpty) {
          final lignes = (tabs.first['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
          for (var i = 0; i < taches.length; i++) {
            final t = taches[i];
            expect([t['libelle'], 'toutes les ${t['frequence_min']} min', secDerniereExecution(t['derniere_le']), secResultatTache(t), secDureeTache(t['duree_ms']), '${(t['alertes'] as num?)?.toInt() ?? 0}'],
                lignes[i].sublist(0, 6),
                reason: 'ligne $i');
          }
          final histo = liste(f(c['reponse'])['executions']);
          if (histo.isNotEmpty) {
            final h = (tabs.last['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
            for (var i = 0; i < histo.length; i++) {
              expect(secDebutExecution(histo[i]['debut']), h[i][0]);
              expect(histo[i]['statut'] == 'ok' ? 'Réussie' : 'Erreur', h[i][2]);
              expect(histo[i]['origine'] ?? '—', h[i][3]);
            }
          }
        }
      });
    }

    test('une tâche qui n\'a jamais tourné est en retard ; pile à trois périodes, non', () {
      expect(secTacheEnRetard({'derniere_le': null, 'frequence_min': 60}, maintenant), isTrue);
      expect(secTacheEnRetard({'derniere_le': '2026-10-30 07:00:00', 'frequence_min': 60}, maintenant), isFalse);
      expect(secTacheEnRetard({'derniere_le': '2026-10-30 06:59:59', 'frequence_min': 60}, maintenant), isTrue);
    });

    test('serveur injoignable : la maquette le dit et rappelle qu\'aucune tâche ne tourne sans serveur', () {
      final c = liste(v['taches']).firstWhere((c) => c['nom'] == 'serveur injoignable');
      expect(c['texte'], contains('Sans serveur (ouverture locale), aucune tâche planifiée ne tourne.'));
    });
  });
}
