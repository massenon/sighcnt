// LOT CONT : la décision de validation d'un fileul est une DEMANDE SIGNÉE que la mère applique mécaniquement (jamais une décision humaine à la mère).
// Chaque ligne de ce fichier échoue sur l'arbre d'avant (la fonction n'existait pas ; le geste direct d'un fileul rendait `CONFIGURATION_DE_LA_MERE` pour les quinze familles).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

final libelles = {for (final f in valFamilles) for (final r in f.roles) r: r};
final signe = DateTime.utc(2026, 11, 14, 8, 30);
final mereLe = DateTime.utc(2026, 11, 14, 12, 0);

/// Un magasin minimal : une fiche « à valider » par famille (ou la cible nommée du registre pour les familles de forme « fiche »).
Map<String, List<M>> magasinTest() {
  final out = <String, List<M>>{valCollectionValidations: [], valCollectionDemandes: []};
  for (final f in valFamilles) {
    for (final c in f.collections) {
      out[c] = [
        {'id': 'X-$c', 'statut': 'actif', 'libelle': 'Élément $c', 'prix': 100, for (final ch in f.champs) ch: true}
      ];
    }
  }
  return out;
}

LectureValidation lecture(Map<String, List<M>> m) => (nom) => m[nom] ?? <M>[];

String cibleDe(FamilleValidation f) => f.cibles.isNotEmpty ? f.cibles.first.id : 'X-${f.collections.first}';

void main() {
  group('le geste direct d\'un fileul reste refusé (mesure de l\'ancien défaut), le dépôt est l\'autre voie', () {
    for (final f in valFamilles) {
      test('${f.id} : le geste direct d\'un fileul refuse en nommant la mère ; le dépôt du profil de la famille est accepté', () {
        final m = magasinTest();
        final direct = valValiderReferentiel(f.id, cibleDe(f), role: f.roles.first, acteur: 'A', maintenant: signe, lire: lecture(m), libelles: libelles, fileul: true);
        expect(direct.ok, isFalse, reason: 'ancien comportement : la configuration est tenue par la mère');
        expect(direct.refus!.code, valCodeFileul);
        final depot = valDeposerValidation(f.id, cibleDe(f), role: f.roles.first, acteur: 'Agent ${f.roles.first}', maintenant: signe, lire: lecture(m), libelles: libelles);
        expect(depot.ok, isTrue, reason: '${depot.refus?.code} ${depot.refus?.motif}');
        final d = depot.fiche!;
        expect([d['famille'], d['cible'], d['etat'], d['demandePar'], d['demandeRole'], d['statut']], [f.id, cibleDe(f), valEtatDeposee, 'Agent ${f.roles.first}', f.roles.first, 'actif']);
        expect(d['demandeLe'], valInstant(signe), reason: 'la signature porte la date de la décision');
      });
    }
  });

  test('refus nommés au dépôt : profil non habilité, famille inconnue, cible inconnue, déjà validée, tarif absent', () {
    final m = magasinTest();
    RefusValidation? refus(String fam, String id, String role) =>
        valDeposerValidation(fam, id, role: role, acteur: 'A', maintenant: signe, lire: lecture(m), libelles: libelles).refus;
    final r1 = refus('labo_variables', 'X-variablesLabo', 'caissier')!;
    expect(r1.code, 'VALIDATION_RESERVEE');
    expect(r1.motif, contains('réservée à'));
    expect(refus('inconnue', 'x', 'direction')!.code, 'INTROUVABLE');
    expect(refus('labo_variables', 'absent', 'laborantin')!.code, 'INTROUVABLE');
    m['variablesLabo']!.first['aValider'] = false;
    m['variablesLabo']!.first['valideLe'] = '2026-11-01T08:00:00.000Z';
    expect(refus('labo_variables', 'X-variablesLabo', 'laborantin')!.code, 'DEJA_VALIDE');
    m['actes']!.first['prix'] = null;
    expect(refus('actes', 'X-actes', 'direction')!.code, 'TARIF_ABSENT');
  });

  test('une seule décision en attente par cible : la seconde est refusée en nommant, jamais doublée ; une autre cible n\'est pas gênée', () {
    final m = magasinTest();
    m['variablesLabo']!.add({'id': 'VL2', 'statut': 'actif', 'libelle': 'Autre', 'aValider': true});
    final p = valDeposerValidation('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'Biologiste', maintenant: signe, lire: lecture(m), libelles: libelles);
    m[valCollectionDemandes]!.add(p.fiche!);
    final deux = valDeposerValidation('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'Autre biologiste', maintenant: signe.add(const Duration(hours: 3, minutes: 10)), lire: lecture(m), libelles: libelles);
    expect(deux.ok, isFalse);
    expect(deux.refus!.code, 'DEMANDE_DEJA_DEPOSEE');
    expect(deux.refus!.motif, allOf(contains('Biologiste'), contains('3 h 10 min')));
    expect(deux.refus!.geste, contains('n\'est pas bloqué'));
    // Même avec une décision en retard de plusieurs jours, une autre cible se décide : l'attente n'est jamais un verrou.
    final autre = valDeposerValidation('labo_variables', 'VL2', role: 'laborantin', acteur: 'Biologiste', maintenant: signe.add(const Duration(days: 9)), lire: lecture(m), libelles: libelles);
    expect(autre.ok, isTrue);
  });

  group('la mère applique mécaniquement', () {
    test('sous le rôle et le nom de l\'auteur, à la date de la SIGNATURE, comme le geste direct (même patch, même journal)', () {
      final m = magasinTest();
      final dep = valDeposerValidation('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'Dr KINNOU', maintenant: signe, lire: lecture(m), libelles: libelles, motif: 'bornes relues').fiche!;
      m[valCollectionDemandes]!.add(dep);
      final a = valAppliquerDemande(dep, maintenant: mereLe, lire: lecture(m), libelles: libelles)!;
      expect(a.verdict.ok, isTrue);
      final direct = valValiderReferentiel('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'Dr KINNOU', maintenant: signe, lire: lecture(m), libelles: libelles, motif: 'bornes relues');
      expect(a.verdict.patch, direct.patch, reason: 'une décision déposée vaut le geste direct');
      expect(a.verdict.validePar, 'Dr KINNOU');
      expect(a.verdict.valideLe, valInstant(signe), reason: 'la date est celle de la signature, pas celle de l\'application par la mère');
      expect(a.champsDemande['etat'], valEtatAppliquee);
      expect(a.champsDemande['traiteLe'], valInstant(mereLe));
    });

    test('la mère REFAIT le contrôle : un rôle falsifié est refusé en nommant (rien n\'est validé)', () {
      final m = magasinTest();
      final dep = {...valDeposerValidation('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'A', maintenant: signe, lire: lecture(m), libelles: libelles).fiche!, 'demandeRole': 'caissier'};
      final a = valAppliquerDemande(dep, maintenant: mereLe, lire: lecture(m), libelles: libelles)!;
      expect(a.verdict.ok, isFalse);
      expect(a.champsDemande['etat'], valEtatRefusee);
      expect(a.champsDemande['resultatCode'], 'VALIDATION_RESERVEE');
      expect(a.champsDemande['resultatGeste'], isNotNull);
    });

    test('idempotence : une demande déjà appliquée ou refusée ne se retraite jamais ; validée entre-temps, elle est refusée en nommant', () {
      final m = magasinTest();
      final dep = valDeposerValidation('labo_variables', 'X-variablesLabo', role: 'laborantin', acteur: 'A', maintenant: signe, lire: lecture(m), libelles: libelles).fiche!;
      expect(valAppliquerDemande({...dep, 'etat': valEtatAppliquee}, maintenant: mereLe, lire: lecture(m), libelles: libelles), isNull);
      expect(valAppliquerDemande({...dep, 'etat': valEtatRefusee}, maintenant: mereLe, lire: lecture(m), libelles: libelles), isNull);
      m['variablesLabo']!.first['aValider'] = false;
      m['variablesLabo']!.first['valideLe'] = '2026-11-14T07:00:00.000Z';
      final a = valAppliquerDemande(dep, maintenant: mereLe, lire: lecture(m), libelles: libelles)!;
      expect(a.champsDemande['etat'], valEtatRefusee);
      expect(a.champsDemande['resultatCode'], 'DEJA_VALIDE');
    });

    test('aucune auto-validation : sans demande, rien ne s\'applique, quel que soit l\'âge de la pièce', () {
      final m = magasinTest();
      expect(valDemandesEnAttente(m[valCollectionDemandes]!), isEmpty);
      final en = valSyntheseEnAttente(m[valCollectionDemandes]!, signe.add(const Duration(days: 60)));
      expect(en.nombre, 0);
      expect(m['variablesLabo']!.first['aValider'], true);
    });
  });

  group('l\'indicateur et l\'alerte', () {
    List<M> demandes() => [
          {'id': 'DV2', 'statut': 'actif', 'etat': valEtatDeposee, 'famille': 'actes', 'cible': 'a', 'demandePar': 'B', 'demandeLe': valInstant(signe.add(const Duration(hours: 5)))},
          {'id': 'DV1', 'statut': 'actif', 'etat': valEtatDeposee, 'famille': 'enquetes', 'cible': 'b', 'demandePar': 'A', 'demandeLe': valInstant(signe)},
          {'id': 'DV0', 'statut': 'actif', 'etat': valEtatAppliquee, 'famille': 'pathologies', 'cible': 'c', 'demandePar': 'A', 'demandeLe': valInstant(signe)},
          {'id': 'DV9', 'statut': 'archive', 'etat': valEtatDeposee, 'famille': 'pathologies', 'cible': 'd', 'demandePar': 'A', 'demandeLe': valInstant(signe)},
        ];

    test('le compte est le compte RÉEL (jamais zéro quand il y en a) avec l\'âge de la plus ancienne', () {
      final s = valSyntheseEnAttente(demandes(), signe.add(const Duration(hours: 6, minutes: 5)));
      expect(s.nombre, 2);
      expect(s.plusAncienne, const Duration(hours: 6, minutes: 5));
      expect(s.libelle, '2 décisions en attente de la mère · la plus ancienne depuis 6 h 5 min');
      expect(valSyntheseEnAttente(demandes().sublist(2), signe).libelle, '');
      expect(valSyntheseEnAttente([demandes()[1]], signe.add(const Duration(minutes: 7))).libelle, '1 décision en attente de la mère · la plus ancienne depuis 7 min');
    });

    test('l\'alerte suit le délai LU de la base : au-delà, jamais en deçà ; délai absent ou nul : aucune alerte inventée', () {
      final t = signe.add(const Duration(hours: 25));
      expect([for (final d in valDemandesEnRetard(demandes(), t, valDelaiAlerteDefautHeures)) d['id']], ['DV1']);
      expect([for (final d in valDemandesEnRetard(demandes(), t, 30)) d['id']], isEmpty);
      expect([for (final d in valDemandesEnRetard(demandes(), t, 1)) d['id']], ['DV1', 'DV2']);
      expect(valDemandesEnRetard(demandes(), t, null), isEmpty);
      expect(valDemandesEnRetard(demandes(), t, 0), isEmpty);
    });

    test('la pastille compte AUSSI les demandes de prix et d\'import qui attendent la mère ; une date sans heure compte sans donner d\'âge', () {
      final s = valSyntheseToutesAttentes({
        valCollectionDemandes: demandes(),
        'propositionsTarif': [
          {'id': 'DT1', 'statut': 'actif', 'etat': 'deposee', 'demandeLe': valInstant(signe.subtract(const Duration(hours: 2)))},
          {'id': 'DT2', 'statut': 'actif', 'etat': 'appliquee', 'demandeLe': valInstant(signe)},
        ],
        'demandesImport': [
          {'id': 'DI1', 'statut': 'actif', 'etat': 'en_attente', 'demandeLe': '2026-11-01'},
          {'id': 'DI2', 'statut': 'actif', 'etat': 'refusee', 'demandeLe': '2026-11-01'},
        ],
      }, signe.add(const Duration(hours: 1)));
      expect(s.nombre, 4, reason: 'deux décisions, une demande de prix, une demande d\'import');
      expect(s.plusAncienne, const Duration(hours: 3), reason: 'la demande de prix est la plus ancienne datée à l\'heure ; l\'import daté du seul jour ne donne pas d\'âge');
    });

    test('le délai d\'alerte est un paramètre déclaré, semé à 24, fermé au téléphone', () {
      final d = definitionDeParametre(valCleDelaiAlerteHeures)!;
      expect([d.defaut, d.type, d.mobile], [24, TypeParametre.entier, false]);
      expect(parFamillesJamaisMobile, contains(d.famille));
    });
  });
}
