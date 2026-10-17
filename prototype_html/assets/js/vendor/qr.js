/* =============================================================================
 * QR — encodeur de codes QR, écrit pour le prototype SIGH-CNT
 * -----------------------------------------------------------------------------
 * VENDORÉ LOCALEMENT, comme Chart.js et Lucide : le prototype ne fait AUCUNE
 * requête réseau, et l'on ne dépend d'aucune API de génération en ligne — une
 * clinique qui imprime ses badges un jour de coupure Internet doit pouvoir le
 * faire. La même contrainte que la cible desktop.
 *
 * Périmètre volontairement étroit, et c'est un choix :
 *   - mode OCTET (UTF-8), niveau de correction M (~15 %) ;
 *   - versions 1 à 6 seulement — jusqu'à 106 caractères latins.
 * Au-delà de la version 6, la norme impose des blocs d'information de version
 * supplémentaires : les charges utiles du logiciel (un matricule, un numéro de
 * série, un jeton) tiennent très largement en deçà, et refuser explicitement
 * vaut mieux qu'un code que rien ne saurait relire.
 *
 * API :
 *   QR.matrice(texte)  → { taille, modules: [[bool]] }  (lève si trop long)
 *   QR.capacite()      → nombre maximal d'octets
 *
 * Algorithme : ISO/IEC 18004. Corps de Galois GF(256) avec le polynôme
 * primitif 0x11D, correction de Reed-Solomon, huit masques évalués par les
 * quatre règles de pénalité de la norme.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --- Corps de Galois GF(256) -------------------------------------------- */
  var EXP = new Array(512), LOG = new Array(256);
  (function () {
    var x = 1;
    for (var i = 0; i < 255; i++) { EXP[i] = x; LOG[x] = i; x <<= 1; if (x & 0x100) x ^= 0x11d; }
    for (var j = 255; j < 512; j++) EXP[j] = EXP[j - 255];
  })();
  function mul(a, b) { return (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]]; }

  /** Polynôme générateur de degré n : ∏ (x + α^i), i de 0 à n-1. */
  function generateur(n) {
    var p = [1];
    for (var i = 0; i < n; i++) {
      var q = [];
      for (var k = 0; k <= p.length; k++) q.push(0);
      for (var j = 0; j < p.length; j++) {
        q[j] ^= p[j];
        q[j + 1] ^= mul(p[j], EXP[i]);
      }
      p = q;
    }
    return p;
  }

  /** Mots de correction d'un bloc de données. */
  function correction(donnees, n) {
    var g = generateur(n);
    var res = donnees.slice();
    for (var k = 0; k < n; k++) res.push(0);
    for (var i = 0; i < donnees.length; i++) {
      var coef = res[i];
      if (coef === 0) continue;
      for (var j = 1; j < g.length; j++) res[i + j] ^= mul(g[j], coef);
    }
    return res.slice(donnees.length);
  }

  /* --- Tables de la norme, niveau M, versions 1 à 6 ------------------------
   * [nombre de blocs, mots total par bloc, mots de données par bloc] — un
   * second triplet quand la version mêle deux tailles de bloc (aucune ici).
   * ---------------------------------------------------------------------- */
  var BLOCS = {
    1: [[1, 26, 16]],
    2: [[1, 44, 28]],
    3: [[1, 70, 44]],
    4: [[2, 50, 32]],
    5: [[2, 67, 43]],
    6: [[4, 43, 27]],
  };
  /* Centres des motifs d'alignement (aucun en version 1). */
  var ALIGNEMENTS = { 1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34] };
  var VERSION_MAX = 6;

  function motsDonnees(version) {
    return BLOCS[version].reduce(function (n, b) { return n + b[0] * b[2]; }, 0);
  }
  function capacite() { return motsDonnees(VERSION_MAX) - 2; }

  /* --- Encodage de la charge utile ---------------------------------------- */
  function octetsUtf8(texte) {
    var out = [];
    var s = unescape(encodeURIComponent(String(texte)));
    for (var i = 0; i < s.length; i++) out.push(s.charCodeAt(i) & 0xff);
    return out;
  }

  function versionPour(nbOctets) {
    for (var v = 1; v <= VERSION_MAX; v++) {
      /* 4 bits de mode + 8 bits de compteur (versions 1 à 9) + les données. */
      var bits = 4 + 8 + 8 * nbOctets;
      if (Math.ceil(bits / 8) <= motsDonnees(v)) return v;
    }
    return null;
  }

  function motsDepuisTexte(texte, version) {
    var donnees = octetsUtf8(texte);
    var bits = [];
    function pousser(valeur, largeur) {
      for (var i = largeur - 1; i >= 0; i--) bits.push((valeur >>> i) & 1);
    }
    pousser(4, 4);                    /* mode octet */
    pousser(donnees.length, 8);       /* compteur, 8 bits en versions 1 à 9 */
    donnees.forEach(function (o) { pousser(o, 8); });

    var capaciteBits = motsDonnees(version) * 8;
    var fin = Math.min(4, capaciteBits - bits.length);
    for (var t = 0; t < fin; t++) bits.push(0);
    while (bits.length % 8) bits.push(0);

    var mots = [];
    for (var i = 0; i < bits.length; i += 8) {
      var o = 0;
      for (var j = 0; j < 8; j++) o = (o << 1) | bits[i + j];
      mots.push(o);
    }
    /* Remplissage normalisé : 0xEC et 0x11 en alternance. */
    var bourrage = [0xec, 0x11], k = 0;
    while (mots.length < motsDonnees(version)) mots.push(bourrage[k++ % 2]);
    return mots;
  }

  /** Découpage en blocs, correction, puis entrelacement — l'ordre de la norme. */
  function motsFinaux(texte, version) {
    var mots = motsDepuisTexte(texte, version);
    var blocsD = [], blocsC = [], curseur = 0;
    BLOCS[version].forEach(function (spec) {
      for (var b = 0; b < spec[0]; b++) {
        var d = mots.slice(curseur, curseur + spec[2]);
        curseur += spec[2];
        blocsD.push(d);
        blocsC.push(correction(d, spec[1] - spec[2]));
      }
    });
    var out = [];
    var maxD = Math.max.apply(null, blocsD.map(function (b) { return b.length; }));
    for (var i = 0; i < maxD; i++) {
      blocsD.forEach(function (b) { if (i < b.length) out.push(b[i]); });
    }
    var maxC = Math.max.apply(null, blocsC.map(function (b) { return b.length; }));
    for (var j = 0; j < maxC; j++) {
      blocsC.forEach(function (b) { if (j < b.length) out.push(b[j]); });
    }
    return out;
  }

  /* --- Information de format (BCH 15,5) ------------------------------------ */
  var G15 = 0x537, G15_MASQUE = 0x5412;
  function chiffres(v) { var n = 0; while (v !== 0) { n++; v >>>= 1; } return n; }
  function formatBits(niveau, masque) {
    var d = ((niveau << 3) | masque);
    var reste = d << 10;
    while (chiffres(reste) - chiffres(G15) >= 0) reste ^= (G15 << (chiffres(reste) - chiffres(G15)));
    return (((d << 10) | reste) ^ G15_MASQUE);
  }
  var NIVEAU_M = 0; /* codage normalisé des niveaux : L=1, M=0, Q=3, H=2 */

  /* --- Masques ------------------------------------------------------------- */
  function masque(n, i, j) {
    switch (n) {
      case 0: return (i + j) % 2 === 0;
      case 1: return i % 2 === 0;
      case 2: return j % 3 === 0;
      case 3: return (i + j) % 3 === 0;
      case 4: return (Math.floor(i / 2) + Math.floor(j / 3)) % 2 === 0;
      case 5: return ((i * j) % 2) + ((i * j) % 3) === 0;
      case 6: return (((i * j) % 2) + ((i * j) % 3)) % 2 === 0;
      default: return (((i * j) % 3) + ((i + j) % 2)) % 2 === 0;
    }
  }

  /* --- Construction de la trame -------------------------------------------- */
  function construire(mots, version, numMasque) {
    var taille = version * 4 + 17;
    var m = [];
    for (var r = 0; r < taille; r++) {
      m.push([]);
      for (var c = 0; c < taille; c++) m[r].push(null);
    }

    function reperage(ligne, colonne) {
      for (var r = -1; r <= 7; r++) {
        for (var c = -1; c <= 7; c++) {
          var rr = ligne + r, cc = colonne + c;
          if (rr < 0 || rr >= taille || cc < 0 || cc >= taille) continue;
          m[rr][cc] = (r >= 0 && r <= 6 && (c === 0 || c === 6))
            || (c >= 0 && c <= 6 && (r === 0 || r === 6))
            || (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        }
      }
    }
    reperage(0, 0);
    reperage(taille - 7, 0);
    reperage(0, taille - 7);

    /* Motifs d'alignement — jamais par-dessus un motif déjà posé. */
    var pos = ALIGNEMENTS[version];
    for (var a = 0; a < pos.length; a++) {
      for (var b = 0; b < pos.length; b++) {
        var ra = pos[a], ca = pos[b];
        if (m[ra][ca] !== null) continue;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            m[ra + dr][ca + dc] = (dr === -2 || dr === 2 || dc === -2 || dc === 2 || (dr === 0 && dc === 0));
          }
        }
      }
    }

    /* Motifs de synchronisation. */
    for (var t = 8; t < taille - 8; t++) {
      if (m[t][6] === null) m[t][6] = (t % 2 === 0);
      if (m[6][t] === null) m[6][t] = (t % 2 === 0);
    }

    /* Information de format, aux deux emplacements, plus le module toujours
       sombre — sans lui, aucun lecteur ne cale la trame. */
    var bits = formatBits(NIVEAU_M, numMasque);
    for (var i = 0; i < 15; i++) {
      var b1 = ((bits >> i) & 1) === 1;
      if (i < 6) m[i][8] = b1;
      else if (i < 8) m[i + 1][8] = b1;
      else m[taille - 15 + i][8] = b1;

      if (i < 8) m[8][taille - i - 1] = b1;
      else if (i < 9) m[8][15 - i - 1 + 1] = b1;
      else m[8][15 - i - 1] = b1;
    }
    m[taille - 8][8] = true;

    /* Données : parcours en zigzag depuis le coin inférieur droit, colonne 6
       (synchronisation verticale) sautée. */
    var inc = -1, ligne = taille - 1, bitIndex = 7, octetIndex = 0;
    for (var col = taille - 1; col > 0; col -= 2) {
      if (col === 6) col--;
      for (;;) {
        for (var k = 0; k < 2; k++) {
          if (m[ligne][col - k] === null) {
            var sombre = false;
            if (octetIndex < mots.length) sombre = (((mots[octetIndex] >>> bitIndex) & 1) === 1);
            if (masque(numMasque, ligne, col - k)) sombre = !sombre;
            m[ligne][col - k] = sombre;
            bitIndex--;
            if (bitIndex === -1) { octetIndex++; bitIndex = 7; }
          }
        }
        ligne += inc;
        if (ligne < 0 || ligne >= taille) { ligne -= inc; inc = -inc; break; }
      }
    }
    return { taille: taille, modules: m };
  }

  /* --- Pénalité : les quatre règles de la norme ---------------------------- */
  function penalite(trame) {
    var n = trame.taille, m = trame.modules, total = 0, i, j;

    /* Règle 1 — suites de cinq modules de même teinte et plus. */
    function suites(lire) {
      var p = 0;
      for (i = 0; i < n; i++) {
        var compte = 1;
        for (j = 1; j < n; j++) {
          if (lire(i, j) === lire(i, j - 1)) compte++;
          else { if (compte >= 5) p += 3 + (compte - 5); compte = 1; }
        }
        if (compte >= 5) p += 3 + (compte - 5);
      }
      return p;
    }
    total += suites(function (a, b) { return m[a][b]; });
    total += suites(function (a, b) { return m[b][a]; });

    /* Règle 2 — blocs 2×2 uniformes. */
    for (i = 0; i < n - 1; i++) {
      for (j = 0; j < n - 1; j++) {
        var v = m[i][j];
        if (m[i][j + 1] === v && m[i + 1][j] === v && m[i + 1][j + 1] === v) total += 3;
      }
    }

    /* Règle 3 — motif 1:1:3:1:1 assimilable à un repère. */
    var motif = [true, false, true, true, true, false, true];
    function cherche(lire) {
      var p = 0;
      for (i = 0; i < n; i++) {
        for (j = 0; j + 7 <= n; j++) {
          var ok = true;
          for (var k = 0; k < 7; k++) if (lire(i, j + k) !== motif[k]) { ok = false; break; }
          if (!ok) continue;
          var avant = true, apres = true, q;
          for (q = 1; q <= 4; q++) if (j - q >= 0 && lire(i, j - q)) avant = false;
          for (q = 7; q <= 10; q++) if (j + q < n && lire(i, j + q)) apres = false;
          if (avant || apres) p += 40;
        }
      }
      return p;
    }
    total += cherche(function (a, b) { return m[a][b]; });
    total += cherche(function (a, b) { return m[b][a]; });

    /* Règle 4 — déséquilibre entre modules sombres et clairs. */
    var sombres = 0;
    for (i = 0; i < n; i++) for (j = 0; j < n; j++) if (m[i][j]) sombres++;
    var ecart = Math.abs(sombres * 100 / (n * n) - 50);
    total += Math.floor(ecart / 5) * 10;
    return total;
  }

  /* --- Point d'entrée ------------------------------------------------------ */
  function matrice(texte) {
    var octets = octetsUtf8(texte);
    var version = versionPour(octets.length);
    if (!version) {
      throw new Error('QR : charge utile de ' + octets.length + ' octets — le maximum est '
        + capacite() + '. Raccourcir le contenu plutôt que de produire un code illisible.');
    }
    var mots = motsFinaux(texte, version);
    var meilleur = null, meilleurScore = Infinity;
    for (var k = 0; k < 8; k++) {
      var t = construire(mots, version, k);
      var s = penalite(t);
      if (s < meilleurScore) { meilleurScore = s; meilleur = t; }
    }
    meilleur.version = version;
    return meilleur;
  }

  global.QR = { matrice: matrice, capacite: capacite, VERSION_MAX: VERSION_MAX };
})(typeof window !== 'undefined' ? window : globalThis);
