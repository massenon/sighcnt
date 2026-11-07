import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'rha_commun.dart';
import 'rhb_commun.dart';
import 'rhc_badge_carte.dart';
import 'rhc_badges.dart';
import 'rhc_commun.dart';

/// `m10-badges-impression` — « Planche d'impression des badges » : pour les cliniques SANS imprimante à cartes, dix badges sur une feuille A4 avec des repères de
/// découpe. Un badge RETIRÉ n'est jamais proposé : réimprimer une carte retirée la remettrait en circulation. Le pied normalisé (date, utilisateur, identifiant) va sur la
/// planche et non sur les cartes.
class EcranBadgesImpression extends StatelessWidget with EcranMaquette {
  const EcranBadgesImpression({super.key});

  @override
  String get titre => 'Planche d’impression des badges';
  @override
  String get description => 'Sélection multiple puis pose sur feuille A4 avec repères de découpe, ou impression carte par carte.';
  @override
  String get regle =>
      'Deux voies, selon le matériel : l’imprimante à cartes reçoit une carte à la fois, au format CR80 ; la planche A4 en pose dix par feuille, à découper. Un badge retiré n’est jamais proposé à l’impression — réimprimer une carte retirée la remettrait en circulation.';

  @override
  Widget build(BuildContext context) => RhbEcoute(collections: const ['badges', 'modelesBadge', 'personnel'], construire: _corps);

  Widget _corps(BuildContext context, ContexteEcran c) {
    final rows = trierPar([for (final b in rhbActives(c, 'badges')) if (rhcEtatBadge(b['etat']).actif) b], (b) => b['agent']);
    final services = trierPar([for (final s in rhcGrouper(rows, (b) => '${b['service'] ?? ''}').keys) if (s.isNotEmpty) OptionChamp(s)], (o) => o.libelle);
    return rhbEspace([
      const NoteSigh(
          'La planche pose dix badges par feuille (2 × 5 au format CR80). Sélectionner davantage de cartes engendre les feuilles nécessaires, dans l’ordre du tableau.',
          icone: LucideIcons.printer),
      TableauSigh(
        titre: 'Badges imprimables',
        lignes: rows,
        taillePage: 15,
        selectionnable: true,
        nomExport: 'badges-a-imprimer',
        messageVide: 'Aucun badge en cours — en émettre au registre des badges.',
        filtres: [
          FiltreTableau(nom: 'etat', libelle: 'État', options: [for (final e in rhcEtatsBadge) if (e.actif) OptionChamp(e.id, e.label)]),
          FiltreTableau(nom: 'service', libelle: 'Service', options: services),
        ],
        // « Imprimer la planche » est une commande de l'émission : ABSENTE sans le droit d'écrire (jamais grisée).
        actionsGroupe: (ctx, selection, effacer) => [
          if (c.droit.editer) BoutonSigh(libelle: 'Imprimer la planche', icone: LucideIcons.printer, taille: TailleBouton.sm, onPressed: () => _planche(ctx, c, selection)),
        ],
        colonnes: [
          const ColonneTableau(cle: 'numero', libelle: 'N° de série'),
          const ColonneTableau(cle: 'agent', libelle: 'Agent'),
          const ColonneTableau(cle: 'service', libelle: 'Service'),
          ColonneTableau(cle: 'etat', libelle: 'État', texte: (b) => rhcEtatBadge(b['etat']).label, rendu: (_, b) => rhcBadge(rhcEtatBadge(b['etat']).label, rhcEtatBadge(b['etat']).ton)),
          ColonneTableau(
              cle: 'photo',
              libelle: 'Photographie',
              texte: (b) => '${b['photo'] ?? ''}'.isNotEmpty ? 'Oui' : 'À coller',
              rendu: (_, b) => '${b['photo'] ?? ''}'.isNotEmpty ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('À coller', ton: TonSigh.attention)),
        ],
        actionsLigne: (ctx, b) => [
          BoutonIcone(
              icone: LucideIcons.printer,
              libelle: 'Imprimer la carte seule',
              onPressed: () => afficherApercuBadge(context, c, badge: b, modele: rhcModeleDe(c, b), agent: rhaAgentPar(c.magasin, b['personnelId']))),
        ],
      ),
      rhcSource('Registre des badges — seuls les badges en cours de validité sont proposés.'),
    ]);
  }

  void _planche(BuildContext ctx, ContexteEcran c, List<Fiche> selection) {
    if (selection.isEmpty) {
      ToastsSigh.afficher(ctx, 'Sélectionner au moins un badge.', type: TypeToast.attention);
      return;
    }
    final modeles = rhbActives(c, 'modelesBadge');
    // Le gabarit est celui du PREMIER badge sélectionné, à défaut le modèle par défaut.
    final modele = rhcModeleNormalise(c.magasin.collection('modelesBadge').parId(selection.first['modeleId']) ?? rhcModeleParDefaut(modeles), modeles);
    afficherApercuPlanche(ctx, c, modele: modele, badges: [for (final b in selection) (badge: b, agent: rhaAgentPar(c.magasin, b['personnelId']))]);
  }
}
