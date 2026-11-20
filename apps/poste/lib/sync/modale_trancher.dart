import 'package:flutter/material.dart';

import '../donnees/magasin.dart';
import '../kit/bouton.dart';
import '../kit/modale.dart';
import '../kit/toast.dart';
import 'package:sigh_sync/sigh_sync.dart' show Err;
import 'moteur_pair.dart';

/// La modale « Conflits à trancher » (ADR-0006, D2) : pour chaque champ écrit en même temps par deux postes, les deux valeurs en présence et un bouton par valeur.
/// Trancher écrit une opération `trancher` ; le moteur refuse en le nommant si le rôle n'a pas ce droit (le message est affiché, jamais avalé).
Future<void> ouvrirModaleTrancher(BuildContext context, {required Magasin magasin, required MoteurPair moteur, required String role}) {
  return afficherModale<void>(context,
      titre: 'Conflits à trancher',
      sousTitre: 'Deux postes ont modifié le même champ en même temps. La valeur la plus récente est retenue en attendant votre décision.',
      taille: TailleModale.lg,
      corps: ListenableBuilder(
          listenable: magasin.collection('conflitsPair'),
          builder: (cc, _) {
            final lignes = magasin.collection('conflitsPair').actives.toList();
            if (lignes.isEmpty) return const Text('Rien à trancher.');
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in lignes)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c['collection']} / ${c['fiche']} : ${c['champ']}'),
                      Wrap(spacing: 8, children: [
                        for (final (i, v) in [(0, c['a']), (1, c['b'])])
                          BoutonSigh(
                              key: Key('pair:trancher-${c['id']}-$i'),
                              libelle: 'Retenir « ${v ?? 'vide'} »',
                              variante: VarianteBouton.secondaire,
                              onPressed: () {
                                try {
                                  moteur.trancher(c, v, role: role);
                                } catch (e) {
                                  ToastsSigh.afficher(cc, e is Err ? e.motif : '$e', type: TypeToast.erreur);
                                }
                              }),
                      ]),
                    ])),
            ]);
          }),
      pied: (fermer) => [BoutonSigh(key: const Key('pair:trancher-fermer'), libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
}
