import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/tarifs_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/tarifs_ecran.dart';

/// LOT TFIN-2 (PRD-TARIFS, lot T5 de la maquette) : le prix d'achat d'un produit est VERSIONNÉ. L'écran « Référentiel produits » ne l'écrit plus sur la fiche : il le PROPOSE par le même moteur que
/// les prix des prestations (`TarifsPoste.proposerPrixAchat`) : date d'effet, motif, alerte Oui ou Non de la Directrice Administrative ou de la Direction, ou « Valider » en un geste pour un profil qui
/// décide. Une proposition ne change RIEN avant le Oui ; une pièce déjà émise garde le prix de sa date ; RG-02 : le prix de vente d'un médicament est son prix d'achat, il se DÉRIVE (aucune marge
/// ne se saisit). Sur un fileul, le même geste DÉPOSE une demande que la mère applique (rien n'est écrit chez lui). La commande est ABSENTE sans le droit de modifier l'écran ; le moteur refuse aussi.

/// « Changer le prix d'achat » : la modale de proposition.
void modaleChangerPrixAchat(BuildContext ctx, ContexteEcran c, Map<String, Object?> produit) {
  final tarifs = tarifsDeEcran(c);
  final jour = tarIso(c.aujourdhui);
  final px = prixDuJour(c, produit);
  final med = produit['categorie'] == tarCategorieSansMarge;
  final peutPassee = tarRolesDatePassee.contains(c.role), peutValider = tarPeutDecider(c.role);
  final defs = <ChampDef>[
    const ChampDef(nom: 'prixAchat', libelle: 'Nouveau prix d’achat (FCFA)', type: TypeChamp.nombre, requis: true, aide: 'Un montant entier, strictement positif.'),
    if (!med)
      const ChampDef(nom: 'prixVente', libelle: 'Prix de vente (FCFA)', type: TypeChamp.nombre, aide: 'Vide : le prix de vente actuel est conservé.'),
    ChampDef(
        nom: 'dateEffet',
        libelle: 'Date d’effet',
        type: TypeChamp.date,
        requis: true,
        aide: peutPassee
            ? 'Aujourd’hui ou plus tard ; une date antérieure se coche ci-dessous et se motive. Le prix en vigueur ne change qu’à cette date, et seulement après un Oui.'
            : 'Au plus tôt aujourd’hui. Le prix en vigueur ne change qu’à cette date, et seulement après un Oui. Une pièce déjà émise ce jour ou après porte déjà l’article : choisir une date postérieure.'),
    if (peutPassee)
      const ChampDef(
          nom: 'datePassee',
          libelle: 'Date antérieure à aujourd’hui (refusée si une pièce porte déjà cet article depuis cette date)',
          type: TypeChamp.case_,
          col: ColChamp.plein),
    const ChampDef(nom: 'motif', libelle: 'Motif du changement', type: TypeChamp.textarea, requis: true, col: ColChamp.plein),
  ];
  final ctl = ControleurFormulaire(defs, {'dateEffet': jour});
  void envoyer(BuildContext modale, VoidCallback fermer, bool valider) {
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(modale, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final r = tarifs.proposerPrixAchat(DemandeProduit(
      code: '${produit['code']}',
      prixAchat: v['prixAchat'],
      prixVente: med ? null : v['prixVente'],
      dateEffet: '${v['dateEffet']}',
      motif: '${v['motif'] ?? ''}',
      datePassee: v['datePassee'] == true,
      valider: valider,
      source: 'Saisi à l’écran « Référentiel produits »',
    ));
    if (!r.ok) {
      ToastsSigh.afficher(modale, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
      return;
    }
    fermer();
    if (r.depose) {
      ToastsSigh.afficher(ctx, 'Demande déposée à la mère : elle l’applique après avoir refait les contrôles.',
          type: TypeToast.succes, detail: 'Ce poste ne peut pas écrire une version de prix (la mère seule écrit) ; le verdict revient ici.');
    } else if (r.valideeEnUnGeste) {
      ToastsSigh.afficher(ctx, 'Prix d’achat validé : il prend effet le ${dateFR(DateTime.parse('${r.version!['dateEffet']}'))}.',
          type: TypeToast.succes, detail: 'Validé en un geste par votre rôle ; les pièces déjà émises gardent leur prix.');
    } else {
      ToastsSigh.afficher(ctx, 'Proposition enregistrée : elle attend la décision (Oui ou Non).', type: TypeToast.succes, detail: 'Le prix en vigueur ne change pas avant le Oui.');
    }
  }

  afficherModale<void>(ctx,
      titre: 'Changer le prix d’achat',
      sousTitre: '${produit['code']} : ${produit['designation']}',
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoteSigh(
            'Prix d’achat en vigueur aujourd’hui : ${px.absent ? 'non renseigné (à valoriser)' : money(px.achat, avecDevise: false)}${px.absent ? '' : ' (version ${px.version})'}. '
            '${med ? 'RG-02 : le prix de vente d’un médicament est son prix d’achat, il suit sans marge. ' : ''}'
            'Une proposition ne change rien tant que la Direction, la Directrice Administrative ou l’administrateur n’a pas répondu Oui ; les pièces déjà émises gardent leur prix.'),
        const SizedBox(height: 12),
        NoteSigh(
            'Deux états, visibles : « Enregistrer » dépose une proposition (à valider : rien ne change) ; ${peutValider ? '« Valider » la met en vigueur à sa date d’effet, en un geste tracé avec votre rôle.' : '« Valider » est réservé à la Direction, à la Directrice Administrative et à l’administrateur : leur décision suit votre proposition.'}',
            icone: LucideIcons.gitCompare),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            Builder(builder: (modale) => BoutonSigh(libelle: 'Enregistrer', icone: LucideIcons.send, variante: VarianteBouton.secondaire, onPressed: () => envoyer(modale, fermer, false))),
            // « Valider » est ABSENT hors de la liste de rôles de la famille ; le moteur refuse de toute façon (VALIDATION_RESERVEE).
            if (peutValider) Builder(builder: (modale) => BoutonSigh(libelle: 'Valider', icone: LucideIcons.shieldCheck, onPressed: () => envoyer(modale, fermer, true))),
          ]);
}

/// « Historique de prix » : toutes les versions du prix d'achat d'un produit (une lecture, offerte à tout profil qui voit la ligne). Aucune version n'est jamais réécrite.
void modaleHistoriquePrixAchat(BuildContext ctx, ContexteEcran c, Map<String, Object?> produit) {
  final h = TarifsPoste.lire(c.magasin);
  final versions = h.versionsDe('${produit['code']}').reversed.toList();
  final jour = tarIso(c.aujourdhui);
  String statut(Map<String, Object?> v) => switch ('${v['statut']}') {
        'propose' => 'Proposition en attente',
        'refuse' => 'Refusée',
        'retire' => 'Retirée',
        'valide' => (v['dateEffet'] != null && '${v['dateEffet']}'.compareTo(jour) > 0) ? 'Changement à venir' : 'Validée',
        final x => x,
      };
  afficherModale<void>(ctx,
      titre: 'Historique du prix d’achat',
      sousTitre: '${produit['code']} : ${produit['designation']}',
      taille: TailleModale.lg,
      corps: versions.isEmpty
          ? const NoteSigh('Aucune version : l’article n’a pas encore de prix d’achat versionné (il en reçoit une version 1 de reprise au démarrage de la mère).')
          : Column(key: const Key('prix-achat:historique'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final v in versions)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        'Version ${v['version']} : ${v['etatNonAssure'] == 'manquant' || v['prixNonAssure'] == null ? 'prix non renseigné' : money(v['prixNonAssure'], avecDevise: false)}'
                        '${v['prixVente'] != null ? ', prix de vente ${money(v['prixVente'], avecDevise: false)}' : ''}'
                        ' · ${v['dateEffet'] != null ? 'effet le ${dateFR(DateTime.parse('${v['dateEffet']}'))}' : 'depuis l’origine'}'
                        ' · ${statut(v)}'
                        '${v['proposePar'] != null ? ' · proposée par ${v['proposePar']}' : ''}'
                        '${(v['motif'] ?? '').toString().isNotEmpty ? ' · ${v['motif']}' : ''}',
                        style: const TextStyle(fontSize: 13, height: 18 / 13, color: JetonsShell.slate700))),
            ]),
      pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
}
