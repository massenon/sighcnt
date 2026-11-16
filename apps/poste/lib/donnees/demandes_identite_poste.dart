import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// L'IDENTITÉ DE LA CLINIQUE ET SES OPTIONS D'IMPRESSION AU POSTE (lot IDENT, décision de la Direction du 16/11/2026) : la colle entre les règles pures de
/// `packages/domaine/lib/src/configuration/demande_identite.dart` et le magasin du poste. Aucune règle d'identité ici.
///
///  * MÈRE : [poser] écrit directement la version datée (la précédente se clôt la veille, jamais réécrite) et les options, après le contrôle de DROIT de la fiche RBAC (le moteur refuse,
///    masquer la commande ne protège rien). La configuration part aux fileuls par le canal habituel, jamais vers un téléphone.
///  * FILEUL habilité : [poser] SIGNE la demande (qui, rôle, quand) et la DÉPOSE dans `demandesIdentite` (famille A). Mère coupée : elle reste « déposée » au journal du fileul, rejouée à la reconnexion.
///  * MÈRE : [appliquer] est l'applicateur : pour chaque demande « déposée », elle refait le contrôle de droit SOUS LE RÔLE DE L'AUTEUR (lu de sa propre matrice), à la date de la SIGNATURE, ajoute la version,
///    écrit les options, journalise (RG-12) et pose le verdict sur la demande (qui revient au fileul). Rejeu sans effet.
class DemandesIdentitePoste {
  DemandesIdentitePoste(this.m, {this.matrice, DateTime Function()? horloge, this.etiquette = 'F'}) : _horloge = horloge ?? DateTime.now;
  final Magasin m;
  final MatriceDroits? matrice;
  final String etiquette;
  final DateTime Function() _horloge;

  CollectionMagasin get versions => m.collection('identiteLegale');
  CollectionMagasin get options => m.collection(idCollectionOptions);
  CollectionMagasin get demandes => m.collection(idCollectionDemandes);

  String libelleRole(String role) => matrice?.libelle(role) ?? role;

  /// Les demandes qui attendent la mère.
  List<Fiche> enAttente() => idDemandesEnAttente(demandes.toutes);

  /// Pose les informations de la clinique. [fileul] : le poste est rattaché à une mère (dépôt) ; sinon écriture directe. Rend le refus nommé, ou le mode (`directe`, `deposee`) et la version créée.
  ({CfbRefus? refus, String? mode, int? version, bool enForceAujourdhui}) poser({
    required bool fileul,
    required String role,
    required String acteur,
    Map<String, Object?> champs = const {},
    Map<String, Object?> optionsImpression = const {},
    Object? dateEffet,
    String? motif,
  }) {
    final maintenant = _horloge();
    final droit = idDroitEcriture(matrice, role);
    final exercices = m.collection('exercices').toutes;
    if (fileul) {
      final r = idDeposerDemande(
          versions: versions.toutes,
          demandes: demandes.toutes,
          champs: champs,
          options: optionsImpression,
          dateEffet: dateEffet,
          motif: motif,
          role: role,
          libelleRole: libelleRole(role),
          droit: droit,
          acteur: acteur,
          maintenant: maintenant,
          exercices: exercices,
          etiquette: etiquette);
      if (!r.ok) return (refus: r.refus, mode: null, version: null, enForceAujourdhui: false);
      try {
        demandes.inserer(r.fiche!);
      } on EcritureRefusee catch (e) {
        return (refus: CfbRefus('ECRITURE_REFUSEE', e.motif), mode: null, version: null, enForceAujourdhui: false);
      }
      m.journaliser('Identité : demande déposée à la mère (signée)', 'CFG', 'IdentiteLegale', '${r.fiche!['id']}', null,
          {'role': role, 'demandePar': acteur, 'demandeLe': r.fiche!['demandeLe'], if (champs.isNotEmpty) 'champs': champs.keys.toList(), if (optionsImpression.isNotEmpty) 'options': optionsImpression});
      return (refus: null, mode: 'deposee', version: null, enForceAujourdhui: false);
    }
    final d = idControleDroit(droit: droit, libelleRole: libelleRole(role));
    if (d != null) return (refus: d, mode: null, version: null, enForceAujourdhui: false);
    final o = idControleOptions(optionsImpression);
    if (o != null) return (refus: o, mode: null, version: null, enForceAujourdhui: false);
    if (champs.isEmpty && optionsImpression.isEmpty) {
      return (refus: const CfbRefus('DEMANDE_VIDE', 'Rien à écrire : aucun champ d’identité, aucune option d’impression.', 'Modifier au moins une information.'), mode: null, version: null, enForceAujourdhui: false);
    }
    CfbEcritureIdentite? e;
    if (champs.isNotEmpty) {
      e = cfbNouvelleVersionIdentite(versions.toutes, champs,
          dateEffet: dateEffet, motif: motif, acteur: acteur, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: false);
      if (!e.ok) return (refus: e.refus, mode: null, version: null, enForceAujourdhui: false);
    }
    _ecrire(e, idEcrituresOptions(options.toutes, optionsImpression, acteur: acteur, maintenant: maintenant));
    return (refus: null, mode: 'directe', version: e?.version, enForceAujourdhui: e?.enForceAujourdhui ?? false);
  }

  /// MÈRE : applique les demandes déposées. Rend le nombre de demandes traitées (appliquées ou refusées en nommant).
  int appliquer() {
    var n = 0;
    for (final d in enAttente()) {
      final role = '${d['demandeRole']}';
      final a = idAppliquerDemande(d,
          versions: versions.toutes,
          options: options.toutes,
          droitDeLAuteur: idDroitEcriture(matrice, role),
          libelleRoleAuteur: libelleRole(role),
          maintenant: _horloge(),
          exercices: m.collection('exercices').toutes);
      if (a == null) continue;
      if (a.ok) _ecrire(a.ecriture, a.options);
      demandes.mettreAJour(d['id'], {...a.champsDemande, 'traitePar': 'Mère'}, journaliser: false);
      m.journaliser(a.ok ? 'Identité : demande d’un fileul appliquée' : 'Identité : demande d’un fileul refusée', 'CFG', 'IdentiteLegale', '${d['id']}',
          null, {'demandePar': d['demandePar'], 'demandeLe': d['demandeLe'], 'etat': a.champsDemande['etat'], if (!a.ok) 'resultatCode': a.refus!.code});
      n++;
    }
    return n;
  }

  /// Écrit ce que la pose commande : la version nouvelle (la couvrante se clôt la veille), puis les options, UNE ligne de journal par écriture (RG-12).
  void _ecrire(CfbEcritureIdentite? e, List<({CfaFiche fiche, Object? avant, bool creation})> opts) {
    if (e != null && e.ok) {
      if (e.precedenteId != null) versions.mettreAJour(e.precedenteId, e.patchPrecedente!);
      versions.inserer(e.fiche!, prefixe: 'IDL');
    }
    for (final o in opts) {
      if (o.creation) {
        options.ajouterSansJournal(o.fiche);
      } else {
        options.mettreAJour(o.fiche['id'], {'valeur': o.fiche['valeur'], 'modifieLe': o.fiche['modifieLe'], 'modifiePar': o.fiche['modifiePar']}, journaliser: false);
      }
      m.journaliser('Option d’impression modifiée', 'CFG', 'optionsImpression', '${o.fiche['cle']}', {'valeur': o.avant}, {'valeur': o.fiche['valeur']});
    }
  }
}
