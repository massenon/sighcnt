/// L'EXTRACTEUR LOCAL DU TEXTE D'UN PDF (lot D5, portage de `prototype_html/api/_pdf_texte.php`, lot D4 de DOCS-1).
///
/// ÉCRIT POUR LE PROJET, sans paquet et sans appel réseau : la règle de la clinique est que du texte médical ne sort jamais d'elle. Il lit ce qu'un PDF PORTE comme couche
/// texte et rien d'autre : il repère les objets, décompresse les flux Flate, lit l'arbre des pages (ressources héritées comprises), suit les polices de chaque page, décode
/// les chaînes des opérateurs Tj, TJ, ' et " par la table ToUnicode de la police (polices Type0 à codes de deux octets) ou par Windows-1252 (polices simples), et rend les
/// MOTS distincts.
///
/// CE QU'IL NE FAIT PAS, et qu'il dit : un scan est une IMAGE, il n'a pas de couche texte, donc rien à lire (la reconnaissance de caractères est la phase 2 du PRD). Un PDF
/// chiffré, une police sans table ToUnicode à codes multiples ou un flux illisible donnent « texte non indexé » avec leur RAISON : jamais une liste vide présentée comme « le
/// document ne contient aucun mot ».
///
/// La décompression Flate est INJECTÉE ([PdfInflater]) : le domaine ne dépend d'aucune bibliothèque d'entrée-sortie ; le poste fournit celle de `dart:io`.
library;

/// Décompresse un flux Flate (zlib, ou DEFLATE brut) ; `null` s'il est illisible.
typedef PdfInflater = List<int>? Function(List<int> flux);

/// Ce que l'extracteur rend : le nombre de pages (`null` s'il est inconnu), si du texte a été indexé, les mots distincts (minuscules), et la RAISON quand il n'y en a pas.
class PdfTexte {
  const PdfTexte({required this.pages, required this.indexe, required this.mots, required this.raison});
  final int? pages;
  final bool indexe;
  final List<String> mots;
  final String? raison;
}

// --- valeurs PDF ------------------------------------------------------------------------------------------------------------------------

class _Dict {
  _Dict(this.d);
  final Map<String, Object?> d;
}

class _Tab {
  _Tab(this.t);
  final List<Object?> t;
}

class _Nom {
  _Nom(this.n);
  final String n;
}

class _Chaine {
  _Chaine(this.s);
  final String s;
}

class _Num {
  _Num(this.v);
  final double v;
}

class _Ref {
  _Ref(this.n);
  final int n;
}

class _Op {
  _Op(this.o);
  final String o;
}

class _Bool {
  _Bool(this.b);
  final bool b;
}

class _Pos {
  int i = 0;
}

const String _blancs = ' \t\r\n\f\u0000';
const String _delimiteurs = ' \t\r\n\f\u0000()<>[]{}/%';

bool _estBlanc(String c) => c.isNotEmpty && _blancs.contains(c);

String _car(String s, int i) => i >= 0 && i < s.length ? s[i] : '';

final RegExp _reRef = RegExp(r'(\d+)\s+(\d+)\s+R(?![A-Za-z])');
final RegExp _reNombre = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)');
final RegExp _reMot = RegExp(r'''[A-Za-z'"*]+''');

Object? _valeur(String s, _Pos p) {
  final n = s.length;
  while (p.i < n && _estBlanc(s[p.i])) {
    p.i++;
  }
  if (p.i >= n) return null;
  final c = s[p.i];
  if (c == '%') {
    while (p.i < n && s[p.i] != '\n' && s[p.i] != '\r') {
      p.i++;
    }
    return _valeur(s, p);
  }
  if (c == '<' && _car(s, p.i + 1) == '<') {
    p.i += 2;
    final d = <String, Object?>{};
    while (p.i < n) {
      while (p.i < n && _estBlanc(s[p.i])) {
        p.i++;
      }
      if (s.startsWith('>>', p.i)) {
        p.i += 2;
        break;
      }
      final cle = _valeur(s, p);
      if (cle is! _Nom) break;
      d[cle.n] = _valeur(s, p);
    }
    return _Dict(d);
  }
  if (c == '[') {
    p.i++;
    final a = <Object?>[];
    while (p.i < n) {
      while (p.i < n && _estBlanc(s[p.i])) {
        p.i++;
      }
      if (_car(s, p.i) == ']') {
        p.i++;
        break;
      }
      final v = _valeur(s, p);
      if (v == null && p.i >= n) break;
      a.add(v);
    }
    return _Tab(a);
  }
  if (c == '/') {
    var j = p.i + 1;
    while (j < n && !_delimiteurs.contains(s[j])) {
      j++;
    }
    final nom = s.substring(p.i + 1, j);
    p.i = j;
    return _Nom(nom);
  }
  if (c == '(') {
    var prof = 1;
    var j = p.i + 1;
    final out = StringBuffer();
    while (j < n && prof > 0) {
      final ch = s[j];
      if (ch == '\\') {
        j++;
        final e = _car(s, j);
        if (e == 'n') {
          out.write('\n');
        } else if (e == 'r') {
          out.write('\r');
        } else if (e == 't') {
          out.write('\t');
        } else if (e == 'b') {
          out.write('\u0008');
        } else if (e == 'f') {
          out.write('\u000c');
        } else if (e.isNotEmpty && e.compareTo('0') >= 0 && e.compareTo('7') <= 0) {
          var o = e;
          for (var k = 0; k < 2; k++) {
            final q = _car(s, j + 1);
            if (q.isNotEmpty && q.compareTo('0') >= 0 && q.compareTo('7') <= 0) {
              o += q;
              j++;
            } else {
              break;
            }
          }
          out.writeCharCode(int.parse(o, radix: 8) & 255);
        } else if (e == '\r' || e == '\n') {
          if (e == '\r' && _car(s, j + 1) == '\n') j++;
        } else {
          out.write(e);
        }
        j++;
        continue;
      }
      if (ch == '(') prof++;
      if (ch == ')') {
        prof--;
        if (prof == 0) {
          j++;
          break;
        }
      }
      out.write(ch);
      j++;
    }
    p.i = j;
    return _Chaine(out.toString());
  }
  if (c == '<') {
    var j = s.indexOf('>', p.i);
    if (j < 0) j = n;
    var hex = s.substring(p.i + 1, j).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.length.isOdd) hex += '0';
    p.i = j + 1;
    return _Chaine(String.fromCharCodes([for (var k = 0; k < hex.length; k += 2) int.parse(hex.substring(k, k + 2), radix: 16)]));
  }
  final r = _reRef.matchAsPrefix(s, p.i);
  if (r != null) {
    p.i += r.group(0)!.length;
    return _Ref(int.parse(r.group(1)!));
  }
  final nb = _reNombre.matchAsPrefix(s, p.i);
  if (nb != null) {
    p.i += nb.group(0)!.length;
    return _Num(double.parse(nb.group(0)!));
  }
  final mot = _reMot.matchAsPrefix(s, p.i);
  if (mot != null) {
    p.i += mot.group(0)!.length;
    final m = mot.group(0)!;
    if (m == 'true') return _Bool(true);
    if (m == 'false') return _Bool(false);
    if (m == 'null') return null;
    return _Op(m);
  }
  p.i++;
  return null;
}

class _Objet {
  _Objet(this.val, this.flux);
  Object? val;
  String? flux;
}

final RegExp _reObjet = RegExp(r'(?<![0-9])(\d+)\s+(\d+)\s+obj\b');
final RegExp _reFlux = RegExp(r'^\s*stream\r?\n');

Map<int, _Objet> _objets(String pdf, PdfInflater inflate) {
  final objets = <int, _Objet>{};
  final ms = _reObjet.allMatches(pdf).toList();
  if (ms.isEmpty) return {};
  for (final m in ms) {
    final num = int.parse(m.group(1)!);
    final p = _Pos()..i = m.end;
    final v = _valeur(pdf, p);
    final o = _Objet(v, null);
    final reste = pdf.substring(p.i, p.i + 12 > pdf.length ? pdf.length : p.i + 12);
    final ms2 = _reFlux.firstMatch(reste);
    if (v is _Dict && ms2 != null) {
      final d0 = p.i + ms2.group(0)!.length;
      final fin = pdf.indexOf('endstream', d0);
      if (fin >= 0) {
        var flux = pdf.substring(d0, fin);
        flux = flux.replaceFirst(RegExp(r'\r?\n$'), '');
        o.flux = flux;
      }
    }
    objets[num] = o;
  }
  // Flux d'objets (PDF 1.5) : leurs objets internes rejoignent la table.
  for (final e in objets.entries.toList()) {
    final d = e.value.val is _Dict ? (e.value.val as _Dict).d : null;
    if (d != null && (d['Type'] is _Nom && (d['Type'] as _Nom).n == 'ObjStm') && e.value.flux != null) {
      final dec = _flux(e.value, inflate);
      if (dec == null) continue;
      final nb = d['N'] is _Num ? (d['N'] as _Num).v.toInt() : 0;
      final premier = d['First'] is _Num ? (d['First'] as _Num).v.toInt() : 0;
      final entete = dec.substring(0, premier > dec.length ? dec.length : premier);
      var pp = RegExp(r'(\d+)\s+(\d+)').allMatches(entete).toList();
      if (pp.isEmpty) continue;
      if (pp.length > nb) pp = pp.sublist(0, nb);
      for (var idx = 0; idx < pp.length; idx++) {
        final deb = premier + int.parse(pp[idx].group(2)!);
        final suiv = idx + 1 < pp.length ? premier + int.parse(pp[idx + 1].group(2)!) : dec.length;
        if (deb > dec.length || suiv < deb) continue;
        final sub = dec.substring(deb, suiv > dec.length ? dec.length : suiv);
        final pj = _Pos();
        objets[int.parse(pp[idx].group(1)!)] = _Objet(_valeur(sub, pj), null);
      }
    }
  }
  return objets;
}

/// Le contenu décodé d'un objet à flux, ou `null` (filtre inconnu, flux illisible).
String? _flux(_Objet o, PdfInflater inflate) {
  if (o.flux == null) return null;
  final d = o.val is _Dict ? (o.val as _Dict).d : const <String, Object?>{};
  final f = d['Filter'];
  final filtres = <String>[];
  if (f is _Nom) {
    filtres.add(f.n);
  } else if (f is _Tab) {
    for (final x in f.t) {
      filtres.add(x is _Nom ? x.n : '?');
    }
  }
  List<int> data = o.flux!.codeUnits;
  for (final nom in filtres) {
    if (nom == 'FlateDecode' || nom == 'Fl') {
      final r = inflate(data);
      if (r == null) return null;
      data = r;
    } else {
      return null;
    }
  }
  return String.fromCharCodes(data);
}

Object? _res(Map<int, _Objet> objets, Object? v) {
  var garde = 0;
  while (v is _Ref && garde++ < 20) {
    v = objets[v.n]?.val;
  }
  return v;
}

// --- polices ----------------------------------------------------------------------------------------------------------------------------

class _ToUnicode {
  _ToUnicode(this.larg, this.carte);
  final int larg;
  final Map<int, String> carte;
}

class _Police {
  _Police(this.tounicode, this.type0);
  final _ToUnicode? tounicode;
  final bool type0;
}

String _u16(String hex) {
  if (hex.length.isOdd) hex += '0';
  final u = <int>[];
  for (var i = 0; i + 4 <= hex.length; i += 4) {
    u.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  // Un octet seul en fin de chaîne (nombre impair d'octets) : ignoré, comme `mb_convert_encoding`.
  return String.fromCharCodes(u);
}

_ToUnicode _tounicode(String cmap) {
  final carte = <int, String>{};
  var larg = 0;
  final cs = RegExp(r'begincodespacerange(.*?)endcodespacerange', dotAll: true).firstMatch(cmap);
  if (cs != null) {
    final c = RegExp(r'<([0-9A-Fa-f]+)>').firstMatch(cs.group(1)!);
    if (c != null) larg = c.group(1)!.length ~/ 2;
  }
  for (final bloc in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(cmap)) {
    for (final e in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(bloc.group(1)!)) {
      carte[int.parse(e.group(1)!, radix: 16)] = _u16(e.group(2)!);
      if (larg == 0) larg = e.group(1)!.length ~/ 2;
    }
  }
  for (final bloc in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(cmap)) {
    for (final e in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(\[[^\]]*\]|<[0-9A-Fa-f]*>)').allMatches(bloc.group(1)!)) {
      final lo = int.parse(e.group(1)!, radix: 16);
      final hi = int.parse(e.group(2)!, radix: 16);
      if (larg == 0) larg = e.group(1)!.length ~/ 2;
      if (hi - lo > 65535) continue;
      final cible = e.group(3)!;
      if (cible.startsWith('[')) {
        var k = 0;
        for (final h in RegExp(r'<([0-9A-Fa-f]*)>').allMatches(cible)) {
          carte[lo + k] = _u16(h.group(1)!);
          k++;
        }
      } else {
        final base = cible.replaceAll(RegExp(r'^<|>$'), '');
        final texte = _u16(base);
        for (var c = lo; c <= hi; c++) {
          if (c == lo) {
            carte[c] = texte;
            continue;
          }
          final chars = texte.runes.toList();
          if (chars.isNotEmpty) {
            final dernier = chars.removeLast();
            chars.add(dernier + (c - lo));
            carte[c] = String.fromCharCodes(chars);
          }
        }
      }
    }
  }
  return _ToUnicode(larg == 0 ? 2 : larg, carte);
}

/// Windows-1252 : les octets 0x80 à 0x9F ont leur propre table, le reste se lit comme Latin-1.
const Map<int, int> _cp1252 = {
  0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160, 0x8b: 0x2039, 0x8c: 0x0152,
  0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a,
  0x9c: 0x0153, 0x9e: 0x017e, 0x9f: 0x0178,
};

String _windows1252(String octets) => String.fromCharCodes([for (final c in octets.codeUnits) _cp1252[c] ?? c]);

String _decoder(String chaine, _Police? police) {
  if (police == null) return _windows1252(chaine);
  final tu = police.tounicode;
  if (tu != null) {
    final out = StringBuffer();
    final n = chaine.length;
    for (var i = 0; i + tu.larg <= n; i += tu.larg) {
      var code = 0;
      for (var k = 0; k < tu.larg; k++) {
        code = (code << 8) | (chaine.codeUnitAt(i + k) & 255);
      }
      final t = tu.carte[code];
      if (t != null) out.write(t);
    }
    return out.toString();
  }
  if (police.type0) return '';
  return _windows1252(chaine);
}

String _contenu(String c, Map<String, _Police> polices) {
  final p = _Pos();
  final n = c.length;
  var pile = <Object?>[];
  final texte = StringBuffer();
  _Police? courante;
  var essais = 0;
  while (p.i < n && essais++ < 2000000) {
    final debut = p.i;
    final v = _valeur(c, p);
    if (p.i <= debut) {
      p.i = debut + 1;
      continue;
    }
    if (v is _Op) {
      final op = v.o;
      if (op == 'Tf') {
        String? nom;
        for (final x in pile) {
          if (x is _Nom) nom = x.n;
        }
        courante = nom != null ? polices[nom] : null;
      } else if (op == 'Tj' || op == "'" || op == '"') {
        String? s;
        for (final x in pile) {
          if (x is _Chaine) s = x.s;
        }
        if (s != null) texte.write(_decoder(s, courante) + (op == 'Tj' ? '' : ' '));
      } else if (op == 'TJ') {
        for (final x in pile) {
          if (x is _Tab) {
            for (final e in x.t) {
              if (e is _Chaine) {
                texte.write(_decoder(e.s, courante));
              } else if (e is _Num && e.v < -200) {
                texte.write(' ');
              }
            }
          }
        }
      } else if (const ['T*', 'Td', 'TD', 'Tm', 'ET', 'BT'].contains(op)) {
        texte.write(' ');
      }
      pile = [];
      continue;
    }
    pile.add(v);
    if (pile.length > 64) pile.removeAt(0);
  }
  return texte.toString();
}

final RegExp _reEncrypt1 = RegExp(r'/Encrypt\b');
final RegExp _reEncrypt2 = RegExp(r'/Encrypt\s+\d+\s+\d+\s+R');
final RegExp _reMots = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’-]*", unicode: true);

/// Extrait pages et mots d'un PDF (octets). Jamais d'exception : un PDF illisible donne `indexe: false` et sa raison.
PdfTexte pdfExtraireTexte(List<int> octets, PdfInflater inflate) {
  final pdf = String.fromCharCodes(octets);
  if (!pdf.startsWith('%PDF-')) return const PdfTexte(pages: null, indexe: false, mots: [], raison: 'pas un PDF');
  try {
    return _extraire(pdf, inflate);
  } catch (_) {
    return const PdfTexte(pages: null, indexe: false, mots: [], raison: 'extraction du texte en échec');
  }
}

PdfTexte _extraire(String pdf, PdfInflater inflate) {
  final objets = _objets(pdf, inflate);
  if (objets.isEmpty) return const PdfTexte(pages: null, indexe: false, mots: [], raison: 'structure du PDF illisible');
  final pages = <int, Map<String, Object?>>{};
  objets.forEach((num, o) {
    final d = o.val is _Dict ? (o.val as _Dict).d : null;
    if (d != null && d['Type'] is _Nom && (d['Type'] as _Nom).n == 'Page') pages[num] = d;
  });
  final nbPages = pages.isEmpty ? null : pages.length;
  final queue = pdf.length > 4096 ? pdf.substring(pdf.length - 4096) : pdf;
  if (_reEncrypt1.hasMatch(queue) || _reEncrypt2.hasMatch(pdf)) {
    return PdfTexte(pages: nbPages, indexe: false, mots: const [], raison: 'PDF chiffré : texte non lisible');
  }
  final tout = StringBuffer();
  var lu = false;
  for (final d in pages.values) {
    // Ressources : celles de la page, sinon héritées de ses parents.
    Object? ressources;
    Map<String, Object?>? courant = d;
    for (var g = 0; g < 12 && courant != null; g++) {
      if (courant['Resources'] != null) {
        ressources = _res(objets, courant['Resources']);
        break;
      }
      final parent = courant['Parent'] != null ? _res(objets, courant['Parent']) : null;
      courant = parent is _Dict ? parent.d : null;
    }
    var fontDict = <String, Object?>{};
    if (ressources is _Dict && ressources.d['Font'] != null) {
      final f = _res(objets, ressources.d['Font']);
      fontDict = f is _Dict ? f.d : <String, Object?>{};
    }
    final polices = <String, _Police>{};
    fontDict.forEach((nom, ref) {
      final fo = _res(objets, ref);
      final fd = fo is _Dict ? fo.d : null;
      if (fd == null) return;
      _ToUnicode? tu;
      final tuRef = fd['ToUnicode'];
      if (tuRef is _Ref) {
        final o = objets[tuRef.n];
        final cm = o == null ? null : _flux(o, inflate);
        if (cm != null) tu = _tounicode(cm);
      }
      polices[nom] = _Police(tu, fd['Subtype'] is _Nom && (fd['Subtype'] as _Nom).n == 'Type0');
    });
    final contenus = <int>[];
    var c = d['Contents'];
    if (c != null) {
      if (c is _Ref) {
        final r = _res(objets, c);
        if (r is _Tab) {
          c = r;
        } else {
          contenus.add(c.n);
          c = null;
        }
      }
      if (c is _Tab) {
        for (final x in c.t) {
          if (x is _Ref) contenus.add(x.n);
        }
      }
    }
    for (final ref in contenus) {
      final o = objets[ref];
      final data = o == null ? null : _flux(o, inflate);
      if (data == null) continue;
      lu = true;
      tout.write(' ${_contenu(data, polices)}');
    }
  }
  final texte = tout.toString().toLowerCase();
  final uniques = <String>{};
  for (final m in _reMots.allMatches(texte)) {
    var mot = m.group(0)!;
    mot = mot.replaceAll(RegExp(r"^['’-]+|['’-]+$"), '');
    if (mot.runes.length >= 2) uniques.add(mot);
  }
  final mots = uniques.toList();
  final indexe = mots.isNotEmpty;
  String? raison;
  if (!indexe) raison = lu ? 'aucune couche texte lisible : scan image' : 'contenu des pages illisible';
  return PdfTexte(pages: nbPages, indexe: indexe, mots: mots, raison: raison);
}

/// Ce que l'indexation d'un fichier déposé rend : pages, texte indexé ou non, les mots (4 000 au plus), et la RAISON d'un « texte non indexé » (`api/fichiers.php`).
class IndexationFichier {
  const IndexationFichier({required this.pages, required this.texteIndexe, required this.mots, required this.motsTronques, required this.raison});
  final int? pages;
  final bool texteIndexe;
  final List<String> mots;
  final bool motsTronques;
  final String? raison;
}

/// Le nombre de mots qu'un fichier garde au registre : au-delà, la liste est tronquée et le dit (`motsTronques`).
const int fichierMotsMax = 4000;

/// L'indexation d'un fichier selon son format : un PDF passe par l'extracteur ; une image n'a pas de couche texte (reconnaissance de caractères : phase 2). Jamais d'appel externe.
IndexationFichier indexerFichier(List<int> octets, String formatId, PdfInflater inflate) {
  if (formatId != 'pdf') return const IndexationFichier(pages: null, texteIndexe: false, mots: [], motsTronques: false, raison: 'image sans couche texte');
  final t = pdfExtraireTexte(octets, inflate);
  final tronque = t.mots.length > fichierMotsMax;
  return IndexationFichier(pages: t.pages, texteIndexe: t.indexe, mots: tronque ? t.mots.sublist(0, fichierMotsMax) : t.mots, motsTronques: tronque, raison: t.raison);
}
