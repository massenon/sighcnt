import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// `C.qr(texte, {taille, marge, alt})` : le code QR d'un texte, dessiné en vectoriel (net à n'importe quelle taille), zone de silence comprise. Aucune
/// requête réseau : le code naît de l'encodeur local, on imprime aussi un jour de coupure. Correction d'erreur M.
class QrSigh extends StatelessWidget {
  const QrSigh(this.texte, {super.key, this.taille = 180, this.marge = 3, this.libelle = 'Code QR du formulaire'});
  final String texte;
  final double taille;

  /// Largeur de la zone de silence, en modules.
  final int marge;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: texte, errorCorrectLevel: QrErrorCorrectLevel.M));
    return Semantics(
        image: true,
        label: libelle,
        child: SizedBox(
            key: const Key('qual:qr'),
            width: taille,
            height: taille,
            child: CustomPaint(painter: _Peintre(image, marge))));
  }
}

class _Peintre extends CustomPainter {
  _Peintre(this.image, this.marge);
  final QrImage image;
  final int marge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final total = image.moduleCount + 2 * marge;
    final u = size.width / total;
    final p = Paint()..color = Colors.black;
    for (var r = 0; r < image.moduleCount; r++) {
      for (var c = 0; c < image.moduleCount; c++) {
        if (image.isDark(r, c)) {
          canvas.drawRect(Rect.fromLTWH((c + marge) * u, (r + marge) * u, u + 0.4, u + 0.4), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Peintre o) => o.image != image || o.marge != marge;
}
