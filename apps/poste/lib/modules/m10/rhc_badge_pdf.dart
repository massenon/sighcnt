import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../impression/pdf.dart' show PolicesPdf;
import 'rhc_badge_carte.dart' show rhcPhoto;

/// Le PDF du badge : la carte CR80 (85,6 × 54 mm), recto puis verso — UNE page par face, aux cotes exactes. Mêmes données que l'aperçu (`CarteBadgeSigh`) : le papier ne peut pas
/// diverger de l'écran. Ni IFU ni RCCM (mentions fiscales) ; le QR ne porte que le matricule et le numéro de série (`rhcBadgeQR`).
const _mm = PdfPageFormat.mm;
final _navy900 = PdfColor.fromInt(0xFF12315E);
final _navy950 = PdfColor.fromInt(0xFF0B1E3B);
final _navy700 = PdfColor.fromInt(0xFF1F4A8A);
final _navy100 = PdfColor.fromInt(0xFFDCE6F4);
final _slate = PdfColor.fromInt(0xFF64748B);
final _slate600 = PdfColor.fromInt(0xFF475569);
final _slate200 = PdfColor.fromInt(0xFFE2E8F0);
final _slate300 = PdfColor.fromInt(0xFFCBD5E1);
final _slate400 = PdfColor.fromInt(0xFF94A3B8);

/// Le code QR, dessiné module par module (aucune requête réseau, vectoriel).
pw.Widget _qr(String charge, double cote) {
  final image = QrImage(QrCode.fromData(data: charge, errorCorrectLevel: QrErrorCorrectLevel.M));
  const marge = 2;
  return pw.SizedBox(
      width: cote,
      height: cote,
      child: pw.CustomPaint(painter: (canvas, taille) {
        final total = image.moduleCount + 2 * marge;
        final u = taille.x / total;
        canvas
          ..setFillColor(PdfColors.white)
          ..drawRect(0, 0, taille.x, taille.y)
          ..fillPath()
          ..setFillColor(PdfColors.black);
        for (var r = 0; r < image.moduleCount; r++) {
          for (var c = 0; c < image.moduleCount; c++) {
            if (image.isDark(r, c)) canvas.drawRect((c + marge) * u, taille.y - (r + marge + 1) * u, u + 0.1, u + 0.1);
          }
        }
        canvas.fillPath();
      }));
}

String _date(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}'.padRight(10).substring(0, 10).trim());
  return d == null ? '$v' : dateFR(d);
}

String _ou(Object? a, Object? b) => '${a ?? ''}'.isNotEmpty ? '$a' : ('${b ?? ''}'.isNotEmpty ? '$b' : '—');

/// Une face de carte.
pw.Widget _carte(Fiche badge, RhcModele modele, Fiche? agent, PolicesPdf p, pw.MemoryImage? logo, {required bool verso}) {
  final l = modele.portrait ? rhcHauteurCr80Pdf : rhcLargeurCr80Pdf, h = modele.portrait ? rhcLargeurCr80Pdf : rhcHauteurCr80Pdf;
  pw.TextStyle s(double t, {pw.Font? f, PdfColor? c}) => pw.TextStyle(font: f ?? p.sans, fontSize: t, color: c ?? PdfColors.black);
  final cadre = pw.BoxDecoration(color: PdfColors.white, border: pw.Border.all(color: _slate300, width: 0.5), borderRadius: pw.BorderRadius.circular(2.5 * _mm));
  if (verso) {
    return pw.Container(
        width: l * _mm,
        height: h * _mm,
        decoration: cadre,
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(IdentiteClinique.nom, style: s(5, f: p.gras, c: _navy900)),
          pw.Container(margin: const pw.EdgeInsets.only(top: 3), height: 0.5, color: _slate200),
          pw.Expanded(
              child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    for (final t in modele.mentionsVerso) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 1.5), child: pw.Text(t, style: s(4.5, c: _slate600))),
                  ]))),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('N° de série', style: s(4.5, c: _slate)),
              pw.Text('${badge['numero'] ?? '—'}', style: s(5, f: p.monoGras)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Valable jusqu’au', style: s(4.5, c: _slate)),
              pw.Text('${badge['expireLe'] ?? ''}'.isNotEmpty ? _date(badge['expireLe']) : 'non fixée', style: s(5, f: p.gras)),
            ]),
          ]),
          pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Center(child: pw.Text(IdentiteClinique.slogan, style: s(4.5, f: p.italique, c: _navy700)))),
        ]));
  }
  final z = modele.zones;
  final photo = rhcPhoto(badge['photo']);
  pw.MemoryImage? image;
  if (photo != null) {
    try {
      image = pw.MemoryImage(photo);
    } catch (_) {
      image = null;
    }
  }
  final charge = rhcBadgeQR(badge);
  return pw.Container(
      width: l * _mm,
      height: h * _mm,
      decoration: cadre,
      child: pw.ClipRRect(
          horizontalRadius: 2.5 * _mm,
          verticalRadius: 2.5 * _mm,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Container(
                height: 11 * _mm,
                color: _navy900,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: pw.Row(children: [
                  if (logo != null) pw.Container(width: 21, height: 21, color: PdfColors.white, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                      child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('CLINIQUE NASSIERA TOO', style: s(6, f: p.gras, c: PdfColors.white)),
                    pw.Text(IdentiteClinique.slogan, style: s(4.5, f: p.italique, c: _navy100)),
                  ])),
                ])),
            pw.Expanded(
                child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
                    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      if (z['photo'] != false) ...[
                        pw.Container(
                            width: 20 * _mm,
                            height: 26 * _mm,
                            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9), border: pw.Border.all(color: _slate300, width: 0.5)),
                            child: image != null
                                ? pw.Image(image, fit: pw.BoxFit.cover)
                                : pw.Center(child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [pw.Text('PHOTO', style: s(4.5, c: _slate400)), pw.Text('À COLLER', style: s(4.5, c: _slate400))]))),
                        pw.SizedBox(width: 6),
                      ],
                      pw.Expanded(
                          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        if (z['nom'] != false) pw.Text((agent != null ? '${agent['nomComplet']}' : '${badge['agent'] ?? '—'}').toUpperCase(), style: s(8, f: p.gras, c: _navy950)),
                        if (z['fonction'] != false) pw.Text(_ou(badge['poste'], agent?['poste']), style: s(5, f: p.gras, c: _navy700)),
                        if (z['service'] != false) pw.Text('Service : ${_ou(badge['service'], agent?['service'])}', style: s(5, c: _slate600)),
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 1.5), child: pw.Text('Matricule ${badge['matricule'] ?? '—'}', style: s(5, f: p.mono))),
                        pw.Spacer(),
                        pw.Text('${badge['numero'] ?? ''}', style: s(4.5, f: p.mono, c: _slate)),
                      ])),
                      if (z['qr'] != false) ...[
                        pw.SizedBox(width: 6),
                        pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                          if (rhcQrAcceptable(charge)) _qr(charge, 17 * _mm) else pw.SizedBox(width: 17 * _mm, child: pw.Text('Code trop long', style: s(4.5))),
                          pw.Padding(padding: const pw.EdgeInsets.only(top: 1.5), child: pw.Text('Contrôle SIGH', style: s(3.5, c: _slate400))),
                        ]),
                      ],
                    ]))),
          ])));
}

const rhcLargeurCr80Pdf = 85.6;
const rhcHauteurCr80Pdf = 54.0;

Future<pw.MemoryImage?> _logo() async {
  try {
    return pw.MemoryImage((await rootBundle.load('assets/img/logo.jpeg')).buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// UNE carte : deux pages CR80, le recto puis le verso.
Future<Uint8List> pdfBadge({required Fiche badge, required RhcModele modele, Fiche? agent, required String reference, required PolicesPdf polices, bool compresser = true}) async {
  final doc = pw.Document(compress: compresser, title: 'Badge ${badge['numero']}', author: IdentiteClinique.nom, subject: reference);
  final logo = await _logo();
  final l = modele.portrait ? rhcHauteurCr80Pdf : rhcLargeurCr80Pdf, h = modele.portrait ? rhcLargeurCr80Pdf : rhcHauteurCr80Pdf;
  for (final verso in [false, true]) {
    doc.addPage(pw.Page(pageFormat: PdfPageFormat(l * _mm, h * _mm), margin: pw.EdgeInsets.zero, build: (_) => _carte(badge, modele, agent, polices, logo, verso: verso)));
  }
  return doc.save();
}

/// La PLANCHE : feuille A4, dix cartes par page (2 × 5), repères de découpe aux angles, pied normalisé (utilisateur, date, identifiant) sur la feuille.
Future<Uint8List> pdfPlanche(
    {required RhcModele modele, required List<({Fiche badge, Fiche? agent})> badges, required String reference, required String utilisateur, required DateTime edite, required PolicesPdf polices, bool compresser = true}) async {
  final doc = pw.Document(compress: compresser, title: 'Planche de badges', author: IdentiteClinique.nom, subject: reference);
  final logo = await _logo();
  pw.TextStyle s(double t, {pw.Font? f, PdfColor? c}) => pw.TextStyle(font: f ?? polices.sans, fontSize: t, color: c ?? PdfColors.black);
  pw.Widget coin(bool haut, bool gauche) => pw.Positioned(
      left: gauche ? 0 : null,
      right: gauche ? null : 0,
      top: haut ? 0 : null,
      bottom: haut ? null : 0,
      child: pw.Container(
          width: 3 * _mm,
          height: 3 * _mm,
          decoration: pw.BoxDecoration(
              border: pw.Border(
                  top: haut ? pw.BorderSide(color: _slate400, width: 0.5) : pw.BorderSide.none,
                  bottom: haut ? pw.BorderSide.none : pw.BorderSide(color: _slate400, width: 0.5),
                  left: gauche ? pw.BorderSide(color: _slate400, width: 0.5) : pw.BorderSide.none,
                  right: gauche ? pw.BorderSide.none : pw.BorderSide(color: _slate400, width: 0.5)))));
  for (var i = 0; i < badges.length; i += 10) {
    final lot = badges.sublist(i, i + 10 > badges.length ? badges.length : i + 10);
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12 * _mm),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text('PLANCHE DE BADGES — ${nombre(lot.length)} CARTE(S)', style: s(8, f: polices.gras, c: _navy900))),
              pw.Wrap(children: [
                for (final b in lot)
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(1.5 * _mm),
                      child: pw.Stack(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(0.1 * _mm), child: _carte(b.badge, modele, b.agent, polices, logo, verso: false)),
                        coin(true, true),
                        coin(true, false),
                        coin(false, true),
                        coin(false, false),
                      ])),
              ]),
              pw.Spacer(),
              pw.Container(
                  padding: const pw.EdgeInsets.only(top: 6),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500, width: 0.5))),
                  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('${IdentiteClinique.nom} — ${IdentiteClinique.rccm} — IFU ${IdentiteClinique.ifu}', style: s(6, c: _slate)),
                      pw.Text('Document généré par $utilisateur le ${dateHeure(edite)}', style: s(6, c: _slate)),
                    ]),
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      pw.Text('Réf. document : $reference', style: s(6, f: polices.mono, c: _slate)),
                      pw.Text('Édité depuis le SIGH-CNT', style: s(6, c: _slate)),
                    ]),
                  ])),
            ])));
  }
  return doc.save();
}
