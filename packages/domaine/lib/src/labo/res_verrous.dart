/// LES DEUX VERROUS D'UN RÉSULTAT, ET LA RECTIFICATION — port de `PR.validerTechnique`, `PR.validerBiologique`, `PR.rectifierResultat`
/// (prototype_html/assets/js/parcours.js). Vecteurs : `test/vecteurs/resultats.json` (section `verrous`).
///
/// « Une première validation technique, puis une validation biologique. Dès que nous faisons la validation biologique, le médecin a le
/// résultat. » La VALIDATION TECHNIQUE atteste la saisie ; la VALIDATION BIOLOGIQUE rend le résultat opposable. Après elle, une correction
/// n'est plus un écrasement : c'est une RECTIFICATION — la version sortante est CONSERVÉE, la nouvelle numérotée, le prescripteur averti.
///
/// Le moteur de la maquette lit et écrit le magasin ; celui-ci reçoit la fiche EN ARGUMENT et RENVOIE le patch et la notification à écrire.
/// Un refus est NOMMÉ (`RefusResultat`) et n'écrit rien.
library;

import 'res_etats.dart';
import 'res_habilitations.dart';

class RefusResultat implements Exception {
  const RefusResultat(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// Ce qu'un geste de validation ou de rectification fait naître : le patch de la demande, la notification au prescripteur (s'il y en a une),
/// et — pour la validation biologique — si elle est portée par intérim.
class GesteResultat {
  const GesteResultat(this.patch, {this.notification, this.interim = false, this.version});
  final FicheLabo patch;
  final FicheLabo? notification;
  final bool interim;
  final int? version;
}

bool _faux(Object? v) => v == null || v == '' || v == false || v == 0;

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// `notifier({...})` : la fiche de la collection `notifications` (une notification s'adresse à un POSTE, pas à une personne).
FicheLabo notificationResultat(
        {required String type,
        required String libelle,
        required String detail,
        required FicheLabo demande,
        String priorite = 'normale'}) =>
    {
      'type': type,
      'poste': 'prescripteur',
      'destinataire': _faux(demande['prescripteur']) ? null : demande['prescripteur'],
      'libelle': libelle,
      'detail': detail,
      'priorite': priorite,
      'demandeId': demande['id'],
      'factureId': null,
      'ordonnanceId': null,
      'patientId': _faux(demande['patientId']) ? null : demande['patientId'],
      'reference': _faux(demande['reference']) ? null : demande['reference'],
      'lue': false,
    };

/// `PR.validerTechnique(demandeId, {utilisateur})`.
GesteResultat validerTechnique(FicheLabo? demande,
    {required String utilisateur, required DateTime maintenant}) {
  if (demande == null) throw const RefusResultat('Demande introuvable.');
  final v = demande['valeurs'];
  if (v is! Map || v.isEmpty) {
    throw const RefusResultat('Aucun résultat saisi : il n’y a rien à valider.');
  }
  return GesteResultat({
    'etatAnalyse': 'valide_technique',
    'valideTechniqueLe': _iso(maintenant),
    'valideTechniquePar': utilisateur,
  });
}

/// `PR.validerBiologique(demandeId, {session, utilisateur})` — le POINT DE NON-RETOUR : au-delà, une correction devient une rectification.
/// Le biologiste médical valide ; le TSL le peut EN SON ABSENCE et l'intérim est PORTÉ SUR LA PIÈCE (le compte rendu dit qui a signé, et à quel titre).
GesteResultat validerBiologique(FicheLabo? demande,
    {SessionLabo? session, required String utilisateur, required DateTime maintenant}) {
  if (demande == null) throw const RefusResultat('Demande introuvable.');
  if (demande['etatAnalyse'] != 'valide_technique') {
    throw const RefusResultat('La validation technique doit précéder la validation biologique.');
  }
  final cap = capacites(session);
  if (_faux(cap.validerBiologique)) {
    throw RefusResultat('${cap.label} n’est pas habilité à porter la validation biologique.');
  }
  final interim = cap.validerBiologique == 'interim';
  final version = _faux(demande['version']) ? 1 : demande['version'];
  return GesteResultat(
      {
        'etatAnalyse': 'valide',
        'valideLe': _iso(maintenant),
        'valideBiologiquePar': utilisateur,
        'validationInterim': interim,
        'qualiteValidateur':
            interim ? '${cap.label} — par intérim du biologiste médical' : cap.label,
        'version': version,
      },
      interim: interim,
      notification: notificationResultat(
          type: 'resultat_disponible',
          libelle: 'Résultat disponible — ${demande['analyse']}',
          detail: '${demande['patient']} (${demande['patientCode']})',
          demande: demande));
}

/// `PR.rectifierResultat(demandeId, valeurs, {motif, commentaireGeneral, utilisateur})`.
/// « Peut-être qu'il a déjà lu le premier, et c'est pas cool. » — La version sortante est figée AVANT d'être remplacée : c'est celle que le médecin
/// a lue, elle doit rester consultable. LA NOTIFICATION EST LE CŒUR DU DISPOSITIF : sans elle, la rectification vaudrait un écrasement silencieux.
GesteResultat rectifierResultat(FicheLabo? demande, Map<String, Object?> valeurs,
    {String? motif,
    String? commentaireGeneral,
    required String utilisateur,
    required DateTime maintenant}) {
  if (_faux(motif)) throw const RefusResultat('Une rectification doit être motivée.');
  if (demande == null) throw const RefusResultat('Demande introuvable.');
  if (!resultatRendu(demande['etatAnalyse'])) {
    throw const RefusResultat(
        'Ce résultat n’a pas été validé biologiquement : le corriger ne demande pas de rectification.');
  }
  final versions = [
    for (final x in (demande['versions'] as List? ?? const [])) x
  ];
  final numero = _faux(demande['version']) ? 1 : (demande['version'] as num).toInt();
  versions.add({
    'numero': numero,
    'valeurs': {...((demande['valeurs'] as Map?)?.cast<String, Object?>() ?? const {})},
    'commentaireGeneral': _faux(demande['commentaireGeneral']) ? null : demande['commentaireGeneral'],
    'conclusion': _faux(demande['conclusion']) ? null : demande['conclusion'],
    if (demande['valideLe'] != null) 'valideLe': demande['valideLe'],
    if (demande['valideBiologiquePar'] != null)
      'valideBiologiquePar': demande['valideBiologiquePar'],
    'remplaceeLe': _iso(maintenant),
    'motifRemplacement': motif,
  });
  return GesteResultat(
      {
        'valeurs': valeurs,
        'versions': versions,
        'version': numero + 1,
        'etatAnalyse': 'rectifie',
        'rectifieLe': _iso(maintenant),
        'rectifiePar': utilisateur,
        'motifRectification': motif,
        'commentaireGeneral':
            commentaireGeneral ?? demande['commentaireGeneral'],
      },
      version: numero + 1,
      notification: notificationResultat(
          type: 'resultat_rectifie',
          priorite: 'haute',
          libelle: 'RÉSULTAT RECTIFIÉ — ${demande['analyse']}',
          detail:
              '${demande['patient']} (${demande['patientCode']}) — version ${numero + 1}. Motif : $motif. Le résultat que vous avez consulté a changé.',
          demande: demande));
}
