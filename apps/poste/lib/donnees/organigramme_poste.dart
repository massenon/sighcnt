import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// Le résultat d'un archivage : le refus nommé, ou la cible, les postes réaffectés et l'annulation.
typedef ResultatArchivage = ({RefusRh? refus, OrgPosteNomme? cible, List<OrgPosteNomme> reaffectes, AnnulationArchivage Function()? annuler});

/// Le résultat d'une annulation : le refus nommé, ou les postes remis sous le poste restauré et ceux qu'elle a laissés (avec la raison).
typedef AnnulationArchivage = ({RefusRh? refus, List<OrgPosteNomme> restaures, List<OrgLaisse> laisses});

/// L'organigramme au poste (lot ORG2, Direction, 11/11/2026, O1 à O5) : le SEUL chemin d'écriture des postes depuis l'écran « Organisation & organigramme ».
///
/// Les règles sont celles du domaine (`organigramme.dart`, rejouées sur les vecteurs de la maquette) : le service applique le PLAN qu'elles rendent, fiche par fiche, avec
/// les lignes de journal que le plan décrit (RG-12) et la trace d'écran (`_modifieLe`, `_modifiePar`) que la reprise lit pour ne jamais réécrire un poste modifié. Un refus
/// porte son code, son motif et son geste ; rien n'est écrit à moitié.
class OrganigrammePoste {
  OrganigrammePoste(this.m, {required this.droitEditer, required this.droitAnnuler, required this.rolesConnus, required this.maintenant, required this.auteur});
  final Magasin m;
  final bool droitEditer, droitAnnuler;
  final Set<String> rolesConnus;
  final DateTime Function() maintenant;
  final String Function() auteur;

  CollectionMagasin get _postes => m.collection('postes');
  CollectionMagasin get _personnel => m.collection('personnel');

  /// L'arbre des postes actifs, chaque nœud portant le titre de son titulaire.
  List<OrgNoeud> arbre() => orgArbre(_postes.actives, _personnel.actives);

  /// Le titre que porte le titulaire du poste, ou `null`.
  String? titreDe(Fiche poste) => orgTitreDuPoste(poste, _personnel.actives);

  /// Contrôle d'une saisie sans rien écrire (le formulaire, avant « Enregistrer »).
  RefusRh? controler(String? posteId, Map<String, Object?> champs) =>
      orgControler(posteId, champs, postes: _postes.toutes, personnelActif: _personnel.actives, rolesConnus: rolesConnus);

  /// Modifie un poste : n'importe quel sous-ensemble de { poste, parentId, effectif, titulaire, chef, role, titreAgent }. Rend le refus nommé, ou `inchange`, ou la
  /// fonction qui RESTITUE l'état d'avant (postes et titre).
  ({RefusRh? refus, bool inchange, VoidCallback? annuler}) modifier(String posteId, Map<String, Object?> champs) {
    final plan = orgPlanifierModification(posteId, champs,
        droitEcriture: droitEditer, postes: _postes.toutes, personnelActif: _personnel.actives, rolesConnus: rolesConnus);
    if (!plan.ok) return (refus: plan.refus, inchange: false, annuler: null);
    if (plan.inchange) return (refus: null, inchange: true, annuler: null);
    final annulations = <VoidCallback>[];
    if (plan.journalPoste != null) {
      final trace = {'_modifiePar': auteur(), '_modifieLe': maintenant().toIso8601String()};
      annulations.add(_postes.mettreAJour(posteId, {...plan.patch, ...trace}, journaliser: false));
      final j = plan.journalPoste!;
      m.journaliser(j.action, j.module, j.entite, posteId, j.avant, j.apres);
    }
    if (plan.agentId != null && plan.journalTitre != null) {
      annulations.add(_personnel.mettreAJour(plan.agentId, {'titreOrganigramme': plan.titrePose}, journaliser: false));
      final j = plan.journalTitre!;
      m.journaliser(j.action, j.module, j.entite, '${plan.agentId}', j.avant, j.apres);
    }
    return (refus: null, inchange: false, annuler: () {
      for (final u in annulations.reversed) {
        u();
      }
    });
  }

  /// La réaffectation d'un poste (et des postes qu'il porte) sous un autre, ou au sommet (`parentId` nul).
  ({RefusRh? refus, bool inchange, VoidCallback? annuler}) reaffecter(String posteId, String? parentId) => modifier(posteId, {'parentId': parentId});

  /// Renomme le titulaire d'un poste (une autre personne est affectée) ; vide : le poste devient vacant.
  ({RefusRh? refus, bool inchange, VoidCallback? annuler}) renommerTitulaire(String posteId, String nom) => modifier(posteId, {'titulaire': nom});

  /// Pose (ou retire, titre vide) le titre de l'agent qui tient le poste.
  ({RefusRh? refus, bool inchange, VoidCallback? annuler}) poserTitre(String posteId, String titre) => modifier(posteId, {'titreAgent': titre});

  /// Crée un poste (sans rattachement : un sommet).
  ({RefusRh? refus, Fiche? fiche, VoidCallback? annuler}) creer(Map<String, Object?> champs) {
    final r = orgPlanifierCreation(champs, droitEcriture: droitEditer, postes: _postes.toutes, personnelActif: _personnel.actives, rolesConnus: rolesConnus);
    if (r.refus != null) return (refus: r.refus, fiche: null, annuler: null);
    final ins = _postes.inserer({...r.fiche!, '_creePar': auteur(), '_creeLe': maintenant().toIso8601String()}, prefixe: 'PST');
    return (refus: null, fiche: ins.fiche, annuler: ins.annuler);
  }

  /// L'aperçu d'un archivage sans rien écrire : les postes portés, la cible (par défaut le rattachement du poste), les postes qui peuvent les accueillir. Sert la modale.
  OrgApercuArchivage apercuArchivage(String posteId, {String? cibleId}) => orgApercuArchivage(posteId, cibleId, _postes.toutes);

  /// Archive un poste (RG-14). S'il porte des postes actifs, ils sont RÉAFFECTÉS à [cibleId] (par défaut son rattachement), tout ou rien (lot ORG3, décision de la Direction du
  /// 11/11/2026) : une écriture refusée en cours de route défait les précédentes et l'abandon s'écrit au journal. Une ligne de journal pour l'archivage (motif et cible), une par
  /// poste réaffecté. [annuler] restaure le poste ET remet chaque poste sous son ancien parent, sauf celui qu'on a déplacé depuis (laissé, et dit) ; il rend le refus nommé
  /// quand il ne peut pas.
  ResultatArchivage archiver(String posteId, {String? motif, String? cibleId}) {
    final plan = orgPlanifierArchivage(posteId, cibleId: cibleId, motif: motif, droitAnnulation: droitAnnuler, droitEcriture: droitEditer, postes: _postes.toutes);
    if (!plan.ok) return (refus: plan.refus, cible: null, reaffectes: const [], annuler: null);
    final poste = _postes.parId(posteId)!;
    final defaits = <VoidCallback>[];
    void defaire(String raison) {
      for (final u in defaits.reversed) {
        u();
      }
      m.journaliser('Archivage abandonné', 'CFG', 'Poste', posteId, {'poste': '${poste['poste']}', 'sousPostes': plan.reaffectes.length},
          {'raison': raison, 'remisEnPlace': defaits.length});
    }

    Fiche trace() => {'_modifiePar': auteur(), '_modifieLe': maintenant().toIso8601String()};
    for (var i = 0; i < plan.reaffectes.length; i++) {
      final p = plan.reaffectes[i];
      try {
        defaits.add(_postes.mettreAJour(p.id, {'parentId': plan.cible!.id, ...trace()}, journaliser: false));
      } on EcritureRefusee {
        defaire('écriture refusée pour « ${p.poste} »');
        return (
          refus: RefusRh('REAFFECTATION_REFUSEE',
              'L’écriture du poste « ${p.poste} » a été refusée par le magasin : l’archivage de « ${poste['poste']} » est abandonné, aucun poste n’a changé de place.', 'Voir le journal, puis réessayer.', {'posteId': p.id}),
          cible: null,
          reaffectes: const [],
          annuler: null
        );
      }
      final j = plan.journalReaffectations[i];
      m.journaliser(j.action, j.module, j.entite, p.id, j.avant, j.apres);
    }
    try {
      defaits.add(_postes.archiver(posteId, journaliser: false));
    } on EcritureRefusee {
      defaire('archivage refusé par le magasin');
      return (
        refus: RefusRh('ECRITURE_REFUSEE', 'L’archivage du poste « ${poste['poste']} » a été refusé par le magasin : aucun poste n’a changé de place.', 'Voir le journal, puis réessayer.'),
        cible: null,
        reaffectes: const [],
        annuler: null
      );
    }
    final ja = plan.journalArchivage!;
    m.journaliser(ja.action, ja.module, ja.entite, posteId, ja.avant, ja.apres);
    AnnulationArchivage annuler() {
      final u = orgPlanifierAnnulationArchivage(posteId,
          cible: plan.cible, reaffectes: plan.reaffectes, droitAnnulation: droitAnnuler, droitEcriture: droitEditer, postes: _postes.toutes);
      if (!u.ok) return (refus: u.refus, restaures: const [], laisses: const []);
      _postes.restaurer(posteId);
      for (var i = 0; i < u.restaures.length; i++) {
        _postes.mettreAJour(u.restaures[i].id, {'parentId': posteId, ...trace()}, journaliser: false);
        final j = u.journalReaffectations[i];
        m.journaliser(j.action, j.module, j.entite, u.restaures[i].id, j.avant, j.apres);
      }
      return (refus: null, restaures: u.restaures, laisses: u.laisses);
    }

    return (refus: null, cible: plan.cible, reaffectes: plan.reaffectes, annuler: annuler);
  }

  /// LA REPRISE (VERSION 78 de la maquette) : remplace par la semence de la photo les postes que la clinique n'a pas touchés, garde les autres, retire tout champ `etoile`.
  /// Journalisée une fois (RG-12) quand elle a touché quelque chose ; idempotente. À appeler au démarrage du poste, après le chargement du magasin.
  static OrgBilanReprise reprendre(Magasin m) {
    final col = m.collection('postes');
    final copies = [for (final f in col.toutes) {...f}];
    if (copies.isEmpty) return OrgBilanReprise();
    final bilan = orgMigrer(copies);
    if (bilan.reecrits.isNotEmpty || bilan.etoiles > 0) {
      col.remplacerContenu(copies);
      m.journaliser('Reprise de l’organigramme', 'CFG', 'Poste', 'ORG-REPRISE', {'gardes': bilan.gardes.length},
          {'reecrits': bilan.reecrits.length, 'gardes': bilan.gardes.length, 'etoiles': bilan.etoiles});
    }
    return bilan;
  }
}
