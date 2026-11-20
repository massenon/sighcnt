// Les réglages de l'AIB tenus au REGISTRE DES PARAMÈTRES du poste (lot L0) : une version datée devient une fiche de réglage (`aibReglagesDepuisParametres`),
// et les mêmes règles que la maquette s'y appliquent (charge arrêtée, comptes choisis, branchement refusé tant qu'il est incomplet), sans recopier de constante.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

Parametre _v(String cle, Object? valeur, String? dateEffet, int version, {String auteur = 'Comptable'}) {
  final d = definitionDeParametre('bareme_aib.$cle')!;
  return Parametre(cle: d.cle, famille: d.famille, type: d.type, choix: d.choix, valeur: valeur, defaut: d.defaut, dateEffet: dateEffet, version: version, auteur: dateEffet == null ? 'semis' : auteur, motif: dateEffet == null ? 'Défaut semé' : 'Réglé', source: d.source);
}

List<Parametre> _semees() => [for (final c in const ['chargePrelevement', 'branchementAchats', 'compteAcompte', 'compteContrepartie']) Parametres.semer(definitionDeParametre('bareme_aib.$c')!)];

AibDonnees _d(List<Parametre> v) => AibDonnees(reglages: aibReglagesDepuisParametres(v), comptes: [
      {'num': '447000', 'libelle': 'Etat impôts retenu à la source', 'statut': 'actif'},
      {'num': '401110', 'libelle': 'Fournisseurs', 'statut': 'actif'},
    ]);

void main() {
  test('les quatre définitions sont au registre, branchées, avec les défauts de la Direction (clinique, désactivé, aucun compte)', () {
    for (final d in aibDefinitionsReglages) {
      final def = definitionDeParametre('$aibPrefixeParametre${d['cle']}');
      expect(def, isNotNull, reason: '${d['cle']}');
      expect(def!.branche, isTrue);
      expect(def.famille, 'bareme_aib');
      expect(def.mobile, isFalse, reason: 'le barème ne va jamais au téléphone (RG-13)');
    }
    expect(definitionDeParametre('bareme_aib.chargePrelevement')!.defaut, 'clinique');
    expect(definitionDeParametre('bareme_aib.branchementAchats')!.defaut, 'desactive');
    expect(definitionDeParametre('bareme_aib.compteAcompte')!.defaut, '');
    // Les valeurs admises sont celles des définitions du moteur (une seule vérité).
    expect(definitionDeParametre('bareme_aib.chargePrelevement')!.choix, [for (final x in (aibDefinitionsReglages[0]['valeurs'] as List)) (x as Map)['value']]);
    expect(definitionDeParametre('bareme_aib.branchementAchats')!.choix, [for (final x in (aibDefinitionsReglages[1]['valeurs'] as List)) (x as Map)['value']]);
  });

  test('à l’état semé : charge « clinique » NON ARRÊTÉE, branchement désactivé, comptes sans version (refus nommé)', () {
    final d = _d(_semees());
    final c = aibChargeALaDate(d, '2026-08-16');
    expect(c['valeur'], 'clinique');
    expect(c['arrete'], isFalse);
    expect(c['message'], isNotNull);
    expect(aibBranchementALaDate(d, '2026-08-16')['actif'], isFalse);
    expect(aibReglageALaDate(d, 'compteAcompte', '2026-08-16')['code'], 'AIB_REGLAGE_SANS_VERSION');
    expect(aibReglageALaDate(d, 'compteContrepartie', '2026-08-16')['code'], 'AIB_REGLAGE_SANS_VERSION');
  });

  test('sans version 0 en base (poste qui n’a pas encore reçu la mère) : le défaut du registre s’applique, comme la résolution du service', () {
    final d = _d(const []);
    expect(aibChargeALaDate(d, '2026-08-16')['valeur'], 'clinique');
    expect(aibBranchementALaDate(d, '2026-08-16')['valeur'], 'desactive');
  });

  test('une version datée est ARRÊTÉE ; la précédente est fermée à la veille ; la valeur d’hier reste lisible', () {
    final d = _d([..._semees(), _v('chargePrelevement', 'acheteur', '2026-08-16', 1)]);
    final avant = aibChargeALaDate(d, '2026-08-15');
    final apres = aibChargeALaDate(d, '2026-08-16');
    expect(avant['valeur'], 'clinique');
    expect(avant['arrete'], isFalse);
    expect(apres['valeur'], 'acheteur');
    expect(apres['arrete'], isTrue);
    expect(apres['message'], isNull);
    expect(d.reglages.firstWhere((f) => f['cle'] == 'chargePrelevement' && f['dateEffet'] == '0001-01-01')['dateFin'], '2026-08-15');
  });

  test('l’activation du branchement est refusée tant que la charge et les deux comptes ne sont pas arrêtés, puis acceptée (mêmes règles que la maquette)', () {
    var v = _semees();
    var r = aibDefinirReglage(_d(v), {'cle': 'branchementAchats', 'valeur': 'actif', 'dateEffet': '2026-08-16', 'motif': 'Essai'},
        role: 'comptable', libelleRole: 'Comptable', id: 'x', creeLe: '2026-08-16', auteur: 'Comptable');
    expect(r['code'], 'AIB_BRANCHEMENT_INCOMPLET');
    expect((r['manque'] as List).length, 3);
    v = [...v, _v('chargePrelevement', 'acheteur', '2026-08-16', 1), _v('compteAcompte', '447000', '2026-08-16', 1), _v('compteContrepartie', '401110', '2026-08-16', 1)];
    r = aibDefinirReglage(_d(v), {'cle': 'branchementAchats', 'valeur': 'actif', 'dateEffet': '2026-08-16', 'motif': 'Essai'},
        role: 'comptable', libelleRole: 'Comptable', id: 'x', creeLe: '2026-08-16', auteur: 'Comptable');
    expect(r['ok'], isTrue);
    v = [...v, _v('branchementAchats', 'actif', '2026-08-16', 1)];
    final b = aibBranchementALaDate(_d(v), '2026-08-16');
    expect(b['actif'], isTrue);
    expect(b['compteAcompte'], '447000');
    // Un compte hors plan est refusé en le nommant : aucun numéro n'est inventé.
    final c = aibDefinirReglage(_d(v), {'cle': 'compteAcompte', 'valeur': '999999', 'dateEffet': '2026-09-01', 'motif': 'Essai'},
        role: 'comptable', libelleRole: 'Comptable', id: 'y', creeLe: '2026-08-16', auteur: 'Comptable');
    expect(c['code'], 'AIB_COMPTE_INCONNU');
  });

  test('les semences du barème sont celles de la maquette (trois situations, quatre versions, toutes « à valider » : texte réglementaire à produire)', () {
    final sem = obj2(lireVecteurs('aib')['semences']);
    memes(aibSituationsSemees, liste(sem['situations']).map((f) => {for (final k in const ['id', 'code', 'libelle', 'declencheur', 'ordre', 'description']) k: f[k]}).toList(), 'situations');
    memes(aibBaremeSeme, liste(sem['bareme']).map((f) => {for (final k in const ['id', 'situation', 'taux', 'dateEffet', 'dateFin', 'source', 'motif']) k: f[k]}).toList(), 'bareme');
    // Le taux se lit à la version datée : sans IFU, 1 % avant le 07/09/2026 et 5 % après.
    final d = AibDonnees(
        situations: [for (final s in aibSituationsSemees) {...s, 'statut': 'actif'}], bareme: [for (final b in aibBaremeSeme) {...b, 'statut': 'actif', 'aValider': true}]);
    expect(aibTauxPourAcheteur(d, ifu: '', date: '2026-09-06')['taux'], 1);
    expect(aibTauxPourAcheteur(d, ifu: '', date: '2026-09-07')['taux'], 5);
    expect(aibTauxPourAcheteur(d, ifu: '3201642748214', date: '2026-11-09')['taux'], 1);
    expect(aibTauxALaDate(d, 'prestation_service', '2026-11-09')['taux'], 3);
    expect(aibTauxALaDate(d, 'ifu_actif', '2025-12-31')['code'], 'AIB_SANS_BAREME');
  });
}

Map<String, Object?> obj2(Object? o) => (o as Map).cast<String, Object?>();
