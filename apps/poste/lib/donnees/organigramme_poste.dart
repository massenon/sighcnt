import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

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

  /// Archive un poste (RG-14) ; un poste qui porte encore des postes actifs ne s'archive pas.
  ({RefusRh? refus, VoidCallback? annuler}) archiver(String posteId) {
    final refus = orgControlerArchivage(posteId, droitAnnulation: droitAnnuler, postes: _postes.toutes);
    if (refus != null) return (refus: refus, annuler: null);
    return (refus: null, annuler: _postes.archiver(posteId));
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
