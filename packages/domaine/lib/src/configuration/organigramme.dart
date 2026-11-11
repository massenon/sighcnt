/// L'ORGANIGRAMME, SES POSTES ET LE TITRE DE L'AGENT (lot ORG2, Direction, 11/11/2026, O1 à O5).
///
/// Port de `SIGH.organigramme` (`prototype_html/assets/js/parcours.js`, fin du fichier), de `S.migrerOrganigramme` (`store.js`), de `D.postesDeLaSemence` (`data.js`) et de
/// `P.organigramme` (`print.js`) ; vecteurs `test/vecteurs/organigramme.json`, engendrés par `prototype_html/build/vecteurs-organigramme.js`. Fonctions PURES : elles reçoivent
/// les postes et le personnel lus au magasin et rendent un PLAN (ce qu'il faut écrire, ce qu'il faut journaliser) ou un refus nommé (code, motif, geste) ; elles n'écrivent rien.
///
/// L'organigramme suit la photo du papier de la clinique MAIS n'est pas figé (O4) : réaffecter un poste, renommer son titulaire quand une autre personne est affectée (O2), poser
/// le titre de l'agent (O3 : le surveillant général est un infirmier, « SG » est porté par l'AGENT et non par le poste) ou archiver un poste (RG-14) se fait au CRUD, et
/// l'impression en paysage suit. Aucune étoile (O5). Le titre est lu sur la fiche du PERSONNEL (`titreOrganigramme`), rattachée au poste par le NOM du titulaire, comme partout.
library;

import '../format/recherche.dart' show normaliser;
import '../rh/planning_rh.dart' show RefusRh;

typedef FichePoste = Map<String, Object?>;

/// Le titre d'un agent dans l'organigramme tient en douze caractères au plus (« SG », « C/S »).
const int orgTitreMax = 12;

/// Les champs d'un poste que le CRUD modifie, dans l'ordre où le journal les cite.
const List<String> orgChampsPoste = ['poste', 'parentId', 'effectif', 'titulaire', 'chef', 'role'];

RefusRh _refus(String code, String motif, String geste, [Map<String, Object?> extra = const {}]) => RefusRh(code, motif, geste, extra);

bool _vrai(Object? v) => v != null && v != false && v != 0 && v != '';

/// `String(v).trim()` de JavaScript : `null` s'écrit « null », jamais vide.
String _texte(Object? v) => '${v ?? 'null'}'.trim();

/// `Number(v)` de JavaScript pour une saisie : chaîne vide ou blanche = 0, non numérique = NaN.
double _nombre(Object? v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v == null) return 0;
  final t = '$v'.trim();
  if (t.isEmpty) return 0;
  return double.tryParse(t.replaceAll(',', '.')) ?? double.nan;
}

String? _nom(Object? v) => v == null ? null : '$v';

// =============================================================================================================================================
// La semence (D.postesDeLaSemence) et celle d'avant (D.ORGANIGRAMME_PRECEDENT)
// =============================================================================================================================================

/// La semence de la collection `postes` : l'organigramme de la photo, aplati dans l'ordre du parcours en profondeur. Les identifiants sont STABLES : c'est ce qui permet à une
/// reprise de reconnaître la fiche qu'elle doit réécrire sans toucher à celles que la clinique a modifiées.
List<FichePoste> orgSemence() => [
      for (final l in _semence)
        {
          'id': l.$1,
          'statut': 'actif',
          'parentId': l.$2,
          'poste': l.$3,
          'effectif': l.$4,
          'titulaire': l.$5,
          'chef': l.$6,
          'role': l.$7,
          'source': 'Organigramme de la Clinique NASSIERA TOO',
          'semence': 2,
        }
    ];

// (id, parent, intitulé, effectif, titulaire, chef de service, rôle)
const List<(String, String?, String, int, String?, bool, String)> _semence = [
  ('PST001', null, 'Directeur Médical', 1, 'BASSONGUI Chabi Séko', false, 'dm'),
  ('PST002', 'PST001', 'Directrice Administrative (DA)', 1, 'TAKI Alimatou épse BASSONGUI', false, 'da'),
  ('PST003', 'PST002', 'Comptable', 1, 'KASSA Augustin', false, 'comptable'),
  ('PST004', 'PST003', 'Assistant comptable', 1, 'GBEDJI Hervé', false, 'comptable'),
  ('PST005', 'PST004', 'Gestionnaire de Stock', 1, 'MAMAN Zoukanéri', false, 'stock'),
  ('PST007', 'PST002', 'Dispensatrices', 4, 'DIEYABIDI Aïssatou', true, 'pharmacien'),
  ('PST008', 'PST002', 'Agents de Sécurités', 3, 'OURTCHA TEREYAMA', true, 'agentadmin'),
  ('PST014', 'PST001', 'Infirmiers', 8, 'GARBA Yahouza', false, 'infirmier'),
  ('PST015', 'PST014', 'Sages-Femmes', 3, null, false, 'infirmier'),
  ('PST016', 'PST014', 'Aide-Soignante', 8, 'TEPA Séraphine', true, 'aide_soignant'),
  ('PST013', 'PST001', 'Laborantins', 2, 'KINNOU Addoul Ganiou', true, 'laborantin'),
  ('PST012', 'PST001', 'Echographiste', 1, 'AHOHOU Rodrigue', false, 'medecin'),
  ('PST011', 'PST001', 'Médecins Généralistes', 2, 'YENI M’PO Florent', false, 'medecin'),
  ('PST006', 'PST001', 'Secrétaires Médicaux', 4, 'OROU YO Edmond', true, 'reception'),
  ('PST010', 'PST006', 'Chauffeur Coursier', 1, 'TCHANE Nourou', false, 'ambulancier'),
  ('PST009', 'PST001', 'Agents d’Entretiens', 3, 'ISSA Rabiatou', true, 'agentadmin'),
];

/// La semence D'AVANT le 11/11/2026 : elle ne sert qu'à RECONNAÎTRE une fiche que la clinique n'a pas touchée.
List<FichePoste> orgPrecedent() => [
      for (final l in _precedent) {'id': l.$1, 'parentId': l.$2, 'poste': l.$3, 'effectif': l.$4, 'titulaire': l.$5, 'chef': l.$6, 'role': l.$7}
    ];

const List<(String, String?, String, int, String?, bool, String)> _precedent = [
  ('PST001', null, 'Directeur Médical', 1, 'BASSONGUI Chabi Séko', false, 'dm'),
  ('PST002', 'PST001', 'Directrice Administrative', 1, 'TAKI Alimatou épse BASSONGUI', false, 'da'),
  ('PST003', 'PST002', 'Comptable', 1, 'KASSA Augustin', false, 'comptable'),
  ('PST004', 'PST003', 'Assistant Comptable', 1, 'GBEDJI Hervé', false, 'comptable'),
  ('PST005', 'PST002', 'Gestionnaire de Stock', 1, 'MAMAN Zoukanéri', false, 'stock'),
  ('PST006', 'PST002', 'Secrétaires Médicaux', 4, 'OROU YO Edmond', true, 'reception'),
  ('PST007', 'PST002', 'Dispensatrices', 4, 'DIEYABIDI Aïssatou', true, 'pharmacien'),
  ('PST008', 'PST002', 'Agents de Sécurité', 3, 'OURTCHA TEREYAMA', true, 'agentadmin'),
  ('PST009', 'PST002', 'Agents d’Entretien', 3, 'ISSA Rabiatou', true, 'agentadmin'),
  ('PST010', 'PST002', 'Chauffeur Coursier', 1, 'TCHANE Nourou', false, 'ambulancier'),
  ('PST011', 'PST001', 'Médecins Généralistes', 2, 'YENI M’PO Florent', false, 'medecin'),
  ('PST012', 'PST001', 'Échographiste', 1, 'AHOHOU Rodrigue', false, 'medecin'),
  ('PST013', 'PST001', 'Laborantins', 2, 'KINNOU Addoul Ganiou', true, 'laborantin'),
  ('PST014', 'PST001', 'Infirmiers', 8, 'GARBA Yahouza', true, 'infirmier'),
  ('PST015', 'PST001', 'Sages-Femmes', 3, null, false, 'infirmier'),
  ('PST016', 'PST001', 'Aide-Soignantes', 8, 'TEPA Séraphine', true, 'aide_soignant'),
];

// =============================================================================================================================================
// Le titre de l'agent
// =============================================================================================================================================

/// Un nom comparable : sans la mention d'épouse, sans accents ni majuscules, espaces réduits (`cleNomOrg`).
String orgCleNom(Object? n) =>
    normaliser('${n ?? ''}'.replaceAll(RegExp(r'\s+[ée]pse\s+.*$', caseSensitive: false), '')).replaceAll(RegExp(r'\s+'), ' ').trim();

/// L'agent du personnel qui porte le nom du titulaire du poste, ou `null` (poste vacant, ou titulaire qui n'est pas au personnel). [personnelActif] : les fiches non archivées.
FichePoste? orgAgentDuPoste(FichePoste? poste, Iterable<FichePoste> personnelActif) {
  if (poste == null || !_vrai(poste['titulaire'])) return null;
  final cle = orgCleNom(poste['titulaire']);
  for (final a in personnelActif) {
    if (orgCleNom(a['nomComplet']) == cle) return a;
  }
  return null;
}

/// Le titre que son titulaire porte dans l'organigramme, ou `null`.
String? orgTitreDuPoste(FichePoste? poste, Iterable<FichePoste> personnelActif) {
  final a = orgAgentDuPoste(poste, personnelActif);
  return a != null && _vrai(a['titreOrganigramme']) ? '${a['titreOrganigramme']}' : null;
}

/// Un nœud de l'arbre des postes actifs, avec le titre de son titulaire (`titreAgent`).
class OrgNoeud {
  OrgNoeud(this.fiche, this.titreAgent);
  final FichePoste fiche;
  final String? titreAgent;
  final List<OrgNoeud> enfants = [];
  String get id => '${fiche['id']}';
  String get poste => '${fiche['poste'] ?? ''}';
}

/// L'arbre des postes ACTIFS (`arbreOrganigramme`) : un poste dont le parent est archivé ou absent est un sommet.
List<OrgNoeud> orgArbre(Iterable<FichePoste> postesActifs, Iterable<FichePoste> personnelActif) {
  final parId = {for (final p in postesActifs) '${p['id']}': OrgNoeud(p, orgTitreDuPoste(p, personnelActif))};
  final racines = <OrgNoeud>[];
  for (final p in postesActifs) {
    final n = parId['${p['id']}']!;
    final parent = p['parentId'];
    if (_vrai(parent) && parId.containsKey('$parent')) {
      parId['$parent']!.enfants.add(n);
    } else {
      racines.add(n);
    }
  }
  return racines;
}

/// Les identifiants des postes ACTIFS sous [id], à tous les niveaux (`descendantsOrganigramme`).
List<String> orgDescendants(String id, Iterable<FichePoste> postesActifs) {
  final actifs = postesActifs.toList();
  final vus = <String>{};
  final pile = [id];
  final out = <String>[];
  while (pile.isNotEmpty) {
    final x = pile.removeLast();
    for (final p in actifs) {
      if (p['parentId'] == x && !vus.contains('${p['id']}')) {
        vus.add('${p['id']}');
        out.add('${p['id']}');
        pile.add('${p['id']}');
      }
    }
  }
  return out;
}

FichePoste? _poste(String? id, Iterable<FichePoste> postes) {
  if (id == null) return null;
  for (final p in postes) {
    if (p['id'] == id) return p;
  }
  return null;
}

bool _archive(FichePoste p) => p['statut'] == 'archive';

// =============================================================================================================================================
// Les contrôles
// =============================================================================================================================================

/// Le refus du droit : seuls les profils qui écrivent (ou, pour archiver, qui annulent) à l'écran « Organisation & organigramme » modifient l'organigramme.
RefusRh orgRefusDroit({bool archivage = false}) => _refus(
    'ORGANIGRAMME_RESERVE',
    archivage
        ? 'L’archivage d’un poste est réservé aux profils qui annulent à l’écran « Organisation & organigramme » (RG-14).'
        : 'La modification de l’organigramme est réservée aux profils qui écrivent à l’écran « Organisation & organigramme ».',
    'Demander à l’administrateur ou à la Directrice Administrative.');

/// Le rattachement demandé est-il permis ? `null` si oui, sinon le refus nommé. [postes] : TOUTES les fiches, archivées comprises.
RefusRh? orgControlerRattachement(String? posteId, String? parentId, Iterable<FichePoste> postes) {
  if (!_vrai(parentId)) return null;
  final parent = _poste(parentId, postes);
  if (parent == null) return _refus('PARENT_INTROUVABLE', 'Le poste de rattachement demandé n’existe pas.', 'Choisir un poste de la liste.');
  if (_archive(parent)) {
    return _refus('PARENT_ARCHIVE', 'Le poste « ${parent['poste']} » est archivé : on ne rattache rien à un poste archivé (RG-14).',
        'Restaurer ce poste depuis la corbeille, ou choisir un poste actif.');
  }
  if (_vrai(posteId) && (parentId == posteId || orgDescendants(posteId!, [for (final p in postes) if (!_archive(p)) p]).contains(parentId))) {
    final moi = _nom(_poste(posteId, postes)?['poste']) ?? 'ce poste';
    return _refus(
        'RATTACHEMENT_CYCLE',
        'Rattacher « $moi » à « ${parent['poste']} » ferait de lui son propre supérieur : '
            '${parentId == posteId ? 'un poste ne se rattache pas à lui-même.' : '« ${parent['poste']} » dépend déjà de « $moi ».'}',
        'Choisir un poste qui ne dépende pas de celui-ci, ou réaffecter d’abord ses rattachés.',
        {'parentId': parentId});
  }
  return null;
}

/// Contrôle d'une saisie de poste SANS rien écrire. [posteId] nul : création. [champs] : les champs saisis (ceux d'une modification partielle suffisent). [rolesConnus] : les
/// identifiants de rôle du manifeste.
RefusRh? orgControler(String? posteId, Map<String, Object?> champs,
    {required Iterable<FichePoste> postes, required Iterable<FichePoste> personnelActif, required Set<String> rolesConnus}) {
  final poste = _vrai(posteId) ? _poste(posteId, postes) : null;
  if (_vrai(posteId) && poste == null) return _refus('POSTE_INTROUVABLE', 'Ce poste n’existe pas.', 'Rouvrir l’écran puis choisir un poste de la liste.');
  if (poste != null && _archive(poste)) {
    return _refus('POSTE_ARCHIVE', 'Le poste « ${poste['poste']} » est archivé : il ne se modifie pas.', 'Le restaurer depuis la corbeille d’abord.');
  }
  if (champs.containsKey('poste') && _texte(champs['poste']).isEmpty) return _refus('INTITULE_VIDE', 'L’intitulé du poste est obligatoire.', 'Saisir l’intitulé du poste.');
  if (champs.containsKey('effectif') && champs['effectif'] != '' && champs['effectif'] != null) {
    final n = _nombre(champs['effectif']);
    if (!n.isFinite || n < 0 || n != n.floorToDouble()) {
      return _refus('EFFECTIF_INVALIDE', 'L’effectif d’un poste est un nombre entier, zéro ou plus.', 'Saisir un nombre entier.');
    }
  }
  if (champs.containsKey('role') && champs['role'] != '' && !rolesConnus.contains('${champs['role']}')) {
    return _refus('ROLE_INCONNU', 'Le rôle « ${champs['role']} » n’existe pas.', 'Choisir un rôle de la liste.');
  }
  if (champs.containsKey('parentId')) {
    final r = orgControlerRattachement(posteId, _vrai(champs['parentId']) ? '${champs['parentId']}' : null, postes);
    if (r != null) return r;
  }
  if (champs.containsKey('titreAgent')) {
    final titre = '${_vrai(champs['titreAgent']) ? champs['titreAgent'] : ''}'.trim();
    final vise = <String, Object?>{...?poste, if (champs.containsKey('titulaire')) 'titulaire': champs['titulaire']};
    if (poste == null) vise['titulaire'] = champs['titulaire'];
    if (titre.length > orgTitreMax) {
      return _refus('TITRE_TROP_LONG', 'Le titre dans l’organigramme tient en $orgTitreMax caractères au plus (« SG », « C/S »).', 'Abréger le titre.');
    }
    final agent = orgAgentDuPoste(vise, personnelActif);
    if (titre.isNotEmpty && !_vrai(vise['titulaire'])) {
      return _refus('POSTE_VACANT', 'Le poste n’a pas de titulaire : le titre est porté par un agent, il n’y en a pas à qui le poser.', 'Saisir d’abord le titulaire du poste.');
    }
    if (titre.isNotEmpty && agent == null) {
      return _refus('AGENT_INTROUVABLE', 'Aucun agent du personnel ne porte le nom « ${vise['titulaire']} » : le titre est porté par l’agent, pas par le poste.',
          'Corriger le nom du titulaire pour qu’il corresponde à une fiche du personnel, ou enregistrer l’agent au personnel.');
    }
  }
  return null;
}

// =============================================================================================================================================
// Le plan d'une modification, d'une création, d'un archivage
// =============================================================================================================================================

/// Une ligne de journal décrite par le plan : action, entité, et valeurs d'avant et d'après (RG-12).
class OrgJournal {
  const OrgJournal(this.action, this.module, this.entite, this.avant, this.apres);
  final String action, module, entite;
  final Map<String, Object?> avant, apres;
}

/// Ce qu'il faut écrire pour une modification de poste, ou le refus nommé.
class OrgPlan {
  const OrgPlan({this.refus, this.inchange = false, this.patch = const {}, this.journalPoste, this.agentId, this.titreAvantAgent, this.titrePose, this.journalTitre, this.titre});
  final RefusRh? refus;
  final bool inchange;

  /// Les champs du poste qui changent (clés dans l'ordre de [orgChampsPoste]).
  final Map<String, Object?> patch;
  final OrgJournal? journalPoste;

  /// La fiche du personnel dont le titre change, ce titre avant, et le titre posé (`null` = retiré).
  final String? agentId;
  final String? titreAvantAgent;
  final String? titrePose;
  final OrgJournal? journalTitre;

  /// Le titre que `modifier` rend : celui d'AVANT quand la saisie n'en pose pas, sinon celui posé.
  final String? titre;
  bool get ok => refus == null;
  bool get changeTitre => journalTitre != null;
}

/// Planifie la modification d'un poste (`modifierPosteOrg`) : n'importe quel sous-ensemble de { poste, parentId, effectif, titulaire, chef, role, titreAgent }. Tout est contrôlé
/// AVANT la première écriture. [droitEcriture] : le profil écrit-il à l'écran ?
OrgPlan orgPlanifierModification(String posteId, Map<String, Object?> champs,
    {required bool droitEcriture, required Iterable<FichePoste> postes, required Iterable<FichePoste> personnelActif, required Set<String> rolesConnus}) {
  if (!droitEcriture) return OrgPlan(refus: orgRefusDroit());
  final refus = orgControler(posteId, champs, postes: postes, personnelActif: personnelActif, rolesConnus: rolesConnus);
  if (refus != null) return OrgPlan(refus: refus);
  final poste = _poste(posteId, postes)!;
  final patch = <String, Object?>{};
  for (final k in orgChampsPoste) {
    if (!champs.containsKey(k)) continue;
    Object? v = champs[k];
    if (k == 'poste') {
      v = _texte(v);
    } else if (k == 'parentId') {
      v = _vrai(v) ? '$v' : null;
    } else if (k == 'effectif') {
      v = v == '' || v == null ? poste['effectif'] : _entier(_nombre(v));
    } else if (k == 'titulaire') {
      final t = '${_vrai(v) ? v : ''}'.trim();
      v = t.isEmpty ? null : t;
    } else if (k == 'chef') {
      v = v == true || v == 'true';
    }
    final avant = poste.containsKey(k) ? poste[k] : null;
    if (!_egaux(avant, v)) patch[k] = v;
  }
  final titreAvant = orgTitreDuPoste(poste, personnelActif);
  final titreSaisi = champs.containsKey('titreAgent');
  final titrePose = !titreSaisi ? null : (('${_vrai(champs['titreAgent']) ? champs['titreAgent'] : ''}'.trim()).isEmpty ? null : '${champs['titreAgent']}'.trim());
  final vise = {...poste, ...patch};
  final agent = orgAgentDuPoste(vise, personnelActif);
  final titreAgentAvant = agent != null && _vrai(agent['titreOrganigramme']) ? '${agent['titreOrganigramme']}' : null;
  final changeTitre = titreSaisi && agent != null && titreAgentAvant != titrePose;
  if (patch.isEmpty && !changeTitre) return OrgPlan(inchange: true);
  OrgJournal? jp;
  if (patch.isNotEmpty) {
    final avant = <String, Object?>{'poste': poste['poste']};
    final apres = <String, Object?>{};
    for (final k in patch.keys) {
      if (k == 'parentId') {
        avant[k] = _nom(_poste(_nom(poste['parentId']), postes)?['poste']);
        apres[k] = _nom(_poste(_nom(patch['parentId']), postes)?['poste']);
      } else {
        if (poste.containsKey(k)) avant[k] = poste[k];
        apres[k] = patch[k];
      }
    }
    final action = patch.length == 1 && patch.containsKey('parentId')
        ? 'Réaffectation d’un poste'
        : patch.length == 1 && patch.containsKey('titulaire')
            ? 'Changement de titulaire d’un poste'
            : 'Modification d’un poste';
    jp = OrgJournal(action, 'CFG', 'Poste', avant, apres);
  }
  OrgJournal? jt;
  if (changeTitre) {
    jt = OrgJournal('Titre d’un agent dans l’organigramme', 'CFG', 'Agent', {'agent': agent['nomComplet'], 'titre': titreAgentAvant}, {'titre': titrePose, 'poste': vise['poste']});
  }
  return OrgPlan(
      patch: patch,
      journalPoste: jp,
      agentId: changeTitre ? '${agent['id']}' : null,
      titreAvantAgent: titreAgentAvant,
      titrePose: titrePose,
      journalTitre: jt,
      titre: !titreSaisi ? titreAvant : titrePose);
}

num _entier(double n) => n == n.floorToDouble() ? n.toInt() : n;

/// `a !== b` de JavaScript pour des valeurs simples : nombres comparés par valeur.
bool _egaux(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

/// La réaffectation : un cas particulier de modification.
OrgPlan orgPlanifierReaffectation(String posteId, String? parentId,
        {required bool droitEcriture, required Iterable<FichePoste> postes, required Iterable<FichePoste> personnelActif, required Set<String> rolesConnus}) =>
    orgPlanifierModification(posteId, {'parentId': parentId}, droitEcriture: droitEcriture, postes: postes, personnelActif: personnelActif, rolesConnus: rolesConnus);

/// La fiche d'un poste créé (sans identifiant : le magasin l'attribue), ou le refus nommé. Un poste sans rattachement est un sommet.
({RefusRh? refus, FichePoste? fiche}) orgPlanifierCreation(Map<String, Object?> champs,
    {required bool droitEcriture, required Iterable<FichePoste> postes, required Iterable<FichePoste> personnelActif, required Set<String> rolesConnus}) {
  if (!droitEcriture) return (refus: orgRefusDroit(), fiche: null);
  final refus = orgControler(null, champs, postes: postes, personnelActif: personnelActif, rolesConnus: rolesConnus);
  if (refus != null) return (refus: refus, fiche: null);
  if (!champs.containsKey('poste')) return (refus: _refus('INTITULE_VIDE', 'L’intitulé du poste est obligatoire.', 'Saisir l’intitulé du poste.'), fiche: null);
  final tit = '${_vrai(champs['titulaire']) ? champs['titulaire'] : ''}'.trim();
  return (
    refus: null,
    fiche: <String, Object?>{
      'statut': 'actif',
      'poste': _texte(champs['poste']),
      'parentId': _vrai(champs['parentId']) ? '${champs['parentId']}' : null,
      'effectif': !champs.containsKey('effectif') || champs['effectif'] == '' ? 1 : _entier(_nombre(champs['effectif'])),
      'titulaire': tit.isEmpty ? null : tit,
      'chef': champs['chef'] == true || champs['chef'] == 'true',
      'role': _vrai(champs['role']) ? '${champs['role']}' : 'agentadmin',
    }
  );
}

/// L'archivage d'un poste : `null` si permis, sinon le refus nommé. Un poste qui porte encore des postes actifs ne s'archive pas : les rattachés deviendraient des sommets sans
/// que personne l'ait décidé. [droitAnnulation] : le profil annule-t-il à l'écran (RG-14) ?
RefusRh? orgControlerArchivage(String posteId, {required bool droitAnnulation, required Iterable<FichePoste> postes}) {
  if (!droitAnnulation) return orgRefusDroit(archivage: true);
  final poste = _poste(posteId, postes);
  if (poste == null) return _refus('POSTE_INTROUVABLE', 'Ce poste n’existe pas.', 'Rouvrir l’écran puis choisir un poste de la liste.');
  if (_archive(poste)) return _refus('POSTE_ARCHIVE', 'Le poste « ${poste['poste']} » est déjà archivé.', 'Le restaurer depuis la corbeille si besoin.');
  final portes = [for (final p in postes) if (!_archive(p) && p['parentId'] == posteId) p];
  if (portes.isNotEmpty) {
    final n = portes.length;
    return _refus(
        'POSTE_PORTE_DES_POSTES',
        'Le poste « ${poste['poste']} » porte encore $n poste${n > 1 ? 's' : ''} (${portes.map((p) => p['poste']).join(', ')}) : l’archiver les ferait remonter au sommet sans que personne l’ait décidé.',
        'Réaffecter d’abord ces postes, puis archiver celui-ci.',
        {'portes': [for (final p in portes) p['id']]});
  }
  return null;
}

// =============================================================================================================================================
// La reprise (S.migrerOrganigramme)
// =============================================================================================================================================

/// Le bilan d'une reprise : les postes réécrits, ceux gardés tels quels (modifiés par la clinique), les champs `etoile` retirés.
class OrgBilanReprise {
  OrgBilanReprise({List<String>? reecrits, List<String>? gardes, this.etoiles = 0})
      : reecrits = reecrits ?? [],
        gardes = gardes ?? [];
  final List<String> reecrits, gardes;
  int etoiles;
  Map<String, Object?> toJson() => {'reecrits': reecrits, 'gardes': gardes, 'etoiles': etoiles};
}

/// Un poste est INTACT s'il ne porte aucune trace d'écran (`_modifieLe`, `_modifiePar`, `_archiveLe`, archivé) ET s'il est identique à la ligne de l'ancienne semence.
bool orgPosteIntact(FichePoste f, FichePoste ref) {
  if (f['statut'] == 'archive' || _vrai(f['_modifieLe']) || _vrai(f['_modifiePar']) || _vrai(f['_archiveLe'])) return false;
  num? eff(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
  return f['poste'] == ref['poste'] &&
      (_vrai(f['parentId']) ? f['parentId'] : null) == (_vrai(ref['parentId']) ? ref['parentId'] : null) &&
      eff(f['effectif']) == eff(ref['effectif']) &&
      (_vrai(f['titulaire']) ? f['titulaire'] : null) == (_vrai(ref['titulaire']) ? ref['titulaire'] : null) &&
      _vrai(f['chef']) == _vrai(ref['chef']) &&
      f['role'] == ref['role'];
}

/// La reprise, EN PLACE sur [postes] : réécrit les postes intacts par la semence de la photo (ils reçoivent `semence: 2` et ne sont plus jamais retouchés), garde les autres tels
/// quels, retire tout champ `etoile`. Idempotente.
OrgBilanReprise orgMigrer(List<FichePoste> postes) {
  final bilan = OrgBilanReprise();
  final precedents = {for (final l in orgPrecedent()) '${l['id']}': l};
  final neufs = {for (final l in orgSemence()) '${l['id']}': l};
  for (final f in postes) {
    if (f.containsKey('etoile')) {
      f.remove('etoile');
      bilan.etoiles++;
    }
    final sem = f['semence'];
    if ((sem is num ? sem : num.tryParse('${sem ?? ''}') ?? 0) >= 2) continue;
    final ref = precedents['${f['id']}'], neuf = neufs['${f['id']}'];
    if (ref == null || neuf == null) continue;
    if (orgPosteIntact(f, ref)) {
      for (final k in const ['poste', 'parentId', 'effectif', 'titulaire', 'chef', 'role', 'semence']) {
        if (neuf[k] == null) {
          f.remove(k);
        } else {
          f[k] = neuf[k];
        }
      }
      bilan.reecrits.add('${f['id']}');
    } else {
      bilan.gardes.add('${f['id']}');
    }
  }
  return bilan;
}

// =============================================================================================================================================
// La mise en page de l'impression (P.organigramme) : A4 paysage, boîtes et connecteurs
// =============================================================================================================================================

/// Une boîte dessinée : le poste, sa position et ses dimensions en millimètres dans le cadre, et ses lignes de texte.
class OrgBoite {
  const OrgBoite(this.poste, this.gauche, this.haut, this.largeur, this.hauteur, this.lignes);
  final String poste;
  final double gauche, haut, largeur, hauteur;
  final List<String> lignes;
}

/// Un trait de connecteur (x1, y1, x2, y2) et une flèche (le triangle d'une descente), en millimètres.
class OrgTrait {
  const OrgTrait(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}

class OrgFleche {
  const OrgFleche(this.points);

  /// Les trois sommets du triangle : (x, y).
  final List<(double, double)> points;
}

class OrgMiseEnPage {
  const OrgMiseEnPage({required this.largeur, required this.hauteur, required this.niveaux, required this.boites, required this.traits, required this.fleches});
  final double largeur, hauteur;
  final int niveaux;
  final List<OrgBoite> boites;
  final List<OrgTrait> traits;
  final List<OrgFleche> fleches;
}

/// Ce que la feuille dit quand aucun poste actif n'est à représenter.
const String orgTexteAucunPoste = 'Aucun poste actif à représenter.';

/// Les mesures par défaut, en millimètres : la feuille A4 paysage offre 273 mm de large (12 mm de marge de chaque côté).
class OrgOptions {
  const OrgOptions({this.largeur = 273, this.hauteurMax = 120, this.hauteurBoite = 19, this.ecartMin = 6, this.boiteMin = 24, this.boiteMax = 52, this.gouttiere = 2.5});
  final double largeur, hauteurMax, hauteurBoite, ecartMin, boiteMin, boiteMax, gouttiere;
}

class _F {
  _F(this.n, this.parent);
  final OrgNoeud n;
  final _F? parent;
  final List<_F> enfants = [];
  double x = 0, cx = 0, w = 0;
  int fentes = 1;
}

/// La mise en page de l'arbre : un ARBRE ORDONNÉ. Les feuilles se rangent de gauche à droite (une fente chacune), un parent se CENTRE au-dessus de ses enfants (un enfant unique
/// tombe pile dessous) ; une boîte est au moins aussi large que sa fente, et plus quand la rangée a de la place, sans jamais chevaucher sa voisine. Aucun connecteur ne traverse
/// le sous-arbre d'un autre. Rend `null` s'il n'y a aucun poste à représenter.
OrgMiseEnPage? orgMiseEnPage(List<OrgNoeud> racines, {OrgOptions o = const OrgOptions()}) {
  final rangees = <List<_F>>[];
  _F fiche(OrgNoeud n, int niveau, _F? parent) {
    final f = _F(n, parent);
    parent?.enfants.add(f);
    while (rangees.length <= niveau) {
      rangees.add([]);
    }
    rangees[niveau].add(f);
    for (final e in n.enfants) {
      fiche(e, niveau + 1, f);
    }
    if (f.enfants.isNotEmpty) f.fentes = f.enfants.fold(0, (s, c) => s + c.fentes);
    return f;
  }

  final forets = [for (final r in racines) fiche(r, 0, null)];
  if (rangees.isEmpty) return null;
  final total = forets.fold<int>(0, (s, f) => s + f.fentes);
  void placer(List<_F> liste, double debut) {
    for (final f in liste) {
      if (f.enfants.isNotEmpty) {
        placer(f.enfants, debut);
        f.cx = (f.enfants.first.cx + f.enfants.last.cx) / 2;
      } else {
        f.cx = debut + 0.5;
      }
      debut += f.fentes;
    }
  }

  placer(forets, 0);
  final w = o.largeur;
  final fente = w / total;
  final bw = (fente - o.gouttiere).clamp(o.boiteMin, o.boiteMax).toDouble();
  final bh = o.hauteurBoite;
  final nb = rangees.length;
  final ecart = nb > 1 ? ((o.hauteurMax - nb * bh) / (nb - 1)).clamp(o.ecartMin, 14.0 < o.ecartMin ? o.ecartMin : 14.0).toDouble() : 0.0;
  final hTotal = nb * bh + (nb - 1) * ecart;
  double haut(int r) => r * (bh + ecart);
  for (final rg in rangees) {
    for (final f in rg) {
      f.x = f.cx * fente;
    }
  }
  for (final rg in rangees) {
    for (var i = 0; i < rg.length; i++) {
      final f = rg[i];
      var dispo = [2 * f.x, 2 * (w - f.x)].reduce((a, b) => a < b ? a : b);
      if (i > 0) dispo = dispo < f.x - rg[i - 1].x - o.gouttiere ? dispo : f.x - rg[i - 1].x - o.gouttiere;
      if (i < rg.length - 1) dispo = dispo < rg[i + 1].x - f.x - o.gouttiere ? dispo : rg[i + 1].x - f.x - o.gouttiere;
      final large = dispo > bw ? dispo : bw;
      f.w = large < o.boiteMax ? large : o.boiteMax;
    }
  }
  final traits = <OrgTrait>[];
  final fleches = <OrgFleche>[];
  for (var r = 0; r < rangees.length; r++) {
    for (final p in rangees[r].where((f) => f.enfants.isNotEmpty)) {
      final yb = haut(r) + bh, yh = haut(r + 1);
      final ym = yb + (yh - yb) / 2;
      final xs = [for (final c in p.enfants) c.x, p.x];
      traits.add(OrgTrait(p.x, yb, p.x, ym));
      traits.add(OrgTrait(xs.reduce((a, b) => a < b ? a : b), ym, xs.reduce((a, b) => a > b ? a : b), ym));
      for (final c in p.enfants) {
        traits.add(OrgTrait(c.x, ym, c.x, yh - 0.6));
        fleches.add(OrgFleche([(c.x - 0.9, yh - 1.8), (c.x, yh - 0.2), (c.x + 0.9, yh - 1.8)]));
      }
    }
  }
  final boites = <OrgBoite>[];
  for (var r = 0; r < rangees.length; r++) {
    for (final f in rangees[r]) {
      final n = f.n;
      final eff = n.fiche['effectif'];
      final e = eff is num ? eff.toInt() : (num.tryParse('${eff ?? ''}')?.toInt() ?? 0);
      final lignes = <String>['${n.poste} (${e.toString().padLeft(2, '0')})'];
      if (_vrai(n.fiche['titulaire'])) {
        lignes.add('${n.fiche['titulaire']}${_vrai(n.titreAgent) ? ' (${n.titreAgent})' : ''}${_vrai(n.fiche['chef']) ? ' C/S' : ''}');
      }
      boites.add(OrgBoite(n.poste, f.x - f.w / 2, haut(r), f.w, bh, lignes));
    }
  }
  return OrgMiseEnPage(largeur: w, hauteur: hTotal, niveaux: nb, boites: boites, traits: traits, fleches: fleches);
}
