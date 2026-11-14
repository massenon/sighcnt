import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sigh_domaine/sigh_domaine.dart';

import 'piece.dart';

/// Génération PDF des mêmes pièces que l'aperçu — à partir des MÊMES lignes (`lignesTicket`, `TableauEtat.pied`) : l'écran et le papier
/// ne peuvent pas diverger. Polices Liberation (métriques d'Arial/Courier, licence SIL OFL) : le paquet `pdf` n'embarque pas les OTF d'Inter.
class PolicesPdf {
  PolicesPdf(this.sans, this.gras, this.italique, this.mono, this.monoGras);
  final pw.Font sans, gras, italique, mono, monoGras;

  static Future<PolicesPdf> charger() async {
    Future<pw.Font> f(String n) async =>
        pw.Font.ttf(await rootBundle.load('assets/polices/pdf/$n.ttf'));
    return PolicesPdf(
        await f('LiberationSans-Regular'),
        await f('LiberationSans-Bold'),
        await f('LiberationSans-Italic'),
        await f('LiberationMono-Regular'),
        await f('LiberationMono-Bold'));
  }
}

const _mm = PdfPageFormat.mm;

/// Rouleau 80 mm : largeur fixe, hauteur selon le contenu (les imprimantes thermiques coupent au bout).
Future<Uint8List> pdfTicket(EntreeTicket e, String reference, PolicesPdf p,
    {bool compresser = true, IdentiteImprimee identite = IdentiteImprimee.semence}) async {
  final doc = pw.Document(
      compress: compresser,
      title: 'Ticket $reference',
      author: identite.nom);
  final lignes = lignesTicket(e, identite: identite);
  pw.Widget ligne(LigneTicket l) {
    if (l.estPaire) {
      final s = pw.TextStyle(font: l.gras ? p.monoGras : p.mono, fontSize: 7);
      return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Flexible(child: pw.Text(l.gauche, style: s)),
            pw.SizedBox(width: 6),
            pw.Text(l.droite!, style: s),
          ]);
    }
    final gras = l.style == StyleLigne.titre ||
        l.style == StyleLigne.centreGras ||
        l.style == StyleLigne.lettres;
    final centre = l.style == StyleLigne.titre ||
        l.style == StyleLigne.centre ||
        l.style == StyleLigne.centreGras;
    return pw.Text(l.gauche,
        textAlign: centre ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
            font: gras ? p.monoGras : p.mono,
            fontSize: l.style == StyleLigne.titre
                ? 8.5
                : (l.style == StyleLigne.centre ? 6 : 7)));
  }

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(80 * _mm, double.infinity, marginAll: 4 * _mm),
    build: (_) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      for (final l in lignes) ligne(l),
      pw.SizedBox(height: 3),
      pw.Text('Réf. $reference',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: p.mono, fontSize: 5)),
    ]),
  ));
  return doc.save();
}

/// A4 : en-tête légal, titre, filtres, tableaux (total refait), signatures, pied normalisé répété sur chaque page.
Future<Uint8List> pdfA4(PieceA4 x, PolicesPdf p,
    {bool compresser = true}) async {
  final doc = pw.Document(
      compress: compresser,
      title: x.titre,
      author: x.identiteImprimee.nom,
      subject: x.reference);
  final i = x.identiteImprimee;
  pw.TextStyle s(double t, {pw.Font? f}) =>
      pw.TextStyle(font: f ?? p.sans, fontSize: t);
  final logo = pw.MemoryImage(
      (await rootBundle.load('assets/img/logo.jpeg')).buffer.asUint8List());
  final bleu = PdfColor.fromInt(0xFF12315E);

  pw.Widget entete() => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: bleu, width: 2.2))),
        child:
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Image(logo, width: 48, height: 48),
          pw.SizedBox(width: 12),
          pw.Column(children: [
            pw.Text(i.nomCourt, style: s(18, f: p.gras)),
            pw.Text(
                '${i.bp}   TÉL. : ${i.telephones.join('  /  ')}',
                style: s(7.5)),
            pw.Text('AUTORISATION D’OUVERTURE ${i.autorisation}',
                style: s(7)),
            pw.Text(
                'IFU : ${i.ifu}   RCCM : ${i.rccm}',
                style: s(7, f: p.gras)),
            pw.Text('E-mail : ${i.email}', style: s(7)),
            pw.Text(i.slogan, style: s(7, f: p.italique)),
          ]),
          pw.SizedBox(width: 12),
          pw.SizedBox(width: 48, height: 48),
        ]),
      );

  pw.Widget pied(pw.Context c) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey500, width: 0.5))),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        '${i.nom} — ${i.rccm} — IFU ${i.ifu}',
                        style: s(6)),
                    pw.Text(
                        'Document généré par ${x.utilisateur} le ${dateHeure(x.edite)}',
                        style: s(6)),
                  ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Réf. document : ${x.reference}',
                        style: s(6, f: p.mono)),
                    pw.Text(
                        'Page ${c.pageNumber} / ${c.pagesCount} — Édité depuis le SIGH-CNT',
                        style: s(6)),
                  ]),
            ]),
      );

  pw.Widget tableau(TableauEtat t) {
    final pi = t.pied;
    return pw.TableHelper.fromTextArray(
      headers: [for (final c in t.colonnes) c.libelle],
      data: [...t.cellules, if (pi != null) pi],
      headerStyle: s(7.5, f: p.gras),
      cellStyle: s(7.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      cellAlignments: {
        for (var i = 0; i < t.colonnes.length; i++)
          i: t.colonnes[i].droite
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    );
  }

  /// L'organigramme en PDF : les boîtes aux mesures du domaine (millimètres), les connecteurs tracés dessous. L'axe vertical d'un PDF monte : la hauteur se retourne.
  pw.Widget organigramme(OrgMiseEnPage m) {
    final gris = PdfColor.fromInt(0xFF64748B);
    return pw.Center(
        child: pw.SizedBox(
            width: m.largeur * _mm,
            height: m.hauteur * _mm,
            child: pw.Stack(children: [
              pw.Positioned.fill(
                  child: pw.CustomPaint(painter: (canvas, taille) {
                double y(double v) => taille.y - v * _mm;
                canvas
                  ..setStrokeColor(gris)
                  ..setLineWidth(0.35 * _mm)
                  ..setLineCap(PdfLineCap.square);
                for (final t in m.traits) {
                  canvas
                    ..moveTo(t.x1 * _mm, y(t.y1))
                    ..lineTo(t.x2 * _mm, y(t.y2))
                    ..strokePath();
                }
                canvas.setFillColor(gris);
                for (final f in m.fleches) {
                  canvas.moveTo(f.points[0].$1 * _mm, y(f.points[0].$2));
                  for (final q in f.points.skip(1)) {
                    canvas.lineTo(q.$1 * _mm, y(q.$2));
                  }
                  canvas
                    ..closePath()
                    ..fillPath();
                }
              })),
              for (final b in m.boites)
                pw.Positioned(
                    left: b.gauche * _mm,
                    top: b.haut * _mm,
                    child: pw.Container(
                        width: b.largeur * _mm,
                        height: b.hauteur * _mm,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                            color: b.racine ? PdfColor.fromInt(0xFFEEF2F8) : PdfColors.white,
                            border: pw.Border.all(color: b.racine ? bleu : gris, width: 0.6),
                            borderRadius: pw.BorderRadius.circular(1.5)),
                        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                          for (var i = 0; i < b.lignes.length; i++)
                            pw.Text(b.lignes[i], textAlign: pw.TextAlign.center, style: s(i == 0 ? 6.8 : 6.4, f: i == 0 ? p.gras : null)),
                        ]))),
            ])));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: (x.paysage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4).copyWith(
        marginLeft: 12 * _mm,
        marginRight: 12 * _mm,
        marginTop: 12 * _mm,
        marginBottom: 12 * _mm),
    header: (c) => c.pageNumber == 1 ? entete() : pw.SizedBox(),
    footer: pied,
    build: (_) => [
      pw.SizedBox(height: 12),
      pw.Center(
          child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 3, left: 18, right: 18),
              decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: bleu, width: 1.5))),
              child: pw.Text(x.titre.toUpperCase(), style: s(12, f: p.gras)))),
      if (x.sousTitre != null)
        pw.Center(child: pw.Text(x.sousTitre!, style: s(8))),
      pw.SizedBox(height: 10),
      if (x.filtres.isNotEmpty)
        pw.Container(
            padding: const pw.EdgeInsets.all(6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('FILTRES APPLIQUÉS À CET ÉTAT',
                      style: s(7, f: p.gras)),
                  for (final f in x.filtres)
                    pw.Text('${f.$1} : ${f.$2}', style: s(7.5)),
                  pw.Text(
                      'L’état ne porte que les enregistrements retenus par ces filtres.',
                      style: s(7, f: p.italique)),
                ])),
      if (x.cartouche.isNotEmpty)
        pw.Container(
            padding: const pw.EdgeInsets.all(6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
            child: pw.Wrap(spacing: 16, runSpacing: 2, children: [
              for (final c in x.cartouche)
                pw.SizedBox(
                    width: 230,
                    child: pw.Text('${c.$1} : ${c.$2}', style: s(7.5))),
            ])),
      for (final b in x.blocs) ...[
        // LOT TFIN : le titre du tableau et le tableau sont deux éléments de la liste, JAMAIS un `Column` : un `Column` ne se coupe pas entre deux pages, et un tableau plus haut qu'une
        // page (la grille tarifaire de 201 lignes) faisait créer des pages sans fin (`PdfTooBigPageException`) dès qu'un pied de page existait. Le `Table` se coupe, son en-tête se répète.
        ...switch (b) {
          BlocTableau() => [
              if (b.titre != null) pw.Text(b.titre!.toUpperCase(), style: s(8, f: p.gras)),
              tableau(b.tableau),
            ],
          BlocTexte() => [
              pw.Text(b.texte, style: s(8, f: b.gras ? p.gras : (b.italique ? p.italique : null)))
            ],
          BlocOrganigramme() => [organigramme(b.miseEnPage)],
        },
        pw.SizedBox(height: 10),
      ],
      if (x.lieuDate)
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Fait à Natitingou, le ${dateLong(x.edite)}',
                style: s(8, f: p.italique))),
      if (x.signatures.isNotEmpty)
        pw.Padding(
            padding: const pw.EdgeInsets.only(top: 28),
            child: pw.Row(children: [
              for (final g in x.signatures.take(4))
                pw.Expanded(
                    child: pw.Column(children: [
                  pw.Text(g.role, style: s(8, f: p.gras)),
                  if (g.nom != null) pw.Text(g.nom!, style: s(7)),
                  pw.SizedBox(height: 32),
                  pw.Container(
                      margin: const pw.EdgeInsets.symmetric(horizontal: 10),
                      height: 0.5,
                      color: PdfColors.grey600),
                  pw.Text(g.mention, style: s(6)),
                ])),
            ])),
    ],
  ));
  return doc.save();
}
