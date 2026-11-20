// Rejoue les vecteurs engendrés par la maquette (prototype_html/build/vecteurs-sessions.js) : « Clôturer » change le statut d'une session, et l'écran
// « Sécurité des utilisateurs » (politique, comptes bloqués, réinitialisation imposée). Les écrans réels sont pilotés dans Chrome.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef F = Map<String, Object?>;

F f(Object? x) => (x as Map).cast<String, Object?>();

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Le motif d'un refus « déjà clôturée » porte la date et l'heure de la clôture : on les neutralise.
String sansDate(String s) => s.replaceAll(RegExp(r'le \d\d/\d\d/\d{4} à \d\dh\d\d'), 'le <D>');

void main() {
  final v = lireVecteurs('sessions_securite');
  final maintenant = DateTime(2026, 11, 1, 16, 40);

  group('sessions : le jeu de démonstration amorcé par l\'écran', () {
    final comptes = [for (final c in liste(v['comptes'])) f(c)];
    final attendues = liste(v['demoFiches']);

    test('douze fiches, mêmes valeurs que la maquette (graine 3413), suspendue à partir de quinze minutes d\'inactivité', () {
      final fiches = secSessionsDemonstration(comptes, maintenant);
      expect(fiches.length, 12);
      for (var i = 0; i < 12; i++) {
        final a = attendues[i];
        final o = fiches[i];
        for (final k in ['id', 'utilisateurId', 'identifiant', 'nomComplet', 'role', 'poste', 'adresseIp', 'inactivite', 'etat', 'source', 'statut']) {
          expect(o[k], a[k], reason: '${a['id']}.$k');
        }
        expect(hhmm(DateTime.parse('${o['debut']}')), a['heureDebut'], reason: '${a['id']} heure');
        expect(o['etat'], (o['inactivite'] as int) >= 15 ? 'suspendue' : 'active');
      }
    });

    test('les indicateurs de l\'ouverture : sessions ouvertes, postes distincts, verrouillées, clôturées', () {
      final moi = f(f(v['ouverture'])['moi']);
      final fiches = [
        ...secSessionsDemonstration(comptes, maintenant),
        {...secNouvelleSession(identifiant: '${moi['identifiant']}', nomComplet: '${moi['nomComplet']}', role: '${moi['role']}', poste: 'localhost', maintenant: maintenant), 'id': 'SESmoi'},
      ];
      final k = secKpisSessions(secLignesSessions(fiches));
      final attendus = {for (final x in (f(v['ouverture'])['kpis'] as List)) (x as List)[0]: x[1]};
      expect('${k.ouvertes}', attendus['Sessions ouvertes']);
      // La maquette compte ici le poste de la session réelle ; le test ne distingue pas son nom d'hôte (le poste « localhost » s'ajoute aux sept postes de démonstration).
      expect('${k.postes}', attendus['Postes distincts']);
      expect('${k.suspendues}', attendus['Verrouillées pour inactivité']);
      expect('${k.cloturees}', attendus['Clôturées']);
    });
  });

  group('« Clôturer » : le moteur de la maquette, cas par cas', () {
    final comptes = [for (final c in liste(v['comptes'])) f(c)];
    final fiches = <String, F>{
      for (final x in secSessionsDemonstration(comptes, maintenant)) '${x['id']}': x,
    };
    final sessionPropre = '${f(v['ouverture'])['sessionId']}';
    final moi = f(f(v['ouverture'])['moi']);
    fiches[sessionPropre] = {
      ...secNouvelleSession(identifiant: '${moi['identifiant']}', nomComplet: '${moi['nomComplet']}', role: '${moi['role']}', poste: 'localhost', maintenant: maintenant),
      'id': sessionPropre,
    };
    for (final c in liste(v['cas'])) {
      final nom = '${c['nom']}';
      test(nom, () {
        final id = '${c['id']}';
        final op = c['opts'] == null ? <String, Object?>{} : f(c['opts']);
        final acteur = SecActeurSession(role: '${c['role']}', identifiant: 'c.bassongui', nom: 'BASSONGUI Chabi Séko', sessionId: sessionPropre);
        final fiche = fiches[id];
        final r = secCloturerSession(
            fiche: fiche,
            acteur: acteur,
            droitEditer: '${c['role']}' == 'admin',
            confirmePropre: op['confirmePropre'] == true,
            motif: op['motif'] as String?,
            maintenant: maintenant);
        final attendu = f(c['resultat']);
        expect(r.ok, attendu['ok'], reason: nom);
        if (!r.ok) {
          expect(r.refus!.code, attendu['code']);
          expect(sansDate(r.refus!.motif), sansDate('${attendu['motif']}'));
          expect(r.refus!.geste, attendu['geste']);
          return;
        }
        final p = f(c['patch']);
        expect(r.patch['etat'], p['etat']);
        expect(r.patch['clotureLe'], isNotNull);
        expect(r.patch['cloturePar'], p['cloturePar']);
        expect(r.patch['clotureParIdentifiant'], p['clotureParIdentifiant']);
        expect(r.patch['clotureMotif'], p['clotureMotif']);
        expect(r.patch['cloturePropre'], p['cloturePropre']);
        fiches[id] = {...fiche!, ...r.patch};
      });
    }
  });

  group('la confirmation de l\'écran', () {
    final g = f(v['geste']);
    test('session d\'un autre agent : titre, message et bouton de la modale de la maquette', () {
      final c = f(g['confirmation']);
      final nom = '${c['titre']}'.replaceFirst('Clôturer la session de ', '').replaceFirst(' ?', '');
      final poste = RegExp(r'poste (POSTE-\w+)').firstMatch('${c['texte']}')!.group(1)!;
      final r = secConfirmationCloture(nomComplet: nom, poste: poste, propre: false);
      expect(r.titre, c['titre']);
      expect('${c['texte']}', contains(r.message));
      expect(c['boutons'], contains(r.libelleOk));
    });
    test('session propre : la maquette le DIT et change le libellé du bouton', () {
      final c = f(g['confirmationPropre']);
      final r = secConfirmationCloture(nomComplet: 'peu importe', poste: 'peu importe', propre: true);
      expect(r.titre, c['titre']);
      expect('${c['texte']}', contains(r.message));
      expect(c['boutons'], contains(r.libelleOk));
    });
    test('après la clôture : le statut, l\'auteur, les indicateurs, le filtre', () {
      expect(f(g['fiche'])['etat'], 'cloturee');
      expect(f(g['fiche'])['cloturePropre'], false);
      expect(f(g['fiche'])['statut'], 'actif', reason: 'rien n\'est archivé ni supprimé (RG-14)');
      expect(g['boutonApres'], false);
      expect(g['filtreClotures'], 1);
      expect(g['filtreOuvertes'], 12);
      expect(((g['toasts'] as List).first as Map)['message'], 'Session clôturée.');
    });
  });

  group('politique de sécurité', () {
    test('les valeurs de référence', () {
      expect(secPolitiqueDefaut, {for (final e in f(f(v['secOuverture'])['defaut']).entries) if (secPolitiqueDefaut.containsKey(e.key)) e.key: e.value});
      expect(secPolitique(null), secPolitiqueDefaut);
    });

    test('les six paramètres : libellé, unité, bornes, source et application', () {
      final p = liste(f(v['secOuverture'])['parametres']);
      expect(secParametresPolitique.length, p.length);
      for (var i = 0; i < p.length; i++) {
        final d = secParametresPolitique[i];
        expect([d.cle, d.libelle, d.unite, d.min, d.max, d.source, d.application],
            [p[i]['cle'], p[i]['libelle'], p[i]['unite'], p[i]['min'], p[i]['max'], p[i]['source'], p[i]['application']]);
      }
      expect(secParametresPolitique.firstWhere((x) => x.cle == 'historique').source, startsWith('Proposition à valider'));
    });

    for (final c in liste(v['politiqueCas'])) {
      test('valeurs : ${c['nom']}', () {
        final r = secValiderPolitique({...secPolitiqueDefaut, ...f(c['valeurs'])});
        final a = f(c['resultat']);
        expect(r.ok, a['ok']);
        if (!r.ok) {
          expect(r.refus!.code, a['code']);
          expect(r.refus!.motif, a['motif']);
          expect(r.refus!.geste, a['geste']);
        } else {
          expect(r.patch['inactiviteMin'], f(c['politique'])['inactiviteMin']);
        }
      });
    }
  });

  group('comptes : bloquer, débloquer, imposer la réinitialisation', () {
    final pol = Map<String, int>.from(secPolitiqueDefaut);
    var u = <String, Object?>{'id': '${v['idDemo']}', 'identifiant': 'demo.anesthesiste', 'echecs': 0};
    final admin = const SecActeurCompte(identifiant: 'c.bassongui', nom: 'BASSONGUI Chabi Séko');
    final lui = const SecActeurCompte(identifiant: 'demo.anesthesiste', nom: 'Compte à pourvoir');
    for (final c in liste(v['comptesCas'])) {
      final nom = '${c['nom']}';
      test(nom, () {
        if (nom == 'débloquer un compte bloqué par ses échecs') u = {...u, 'echecs': 3};
        final fiche = '${f(c['resultat'])['code']}' == 'COMPTE_INCONNU' ? null : u;
        ResultatSec r;
        if (nom.startsWith('bloquer')) {
          final motif = nom == 'bloquer sans motif' ? '  ' : (nom == 'bloquer avec motif' ? '  Départ du poste  ' : (nom == 'bloquer deux fois' ? 'encore' : (nom == 'bloquer son propre compte' ? 'essai' : 'motif')));
          r = secBloquerCompte(fiche, motif: motif, acteur: nom == 'bloquer son propre compte' ? lui : admin, politique: pol, maintenant: maintenant);
        } else if (nom.startsWith('débloquer')) {
          r = secDebloquerCompte(fiche, acteur: admin, politique: pol, maintenant: maintenant);
        } else {
          r = secImposerReinitialisation(fiche, acteur: admin, maintenant: maintenant);
        }
        final a = f(c['resultat']);
        expect(r.ok, a['ok'], reason: nom);
        if (!r.ok) {
          expect(r.refus!.code, a['code']);
          expect(r.refus!.motif, a['motif']);
          expect(r.refus!.geste, a['geste']);
          return;
        }
        final diff = f(c['diff']);
        // Les clés du patch sont celles que la maquette a écrites (la maquette ne ré-écrit pas `echecs` quand il valait déjà zéro).
        for (final e in diff.entries) {
          if (e.value == '<date>') {
            expect(r.patch[e.key], isNotNull, reason: e.key);
          } else {
            expect(r.patch[e.key], e.value, reason: e.key);
          }
        }
        // Une clé que la maquette n'a pas changée est une clé qui valait déjà la valeur du patch.
        for (final k in r.patch.keys) {
          if (diff.containsKey(k)) continue;
          expect(u[k] ?? (k == 'echecs' ? 0 : false), r.patch[k], reason: 'clé changée sans que la maquette la change : $k');
        }
        u = {...u, ...r.patch};
      });
    }

    test('expiration du mot de passe : jours restants et réinitialisation, sur dates relatives', () {
      // Le vecteur est tiré avec une horloge lue une milliseconde AVANT les dates (la maquette lit `AUJ` au chargement du module) : le plancher donne un jour de moins.
      final reference = DateTime(2026, 11, 1, 12);
      final aujourdhui = reference.subtract(const Duration(milliseconds: 1));
      for (final e in liste(v['expiration'])) {
        final age = e['age'] as int?;
        final fiche = <String, Object?>{
          if (age != null) 'motDePasseDefiniLe': reference.subtract(Duration(days: age)).toIso8601String(),
          if (e['imposee'] == true) 'doitChangerMotDePasse': true,
        };
        expect(secJoursAvantExpiration(fiche, pol, aujourdhui), e['restant'], reason: 'âge $age');
        expect(secAReinitialiser(fiche, pol, aujourdhui), e['reinit'], reason: 'âge $age');
      }
    });

    test('un compte est bloqué à partir de trois échecs, ou à la main', () {
      for (final b in liste(v['bloquage'])) {
        expect(secEstBloque({'echecs': b['echecs'], 'bloque': b['bloque']}, pol), b['attendu'], reason: '$b');
      }
      expect(secEstBloque({'echecs': 0}, pol, verrouEnCours: true), isTrue, reason: 'le verrou après échecs du poste bloque aussi');
    });

    test('double facteur exigé : administrateur, Direction, DAF et Directeur Médical', () {
      expect(f(v['secOuverture'])['rolesDoubleFacteur'], secRolesDoubleFacteur);
      expect(secDoubleFacteurExige('direction'), isTrue);
      expect(secDoubleFacteurExige('caissier'), isFalse);
    });

    test('clôturer les sessions d\'un compte : aucune session, ou la sienne, sont refusées en le disant', () {
      expect(secRefusCloturerSessionsCompte([]) ?.code, 'AUCUNE_SESSION');
      expect(secRefusCloturerSessionsCompte([{'id': 'A'}], sessionPropre: 'A')?.code, 'SESSION_PROPRE');
      expect(secRefusCloturerSessionsCompte([{'id': 'B'}], sessionPropre: 'A'), isNull);
    });
  });

  group('l\'écran Sécurité des utilisateurs : la maquette', () {
    final o = f(v['secOuverture']);
    test('six indicateurs, quatre onglets, huit lignes de politique', () {
      expect([for (final k in o['kpis'] as List) (k as List)[0]], [
        'Comptes actifs',
        'Comptes bloqués',
        'Mots de passe à renouveler',
        'Double facteur manquant',
        'Tentatives refusées',
        'Sessions ouvertes'
      ]);
      expect([for (final t in o['onglets'] as List) '$t'.replaceAll(RegExp(r'\d+$'), '')], ['Politique', 'Comptes', 'Tentatives de connexion', 'Sessions']);
      expect((f(o['politique'])['lignes'] as List).length, 8);
    });
  });
}
