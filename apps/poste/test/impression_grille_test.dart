import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LA GRILLE TARIFAIRE IMPRIMÉE (« Imprimer la grille » de « Tarifs et prix »), comparée à celle de la maquette (lot TFIN). La STRUCTURE de la feuille de la maquette est tirée du DOM réel
/// et de son PDF Chrome (`prototype_html/build/vecteurs-impression-grille.js`) ; le poste en tire son PDF A4 (`pdfA4`, sans fenêtre native) et on compare : en-tête officiel, titre et sous-titre,
/// colonnes, nombre de lignes et valeurs, signatures, pied normalisé. LA COMPARAISON PIXEL À PIXEL N'EST PAS POSSIBLE : le poste (paquet `pdf`, Liberation Sans) et la maquette (Chrome, Inter)
/// n'ont ni le même moteur de rendu ni les mêmes métriques de police ; le test dit les deux pagination mesurées et ne prétend pas à l'identité des pixels.
final V = (jsonDecode(File('test/vecteurs/impression_grille.json').readAsStringSync()) as Map).cast<String, Object?>();

Future<String> texte(String pdf, {String? options}) async {
  final r = await Process.run('pdftotext', ['-layout', pdf, '-']);
  return '${r.stdout}';
}

String compact(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('la grille imprimée du poste a la structure de celle de la maquette : en-tête officiel, titre, colonnes, 201 lignes, signatures, pied normalisé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await toucherM14(t, find.text('Imprimer la grille'));
    await t.pumpAndSettle();
    final feuille = t.widget<FeuilleA4>(find.byType(FeuilleA4));
    final piece = feuille.piece;
    final octets = await t.runAsync(() async => pdfA4(piece, await PolicesPdf.charger())) as List<int>;
    final dossier = Directory.systemTemp.createTempSync('grille-poste-');
    final f = File('${dossier.path}/grille-poste.pdf')..writeAsBytesSync(octets);
    // Un processus ne se lance pas dans la zone simulée d'un test de widget : `runAsync`.
    final txt = compact((await t.runAsync(() => texte(f.path)))!);
    final info = '${(await t.runAsync(() => Process.run('pdfinfo', [f.path])))!.stdout}';
    final pages = int.parse(RegExp(r'Pages:\s+(\d+)').firstMatch(info)!.group(1)!);
    // ignore: avoid_print
    print('GRILLE : poste ${pages} page(s) A4, maquette (Chrome) ${V['pagesPdf']} page(s) ; ${V['nbLignes']} lignes de part et d\'autre');

    // Le titre et le sous-titre (la date est celle du jour de chaque banc : on compare le gabarit, pas la date).
    expect(piece.titre, V['titre']);
    expect(piece.sousTitre!.replaceAll(RegExp(r'\d{2}/\d{2}/\d{4}'), 'JJ/MM/AAAA'), '${V['sousTitre']}'.replaceAll(RegExp(r'\d{2}/\d{2}/\d{4}'), 'JJ/MM/AAAA'));
    // L'en-tête officiel : les mêmes lignes d'identité que la maquette (dénomination, BP, téléphones, autorisation, IFU, RCCM, e-mail, devise).
    final entete = '${V['entete']}';
    for (final mot in ['CLINIQUE NASSIERA TOO', 'BP : 507 NATITINGOU', '01 95 44 51 51', '01 66 43 28 20', '3201642748214', 'RB/NAT/2016-B-268', 'cliniquenassiera@gmail.com', 'Votre santé, notre raison de vivre']) {
      expect(entete, contains(mot), reason: 'la maquette porte « $mot » en en-tête');
      expect(txt, contains(mot), reason: 'le PDF du poste porte « $mot » en en-tête');
    }
    // Les colonnes, dans l'ordre, et les lignes : les 3 premières et les 3 dernières de la maquette se retrouvent, dans l'ordre, dans le PDF du poste.
    final colonnes = (V['colonnes'] as List).cast<String>();
    expect(piece.blocs.length, greaterThan(0));
    final ordre = [for (final c in colonnes) txt.toLowerCase().indexOf(c.toLowerCase())];
    expect(ordre.every((i) => i >= 0), isTrue, reason: 'toutes les colonnes ($colonnes) sont dans le PDF');
    final lignes = [...(V['premieres'] as List), ...(V['dernieres'] as List)].map((l) => (l as List).cast<String>()).toList();
    var depuis = 0;
    for (final l in lignes) {
      final i = txt.indexOf(l[0], depuis);
      expect(i, greaterThanOrEqualTo(0), reason: 'le code « ${l[0]} » est dans le PDF du poste, après le précédent');
      final fin = txt.indexOf(RegExp(r'[A-Z]{2,}[-0-9]+ '), i + l[0].length);
      final segment = txt.substring(i, fin < 0 ? txt.length : fin);
      expect(segment, contains(l[1].substring(0, 12)), reason: 'le libellé de ${l[0]}');
      expect(compact(segment).replaceAll(' ', ' ').replaceAll(' ', ' '), contains(l[2].replaceAll(' ', ' ')), reason: 'le prix non assuré de ${l[0]}');
      depuis = i;
    }
    // Les deux signatures (la Directrice Administrative, la Direction) et le pied normalisé (société, document généré par, référence, « Édité depuis »).
    for (final mot in ['Directrice Administrative', 'La Direction', 'Fait à Natitingou', 'Document généré par', 'Réf. document', 'CLINIQUE NASSIERA TOO SARL']) {
      expect('${V['texteComplet']}', contains(mot), reason: 'la maquette porte « $mot »');
      expect(txt, contains(mot), reason: 'le PDF du poste porte « $mot »');
    }
    // Le nombre de lignes : 201 prestations de part et d'autre (une ligne par prestation, jamais de total inventé) : 201 codes DISTINCTS en début de ligne du PDF du poste.
    final brut = (await t.runAsync(() => texte(f.path)))!;
    final codes = {
      for (final l in brut.split('\n'))
        if (RegExp(r'^\s*([A-Z][A-Z0-9-]*[0-9A-Z])\s{2,}\S').firstMatch(l) != null) RegExp(r'^\s*([A-Z][A-Z0-9-]*[0-9A-Z])').firstMatch(l)!.group(1)!
    }..removeAll({'CLINIQUE', 'CODE', 'BP', 'IFU', 'RCCM'});
    expect(V['nbLignes'], 201);
    expect(codes.length, 201, reason: 'une ligne par prestation, 201 codes distincts dans le PDF du poste');
    expect(pages, greaterThanOrEqualTo(2), reason: 'la grille de 201 lignes tient sur plusieurs pages A4');
    expect((V['pagesPdf'] as num).toInt(), greaterThanOrEqualTo(2), reason: 'la maquette aussi (PDF de Chrome)');
    expect(info, contains('A4'));
    dossier.deleteSync(recursive: true);
  });
}
