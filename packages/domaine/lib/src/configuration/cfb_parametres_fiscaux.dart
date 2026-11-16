// LES PARAMÈTRES DU CALENDRIER FISCAL, DATÉS (Direction, 09/11/2026, lot A3b ; portage au lot FISC-2), portés de `D.delaisFiscauxALaDate`, `D.montantCcibALaDate`
// et `D.parametreFiscalALaDate` (data.js), rejoués sur `test/vecteurs/fisc2.json` (prototype_html/build/vecteurs-fisc2.js).
//
// Trois valeurs vivaient dans le code : les seuils d'état du suivi (10 et 30 jours), le seuil d'alerte du planificateur et le montant de la CCIB. Elles sont une
// collection, `parametresFiscaux` : UNE FICHE PAR VERSION, la version en vigueur à une date est celle de la plus grande date d'effet qui ne la dépasse pas (une
// version à venir est une fiche dont la date d'effet n'est pas atteinte ; l'annuler l'archive). Les valeurs ci-dessous ne sont que la SEMENCE, « à valider ».
library;

import 'cfa_regles.dart' show CfaFiche;

/// La semence (`semenceParametresFiscaux()`) : les délais d'alerte (10 et 30 jours) et le montant de la CCIB (300 000 FCFA en deux tranches), « à valider ».
List<CfaFiche> cfbSemenceParametresFiscaux() => [
      {
        'id': 'PFI-DELAIS',
        'statut': 'actif',
        'code': 'DELAIS-ALERTE',
        'libelle': 'Délais d’alerte du calendrier fiscal',
        'delaiAPayer': 10,
        'delaiDeclaration': 30,
        'source': 'Valeurs d’attente de la maquette (suivi des échéances, jusqu’ici écrites dans le code) : à confirmer par la Direction',
        'aValider': true,
        'dateEffet': null,
        'motif': null,
        'modifieLe': null,
        'modifiePar': null,
      },
      {
        'id': 'PFI-CCIB',
        'statut': 'actif',
        'code': 'CCIB-MONTANT',
        'libelle': 'Montant annuel de la CCIB',
        'montantTotal': 300000,
        'tranches': 2,
        'source': 'Montant à confirmer par le cabinet comptable',
        'aValider': true,
        'dateEffet': null,
        'motif': null,
        'modifieLe': null,
        'modifiePar': null,
      },
    ];

String _jour(Object? d) {
  final s = '${d ?? ''}';
  return s.length > 10 ? s.substring(0, 10) : s;
}

/// Les versions d'un paramètre, de la plus ancienne à la plus récente (les archivées n'y sont pas) ; la semence si la collection n'en porte aucune.
List<CfaFiche> cfbVersionsParametreFiscal(Iterable<CfaFiche> fiches, String code) {
  var l = [for (final p in fiches) if (p['code'] == code && p['statut'] != 'archive') p];
  if (l.isEmpty) l = [for (final p in cfbSemenceParametresFiscaux()) if (p['code'] == code) p];
  l.sort((a, b) => '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}'));
  return l;
}

/// La version d'un paramètre en vigueur à [date] (`null` : paramètre inconnu).
CfaFiche? cfbParametreFiscalALaDate(Iterable<CfaFiche> fiches, String code, Object date) {
  final d = _jour(date);
  CfaFiche? v;
  for (final p in cfbVersionsParametreFiscal(fiches, code)) {
    if (p['dateEffet'] == null || _jour(p['dateEffet']).compareTo(d) <= 0) v = p;
  }
  return v;
}

num _nombre(Object? x) => x is num ? x : (num.tryParse('${x ?? ''}') ?? 0);

/// Les délais d'alerte en vigueur : `(delaiAPayer, delaiDeclaration)`. UNE SEULE définition de « proche » pour le suivi, la vue mensuelle, la fiscalité, la cloche
/// et le planificateur.
({int delaiAPayer, int delaiDeclaration}) cfbDelaisFiscauxALaDate(Iterable<CfaFiche> fiches, Object date) {
  final v = cfbParametreFiscalALaDate(fiches, 'DELAIS-ALERTE', date) ?? cfbSemenceParametresFiscaux().first;
  return (delaiAPayer: _nombre(v['delaiAPayer']).toInt(), delaiDeclaration: _nombre(v['delaiDeclaration']).toInt());
}

/// Le montant de la CCIB en vigueur : `(total, tranches, tranche)`.
({num total, int tranches, num tranche}) cfbMontantCcibALaDate(Iterable<CfaFiche> fiches, Object date) {
  final v = cfbParametreFiscalALaDate(fiches, 'CCIB-MONTANT', date) ?? cfbSemenceParametresFiscaux()[1];
  final t = _nombre(v['tranches']).toInt();
  final n = t == 0 ? 2 : t;
  final total = _nombre(v['montantTotal']);
  return (total: total, tranches: n, tranche: total / n);
}
