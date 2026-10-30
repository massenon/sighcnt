import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// Utilitaires des écrans de mouvements de stock (M6 : transferts, mouvements, inventaires, pertes). Préfixe `mvt_` : ce module est porté en
/// parallèle par plusieurs mains, chacune dans ses fichiers.

num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// `C.money(v, false)`.
String m(Object? v) => money(v, avecDevise: false);

String dateDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Les produits actifs du magasin.
List<Fiche> produitsActifs(ContexteEcran c) => c.magasin.collection('produits').actives;

/// `valeurStock(rows)` : Σ stock × CUMP.
num valeurStock(Iterable<Fiche> rows) => rows.fold<num>(0, (a, p) => a + n(p['stock']) * n(p['cump']));

/// Le ton d'un badge de la maquette (`success`, `navy`, `danger`…) → ton du kit.
TonSigh tonDe(String? t) => switch (t) {
      'success' => TonSigh.succes,
      'navy' => TonSigh.navy,
      'danger' => TonSigh.danger,
      'warning' => TonSigh.attention,
      'info' => TonSigh.info,
      _ => TonSigh.neutre,
    };

/// `D.TYPES_STOCK` : libellé d'un stock.
String stockLabel(Object? id) {
  for (final s in typesStock) {
    if (s.$1 == id) return s.$2;
  }
  return '$id';
}

const styleMono = TextStyle(
    fontFamily: 'LiberationMono',
    color: JetonsShell.slate900,
    fontSize: 12,
    height: 16 / 12);

/// Référence en police fixe (colonne N° des registres).
Widget reference(Object? v, {bool gras = false}) => Text('${v ?? ''}',
    style: styleMono.copyWith(fontWeight: gras ? FontWeight.w600 : null));

/// Les clés d'archives de la maquette : une annulation DOIT être visible. Remplace `U.toast(…, {undo})`.
void annonce(BuildContext ctx, String message,
        {TypeToast type = TypeToast.succes,
        String? detail,
        VoidCallback? annuler,
        String messageAnnulation = 'Action annulée.',
        Duration? duree}) =>
    ToastsSigh.afficher(ctx, message,
        type: type,
        detail: detail,
        annuler: annuler,
        messageAnnulation: messageAnnulation,
        duree: duree);

/// Dates ISO du jour de l'horloge du poste.
String jourIso(ContexteEcran c) => iso(c.aujourdhui);

/// Applique un correctif de stock `{id, patch}` du domaine au magasin ; rend la fonction qui le restitue (`col.update(...).undo`).
VoidCallback appliquerCorrectif(CollectionMagasin produits, ({String id, Map<String, Object?> patch}) c) =>
    produits.mettreAJour(c.id, c.patch);
