import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import '../donnees/magasin.dart';
import '../modules/m14/commun_m14.dart' show rolesDe;
import '../shell/contexte_ecran.dart';
import '../sync/configuration_sync.dart' show ApplicateurConfiguration;
import 'acteur.dart';
import 'badge.dart';
import 'bouton.dart';
import 'modale.dart';
import 'toast.dart';
import 'ton.dart';

/// LA VALIDATION D'UN RÉFÉRENTIEL AU POSTE (Direction, 07/11/2026) : le branchement du MOTEUR du domaine (`validation.dart`, fonctions pures rejouées sur les
/// vecteurs de la maquette) sur le magasin du poste. Équivalent de `K.boutonValider`, `K.badgeValidation`, `K.peutValider` et `K.remettreAValider`.
///
/// Doctrine : le domaine rend ce qu'il faut écrire ; c'est ICI que l'on écrit, journalise (RG-12) et notifie. Le rôle vient de la SESSION (`c.role`), jamais
/// de l'écran. Le geste est UNITAIRE : aucune méthode ne valide plusieurs éléments. Une commande interdite est ABSENTE (jamais grisée) et le moteur refait le
/// contrôle. La validation écrit le marquage et ses trois traces, rien d'autre ; toute modification d'un élément validé le remet « à valider »
/// ([remettre], appelé par l'écran qui modifie).
///
/// Sur un FILEUL rattaché, la configuration est tenue par la mère : ces collections sont gardées « réglé sur la mère », donc la commande est absente et le
/// geste refusé en le nommant (code `CONFIGURATION_DE_LA_MERE`). La validation écrite sur la mère voyage aux fileuls avec la collection `validationsReferentiels`
/// (famille R) ; un fileul ne l'écrit jamais, donc deux postes ne peuvent pas se contredire : aucune règle de fusion n'est nécessaire.
class ValidationPoste {
  ValidationPoste(this.c);
  final ContexteEcran c;

  Magasin get m => c.magasin;

  LectureValidation get lire => (nom) => m.collection(nom).toutes;

  /// Les libellés de rôle de la matrice en force (rôles renommés compris).
  Map<String, String> get libelles {
    final out = <String, String>{};
    final matrice = c.donnees?.matrice;
    for (final r in rolesDe(m)) {
      out[r.id] = r.label;
    }
    if (matrice != null) {
      for (final f in valFamilles) {
        for (final r in f.roles) {
          out.putIfAbsent(r, () => matrice.libelle(r) ?? r);
        }
      }
      out.putIfAbsent(c.role, () => matrice.libelle(c.role) ?? c.role);
    }
    return out;
  }

  /// Le poste est-il un fileul rattaché à une mère ? La configuration y est en lecture seule.
  bool get fileul => ServiceInstallation.de(m).rattache;

  /// `K.peutValider(famille)` : le rôle de la SESSION est un des rôles de la famille, et le poste tient sa configuration.
  bool peutValider(String famille) => !fileul && valPeutValider(famille, c.role);

  EtatValidation? etat(String famille, Object? id) => valEtatValidation(famille, '$id', lire, libelles);

  /// `K.badgeValidation` : l'état LU (jamais stocké). `null` si l'élément est inconnu de la famille.
  Widget? badge(String famille, Object? id) {
    final e = etat(famille, id);
    if (e == null) return null;
    if (e.enAttente) return BadgeSigh('À valider', key: Key('val:badge:$famille:$id'), ton: TonSigh.attention);
    final morceaux = [
      if (e.valideRole != null) e.valideRole!,
      if (e.valideLe != null) _dateCourte(e.valideLe!),
    ];
    final t = e.valideLe == null ? 'Validé' : 'Validé (${morceaux.join(', ')})';
    return BadgeSigh(t, key: Key('val:badge:$famille:$id'), ton: TonSigh.succes);
  }

  static String _dateCourte(String iso) {
    final d = DateTime.tryParse(iso.length >= 10 ? iso.substring(0, 10) : iso);
    return d == null ? iso : dateFR(d);
  }

  /// Le texte du badge en clair (colonnes triables, exports).
  String texteBadge(String famille, Object? id) {
    final e = etat(famille, id);
    if (e == null) return '';
    if (e.enAttente) return 'À valider';
    return e.valideLe == null ? 'Validé' : 'Validé (${[if (e.valideRole != null) e.valideRole!, _dateCourte(e.valideLe!)].join(', ')})';
  }

  /// Le geste : refus nommé, ou écriture du marquage et de ses trois traces, UNE ligne de journal (RG-12).
  VerdictValidation valider(String famille, Object? id) {
    if (fileul) {
      return VerdictValidation.refus(const RefusValidation('CONFIGURATION_DE_LA_MERE', ApplicateurConfiguration.motifGarde,
          'Valider depuis le poste principal : la validation est reprise ici ensuite.'));
    }
    final r = valValiderReferentiel(famille, '$id',
        role: c.role, acteur: acteur(c).nom, maintenant: c.aujourdhui, lire: lire, libelles: libelles);
    if (!r.ok) return r;
    try {
      final col = m.collection(r.collection!);
      if (r.creation != null) {
        // La maquette pose la fiche de validation sans ligne « Création » : le geste est UNE ligne « Validation ».
        col.ajouterSansJournal(r.creation!);
      } else {
        final cible = r.collection == valCollectionValidations ? 'VRF-${r.id}' : '${r.id}';
        col.mettreAJour(cible, r.patch, journaliser: false);
      }
    } on EcritureRefusee catch (e) {
      return VerdictValidation.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    final j = r.journal!;
    m.journaliser(j.action, j.module, j.entite, j.reference, j.avant, j.apres);
    return r;
  }

  /// `K.remettreAValider` : à appeler sur TOUT chemin qui modifie un élément. Rend le verdict ; ne fait rien si l'élément est déjà « à valider » ou inconnu.
  VerdictRemise remettre(String famille, Object? id) {
    final r = valRemettreAValider(famille, '$id', lire: lire);
    if (!r.ok || !r.remis) return r;
    try {
      final col = m.collection(r.collection!);
      final cible = r.collection == valCollectionValidations ? 'VRF-${r.id}' : '${r.id}';
      col.mettreAJour(cible, r.patch, journaliser: false);
    } on EcritureRefusee {
      return r;
    }
    final j = r.journal!;
    m.journaliser(j.action, j.module, j.entite, j.reference, j.avant, j.apres);
    return r;
  }

  /// Le bouton dans une liste d'actions (`...vp.boutons(...)`) : vide quand la commande est absente.
  List<Widget> boutons(BuildContext ctx, String famille, Object? id,
      {VoidCallback? apres, String libelle = 'Valider'}) {
    final b = bouton(ctx, famille, id, apres: apres, libelle: libelle);
    return b == null ? const [] : [b];
  }

  /// `validation: { famille, cible?, siChange? }` à l'ENREGISTREMENT d'une modification : remet l'artefact « à valider » si la configuration le demande.
  /// [avant] est la copie de la fiche prise AVANT l'écriture (la fiche du magasin est modifiée en place).
  void remettreApresModification(ValidationCrud v, Map<String, Object?> avant, Map<String, Object?> apres) {
    final cible = v.cible == null ? apres['id'] : v.cible!(apres);
    if (cible != null && (v.siChange == null || v.siChange!(avant, apres))) remettre(v.famille, cible);
  }

  /// Les boutons de validation d'une LIGNE de tableau déclaré `validation:`.
  List<Widget> boutonsDeLigne(BuildContext ctx, ValidationCrud v, Map<String, Object?> f, {VoidCallback? apres}) {
    final cible = v.cible == null ? f['id'] : v.cible!(f);
    return cible == null ? const <Widget>[] : boutons(ctx, v.famille, cible, apres: apres, libelle: v.libelle);
  }

  /// Le badge d'état et le bouton Valider d'une pièce dans une même rangée ([titre] à gauche). Vide quand ni l'un ni l'autre n'est à montrer.
  Widget bandeau(BuildContext ctx, String famille, Object? id, {String? titre, VoidCallback? apres}) {
    final b = badge(famille, id);
    final bt = bouton(ctx, famille, id, apres: apres);
    return Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (titre != null) Flexible(child: Text(titre, style: const TextStyle(fontSize: 14, height: 20 / 14, color: Color(0xFF475569)))),
        if (titre != null && b != null) const SizedBox(width: 8),
        if (b != null) b,
      ]),
      if (bt != null) bt,
    ]);
  }

  /// `K.boutonValider` : ABSENT hors des rôles de la famille et pour un élément déjà validé (ou inconnu). [apres] se déclenche après une validation réussie.
  Widget? bouton(BuildContext ctx, String famille, Object? id,
      {VoidCallback? apres, String libelle = 'Valider', TailleBouton taille = TailleBouton.sm, VarianteBouton variante = VarianteBouton.primaire}) {
    if (!peutValider(famille)) return null;
    final e = etat(famille, id);
    if (e == null || !e.enAttente) return null;
    return Tooltip(
        message: 'Valider « ${e.libelle} »',
        child: BoutonSigh(
            key: Key('val:valider:$famille:$id'),
            libelle: libelle,
            icone: LucideIcons.shieldCheck,
            taille: taille,
            variante: variante,
            onPressed: () async {
              final ok = await confirmerSigh(ctx,
                  titre: 'Valider « ${e.libelle} »',
                  message: 'La validation atteste que cet élément a été vérifié par un profil habilité (${e.profil}). Elle est journalisée (RG-12), '
                      'ne modifie aucune valeur, et toute modification ultérieure le remettra à valider.',
                  libelleOk: 'Valider');
              if (!ok || !ctx.mounted) return;
              final r = valider(famille, id);
              if (!r.ok) {
                ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
                return;
              }
              final quand = DateTime.tryParse(r.valideLe!);
              ToastsSigh.afficher(ctx, '« ${e.libelle} » validé.',
                  type: TypeToast.succes, detail: 'Le ${quand == null ? r.valideLe : dateHeure(quand.toLocal())} par ${r.validePar}.');
              apres?.call();
            }));
  }
}

/// `validation: { famille, cible?, siChange?, label? }` du `K.crud` de la maquette : l'élément de la ligne se valide par le geste unitaire du moteur de
/// validation commun (bouton ABSENT hors des rôles de la famille et pour un élément déjà validé), et le modifier le remet « à valider ».
class ValidationCrud {
  const ValidationCrud(this.famille, {this.cible, this.siChange, this.libelle = 'Valider'});
  final String famille;

  /// L'identifiant de l'artefact validé pour cette fiche (défaut : son `id`) ; `null` : la fiche n'est pas un artefact à valider.
  final Object? Function(Map<String, Object?>)? cible;

  /// Ne remet « à valider » que si la modification change vraiment l'artefact : `siChange(avant, apres)`.
  final bool Function(Map<String, Object?> avant, Map<String, Object?> apres)? siChange;
  final String libelle;
}
