import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'imp_ecrans.dart';

/// LE BOUTON « Importer les données » : FABRIQUE UNIQUE (équivalent de `K.importer` de la maquette), posée une seule fois par la coque dans les commandes de l'en-tête de
/// chaque écran hôte. Les hôtes d'un jeu sont DÉCLARÉS au manifeste de la maquette (`N.IMPORTS`, section `import` de `rbac.json`), jamais devinés écran par écran ; un écran
/// hôte n'a rien à écrire.
///
///  * Le bouton est ABSENT (jamais grisé) sans le droit d'IMPORTER au moins un jeu de l'écran : le droit est celui du jeu (`MatriceDroits.droitImport`), pas le droit d'éditer
///    l'écran. Le moteur du domaine refuse aussi (`DROIT_IMPORT_REFUSE`) : masquer un bouton ne protège rien.
///  * Un jeu que le poste ne porte pas encore (hôte déclaré, jeu absent du registre) n'ouvre rien : il ne propose pas de bouton.
///  * La fenêtre est celle de la page du jeu, en trois temps (modèle, vérification sans écriture, import) : UN seul contenu, deux portes (`EcranImportJeu(modale: true)`).
List<Widget> boutonsImporter(BuildContext context, {required String ecranId, required MatriceDroits matrice, required String role}) {
  final jeux = [for (final d in matrice.matriceImport.deLHote(ecranId, role)) if (jeuImportParId(d.id) != null) d];
  if (jeux.isEmpty) return const [];
  return [
    BoutonSigh(
      key: const Key('imp-bouton-importer'),
      libelle: 'Importer les données',
      icone: LucideIcons.upload,
      variante: VarianteBouton.secondaire,
      onPressed: () => ouvrirFenetreImport(context, jeux),
    ),
  ];
}

/// La fenêtre du bouton : un jeu, ou le choix parmi ceux que le profil peut importer.
Future<void> ouvrirFenetreImport(BuildContext context, List<DeclarationImport> jeux) {
  final c = ContexteEcran.of(context);
  return afficherModale<void>(
    context,
    titre: 'Importer les données',
    sousTitre: jeux.length == 1 ? jeux.single.libelle : 'Choix du jeu',
    taille: TailleModale.xl,
    corps: c.enveloppe(_CorpsImport(jeux)),
    pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)],
  );
}

class _CorpsImport extends StatefulWidget {
  const _CorpsImport(this.jeux);
  final List<DeclarationImport> jeux;

  @override
  State<_CorpsImport> createState() => _EtatCorpsImport();
}

class _EtatCorpsImport extends State<_CorpsImport> {
  String? _choix;

  @override
  void initState() {
    super.initState();
    if (widget.jeux.length == 1) _choix = widget.jeux.single.id;
  }

  @override
  Widget build(BuildContext context) {
    final id = _choix;
    if (id != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.jeux.length > 1)
          Align(
              alignment: Alignment.centerLeft,
              child: BoutonSigh(
                  libelle: 'Changer de jeu',
                  icone: LucideIcons.arrowLeft,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => setState(() => _choix = null))),
        if (widget.jeux.length > 1) const SizedBox(height: 12),
        EcranImportJeu(id, modale: true, key: ValueKey('imp-fenetre-$id')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Cet écran reçoit plusieurs jeux d’import : choisissez celui qui correspond à votre fichier.', style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final d in widget.jeux)
          SizedBox(
              width: 420,
              child: CarteSigh(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.libelle, style: const TextStyle(fontWeight: FontWeight.w600, color: JetonsShell.navy900)),
                const SizedBox(height: 8),
                Text(jeuImportParId(d.id)!.description, style: const TextStyle(fontSize: 14, color: JetonsShell.slate600)),
                const SizedBox(height: 12),
                BoutonSigh(key: Key('imp-choisir-${d.id}'), libelle: 'Choisir ce jeu', icone: LucideIcons.arrowRight, onPressed: () => setState(() => _choix = d.id)),
              ]))),
      ]),
    ]);
  }
}
