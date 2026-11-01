import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Écrivain et lecteur de classeurs .xlsx (OOXML) du poste : port de `prototype_html/assets/js/vendor/xlsx-mini.js`.
///
/// Aucune requête réseau : un import se fait aussi un jour de coupure. Le paquet `excel` aurait exigé `xml` < 7 quand `pdf` (impression des pièces)
/// exige `xml` ^7 ; on lit donc l'archive avec `archive` et ses feuilles avec `xml`, deux paquets que le poste tirait déjà. LIMITES NOMMÉES : pas de
/// formule évaluée (la valeur en cache est lue), pas de style lu, pas de classeur chiffré, pas de .xls (ancien binaire). Une cellule date est rendue en
/// NOMBRE (série Excel) : c'est au moteur d'import, qui connaît la colonne, de la convertir (`importVersDate`).
class FeuilleXlsx {
  const FeuilleXlsx(this.nom, this.lignes,
      {this.largeurs = const [], this.entete = true, this.validations = const [], this.colonnesTexte = const []});
  final String nom;
  final List<List<Object?>> lignes;
  final List<double> largeurs;

  /// Première ligne = en-tête (gras sur fond bleu clair, figée).
  final bool entete;

  /// Listes déroulantes : pour la colonne [colonne] (rang depuis 0), la [formule] de la plage des valeurs permises.
  final List<({int colonne, String formule})> validations;

  /// Colonnes au format texte (`@`) : elles conservent les zéros de tête d'un téléphone.
  final List<int> colonnesTexte;
}

const _enteteXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

String _echappe(Object s) => '$s'
    .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _nomColonne(int i) {
  var s = '';
  var k = i + 1;
  while (k > 0) {
    final r = (k - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    k = (k - 1) ~/ 26;
  }
  return s;
}

/// Écrit un classeur : archive ZIP, chaînes partagées, entête figé, listes déroulantes. Les feuilles sont écrites dans l'ordre donné.
Uint8List ecrireClasseur(List<FeuilleXlsx> feuilles) {
  final chaines = <String>[];
  final indexChaine = <String, int>{};
  int sst(String s) => indexChaine.putIfAbsent(s, () {
        chaines.add(s);
        return chaines.length - 1;
      });
  final xmlFeuilles = <String>[];
  for (final f in feuilles) {
    final nbCol = f.lignes.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final b = StringBuffer('$_enteteXml<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    b.write('<dimension ref="A1:${_nomColonne(nbCol > 0 ? nbCol - 1 : 0)}${f.lignes.isEmpty ? 1 : f.lignes.length}"/>');
    if (f.entete) {
      b.write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');
    }
    if (f.largeurs.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < f.largeurs.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${f.largeurs[i]}" customWidth="1"${f.colonnesTexte.contains(i) ? ' style="4"' : ''}/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < f.lignes.length; r++) {
      b.write('<row r="${r + 1}">');
      final l = f.lignes[r];
      for (var c = 0; c < l.length; c++) {
        final v = l[c];
        if (v == null || (v is String && v.isEmpty)) continue;
        final ref = '${_nomColonne(c)}${r + 1}';
        final style = (r == 0 && f.entete) ? ' s="1"' : '';
        if (v is num && v.isFinite) {
          b.write('<c r="$ref"$style><v>${v == v.truncate() ? v.truncate() : v}</v></c>');
        } else if (v is bool) {
          b.write('<c r="$ref"$style t="b"><v>${v ? 1 : 0}</v></c>');
        } else {
          b.write('<c r="$ref"$style t="s"><v>${sst('$v')}</v></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (f.validations.isNotEmpty) {
      b.write('<dataValidations count="${f.validations.length}">');
      for (final v in f.validations) {
        final col = _nomColonne(v.colonne);
        b.write('<dataValidation type="list" allowBlank="1" showErrorMessage="1" errorStyle="warning" sqref="${col}2:${col}1001"><formula1>${_echappe(v.formule)}</formula1></dataValidation>');
      }
      b.write('</dataValidations>');
    }
    b.write('</worksheet>');
    xmlFeuilles.add(b.toString());
  }
  final partie = <String, String>{
    '[Content_Types].xml': '$_enteteXml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '${[for (var i = 0; i < feuilles.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '</Types>',
    '_rels/.rels': '$_enteteXml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '$_enteteXml<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < feuilles.length; i++) '<sheet name="${_echappe(feuilles[i].nom)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '$_enteteXml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < feuilles.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${feuilles.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId${feuilles.length + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
        '</Relationships>',
    // Styles : 0 normal, 1 entête (gras sur fond bleu clair), 2 note en italique, 3 texte renvoyé à la ligne, 4 texte (format @, conserve les zéros de tête).
    'xl/styles.xml': '$_enteteXml<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><i/><sz val="11"/><color rgb="FF475569"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDBEAFE"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
        '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>'
        '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
        '</styleSheet>',
    'xl/sharedStrings.xml': '$_enteteXml<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${chaines.length}" uniqueCount="${chaines.length}">'
        '${chaines.map((s) => '<si><t xml:space="preserve">${_echappe(s)}</t></si>').join()}</sst>',
  };
  final archive = Archive();
  void ajouter(String nom, String contenu) => archive.addFile(ArchiveFile.bytes(nom, utf8.encode(contenu)));
  partie.forEach(ajouter);
  for (var i = 0; i < xmlFeuilles.length; i++) {
    ajouter('xl/worksheets/sheet${i + 1}.xml', xmlFeuilles[i]);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// --- Lecture ---------------------------------------------------------------------------------------------------------------------

int _colonneDe(String? ref) {
  final m = RegExp(r'^([A-Z]+)').firstMatch(ref ?? '');
  if (m == null) return 0;
  var n = 0;
  for (final u in m[1]!.codeUnits) {
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

String _textes(XmlElement noeud) {
  final b = StringBuffer();
  for (final t in noeud.findAllElements('t')) {
    if ((t.parent as XmlElement?)?.name.local == 'rPh') continue;
    b.write(t.innerText);
  }
  return b.toString();
}

/// Lit un classeur .xlsx : les feuilles dans l'ordre du classeur, leurs lignes sans les lignes vides de queue. Lève [FormatException] avec un motif
/// lisible quand le fichier n'est pas un classeur.
List<FeuilleXlsx> lireClasseur(List<int> octets) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(octets);
    if (archive.isEmpty) throw const FormatException('vide');
  } catch (_) {
    throw const FormatException('Ce fichier n’est pas une archive ZIP : un classeur .xlsx est attendu.');
  }
  String? lire(String nom) {
    final f = archive.findFile(nom);
    return f == null ? null : utf8.decode(f.readBytes() ?? Uint8List(0));
  }

  final classeur = lire('xl/workbook.xml');
  if (classeur == null) throw const FormatException('Ce fichier n’est pas un classeur .xlsx (xl/workbook.xml absent).');
  final wb = XmlDocument.parse(classeur);
  final cibles = <String, String>{};
  final rels = lire('xl/_rels/workbook.xml.rels');
  if (rels != null) {
    for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
      cibles[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
  }
  final partages = <String>[];
  final sstXml = lire('xl/sharedStrings.xml');
  if (sstXml != null) {
    for (final si in XmlDocument.parse(sstXml).findAllElements('si')) {
      partages.add(_textes(si));
    }
  }
  final sortie = <FeuilleXlsx>[];
  var k = 0;
  for (final s in wb.findAllElements('sheet')) {
    k++;
    final nom = s.getAttribute('name') ?? 'Feuille$k';
    final rid = s.getAttribute('r:id') ?? '';
    var cible = cibles[rid] ?? 'worksheets/sheet$k.xml';
    cible = cible.startsWith('/') ? cible.substring(1) : 'xl/$cible';
    final brut = lire(cible);
    if (brut == null) throw FormatException('Feuille « $nom » introuvable dans le classeur.');
    final doc = XmlDocument.parse(brut);
    final lignes = <List<Object?>>[];
    for (final row in doc.findAllElements('row')) {
      var idx = (int.tryParse(row.getAttribute('r') ?? '') ?? (lignes.length + 1)) - 1;
      if (idx < 0) idx = lignes.length;
      final ligne = <Object?>[];
      for (final cell in row.findElements('c')) {
        final t = cell.getAttribute('t');
        final col = _colonneDe(cell.getAttribute('r'));
        final vEl = cell.findElements('v').firstOrNull;
        Object? v = '';
        if (t == 'inlineStr') {
          v = _textes(cell);
        } else if (vEl != null) {
          final b = vEl.innerText;
          if (t == 's') {
            final i = int.tryParse(b);
            v = i != null && i < partages.length ? partages[i] : '';
          } else if (t == 'b') {
            v = b == '1';
          } else if (t == 'str' || t == 'e') {
            v = b;
          } else {
            final nb = num.tryParse(b);
            v = nb != null && b.isNotEmpty ? (nb == nb.truncate() ? nb.truncate() : nb) : b;
          }
        }
        while (ligne.length < col) {
          ligne.add('');
        }
        if (ligne.length == col) {
          ligne.add(v);
        } else {
          ligne[col] = v;
        }
      }
      while (lignes.length < idx) {
        lignes.add(<Object?>[]);
      }
      if (lignes.length == idx) {
        lignes.add(ligne);
      } else {
        lignes[idx] = ligne;
      }
    }
    while (lignes.isNotEmpty && lignes.last.every((v) => v == '' || v == null)) {
      lignes.removeLast();
    }
    sortie.add(FeuilleXlsx(nom, lignes));
  }
  return sortie;
}
