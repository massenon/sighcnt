// L'espace « Mes » (lot L7) et le pointage par badge (lot L8) : rejoue les vecteurs engendrés par les moteurs de la maquette
// (prototype_html/build/vecteurs-mes-pointage.js) sur les MÊMES entrées : lecture des dix-sept rubriques, copie de la fiche de paie pour le téléphone, assurance du
// personnel sans prix courant, refus nommés (code, motif, geste) du pointage par badge, réglages.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();

void main() {
  final j = lireVecteurs('mes_pointage');
  final monde = m(j['monde']);
  final personnel = liste(monde['personnel']);
  final personnelActif = [for (final e in personnel) if (e['statut'] != 'archive') e];
  final collections = {
    for (final e in m(monde['collections']).entries) e.key: [for (final f in liste(e.value)) if (f['statut'] != 'archive') f]
  };
  final notes = [for (final x in (monde['notes'] as List)) '$x'];

  group('les dix-sept rubriques', () {
    test('le catalogue est celui du PRD M10, dans l\'ordre, comme à la maquette', () {
      final v = liste(j['rubriques']);
      expect(rubriquesMes.length, 17);
      expect(v.length, rubriquesMes.length);
      for (var i = 0; i < v.length; i++) {
        final r = rubriquesMes[i];
        expect([r.n, r.id, r.libelle, r.ecran, r.source, r.lien, r.calcule, r.emise, r.sensible, r.lectureSeule],
            [v[i]['n'], v[i]['id'], v[i]['libelle'], v[i]['ecran'], v[i]['source'], v[i]['lien'], v[i]['calcule'], v[i]['emise'], v[i]['sensible'], v[i]['lectureSeule']],
            reason: '${v[i]['id']}');
      }
    });
  });

  group('lire une rubrique : l\'agent de la session, et aucun autre (RG-13)', () {
    for (final c in liste(j['lectures'])) {
      test(c['nom'] as String, () {
        final r = lireMes(rubriqueId: c['rubrique'], acteur: c['acteur'] as String, personnelActif: personnelActif, collections: collections, notes: notes);
        final a = m(c['attendu']);
        expect(r.ok, a['ok']);
        if (a['ok'] == true) {
          expect(r.rubrique, a['rubrique']);
          expect(r.agentId, a['agentId']);
          expect(r.lectureSeule, a['lectureSeule']);
          expect(r.ids, [for (final x in (a['ids'] as List)) '$x']);
          expect(r.total, a['total']);
          expect(r.valeur, a['valeur']);
          expect(r.sansMontant, a['sansMontant']);
          expect(r.presents, a['presents']);
          expect(r.retards, a['retards']);
          expect(r.absents, a['absents']);
        } else {
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [a['code'], a['motif'], a['geste']]);
        }
      });
    }
  });

  group('la copie de la fiche de paie pour le téléphone : les pièces émises de l\'agent demandeur seul', () {
    for (final c in liste(j['copies'])) {
      test(c['nom'] as String, () {
        final r = copiePaieAgent(
            actif: c['actif'] as bool, acteur: c['acteur'] as String, personnelActif: personnelActif, bulletins: collections['bulletins']!, agentIdDemande: c['agentIdDemande']);
        final a = m(c['attendu']);
        expect(r.ok, a['ok']);
        if (a['ok'] == true) {
          expect(r.agentId, a['agentId']);
          expect(r.ids, [for (final x in (a['ids'] as List)) '$x']);
          expect(r.references, [for (final x in (a['references'] as List)) '$x']);
          expect(r.total, a['total']);
          expect([r.chiffree, r.recalculee], [a['chiffree'], a['recalculee']]);
        } else {
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste], [a['code'], a['motif'], a['geste']]);
        }
      });
    }
    for (final c in liste(j['reglagesCopie'])) {
      test('réglage de la copie par le rôle « ${c['role']} »', () {
        final r = controlerReglageCopiePaie(c['role'] as String);
        final a = m(c['attendu']);
        expect(r == null, a['ok']);
        if (r != null) expect([r.code, r.motif, r.geste], [a['code'], a['motif'], a['geste']]);
      });
    }
    test('jamais une copie d\'une pièce non émise : ni validée non diffusée, ni à valider, ni archivée', () {
      final r = copiePaieAgent(
          actif: true,
          acteur: personnelActif.first['nomComplet'] as String,
          personnelActif: personnelActif,
          bulletins: [
            {'id': 'X1', 'employeId': personnelActif.first['id'], 'statutBulletin': 'valide', 'reference': 'X1'},
            {'id': 'X2', 'employeId': personnelActif.first['id'], 'statutBulletin': 'a_valider', 'reference': 'X2'},
          ]);
      expect(r.ids, isEmpty);
    });
  });

  group('« Mon assurance du personnel » : non renseigné, jamais le prix courant', () {
    test('un montant porté est un nombre ; son absence est null, 0 est un montant', () {
      expect([montantPorte(null), montantPorte(''), montantPorte('abc'), montantPorte(0), montantPorte('1500'), montantPorte(2000)], [null, null, null, 0, 1500, 2000]);
    });
  });

  group('le pointage par badge : refus nommés et fiches écrites (vecteurs de la maquette)', () {
    final badges = liste(m(j['pointage'])['badges']);
    final agents = liste(m(j['pointage'])['personnel']);
    for (final c in liste(m(j['pointage'])['cas'])) {
      test(c['nom'] as String, () {
        final r = pointerParBadge(
            role: c['role'] as String,
            actif: c['actif'] as bool,
            delai: c['delai'] as int,
            texte: c['texte'] as String,
            jour: c['jour'] as String,
            heure: c['heure'] as String,
            badges: badges,
            personnel: agents,
            presences: liste(c['presences']),
            acteur: c['acteur'] as String,
            aujourdhui: c['aujourdhui'] as String);
        final a = m(c['attendu']);
        expect(r.ok, a['ok']);
        if (a['ok'] == true) {
          expect([r.geste, r.agentId, r.badgeId, r.heure, r.etat], [a['geste'], a['agentId'], a['badgeId'], a['heure'], a['etat']]);
          if (a['geste'] == 'arrivee') {
            memes(r.creation, a['creation'], 'creation');
            expect(r.patch, isNull);
          } else {
            memes(r.patch, a['patch'], 'patch');
            expect(r.creation, isNull);
          }
        } else {
          final extra = r.refus!.extra['delai'];
          expect([r.refus!.code, r.refus!.motif, r.refus!.geste, extra], [a['code'], a['motif'], a['geste'], a['delai']]);
        }
      });
    }
  });

  group('les réglages du pointage (délai en base, entier de 0 à 720)', () {
    for (final c in liste(m(j['pointage'])['reglages'])) {
      test(c['nom'] as String, () {
        final o = m(c['options']);
        final courant = m(c['courant']);
        final delaiPasse = o.containsKey('delai') ? o['delai'] : courant['delai'];
        final refus = controlerReglagePointageBadge(role: c['role'] as String, delai: delaiPasse);
        final a = m(c['attendu']);
        expect(refus == null, a['ok']);
        if (refus != null) {
          expect([refus.code, refus.motif, refus.geste], [a['code'], a['motif'], a['geste']]);
          expect(m(a['enBase']), {'actif': courant['actif'], 'delai': courant['delai']}, reason: 'refusé : rien n\'est écrit');
        } else {
          final delai = delaiPasse is num ? delaiPasse.toInt() : int.parse('$delaiPasse');
          final actif = o.containsKey('actif') ? o['actif'] == true : courant['actif'] == true;
          expect([actif, delai], [a['actif'], a['delai']]);
        }
      });
    }
    test('le défaut de 5 minutes est une proposition à valider, déclarée au registre', () {
      expect(delaiPointageBadgeDefaut, 5);
      final d = definitionDeParametre('planning.delaiEntrePointagesBadge')!;
      expect([d.defaut, d.type, d.branche, d.mobile], [5, TypeParametre.entier, true, false]);
      expect(d.source, contains('Proposition à valider'));
    });
    test('les paramètres de la copie et du badge sont branchés ; la famille « paie » reste fermée au téléphone', () {
      for (final cle in ['paie.copieFichePaieTelephone', 'planning.badgeSertDePointage', 'planning.delaiEntrePointagesBadge']) {
        final d = definitionDeParametre(cle)!;
        expect(d.branche, isTrue, reason: cle);
        expect(Parametres.autoriseMobile(Parametres.semer(d).toJson()), isFalse, reason: '$cle ne va jamais à un téléphone par la liste blanche');
      }
      expect(parFamillesJamaisMobile, contains('paie'));
    });
  });
}
