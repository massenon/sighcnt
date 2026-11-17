// Lot SURV (16/11/2026) : la fiche de l'équipe et le périmètre d'équipe. Rejoue les vecteurs engendrés par le moteur de la maquette
// (prototype_html/build/vecteurs-fiche-equipe.js) sur les MÊMES entrées, puis éprouve la liste blanche et la portée de la valeur d'attente.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

Map<String, Object?> m(Object? x) => (x as Map).cast<String, Object?>();
Map<String, Object?>? mn(Object? x) => x == null ? null : m(x);

PorteePersonnel portee(Map<String, Object?> c) => porteePersonnelRh(lectureComplete: c['lectureComplete'] as bool, geste: c['geste'] as bool);

Map<String, Object?>? refusJson(RefusRh? r) => r == null ? null : {'code': r.code, 'motif': r.motif, 'geste': r.geste};

void main() {
  final j = lireVecteurs('fiche_equipe');

  test('le geste et l\'écran sont ceux du manifeste, la liste blanche est celle de la maquette', () {
    expect(gesteFicheEquipe, 'ouvrir_fiche_personnel_equipe');
    expect(ecranFicheEquipe, 'm10-fiche-equipe');
    expect(champsFicheEquipeRh, m(j['defauts'])['champsBlancs']);
  });

  group('la fiche d\'un agent, lue depuis l\'équipe (vecteurs de la maquette)', () {
    for (final c in liste(j['cas'])) {
      test(c['nom'] as String, () {
        expect(portee(c).nom, c['portee']);
        final r = ficheEquipeRh(portee: portee(c), agent: mn(c['agent']), moi: mn(c['moi']));
        final a = m(c['attendu']);
        expect(r.refus == null, a['ok'], reason: 'ok');
        memes(refusJson(r.refus), a['refus'], 'refus');
        memes(r.fiche, a['fiche'], 'fiche');
      });
    }
  });

  group('l\'équipe de la session (vecteurs de la maquette)', () {
    for (final c in liste(j['equipes'])) {
      test(c['nom'] as String, () {
        final r = equipeDeLaSessionRh(portee: portee(c), personnelActif: liste(j['personnelActif']), moi: mn(c['moi']));
        final a = m(c['attendu']);
        expect(r.refus == null, a['ok'], reason: 'ok');
        memes(refusJson(r.refus), a['refus'], 'refus');
        if (a['ok'] == true) memes(r.agents, a['agents'], 'agents');
      });
    }
  });

  group('le périmètre seul (vecteurs de la maquette)', () {
    for (final c in liste(j['perimetres'])) {
      test(c['nom'] as String, () {
        final r = controlerPerimetreEquipeRh(portee: portee(c), agent: m(c['agent']), moi: mn(c['moi']));
        memes(refusJson(r), c['attendu'], 'refus');
      });
    }
  });

  group('la lecture restreinte ne porte jamais la paie', () {
    final agent = <String, Object?>{
      'id': 'E1', 'matricule': '001', 'nomComplet': 'A B', 'sexe': 'F', 'fonction': 'infirmier', 'poste': 'IDE', 'service': 'S',
      'salaireBase': 150000, 'categorie': 'E3-1', 'dateEmbauche': '2015-01-01', 'cnss': '123', 'telephone': '97000000', 'assurance': 'X', 'champInconnuDemain': 'secret', 'valeursAttente': {'cnss': true},
    };
    test('liste BLANCHE : un champ ajouté demain ne fuit pas', () {
      final p = projeterFicheEquipeRh(agent);
      expect(p.keys.toSet(), champsFicheEquipeRh.toSet());
      for (final interdit in ['salaireBase', 'categorie', 'dateEmbauche', 'cnss', 'telephone', 'assurance', 'champInconnuDemain', 'valeursAttente']) {
        expect(p.containsKey(interdit), isFalse, reason: interdit);
      }
    });
    test('la portée « équipe » ne lit ni ne confirme une valeur d\'attente ; la portée complète oui', () {
      expect(controlerPorteeValeurAttenteRh(PorteePersonnel.equipe)?.code, 'VALEUR_ATTENTE_HORS_PORTEE');
      expect(controlerPorteeValeurAttenteRh(PorteePersonnel.aucune)?.code, 'VALEUR_ATTENTE_HORS_PORTEE');
      expect(controlerPorteeValeurAttenteRh(PorteePersonnel.complete), isNull);
    });
    test('la portée vient des droits, dans cet ordre : lecture complète, puis geste, sinon aucune', () {
      expect(porteePersonnelRh(lectureComplete: true, geste: true), PorteePersonnel.complete);
      expect(porteePersonnelRh(lectureComplete: true, geste: false), PorteePersonnel.complete);
      expect(porteePersonnelRh(lectureComplete: false, geste: true), PorteePersonnel.equipe);
      expect(porteePersonnelRh(lectureComplete: false, geste: false), PorteePersonnel.aucune);
    });
  });

  group('l\'écran est ouvert PAR LE GESTE (matrice recalculée à chaud, jamais une liste de rôles)', () {
    final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
    final base = MatriceDroits.depuisJson(brut);
    final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
    final jeuRbac = [for (final f in jsonDecode(File('../../apps/poste/assets/donnees/jeu/rbac.json').readAsStringSync()) as List) (f as Map).cast<String, Object?>()];
    final modules = [for (final f in jsonDecode(File('../../apps/poste/assets/donnees/jeu/modulesActifs.json').readAsStringSync()) as List) (f as Map).cast<String, Object?>()]
        .where((f) => f['proprePoste'] != true)
        .toList();
    MatriceDroits calc(List<Map<String, Object?>> rbac) => superposerDroits(base, manifeste, rbac: rbac, modulesActifs: modules, referenceRbac: jeuRbac, referenceModules: modules);
    Map<String, Object?> fiche(String role, Map<String, Object?> droitsGestes) => {'id': 'RBAC-$role', 'role': role, 'statut': 'actif', 'droitsGestes': droitsGestes};
    List<Map<String, Object?>> sansFiche(String role) => [for (final f in jeuRbac) if (f['role'] != role) f];

    test('le manifeste déclare l\'écran par son geste', () {
      expect(manifeste.ecran(ecranFicheEquipe)?.parGeste, gesteFicheEquipe);
      expect(manifeste.ecran('m10-employe-profil')?.parGeste, isNull);
    });
    test('d\'origine : le Surveillant seul voit l\'écran (lecture seule), pas la fiche complète ni la liste du personnel', () {
      final mat = calc(jeuRbac);
      for (final r in ['surveillant']) {
        expect(mat.peutVoir(r, ecranFicheEquipe), isTrue);
        expect(mat.peutEditer(r, ecranFicheEquipe), isFalse);
        expect(mat.droit(r, ecranFicheEquipe).annuler, isFalse);
        expect(mat.peutVoir(r, 'm10-employe-profil'), isFalse);
        expect(mat.peutVoir(r, 'm10-personnel'), isFalse);
      }
      for (final r in ['infirmier', 'medecin', 'caissier', 'rh']) {
        expect(mat.peutVoir(r, ecranFicheEquipe), isFalse, reason: r);
      }
      expect(mat.droitGeste('surveillant', gesteFicheEquipe), isTrue);
    });
    test('retirer le geste au Surveillant FERME l\'écran et le geste ; l\'attribuer à un autre rôle le lui OUVRE ; une fiche créée part de zéro', () {
      final sans = calc([...sansFiche('surveillant'), fiche('surveillant', {gesteFicheEquipe: false})]);
      expect(sans.peutVoir('surveillant', ecranFicheEquipe), isFalse);
      expect(sans.droitGeste('surveillant', gesteFicheEquipe), isFalse);
      expect(sans.ecransVisibles('surveillant').contains(ecranFicheEquipe), isFalse);
      final autre = calc([...sansFiche('infirmier'), fiche('infirmier', {gesteFicheEquipe: true})]);
      expect(autre.peutVoir('infirmier', ecranFicheEquipe), isTrue);
      expect(autre.peutEditer('infirmier', ecranFicheEquipe), isFalse);
      expect(autre.peutVoir('infirmier', 'm10-employe-profil'), isFalse);
      expect(calc(jeuRbac).peutVoir('infirmier', ecranFicheEquipe), isFalse, reason: 'fiches restaurées : l\'infirmier ne l\'a plus');
    });
    test('une surcharge d\'ÉCRAN qui ferme nommément l\'écran garde la main, comme à la maquette', () {
      final f = {
        ...fiche('surveillant', {gesteFicheEquipe: true}),
        'droitsEcrans': {ecranFicheEquipe: {'voir': false}}
      };
      final mat = calc([...sansFiche('surveillant'), f]);
      expect(mat.peutVoir('surveillant', ecranFicheEquipe), isFalse);
    });
  });
}
