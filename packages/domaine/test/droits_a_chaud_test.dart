import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

List<Fiche> _lire(String chemin) => [for (final f in jsonDecode(File(chemin).readAsStringSync()) as List) (f as Map).cast<String, Object?>()];

/// Droits À CHAUD : la matrice recalculée depuis le manifeste, la collection `rbac` et `modulesActifs`, comme `N.can()` / `N.droits()` de la maquette.
void main() {
  final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final base = MatriceDroits.depuisJson(brut);
  final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
  final jeuRbac = _lire('../../apps/poste/assets/donnees/jeu/rbac.json');
  final jeuModules = _lire('../../apps/poste/assets/donnees/jeu/modulesActifs.json');

  MatriceDroits calc({List<Fiche>? rbac, List<Fiche>? modules}) =>
      superposerDroits(base, manifeste, rbac: rbac ?? jeuRbac, modulesActifs: modules ?? jeuModules);
  List<Fiche> rouvertes() => [for (final f in jeuModules) {...f, 'statut': 'archive'}];
  String d(MatriceDroits m, String role, String ecran) {
    final x = m.droit(role, ecran);
    return '${x.voir ? 1 : 0}${x.editer ? 1 : 0}${x.annuler ? 1 : 0}';
  }

  test('PARITÉ : recalculée depuis le manifeste et le jeu, la matrice égale celle que la maquette a extraite (22 rôles, tous les écrans)', () {
    final m = calc();
    final ecarts = <String>[];
    var n = 0;
    final parRole = (brut['parRole'] as Map).cast<String, Object?>();
    for (final role in parRole.keys) {
      final attendu = (parRole[role] as Map).cast<String, Object?>();
      for (final e in manifeste.tousLesEcrans.where((e) => !e.hub)) {
        // Une page de saisie porte les droits du registre qu'elle alimente (`servant`) : la matrice extraite, elle, la résolvait sur son propre module.
        final cible = e.servant ?? e.id;
        final a = attendu[cible] as List?;
        final att = a == null ? 'absent' : '${a[0]}${a[1]}${a[2]}';
        final cal = m.peutVoir(role, e.id) ? d(m, role, e.id) : 'absent';
        n++;
        if (att != cal) ecarts.add('$role/${e.id}: attendu $att, calculé $cal');
      }
      expect(m.estArchive(role), base.estArchive(role), reason: '$role archive');
      expect(m.libelle(role), base.libelle(role), reason: '$role libellé');
      expect(m.accueil(role), base.accueil(role), reason: '$role accueil');
    }
    expect(n, greaterThan(5000));
    expect(ecarts, isEmpty, reason: ecarts.take(40).join('\n'));
  });

  test('MATRICE ENGENDRÉE : une page de saisie y porte les mêmes droits que son registre (extraction corrigée, E1123)', () {
    final pages = manifeste.tousLesEcrans.where((e) => e.servant != null).toList();
    expect(pages, isNotEmpty);
    for (final role in base.rolesBruts.map((r) => '${r['id']}')) {
      for (final e in pages) {
        expect(base.droit(role, e.id), base.droit(role, e.servant!), reason: '$role : ${e.id} suit ${e.servant}');
      }
    }
  });

  test('FERMETURE : la banque de sang et la transfusion sont fermées pour TOUS les rôles, administrateur compris (E203)', () {
    final m = calc();
    for (final role in base.rolesBruts.map((r) => '${r['id']}')) {
      expect(m.peutVoir(role, 'm5-banque-sang'), isFalse, reason: role);
      expect(m.peutVoir(role, 'm5-donneurs'), isFalse, reason: role);
    }
    // Le laboratoire, lui, reste ouvert : la fermeture porte sur des ÉCRANS nommés, pas sur le module.
    expect(m.peutVoir('admin', 'm5-demandes'), isTrue);
    expect(m.peutVoir('laborantin', 'm5-demandes'), isTrue);
    final f = m.fermetures!.fermeturePour('m5-banque-sang', 'M5')!;
    expect(f['motif'], 'La clinique ne pratique pas la banque de sang.');
    expect(m.ecranActif('m5-banque-sang', 'M5'), isFalse);
    expect(m.ecranActif('m5-demandes', 'M5'), isTrue);
  });

  test('RÉOUVERTURE : une fiche de fermeture ARCHIVÉE ne ferme plus rien (RG-14) ; les droits d\'origine reviennent', () {
    final m = calc(modules: rouvertes());
    expect(m.fermetures!.ecrans, isEmpty);
    // Les rôles que le manifeste ouvre à la banque de sang : laborantin, médecin, dm, admin, direction.
    expect(d(m, 'admin', 'm5-banque-sang'), '111');
    expect(d(m, 'laborantin', 'm5-banque-sang'), '111');
    expect(d(m, 'direction', 'm5-banque-sang'), '100', reason: 'la direction lit tout, n\'écrit pas le clinique');
    expect(d(m, 'admin', 'm5-donneurs'), '111');
    expect(m.peutVoir('caissier', 'm5-banque-sang'), isFalse, reason: 'rouvrir une activité n\'ouvre pas un écran à un rôle que le manifeste exclut');
    expect(m.peutVoir('reception', 'm5-donneurs'), isFalse);
  });

  test('FERMETURE D\'UN MODULE ENTIER : tous ses écrans disparaissent, pour tous les rôles ; la réouverture rend tout', () {
    final fiche = <Fiche>[
      {'id': 'MOD9', 'code': 'M13', 'libelle': 'Administration', 'module': 'M13', 'actif': false, 'motif': 'Essai'}
    ];
    final m = calc(modules: fiche);
    for (final role in ['admin', 'direction', 'reception']) {
      expect(m.peutVoir(role, 'm13-courriers'), isFalse, reason: role);
      expect(m.peutVoir(role, 'm13-repertoire-ambulances'), isFalse, reason: role);
    }
    expect(m.peutVoir('admin', 'm1-patients'), isTrue);
    expect(m.fermetures!.fermeturePour('m13-courriers', 'M13')!['motif'], 'Essai');
    final rouvert = calc(modules: [
      {...fiche.first, 'statut': 'archive'}
    ]);
    expect(rouvert.peutVoir('admin', 'm13-courriers'), isTrue);
    // Une fiche réactivée (actif: true) ne ferme rien non plus.
    expect(calc(modules: [
      {...fiche.first, 'actif': true}
    ]).peutVoir('admin', 'm13-courriers'), isTrue);
  });

  test('LE NOYAU NE SE FERME PAS : une fiche qui fermerait CFG ou DASH en entier est sans effet (l\'interrupteur et la page d\'accueil restent)', () {
    final m = calc(modules: [
      ...jeuModules,
      {'id': 'X1', 'module': 'CFG', 'libelle': 'Configuration', 'actif': false},
      {'id': 'X2', 'module': 'DASH', 'libelle': 'Tableaux de bord', 'actif': false},
    ]);
    expect(m.peutVoir('admin', 'cfg-modules'), isTrue);
    expect(m.peutVoir('admin', 'dash-admin'), isTrue);
    expect(m.ecranActif('cfg-modules', 'CFG'), isTrue);
    // Fermer un ÉCRAN nommé de ces modules reste possible (c'est un geste voulu, pas la fermeture du module).
    final nomme = calc(modules: [
      {'id': 'X3', 'module': 'DASH', 'ecrans': ['dash-direction'], 'actif': false}
    ]);
    expect(nomme.peutVoir('direction', 'dash-direction'), isFalse);
    expect(nomme.peutVoir('admin', 'dash-admin'), isTrue);
  });

  test('SURCHARGE : un écran l\'emporte sur son module ; un écran non réglé suit son module', () {
    final sansFiche = calc(rbac: const []);
    expect(d(sansFiche, 'reception', 'm1-patients'), '111', reason: 'sans fiche, le manifeste ouvre tout au rôle qui voit le module');
    final m = calc(rbac: [
      {
        'id': 'T1',
        'role': 'reception',
        'statut': 'actif',
        'droits': {
          'M1': {'editer': true, 'annuler': false}
        },
        'droitsEcrans': {
          'm1-patients': {'voir': true, 'editer': false, 'annuler': false}
        }
      }
    ]);
    expect(d(m, 'reception', 'm1-patients'), '100', reason: 'l\'écran l\'emporte');
    expect(d(m, 'reception', 'm1-pieces'), '110', reason: 'l\'écran non réglé suit le module');
  });

  test('SURCHARGE : fermer un module retire ses écrans ; voir:false sur un écran le retire seul', () {
    final m = calc(rbac: [
      {
        'id': 'T2',
        'role': 'reception',
        'statut': 'actif',
        'droits': {
          'M13': {'voir': false}
        },
        'droitsEcrans': {
          'm1-pieces': {'voir': false}
        }
      }
    ]);
    expect(m.peutVoir('reception', 'm13-courriers'), isFalse);
    expect(m.droit('reception', 'm13-courriers'), Droit.aucun);
    expect(m.peutVoir('reception', 'm1-pieces'), isFalse);
    expect(m.peutVoir('reception', 'm1-patients'), isTrue);
  });

  test('UNE SURCHARGE QUI POSE voir:true ACCORDE : un rôle créé part de zéro et s\'ouvre par ses fiches', () {
    final m = calc(rbac: [
      ...jeuRbac,
      {
        'id': 'T3',
        'role': 'role-cree',
        'nouveau': true,
        'statut': 'actif',
        'libelle': 'Auditeur',
        'accueil': 'm1-patients',
        'droits': {
          'M1': {'voir': true, 'editer': false, 'annuler': false}
        },
        'droitsEcrans': {
          'm12-journaux': {'voir': true, 'editer': false, 'annuler': false}
        }
      }
    ]);
    expect(m.roleConnu('role-cree'), isTrue);
    expect(m.libelle('role-cree'), 'Auditeur');
    expect(m.accueil('role-cree'), 'm1-patients');
    expect(m.peutVoir('role-cree', 'm12-journaux'), isTrue, reason: 'accordé par l\'écran, hors de tout rôle du manifeste');
    expect(m.peutEditer('role-cree', 'm12-journaux'), isFalse);
    expect(m.peutVoir('role-cree', 'm12-ecritures'), isFalse, reason: 'le reste du module ne s\'ouvre pas');
    expect(m.peutVoir('role-cree', 'm8-caisse'), isFalse, reason: 'tout ce qui n\'est pas ouvert est refusé');
    // Une surcharge accordant l'écran d'une ACTIVITÉ FERMÉE ne la rouvre pas.
    final fermee = calc(rbac: [
      ...jeuRbac,
      {
        'id': 'T4',
        'role': 'admin',
        'statut': 'actif',
        'droitsEcrans': {
          'm5-banque-sang': {'voir': true, 'editer': true, 'annuler': true}
        }
      }
    ]);
    expect(fermee.peutVoir('admin', 'm5-banque-sang'), isFalse);
  });

  test('RÔLE ARCHIVÉ (RG-14) : aucun écran, mais le rôle reste connu ; la restauration le rend', () {
    final fiches = [
      ...jeuRbac,
      {'id': 'T5', 'role': 'comptable', 'statut': 'archive'}
    ];
    final m = calc(rbac: fiches);
    expect(m.estArchive('comptable'), isTrue);
    expect(m.roleConnu('comptable'), isTrue);
    expect(m.ecransVisibles('comptable'), isEmpty);
    expect(m.peutVoir('comptable', 'm12-journaux'), isFalse);
    expect(calc().peutVoir('comptable', 'm12-journaux'), isTrue);
    expect(calc().estArchive('comptable'), isFalse);
  });

  test('RENOMMAGE : le libellé de la fiche l\'emporte sur celui d\'origine, et se rend quand la fiche le retire', () {
    final m = calc(rbac: [
      ...jeuRbac,
      {'id': 'T6', 'role': 'stock', 'statut': 'actif', 'libelle': 'Magasinier principal'}
    ]);
    expect(m.libelle('stock'), 'Magasinier principal');
    expect(calc(rbac: jeuRbac).libelle('stock'), base.libelle('stock'));
  });

  test('ÉCRAN UNIVERSEL : ouvert à tout poste (voir et éditer, jamais annuler), ne rouvre pas un module fermé, cède devant une surcharge d\'écran', () {
    final m = calc();
    // `m7-besoins` : exprimer un besoin appartient à tout agent, même à un rôle dont M7 n'est pas ouvert.
    for (final role in ['medecin', 'aide_soignant', 'reception', 'caissier']) {
      expect(m.peutVoir(role, 'm7-besoins'), isTrue, reason: role);
      expect(m.peutEditer(role, 'm7-besoins'), isTrue, reason: role);
      expect(m.peutAnnuler(role, 'm7-besoins'), isFalse, reason: '$role n\'annule pas le bon d\'un autre service');
    }
    // Un module fermé n'est PAS rouvert par l'universel, administrateur compris.
    final ferme = calc(modules: [
      {'id': 'F7', 'module': 'M7', 'libelle': 'Achats', 'actif': false}
    ]);
    expect(ferme.peutVoir('medecin', 'm7-besoins'), isFalse);
    expect(ferme.peutVoir('admin', 'm7-besoins'), isFalse);
    // Une surcharge d'écran explicite garde le dernier mot.
    final nomme = calc(rbac: [
      {
        'id': 'T7',
        'role': 'medecin',
        'statut': 'actif',
        'droitsEcrans': {
          'm7-besoins': {'voir': false}
        }
      }
    ]);
    expect(nomme.peutVoir('medecin', 'm7-besoins'), isFalse);
    expect(nomme.peutVoir('aide_soignant', 'm7-besoins'), isTrue);
    // La fermeture du MODULE par une fiche de rôle (rôle créé « à zéro ») ne retire pas l'écran universel.
    final zero = calc(rbac: [
      {
        'id': 'T8',
        'role': 'medecin',
        'statut': 'actif',
        'droits': {
          'M7': {'voir': false, 'editer': false, 'annuler': false}
        }
      }
    ]);
    expect(zero.peutVoir('medecin', 'm7-besoins'), isTrue);
  });

  test('PAGE DE SAISIE (servant) : elle porte les droits du registre qu\'elle alimente et se ferme avec lui', () {
    final m = calc();
    // L'échographiste écrit `m2-imagerie` par surcharge d'écran : il saisit donc le compte rendu, qu'il n'écrirait pas par son module (M2 en lecture).
    expect(d(m, 'echographiste', 'm2-imagerie'), '111');
    expect(d(m, 'echographiste', 'm2-imagerie-cr'), '111');
    // Le caissier lit l'inventaire : sa feuille de comptage est en lecture, pas en écriture par son module M6.
    expect(d(m, 'caissier', 'm6-inventaire-feuille'), d(m, 'caissier', 'm6-inventaire'));
    // Fermer le registre ferme la page : son adresse serait sinon une porte dérobée.
    final fermeeEcran = calc(modules: [
      {'id': 'F8', 'module': 'M2', 'ecrans': ['m2-imagerie'], 'actif': false}
    ]);
    expect(fermeeEcran.peutVoir('echographiste', 'm2-imagerie-cr'), isFalse);
    expect(fermeeEcran.peutVoir('echographiste', 'm2-imagerie-radiographie'), isTrue);
  });

  test('DOUBLONS : plusieurs fiches pour un même rôle se FUSIONNENT champ par champ, la dernière l\'emportant sur ce qu\'elle définit seulement', () {
    final f = surchargesParRole([
      {
        'role': 'x',
        'libelle': 'Premier',
        'statut': 'archive',
        'droits': {
          'M1': {'voir': true}
        }
      },
      {
        'role': 'x',
        'libelle': 'Second',
        'statut': 'actif',
        'droits': {
          'M2': {'voir': false}
        }
      },
      {'role': 'x', 'libelleCourt': null},
    ]);
    expect(f['x']!['libelle'], 'Second');
    expect(f['x']!['statut'], 'actif');
    expect((f['x']!['droits'] as Map).keys.toSet(), {'M1', 'M2'});
  });

  test('SANS FICHE : la collection vide ne change rien à la matrice calculée (aucune fermeture, droits d\'origine du manifeste)', () {
    final m = superposerDroits(base, manifeste);
    expect(m.fermetures!.ecrans, isEmpty);
    expect(m.fermetures!.modules, isEmpty);
    expect(m.peutVoir('admin', 'm5-banque-sang'), isTrue);
  });

  group('AVEC RÉFÉRENCE : la matrice engendrée reste la BASE, seul ce qui a changé depuis les fiches de l\'extraction la remplace', () {
    MatriceDroits chaud({List<Fiche>? rbac, List<Fiche>? modules, MatriceDroits? sur}) => superposerDroits(sur ?? base, manifeste,
        rbac: rbac ?? jeuRbac, modulesActifs: modules ?? jeuModules, referenceRbac: jeuRbac, referenceModules: jeuModules);
    String cases(MatriceDroits m, String role) {
      final l = [for (final e in manifeste.tousLesEcrans.where((e) => !e.hub)) '${e.id}=${m.peutVoir(role, e.id) ? d(m, role, e.id) : '-'}']..sort();
      return l.join(',');
    }

    test('fiches inchangées : la matrice est EXACTEMENT la matrice engendrée, case pour case, pour les 22 rôles', () {
      final m = chaud();
      for (final role in base.rolesBruts.map((r) => '${r['id']}')) {
        expect(cases(m, role), cases(base, role), reason: role);
        expect(m.estArchive(role), base.estArchive(role), reason: role);
        expect(m.libelle(role), base.libelle(role), reason: role);
        expect(m.accueil(role), base.accueil(role), reason: role);
      }
    });

    test('une case retouchée dans la matrice engendrée (banc de test) survit tant que les fiches ne changent pas', () {
      final j = jsonDecode(jsonEncode(brut)) as Map<String, Object?>;
      ((j['parRole'] as Map)['da'] as Map)['m14-taches'] = [1, 0, 0];
      final retouchee = MatriceDroits.depuisJson(j);
      expect(retouchee.droit('da', 'm14-taches').voir, isTrue);
      final m = chaud(sur: retouchee);
      expect(d(m, 'da', 'm14-taches'), '100');
      expect(m.peutVoir('da', 'm1-patients'), base.peutVoir('da', 'm1-patients'));
    });

    test('RÉOUVERTURE : les fiches de fermeture archivées font paraître l\'écran, avec les droits que le manifeste donne', () {
      final m = chaud(modules: rouvertes());
      expect(base.peutVoir('admin', 'm5-banque-sang'), isFalse, reason: 'la matrice engendrée ne le porte pas');
      expect(d(m, 'admin', 'm5-banque-sang'), '111');
      expect(d(m, 'laborantin', 'm5-donneurs'), '111');
      expect(d(m, 'direction', 'm5-banque-sang'), '100');
      expect(m.peutVoir('caissier', 'm5-banque-sang'), isFalse);
      expect(m.peutVoir('admin', 'm5-demandes'), base.peutVoir('admin', 'm5-demandes'));
    });

    test('FERMETURE À CHAUD : un module fermé retire ses écrans de tous les rôles, le reste de la matrice ne bouge pas', () {
      final m = chaud(modules: [
        ...jeuModules,
        {'id': 'F9', 'module': 'M13', 'libelle': 'Administration', 'actif': false, 'motif': 'Essai'}
      ]);
      expect(m.peutVoir('admin', 'm13-courriers'), isFalse);
      expect(m.peutVoir('reception', 'm13-repertoire-ambulances'), isFalse);
      expect(cases(m, 'caissier'), cases(base, 'caissier'));
      expect(m.fermetures!.fermeturePour('m13-courriers', 'M13')!['motif'], 'Essai');
    });

    test('FICHE MODIFIÉE : seules les cases touchées changent ; un écran retiré à un rôle disparaît, son module reste', () {
      final modifiees = [
        for (final f in jeuRbac)
          f['role'] == 'reception'
              ? {
                  ...f,
                  'droitsEcrans': {
                    ...(f['droitsEcrans'] as Map).cast<String, Object?>(),
                    'm13-repertoire-ambulances': {'voir': false}
                  }
                }
              : f
      ];
      final m = chaud(rbac: modifiees);
      expect(m.peutVoir('reception', 'm13-repertoire-ambulances'), isFalse);
      expect(m.peutVoir('reception', 'm13-courriers'), base.peutVoir('reception', 'm13-courriers'));
      expect(cases(m, 'medecin'), cases(base, 'medecin'));
    });

    test('ARCHIVAGE DE RÔLE : le rôle n\'a plus aucun écran ; restauré, il retrouve la matrice engendrée', () {
      final archive = [
        for (final f in jeuRbac) f['role'] == 'comptable' ? {...f, 'statut': 'archive'} : f
      ];
      final m = chaud(rbac: archive);
      expect(m.estArchive('comptable'), isTrue);
      expect(m.ecransVisibles('comptable'), isEmpty);
      expect(cases(chaud(), 'comptable'), cases(base, 'comptable'));
    });

    test('RÔLE CRÉÉ : il vient entièrement des fiches, la matrice engendrée n\'en sait rien', () {
      final m = chaud(rbac: [
        ...jeuRbac,
        {
          'id': 'N1',
          'role': 'auditeur',
          'nouveau': true,
          'statut': 'actif',
          'libelle': 'Auditeur',
          'droitsEcrans': {
            'm12-journaux': {'voir': true, 'editer': false, 'annuler': false}
          }
        }
      ]);
      expect(m.roleConnu('auditeur'), isTrue);
      expect(m.libelle('auditeur'), 'Auditeur');
      expect(d(m, 'auditeur', 'm12-journaux'), '100');
      expect(m.peutVoir('auditeur', 'm8-caisse'), isFalse);
    });
  });
}
