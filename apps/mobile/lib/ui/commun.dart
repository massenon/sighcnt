import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';

/// Un refus nommé s'affiche toujours avec ses trois parties : ce qui est refusé (motif), pourquoi il a un code, et le geste qui corrige.
class CarteRefus extends StatelessWidget {
  const CarteRefus(this.refus, {super.key});
  final RefusMobile refus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: ThemeSigh.dangerFond, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(refus.motif, key: const Key('refus-motif'), style: t.bodyMedium?.copyWith(color: ThemeSigh.danger, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('À faire : ${refus.geste}', key: const Key('refus-geste'), style: t.bodyMedium),
        const SizedBox(height: 4),
        Text(refus.code, key: const Key('refus-code'), style: t.bodySmall),
        if (mobRefusAValider(refus.code)) Text(mobMentionAValider, key: const Key('refus-a-valider'), style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

/// Une carte à titre (le gabarit des cartes du dossier et des formulaires).
class CarteTitre extends StatelessWidget {
  const CarteTitre({super.key, required this.titre, required this.enfants});
  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...enfants,
        ]),
      ),
    );
  }
}

/// Un texte d'information (la note d'un écran).
class NoteInfo extends StatelessWidget {
  const NoteInfo(this.texte, {super.key, this.ton});
  final String texte;
  final Color? ton;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: ton ?? ThemeSigh.navyDoux, borderRadius: BorderRadius.circular(8)),
        child: Text(texte, style: Theme.of(context).textTheme.bodyMedium),
      );
}

/// Un champ de saisie : l'erreur du champ vient du refus nommé du domaine.
Widget champSaisie({
  required String cle,
  required String libelle,
  required TextEditingController controleur,
  Map<String, String> erreurs = const {},
  bool requis = false,
  int lignes = 1,
  TextInputType? clavier,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('champ-$cle'),
        controller: controleur,
        keyboardType: clavier,
        minLines: lignes,
        maxLines: lignes,
        decoration: InputDecoration(labelText: requis ? '$libelle *' : libelle, errorText: erreurs[cle], border: const OutlineInputBorder()),
      ),
    );

/// Le message d'un geste enregistré : visible aussitôt, part à la première occasion.
const messageEnregistre = 'Enregistré sur le téléphone, part dès que le réseau revient.';
