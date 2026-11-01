/* =============================================================================
 * XLSX-MINI : écrivain et lecteur OOXML (.xlsx) écrits pour le prototype.
 * -----------------------------------------------------------------------------
 * Aucune dépendance, aucune requête réseau : on importe aussi un jour de coupure. Pas de bibliothèque tierce,
 * donc pas de licence à tenir ni de version à épingler : ce fichier est du code du dépôt, relu et testé comme tel.
 *
 *   SIGH.xlsx.ecrire({ feuilles: [{ nom, lignes: [[...]], largeurs: [20, 12], entete: true, listes: [{colonne, liste}] }] })
 *       -> Uint8Array (un classeur .xlsx, archive ZIP sans compression, chaînes partagées, entête figé)
 *   SIGH.xlsx.lire(octets)       -> { feuilles: [{ nom, lignes: [[valeur, ...], ...] }] }  (inflate intégré : lit aussi les classeurs d'Excel)
 *   SIGH.xlsx.lireCsv(texte)     -> lignes (séparateur ; , ou tabulation détecté, guillemets, BOM)
 *   SIGH.xlsx.versDate(n)        -> 'AAAA-MM-JJ' depuis un numéro de série Excel (système 1900)
 *
 * LIMITES NOMMÉES : pas de formules évaluées (la valeur en cache est lue), pas de styles lus, pas de classeur
 * chiffré, pas de ZIP64, pas de .xls (ancien binaire). Une cellule date est rendue en NOMBRE (série) : c'est à
 * l'appelant qui connaît la colonne de la convertir.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --- CRC-32 ---------------------------------------------------------------------------------------------- */
  var TABLE_CRC = (function () {
    var t = new Uint32Array(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(octets) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < octets.length; i++) c = TABLE_CRC[(c ^ octets[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  function enOctets(texte) { return new TextEncoder().encode(texte); }
  function enTexte(octets) { return new TextDecoder('utf-8').decode(octets); }

  /* --- ZIP (écriture : méthode 0, sans compression) ------------------------------------------------------- */
  function zipper(fichiers) {
    var morceaux = [], centrale = [], decalage = 0;
    var DATE_DOS = ((2026 - 1980) << 9) | (11 << 5) | 1, HEURE_DOS = 0;
    function u16(v) { return [v & 255, (v >>> 8) & 255]; }
    function u32(v) { return [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255]; }
    fichiers.forEach(function (f) {
      var nom = enOctets(f.nom), data = f.octets, crc = crc32(data);
      var entete = [].concat(u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(HEURE_DOS), u16(DATE_DOS),
        u32(crc), u32(data.length), u32(data.length), u16(nom.length), u16(0));
      morceaux.push(Uint8Array.from(entete), nom, data);
      centrale.push({ nom: nom, crc: crc, taille: data.length, decalage: decalage });
      decalage += entete.length + nom.length + data.length;
    });
    var debutCentrale = decalage, tailleCentrale = 0;
    centrale.forEach(function (c) {
      var e = [].concat(u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(HEURE_DOS), u16(DATE_DOS),
        u32(c.crc), u32(c.taille), u32(c.taille), u16(c.nom.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(c.decalage));
      morceaux.push(Uint8Array.from(e), c.nom);
      tailleCentrale += e.length + c.nom.length;
    });
    morceaux.push(Uint8Array.from([].concat(u32(0x06054b50), u16(0), u16(0), u16(centrale.length), u16(centrale.length),
      u32(tailleCentrale), u32(debutCentrale), u16(0))));
    var total = morceaux.reduce(function (t, m) { return t + m.length; }, 0);
    var sortie = new Uint8Array(total), p = 0;
    morceaux.forEach(function (m) { sortie.set(m, p); p += m.length; });
    return sortie;
  }

  /* --- INFLATE (RFC 1951), d'après l'algorithme de référence « puff » ------------------------------------- */
  var LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  var LEXT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  var DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
  var DEXT = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
  var ORDRE = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

  function huffman(longueurs, n) {
    var count = new Array(16).fill(0), symbol = new Array(n), offs = new Array(16), i;
    for (i = 0; i < n; i++) count[longueurs[i]]++;
    offs[1] = 0;
    for (i = 1; i < 15; i++) offs[i + 1] = offs[i] + count[i];
    for (i = 0; i < n; i++) if (longueurs[i] !== 0) symbol[offs[longueurs[i]]++] = i;
    return { count: count, symbol: symbol };
  }

  function inflate(src, tailleSortie) {
    var pos = 0, tampon = 0, nbits = 0;
    var out = new Uint8Array(tailleSortie || src.length * 4 + 1024), op = 0;
    function bits(besoin) {
      var v = tampon;
      while (nbits < besoin) {
        if (pos >= src.length) throw new Error('flux deflate tronqué');
        v |= src[pos++] << nbits; nbits += 8;
      }
      tampon = v >>> besoin; nbits -= besoin;
      return v & ((1 << besoin) - 1);
    }
    function decoder(h) {
      var code = 0, first = 0, index = 0;
      for (var len = 1; len <= 15; len++) {
        code |= bits(1);
        var count = h.count[len];
        if (code - count < first) return h.symbol[index + (code - first)];
        index += count; first += count; first <<= 1; code <<= 1;
      }
      throw new Error('code deflate invalide');
    }
    function reserver(plus) {
      if (op + plus <= out.length) return;
      var n = new Uint8Array(Math.max(out.length * 2, op + plus));
      n.set(out); out = n;
    }
    function codes(lc, dc) {
      for (;;) {
        var s = decoder(lc);
        if (s < 256) { reserver(1); out[op++] = s; } else if (s === 256) { return; } else {
          s -= 257;
          if (s >= 29) throw new Error('longueur deflate invalide');
          var len = LBASE[s] + bits(LEXT[s]);
          var d = decoder(dc);
          var dist = DBASE[d] + bits(DEXT[d]);
          if (dist > op) throw new Error('distance deflate invalide');
          reserver(len);
          for (var k = 0; k < len; k++) { out[op] = out[op - dist]; op++; }
        }
      }
    }
    var fixe = null;
    var dernier;
    do {
      dernier = bits(1);
      var type = bits(2);
      if (type === 0) {
        tampon = 0; nbits = 0;
        var len = src[pos] | (src[pos + 1] << 8);
        pos += 4;
        reserver(len);
        out.set(src.subarray(pos, pos + len), op); op += len; pos += len;
      } else if (type === 1) {
        if (!fixe) {
          var l = [], i;
          for (i = 0; i < 144; i++) l[i] = 8;
          for (; i < 256; i++) l[i] = 9;
          for (; i < 280; i++) l[i] = 7;
          for (; i < 288; i++) l[i] = 8;
          fixe = { lc: huffman(l, 288), dc: huffman(new Array(30).fill(5), 30) };
        }
        codes(fixe.lc, fixe.dc);
      } else if (type === 2) {
        var nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4, idx;
        var lg = new Array(320).fill(0);
        for (idx = 0; idx < ncode; idx++) lg[ORDRE[idx]] = bits(3);
        var hc = huffman(lg.slice(0, 19), 19);
        idx = 0;
        var lengths = new Array(nlen + ndist).fill(0);
        while (idx < nlen + ndist) {
          var sym = decoder(hc);
          if (sym < 16) { lengths[idx++] = sym; } else {
            var prev = 0, rep;
            if (sym === 16) { if (idx === 0) throw new Error('répétition deflate invalide'); prev = lengths[idx - 1]; rep = 3 + bits(2); }
            else if (sym === 17) rep = 3 + bits(3);
            else rep = 11 + bits(7);
            if (idx + rep > nlen + ndist) throw new Error('longueurs deflate trop nombreuses');
            while (rep--) lengths[idx++] = prev;
          }
        }
        codes(huffman(lengths.slice(0, nlen), nlen), huffman(lengths.slice(nlen), ndist));
      } else {
        throw new Error('bloc deflate de type invalide');
      }
    } while (!dernier);
    return out.subarray(0, op);
  }

  /* --- ZIP (lecture) ---------------------------------------------------------------------------------------- */
  function dezipper(octets) {
    var vue = new DataView(octets.buffer, octets.byteOffset, octets.byteLength);
    var fin = -1;
    for (var i = octets.length - 22; i >= Math.max(0, octets.length - 65557); i--) {
      if (vue.getUint32(i, true) === 0x06054b50) { fin = i; break; }
    }
    if (fin < 0) throw new Error('Ce fichier n’est pas une archive ZIP : un classeur .xlsx est attendu.');
    var n = vue.getUint16(fin + 10, true), p = vue.getUint32(fin + 16, true);
    var fichiers = {};
    for (var k = 0; k < n; k++) {
      if (vue.getUint32(p, true) !== 0x02014b50) throw new Error('Répertoire central ZIP corrompu.');
      var methode = vue.getUint16(p + 10, true), csize = vue.getUint32(p + 20, true), usize = vue.getUint32(p + 24, true);
      var ln = vue.getUint16(p + 28, true), le = vue.getUint16(p + 30, true), lc = vue.getUint16(p + 32, true), dec = vue.getUint32(p + 42, true);
      var nom = enTexte(octets.subarray(p + 46, p + 46 + ln));
      var lnLocal = vue.getUint16(dec + 26, true), leLocal = vue.getUint16(dec + 28, true);
      var debut = dec + 30 + lnLocal + leLocal;
      var brut = octets.subarray(debut, debut + csize);
      fichiers[nom] = { methode: methode, brut: brut, taille: usize };
      p += 46 + ln + le + lc;
    }
    function lire(nom) {
      var f = fichiers[nom];
      if (!f) return null;
      if (f.methode === 0) return f.brut;
      if (f.methode === 8) return inflate(f.brut, f.taille);
      throw new Error('Méthode de compression ZIP ' + f.methode + ' non prise en charge.');
    }
    return { noms: Object.keys(fichiers), lire: lire };
  }

  /* --- Écriture du classeur --------------------------------------------------------------------------------- */
  function xmlEchappe(s) {
    return String(s).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function nomColonne(i) {
    var s = '';
    i++;
    while (i > 0) { var r = (i - 1) % 26; s = String.fromCharCode(65 + r) + s; i = Math.floor((i - 1) / 26); }
    return s;
  }
  var ENTETE_XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  function ecrire(classeur) {
    var feuilles = classeur.feuilles;
    var chaines = [], indexChaine = {};
    function sst(s) {
      s = String(s);
      if (indexChaine[s] === undefined) { indexChaine[s] = chaines.length; chaines.push(s); }
      return indexChaine[s];
    }
    var xmlFeuilles = feuilles.map(function (f) {
      var lignes = f.lignes || [];
      var nbCol = lignes.reduce(function (m, l) { return Math.max(m, l.length); }, 0);
      var x = ENTETE_XML + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';
      x += '<dimension ref="A1:' + nomColonne(Math.max(nbCol - 1, 0)) + Math.max(lignes.length, 1) + '"/>';
      if (f.entete !== false) {
        x += '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>';
      }
      if (f.largeurs && f.largeurs.length) {
        x += '<cols>' + f.largeurs.map(function (w, i) { return '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + w + '" customWidth="1"' + (f.texteColonnes && f.texteColonnes.indexOf(i) >= 0 ? ' style="4"' : '') + '/>'; }).join('') + '</cols>';
      }
      x += '<sheetData>';
      lignes.forEach(function (l, r) {
        x += '<row r="' + (r + 1) + '">';
        l.forEach(function (v, c) {
          if (v === null || v === undefined || v === '') return;
          var ref = nomColonne(c) + (r + 1);
          var style = (r === 0 && f.entete !== false) ? ' s="1"' : (f.styles && f.styles[r] ? ' s="' + f.styles[r] + '"' : '');
          if (typeof v === 'number' && isFinite(v)) x += '<c r="' + ref + '"' + style + '><v>' + v + '</v></c>';
          else if (typeof v === 'boolean') x += '<c r="' + ref + '"' + style + ' t="b"><v>' + (v ? 1 : 0) + '</v></c>';
          else x += '<c r="' + ref + '"' + style + ' t="s"><v>' + sst(v) + '</v></c>';
        });
        x += '</row>';
      });
      x += '</sheetData>';
      if (f.listes && f.listes.length) {
        x += '<dataValidations count="' + f.listes.length + '">' + f.listes.map(function (l) {
          var col = nomColonne(l.colonne);
          return '<dataValidation type="list" allowBlank="1" showErrorMessage="1" errorStyle="warning" sqref="' + col + '2:' + col + '1001">'
            + '<formula1>' + xmlEchappe(l.formule) + '</formula1></dataValidation>';
        }).join('') + '</dataValidations>';
      }
      return x + '</worksheet>';
    });
    var xml = {};
    xml['[Content_Types].xml'] = ENTETE_XML + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      + '<Default Extension="xml" ContentType="application/xml"/>'
      + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      + feuilles.map(function (f, i) { return '<Override PartName="/xl/worksheets/sheet' + (i + 1) + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'; }).join('')
      + '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      + '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
      + '</Types>';
    xml['_rels/.rels'] = ENTETE_XML + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
    xml['xl/workbook.xml'] = ENTETE_XML + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
      + feuilles.map(function (f, i) { return '<sheet name="' + xmlEchappe(f.nom) + '" sheetId="' + (i + 1) + '" r:id="rId' + (i + 1) + '"/>'; }).join('')
      + '</sheets></workbook>';
    xml['xl/_rels/workbook.xml.rels'] = ENTETE_XML + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      + feuilles.map(function (f, i) { return '<Relationship Id="rId' + (i + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet' + (i + 1) + '.xml"/>'; }).join('')
      + '<Relationship Id="rId' + (feuilles.length + 1) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      + '<Relationship Id="rId' + (feuilles.length + 2) + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
      + '</Relationships>';
    /* Styles : 0 normal, 1 entête (gras sur fond bleu clair), 2 note en italique, 3 texte renvoyé à la ligne, 4 texte (format @, conserve les zéros de tête). */
    xml['xl/styles.xml'] = ENTETE_XML + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      + '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><i/><sz val="11"/><color rgb="FF475569"/><name val="Calibri"/></font></fonts>'
      + '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDBEAFE"/><bgColor indexed="64"/></patternFill></fill></fills>'
      + '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      + '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      + '<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      + '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
      + '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      + '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
      + '</styleSheet>';
    xml['xl/sharedStrings.xml'] = ENTETE_XML + '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="' + chaines.length + '" uniqueCount="' + chaines.length + '">'
      + chaines.map(function (s) { return '<si><t xml:space="preserve">' + xmlEchappe(s) + '</t></si>'; }).join('') + '</sst>';
    var fichiers = Object.keys(xml).map(function (nom) { return { nom: nom, octets: enOctets(xml[nom]) }; });
    xmlFeuilles.forEach(function (x, i) { fichiers.push({ nom: 'xl/worksheets/sheet' + (i + 1) + '.xml', octets: enOctets(x) }); });
    return zipper(fichiers);
  }

  /* --- Lecture du classeur ---------------------------------------------------------------------------------- */
  function parserXml(texte) {
    var d = new DOMParser().parseFromString(texte, 'application/xml');
    if (d.getElementsByTagName('parsererror').length) throw new Error('Contenu XML illisible dans le classeur.');
    return d;
  }
  function colonneDe(ref) {
    var m = /^([A-Z]+)/.exec(ref || ''), n = 0;
    if (!m) return 0;
    for (var i = 0; i < m[1].length; i++) n = n * 26 + (m[1].charCodeAt(i) - 64);
    return n - 1;
  }
  function textesDe(noeud) {
    var s = '';
    var ts = noeud.getElementsByTagName('t');
    for (var i = 0; i < ts.length; i++) {
      var p = ts[i].parentNode;
      if (p && p.nodeName === 'rPh') continue;
      s += ts[i].textContent;
    }
    return s;
  }

  function lire(octets) {
    var zip = dezipper(octets);
    var classeur = zip.lire('xl/workbook.xml');
    if (!classeur) throw new Error('Ce fichier n’est pas un classeur .xlsx (xl/workbook.xml absent).');
    var wb = parserXml(enTexte(classeur));
    var rels = zip.lire('xl/_rels/workbook.xml.rels');
    var cibles = {};
    if (rels) {
      var rr = parserXml(enTexte(rels)).getElementsByTagName('Relationship');
      for (var i = 0; i < rr.length; i++) cibles[rr[i].getAttribute('Id')] = rr[i].getAttribute('Target');
    }
    var partages = [];
    var sstOctets = zip.lire('xl/sharedStrings.xml');
    if (sstOctets) {
      var sis = parserXml(enTexte(sstOctets)).getElementsByTagName('si');
      for (var j = 0; j < sis.length; j++) partages.push(textesDe(sis[j]));
    }
    var sheets = wb.getElementsByTagName('sheet'), sortie = [];
    for (var k = 0; k < sheets.length; k++) {
      var nom = sheets[k].getAttribute('name');
      var rid = sheets[k].getAttribute('r:id') || sheets[k].getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id');
      var cible = cibles[rid] || ('worksheets/sheet' + (k + 1) + '.xml');
      cible = cible.charAt(0) === '/' ? cible.slice(1) : 'xl/' + cible;
      var brut = zip.lire(cible);
      if (!brut) throw new Error('Feuille « ' + nom + ' » introuvable dans le classeur.');
      var doc = parserXml(enTexte(brut));
      var rows = doc.getElementsByTagName('row'), lignes = [];
      for (var r = 0; r < rows.length; r++) {
        var idxLigne = Number(rows[r].getAttribute('r')) - 1;
        if (!(idxLigne >= 0)) idxLigne = lignes.length;
        var cells = rows[r].getElementsByTagName('c'), ligne = [];
        for (var c = 0; c < cells.length; c++) {
          var cell = cells[c], t = cell.getAttribute('t'), col = colonneDe(cell.getAttribute('r'));
          var vEl = cell.getElementsByTagName('v')[0], v = '';
          if (t === 'inlineStr') v = textesDe(cell);
          else if (vEl) {
            var brutV = vEl.textContent;
            if (t === 's') v = partages[Number(brutV)] !== undefined ? partages[Number(brutV)] : '';
            else if (t === 'b') v = brutV === '1';
            else if (t === 'str' || t === 'e') v = brutV;
            else { var nb = Number(brutV); v = isFinite(nb) && brutV !== '' ? nb : brutV; }
          }
          while (ligne.length < col) ligne.push('');
          ligne[col] = v;
        }
        while (lignes.length < idxLigne) lignes.push([]);
        lignes[idxLigne] = ligne;
      }
      while (lignes.length && lignes[lignes.length - 1].every(function (v) { return v === '' || v == null; })) lignes.pop();
      sortie.push({ nom: nom, lignes: lignes });
    }
    return { feuilles: sortie };
  }

  /* --- CSV ------------------------------------------------------------------------------------------------- */
  function lireCsv(texte) {
    if (texte.charCodeAt(0) === 0xFEFF) texte = texte.slice(1);
    var premiere = texte.split(/\r?\n/)[0] || '';
    var sep = ';', meilleur = -1;
    [';', ',', '\t'].forEach(function (s) {
      var n = premiere.split(s).length;
      if (n > meilleur) { meilleur = n; sep = s; }
    });
    var lignes = [], ligne = [], champ = '', guillemets = false;
    for (var i = 0; i < texte.length; i++) {
      var ch = texte.charAt(i);
      if (guillemets) {
        if (ch === '"') { if (texte.charAt(i + 1) === '"') { champ += '"'; i++; } else guillemets = false; } else champ += ch;
      } else if (ch === '"') guillemets = true;
      else if (ch === sep) { ligne.push(champ); champ = ''; }
      else if (ch === '\n' || ch === '\r') {
        if (ch === '\r' && texte.charAt(i + 1) === '\n') i++;
        ligne.push(champ); champ = '';
        lignes.push(ligne); ligne = [];
      } else champ += ch;
    }
    if (champ !== '' || ligne.length) { ligne.push(champ); lignes.push(ligne); }
    while (lignes.length && lignes[lignes.length - 1].every(function (v) { return String(v).trim() === ''; })) lignes.pop();
    return lignes;
  }

  /* --- Série Excel (système 1900) vers AAAA-MM-JJ -------------------------------------------------------------
     Le jour 60 d'Excel est le 29/02/1900, qui n'a jamais existé : la série 61 vaut le 01/03/1900. */
  function versDate(n) {
    var s = Math.floor(Number(n));
    if (!(s >= 1)) return null;
    var ms = Date.UTC(1899, 11, 30) + (s > 59 ? s : s + 1) * 86400000;
    var d = new Date(ms);
    return d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0') + '-' + String(d.getUTCDate()).padStart(2, '0');
  }

  global.SIGH = global.SIGH || {};
  global.SIGH.xlsx = { ecrire: ecrire, lire: lire, lireCsv: lireCsv, versDate: versDate, crc32: crc32, inflate: inflate };
})(window);
