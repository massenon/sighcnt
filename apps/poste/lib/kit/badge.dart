import 'package:flutter/material.dart';

import 'ton.dart';

/// `.badge` : pastille pleine (rayon 9999), px 8 py 2, 12/16 en 500 — hauteur 20.
class BadgeSigh extends StatelessWidget {
  const BadgeSigh(this.libelle, {super.key, this.ton = TonSigh.neutre});
  final String libelle;
  final TonSigh ton;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: ton.fond50, borderRadius: BorderRadius.circular(9999)),
        child: Text(libelle,
            style: TextStyle(
                color: ton.texteBadge,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w500)),
      );
}
