import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';

/// Ce que la console de la mère affecte à un TÉLÉPHONE en émettant son code d'appairage (E1600) : un nom, un profil et, pour un soignant, sa
/// fonction. La fonction est FIXÉE par ce code : le téléphone la reçoit de la mère, ne peut ni la déclarer ni la changer, et la mère la relit dans sa
/// table à chaque dépôt. Un autre rôle exige un nouveau code (donc un nouvel appairage).
typedef AffectationMobile = ({String etiquette, String profil, String? fonction});

/// Le libellé d'un profil de mobile, tel que la console l'affiche.
String libelleProfilMobile(String? profil) => switch (profil) {
      'soignant' => 'Soignant',
      'reception' => 'Réception de secours',
      _ => 'Aucun',
    };

/// « Soignant, Médecin » / « Réception de secours » / « Aucune » : la colonne « Fonction » des appareils.
String libelleFonctionMobile(String? profil, String? fonction) {
  // Un mobile appairé AVANT la fixation de la fonction n'a pas de profil dans la table de la mère : sa fonction n'est pas fixée et la mère refuse ses pièces.
  if (profil == null) return 'Non fixée';
  if (profil == 'reception') return 'Aucune';
  return fonction == null || fonction.isEmpty ? 'Non fixée' : mobLibelleFonction(fonction);
}

/// Demande à l'administrateur le nom, le profil et (pour un soignant) la fonction du téléphone à appairer. `null` : annulé.
Future<AffectationMobile?> demanderAffectationMobile(BuildContext context, {String titre = 'Appairer un mobile', String libelleOk = 'Générer le code'}) async {
  final ctl = ControleurFormulaire([
    const ChampDef(nom: 'etiquette', libelle: 'Nom de l’appareil (ex. Réception, Dr Yeni)', requis: true, col: ColChamp.plein),
    const ChampDef(
      nom: 'profil',
      libelle: 'Profil du téléphone',
      type: TypeChamp.select,
      requis: true,
      col: ColChamp.plein,
      options: [OptionChamp('soignant', 'Soignant'), OptionChamp('reception', 'Réception de secours')],
    ),
    ChampDef(
      nom: 'fonction',
      libelle: 'Fonction du soignant',
      type: TypeChamp.select,
      requis: true,
      col: ColChamp.plein,
      condition: (controle: 'profil', quand: const ['soignant']),
      options: [for (final f in mobFonctions) OptionChamp(f, mobLibelleFonction(f))],
      aide: 'La fonction est fixée par ce code. Le téléphone ne peut ni la choisir ni la changer : un autre rôle exige un nouveau code.',
    ),
  ]);
  final v = await afficherModale<Map<String, Object?>>(context,
      titre: titre,
      taille: TailleModale.sm,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: libelleOk,
                onPressed: () {
                  final r = ctl.valider();
                  if (r != null) Navigator.of(context, rootNavigator: true).pop(r);
                }),
          ]);
  if (v == null) return null;
  final profil = '${v['profil']}';
  return (etiquette: '${v['etiquette']}'.trim(), profil: profil, fonction: profil == 'soignant' ? '${v['fonction']}' : null);
}
