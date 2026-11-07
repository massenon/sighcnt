/// COMPTES UTILISATEURS ET SOIGNANTS (M14) — port de `m14-utilisateurs` et `m14-soignants` (prototype_html/assets/js/modules/m14-securite.js).
/// Vecteurs : `test/vecteurs/securite.json` (les formulaires de la maquette pilotés dans Chrome).
///
/// LE MOT DE PASSE EST SAISI, IL N'EST PAS GARDÉ (vague 67) : ce qui entre au magasin, c'est la DATE de définition, son auteur et l'obligation de
/// changer à la première connexion — jamais le secret. [secTransformerCompte] retire la saisie avant toute écriture, et un test le prouve.
library;

import '../consultation/cs_referentiels.dart' show csSecteursSoins;
import 'sec_donnees.dart';

typedef FicheSec = Map<String, Object?>;

/// Vérité à la manière de JavaScript : ni `null`, ni `''`, ni `false`, ni `0`.
bool secVrai(Object? v) => v != null && v != '' && v != false && v != 0;

/// Les rôles à privilèges élevés : le double facteur leur est IMPOSÉ, que la case soit cochée ou non.
const secRolesDoubleFacteur = ['dm', 'da', 'direction', 'admin'];

/// Longueur minimale d'un mot de passe saisi à la création.
const secLongueurMinMotDePasse = 8;

/// `D.SERVICES` (data.js) : les services proposés au rattachement d'un compte.
const secServices = [
  'Médecine générale',
  'Maternité',
  'Chirurgie',
  'Laboratoire',
  'Pharmacie',
  'Imagerie / Échographie',
  'Soins infirmiers',
  'Accueil',
  'Direction',
  'Comptabilité',
];

/// Valeurs d'un compte NEUF (`onCreate`).
FicheSec secCompteParDefaut() =>
    {'actif': true, 'mfa': false, 'role': 'reception', 'doitChangerMotDePasse': true};

/// `beforeSave` : le refus se dit, il n'est jamais muet. Un identifiant ne se partage pas (aucun compte partagé) ; les deux mots de passe se
/// contrôlent à la CRÉATION seulement (à la modification, le formulaire n'en porte pas). Les comptes archivés comptent : l'identifiant reste pris.
String? secVerifierCompte(FicheSec saisie,
    {required Iterable<FicheSec> comptes, FicheSec? record}) {
  final existe = comptes.any((u) =>
      u['identifiant'] == saisie['identifiant'] &&
      (record == null || u['id'] != record['id']));
  if (existe) {
    return 'Cet identifiant est déjà attribué : aucun compte ne peut être partagé.';
  }
  if (record == null) {
    final mdp = secVrai(saisie['motDePasse']) ? '${saisie['motDePasse']}' : '';
    if (mdp.length < secLongueurMinMotDePasse) {
      return 'Le mot de passe doit compter au moins huit caractères.';
    }
    final conf = secVrai(saisie['motDePasseConfirmation'])
        ? '${saisie['motDePasseConfirmation']}'
        : '';
    if (mdp != conf) return 'Les deux mots de passe saisis ne correspondent pas.';
  }
  return null;
}

/// `transform` : ce qui est ÉCRIT. Le secret ne franchit pas cette ligne. [agent] : la fiche du personnel désignée par `employeId` (ou `null`).
/// [jour] : `AAAA-MM-JJ` du jour. Un compte neuf naît avec un dernier accès (le jour) et zéro échec ; une modification n'y touche pas (E591 :
/// la maquette les remettait à zéro à chaque correction de fiche).
FicheSec secTransformerCompte(FicheSec saisie,
    {FicheSec? record,
    FicheSec? agent,
    required String utilisateur,
    required DateTime maintenant,
    required String jour}) {
  final v = {...saisie};
  if (secVrai(v['motDePasse'])) {
    final t = maintenant.toUtc();
    v['motDePasseDefiniLe'] =
        DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond)
            .toIso8601String();
    v['motDePasseDefiniPar'] = utilisateur;
    v['doitChangerMotDePasse'] ??= true;
  }
  v.remove('motDePasse');
  v.remove('motDePasseConfirmation');
  if (agent != null) {
    v['nomComplet'] = agent['nomComplet'];
    v['matricule'] = agent['matricule'];
    v['poste'] = agent['poste'];
    v['service'] = secVrai(v['service']) ? v['service'] : agent['service'];
  }
  if (record == null) {
    if (!secVrai(v['dernierAcces'])) v['dernierAcces'] = jour;
    v['echecs'] ??= 0;
  }
  if (secRolesDoubleFacteur.contains(v['role'])) v['mfa'] = true;
  return v;
}

// --- Prescripteurs & exécutants de soins ---------------------------------------------------------------------------------------------------

/// `D.QUALITES_SOIGNANT` : médecin, sage-femme, infirmier.
List<FicheSec> get secQualitesSoignant => [
      for (final q in (secDonnees['qualites'] as List))
        (q as Map).cast<String, Object?>()
    ];

FicheSec? secQualite(Object? code) {
  for (final q in secQualitesSoignant) {
    if (q['code'] == code) return q;
  }
  return null;
}

/// `D.SECTEURS_SOINS` (salle de soins, hospitalisation, maternité) — le référentiel de la consultation, qui est le même.
List<FicheSec> get secSecteursSoins => csSecteursSoins;

/// Le libellé d'un secteur, ou son code s'il est inconnu.
String secLibelleSecteurSoins(Object? code) {
  for (final s in csSecteursSoins) {
    if (s['code'] == code) return '${s['label']}';
  }
  return '$code';
}

/// Colonne « Secteurs » : les libellés séparés par « · », ou « — ».
String secSecteursEnTexte(Object? secteurs) {
  final l = (secteurs as List? ?? const []).map(secLibelleSecteurSoins).toList();
  return l.isEmpty ? '—' : l.join(' · ');
}

/// `transform` de « Nouveau soignant » : la fiche est DÉRIVÉE du personnel — le nom ne se ressaisit pas.
FicheSec secTransformerSoignant(FicheSec saisie, FicheSec? agent) => {
      ...saisie,
      'nomComplet': agent != null ? agent['nomComplet'] : '—',
      'poste': agent != null ? agent['poste'] : '',
      'source': 'Habilitation saisie par l’administrateur',
    };

/// Les quatre indicateurs : soignants, prescripteurs, exécutants, ceux qui cumulent.
({int total, int prescripteurs, int executants, int cumul}) secCompteSoignants(
        Iterable<FicheSec> fiches) =>
    (
      total: fiches.length,
      prescripteurs: fiches.where((x) => secVrai(x['prescrit'])).length,
      executants: fiches.where((x) => secVrai(x['execute'])).length,
      cumul: fiches.where((x) => secVrai(x['prescrit']) && secVrai(x['execute'])).length,
    );

// --- Habilitations métier (onglet de m14-roles) --------------------------------------------------------------------------------------------

/// Une ligne de l'onglet « Habilitations métier » : `D.CAPACITES`, ligne à ligne.
List<FicheSec> secHabilitationsMetier() {
  final capacites = (secDonnees['capacites'] as Map).cast<String, Object?>();
  final natures = [
    for (final n in (secDonnees['naturesPrescription'] as List))
      (n as Map).cast<String, Object?>()
  ];
  return [
    for (final e in capacites.entries)
      () {
        final c = (e.value as Map).cast<String, Object?>();
        final prescrire = ((c['prescrire'] as List?) ?? const []).cast<String>();
        return <String, Object?>{
          'fonction': e.key,
          'label': c['label'],
          'resultats': c['voirResultats'],
          'echographie': c['voirEchographie'],
          'prescrire': prescrire.length,
          'natures': [
            for (final n in prescrire)
              () {
                for (final x in natures) {
                  if (x['id'] == n) return '${x['label']}';
                }
                return n;
              }()
          ].join(', '),
          'soins': c['executerSoins'],
          'remise': c['remettreResultats'],
          'note': c['note'] ?? '',
        };
      }()
  ];
}
