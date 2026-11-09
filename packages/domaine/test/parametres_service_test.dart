// Le service des paramètres (lot L0) branché sur des listes en mémoire : semis, valeur en vigueur par date, réglage daté, refus après usage, historique.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

class Banc {
  final versions = <Map<String, Object?>>[];
  final usages = <Map<String, Object?>>[];
  DateTime maintenant = DateTime.utc(2026, 11, 9, 8);
  String auteur = 'admin';
  late final ServiceParametres s = ServiceParametres(
    definitions: definitionsParametres,
    lireVersions: () => versions,
    lireUsages: () => usages,
    ecrireVersion: (id, c) => versions.add({'id': id, 'statut': 'actif', ...c}),
    ecrireUsage: (id, c) => usages.add({'id': id, ...c}),
    auteur: () => auteur,
    maintenant: () => maintenant,
  );
}

void main() {
  const circuit = 'planning.circuitPresences';

  test('semis : une version 0 par définition, une seule fois', () {
    final b = Banc();
    expect(b.s.semerDefauts(), definitionsParametres.length);
    expect(b.s.semerDefauts(), 0);
    expect(b.versions.map((f) => f['id']).toSet().length, definitionsParametres.length);
    expect(b.versions.every((f) => f['version'] == 0 && f['dateEffet'] == null), isTrue);
  });

  test('sans semis, la valeur en vigueur est le défaut de la définition (un fileul avant réception)', () {
    final b = Banc();
    expect(b.s.valeur(circuit, '2026-11-09'), 'surveillant');
    expect(b.s.valeurA(circuit, '2026-11-09').valeur!.origine, 'defaut');
    expect(b.s.valeur('planning.badgeSertDePointage', '2026-11-09'), true);
    expect(b.s.valeur('planning.agentModifieDirectement', '2026-11-09'), false);
  });

  test('un paramètre inconnu se refuse en le nommant, et rend null à l\'affichage', () {
    final b = Banc();
    expect(b.s.valeurA('inconnu', '2026-11-09').refus!.code, 'parametre_inconnu');
    expect(b.s.valeur('inconnu', '2026-11-09'), isNull);
    expect(b.s.regler('inconnu', true, '2026-12-01').refus!.code, 'parametre_inconnu');
    expect(b.s.enregistrerUsage('inconnu', '2026-11-09', 'F-1')!.code, 'parametre_inconnu');
  });

  test('régler écrit une version datée ; la valeur dépend de la date, pas du jour', () {
    final b = Banc()..s.semerDefauts();
    final r = b.s.regler(circuit, 'daf', '2026-12-01', motif: ' test ');
    expect(r.ok, isTrue);
    expect(r.valeur!.version, 1);
    expect(r.valeur!.auteur, 'admin');
    expect(r.valeur!.motif, 'test');
    expect(r.valeur!.creeLe, '2026-11-09T08:00:00.000Z');
    expect(b.s.valeur(circuit, '2026-11-30'), 'surveillant');
    expect(b.s.valeur(circuit, '2026-12-01'), 'daf');
    expect(b.versions.last['id'], '$circuit@2026-12-01@1');
  });

  test('une valeur déjà utilisée par une pièce ne se réécrit jamais ; une date postérieure est acceptée', () {
    final b = Banc()..s.semerDefauts();
    expect(b.s.enregistrerUsage(circuit, '2026-11-08', 'F-1'), isNull);
    expect(b.s.enregistrerUsage(circuit, '2026-11-08', 'F-1'), isNull); // idempotent
    expect(b.usages.length, 1);
    final r = b.s.regler(circuit, 'daf', '2026-11-08');
    expect(r.refus!.code, 'parametre_deja_utilise');
    expect(r.refus!.geste, contains('postérieure au 2026-11-08'));
    expect(b.versions.where((f) => f['version'] == 1), isEmpty, reason: 'rien n\'est écrit sur un refus');
    expect(b.s.regler(circuit, 'daf', '2026-11-09').ok, isTrue);
  });

  test('refus nommés : valeur hors choix, auteur absent, date illisible', () {
    final b = Banc()..s.semerDefauts();
    expect(b.s.regler(circuit, 'personne', '2026-12-01').refus!.code, 'valeur_invalide');
    expect(b.s.regler(circuit, 'daf', '1er décembre').refus!.code, 'date_invalide');
    b.auteur = '';
    expect(b.s.regler(circuit, 'daf', '2026-12-01').refus!.code, 'auteur_manquant');
    expect(b.s.enregistrerUsage(circuit, 'hier', 'F-2')!.code, 'date_invalide');
  });

  test('historique (récent d\'abord) et vue par famille avec la prochaine version', () {
    final b = Banc()..s.semerDefauts();
    b.s.regler(circuit, 'daf', '2026-12-01');
    b.s.regler(circuit, 'surveillant_puis_daf', '2027-02-01');
    expect(b.s.historique(circuit).map((p) => p.version), [2, 1, 0]);
    final fam = b.s.parFamille('2026-11-09');
    expect(fam.keys, containsAll(['mecef', 'bareme_aib', 'planning', 'paie']));
    final p = fam['planning']!.firstWhere((x) => x.definition.cle == circuit);
    expect(p.valeur, 'surveillant');
    expect(p.origine, 'version');
    expect(p.prochaine!.dateEffet, '2026-12-01');
    expect(p.nbVersions, 3);
    expect(parametreDateIso(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('chaque famille du registre a son libellé', () {
    for (final d in definitionsParametres) {
      expect(libellesFamillesParametres.containsKey(d.famille), isTrue, reason: d.famille);
    }
  });
}
