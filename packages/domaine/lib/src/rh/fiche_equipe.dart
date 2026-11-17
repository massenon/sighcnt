/// Lot SURV (Direction, 16/11/2026, section AQ point 37) : la fiche du personnel de SON ÉQUIPE et le périmètre d'équipe du Surveillant.
///
/// Port de `SIGH.planningRh.porteePersonnel`, `controlerPerimetreEquipe`, `ficheEquipe` et `equipeDeLaSession` (`prototype_html/assets/js/parcours.js`) ; vecteurs
/// `test/vecteurs/fiche_equipe.json`, engendrés par `prototype_html/build/vecteurs-fiche-equipe.js` (le moteur de la maquette, piloté dans Chrome). Fonctions PURES : elles
/// reçoivent les fiches, la portée de la session et rendent un résultat ou un refus nommé.
///
/// Trois portées, TIRÉES DES DROITS (jamais d'une liste de rôles) : « complète » (la session lit déjà tout le personnel), « équipe » (elle détient le geste réservé
/// [gesteFicheEquipe] sans lire tout le personnel), « aucune ». Dans la portée « équipe », l'équipe est LE SERVICE de l'agent de la session, SANS lui-même (nul ne règle son
/// propre planning) ; une session qui n'est pas un agent du personnel n'a pas d'équipe déterminable (refus nommé, jamais « tout le monde »). La lecture restreinte est une
/// LISTE BLANCHE de champs : ni salaire, ni catégorie, ni date d'embauche, ni numéro CNSS, ni assurance (RG-13).
library;

import 'planning_rh.dart' show RefusRh;

/// Le geste réservé qui ouvre la fiche de l'équipe (fiche RBAC, défaut semé : le Surveillant).
const String gesteFicheEquipe = 'ouvrir_fiche_personnel_equipe';

/// L'écran que ce geste ouvre en lecture.
const String ecranFicheEquipe = 'm10-fiche-equipe';

/// La liste BLANCHE des champs d'une fiche lue depuis l'équipe.
const List<String> champsFicheEquipeRh = ['id', 'matricule', 'nomComplet', 'sexe', 'fonction', 'poste', 'service'];

enum PorteePersonnel { complete, equipe, aucune }

extension PorteePersonnelNom on PorteePersonnel {
  String get nom => name;
}

/// La portée d'une session : [lectureComplete] (elle ouvre déjà `m10-personnel`) puis [geste] (elle détient `ouvrir_fiche_personnel_equipe`).
PorteePersonnel porteePersonnelRh({required bool lectureComplete, required bool geste}) =>
    lectureComplete ? PorteePersonnel.complete : (geste ? PorteePersonnel.equipe : PorteePersonnel.aucune);

RefusRh _reserve() => const RefusRh('FICHE_EQUIPE_RESERVEE',
    'La fiche du personnel de l’équipe s’ouvre par un rôle qui détient le droit « Ouvrir la fiche du personnel de son équipe » (fiche de droits du rôle).', 'Demander à l’administrateur d’attribuer ce droit au rôle.');

RefusRh _indeterminee() => const RefusRh('EQUIPE_INDETERMINEE', 'La session n’est pas un agent du personnel avec un service : son équipe ne se détermine pas.',
    'Se connecter sous le compte d’un agent du personnel, ou faire rattacher le compte à un service.');

String? _service(Map<String, Object?>? moi) {
  final s = moi?['service'];
  return s is String && s.isNotEmpty ? s : null;
}

/// Ce que la portée de la session permet pour [agent] : `null` (permis) ou le refus nommé. [moi] : l'agent du personnel qui porte le nom de la session (`null` : aucun).
RefusRh? controlerPerimetreEquipeRh({required PorteePersonnel portee, required Map<String, Object?> agent, required Map<String, Object?>? moi}) {
  if (portee == PorteePersonnel.complete) return null;
  if (portee == PorteePersonnel.aucune) return _reserve();
  final service = _service(moi);
  if (moi == null || service == null) return _indeterminee();
  if (agent['id'] == moi['id']) {
    return RefusRh('AGENT_HORS_EQUIPE', 'Nul ne règle son propre planning : ${agent['nomComplet']} est l’agent de la session.', 'Demander à la Directrice Administrative ou à l’administrateur.', {'service': service});
  }
  if (agent['service'] != service) {
    return RefusRh('AGENT_HORS_EQUIPE', '${agent['nomComplet']} n’est pas de votre équipe (service « $service »).', 'Choisir un agent de votre service.', {'service': service, 'serviceAgent': agent['service']});
  }
  return null;
}

/// La projection RESTREINTE d'une fiche : la liste blanche, jamais « la fiche moins quelques champs » (un champ ajouté demain ne fuit pas).
Map<String, Object?> projeterFicheEquipeRh(Map<String, Object?> agent) => {
      for (final c in champsFicheEquipeRh)
        if (agent.containsKey(c)) c: agent[c],
    };

/// L'équipe de la session : `refus` ou la liste des fiches restreintes.
({RefusRh? refus, List<Map<String, Object?>> agents}) equipeDeLaSessionRh({required PorteePersonnel portee, required List<Map<String, Object?>> personnelActif, required Map<String, Object?>? moi}) {
  if (portee == PorteePersonnel.aucune) return (refus: _reserve(), agents: const []);
  Iterable<Map<String, Object?>> liste = personnelActif;
  if (portee == PorteePersonnel.equipe) {
    final service = _service(moi);
    if (moi == null || service == null) return (refus: _indeterminee(), agents: const []);
    liste = personnelActif.where((e) => e['service'] == service && e['id'] != moi['id']);
  }
  return (refus: null, agents: [for (final e in liste) projeterFicheEquipeRh(e)]);
}

/// La fiche restreinte d'un agent : [agent] `null` = agent introuvable (la portée « aucune » est refusée d'abord).
({RefusRh? refus, Map<String, Object?>? fiche}) ficheEquipeRh({required PorteePersonnel portee, required Map<String, Object?>? agent, required Map<String, Object?>? moi}) {
  if (agent == null) {
    return (
      refus: portee == PorteePersonnel.aucune ? _reserve() : const RefusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.'),
      fiche: null
    );
  }
  final r = controlerPerimetreEquipeRh(portee: portee, agent: agent, moi: moi);
  if (r != null) return (refus: r, fiche: null);
  return (refus: null, fiche: projeterFicheEquipeRh(agent));
}

/// Confirmer une valeur d'attente (salaire, catégorie, embauche, CNSS) exige la portée complète : la fiche d'équipe ne la lit ni ne la confirme.
RefusRh? controlerPorteeValeurAttenteRh(PorteePersonnel portee) => portee == PorteePersonnel.complete
    ? null
    : const RefusRh('VALEUR_ATTENTE_HORS_PORTEE', 'Les valeurs d’attente (salaire, catégorie, date d’embauche, numéro CNSS) ne se lisent ni ne se confirment depuis la fiche de l’équipe.',
        'Demander à un rôle qui lit tout le personnel.');
