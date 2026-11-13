/* =============================================================================
 * VECTEURS DES FICHIERS NUMÉRISÉS (lot D5, portage du lot DOCS-1) : `modules/fichiers.js`, `D.DOCUMENTS`, `PR.peutVoirDocument` et le serveur `api/fichiers.php`
 * -----------------------------------------------------------------------------
 * La maquette réelle est PILOTÉE dans Chrome, son serveur PHP aussi (base et dossiers du banc), et ce qu'elle répond est écrit en vecteurs. Rien n'est tiré de la lecture du code :
 *   - le contrôle d'un fichier déclaré (format par le nom ou le type, taille, vide) et le geste de dépôt (`deposerSurFiche`) contre le serveur réel, refus nommés compris ;
 *   - le format lu sur les OCTETS, l'empreinte SHA-256 (celle de la maquette ET celle de Node, comparées), les noms normalisés, la zone et le droit de lire un type de document ;
 *   - ce que le SERVEUR répond à chaque profil (dépôt par famille et type, lecture), la règle par famille engendrée de `rbac.json` ;
 *   - le rattachement, le retrait (RG-14), l'annulation, le registre par empreinte, le doublon, la taille maximale réglée en base ;
 *   - l'extracteur de texte PDF du serveur (`api/_pdf_texte.php`) sur des PDF produits par Chrome et à la main : pages, mots, raison d'un « texte non indexé ».
 *   node build/vecteurs-fichiers.js   →   packages/domaine/test/vecteurs/fichiers.json
 *                                         packages/domaine/lib/src/fichiers/fichiers_donnees.dart
 *                                         apps/poste/test/fixtures/fichiers/*
 * Banc ISOLÉ : SIGH_PORT_PHP=<port libre> SIGH_BASE_TEST=<base à soi> SIGH_FICHIERS_DIR=<dossier à soi> CHROME_PATH=/opt/pw-browsers/chromium node build/vecteurs-fichiers.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');
const { ouvrirMaquette, ecrire, ROOT, REPO } = require('./extraire');
const BANC = require('./_banc');

const FIXT = path.join(REPO, 'apps/poste/test/fixtures/fichiers');
const shaNode = (b) => crypto.createHash('sha256').update(b).digest('hex');
const base = () => 'http://127.0.0.1:' + BANC.PORT_PHP;

/** Un PDF écrit à la main : police simple Windows-1252, flux non compressé (le cas que Chrome ne produit pas). */
function pdfSimple(texte) {
  const flux = 'BT /F1 12 Tf 72 700 Td (' + texte + ') Tj ET';
  return Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    + '3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n'
    + '4 0 obj\n<< /Length ' + Buffer.byteLength(flux, 'latin1') + ' >>\nstream\n' + flux + '\nendstream\nendobj\n'
    + '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n', 'latin1');
}
/** Le même PDF, flux compressé (Flate) : le chemin que la plupart des PDF empruntent. */
function pdfFlate(texte) {
  const flux = zlib.deflateSync(Buffer.from('BT /F1 12 Tf 72 700 Td (' + texte + ') Tj ET', 'latin1'));
  return Buffer.concat([Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    + '3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n4 0 obj\n<< /Length ' + flux.length + ' /Filter /FlateDecode >>\nstream\n', 'latin1'),
    flux, Buffer.from('\nendstream\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n', 'latin1')]);
}

(async () => {
  console.log('▶ Vecteurs des fichiers numérisés');
  const m = await ouvrirMaquette();
  const out = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-fichiers.js : ne pas éditer. Maquette réelle pilotée dans Chrome, serveur PHP du banc, horloge 30/10/2026 10 h.' };
  try {
    const page = m.page;
    const browser = page.context().browser();
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-vec-fichiers-'));
    /* Les fabriques de `_documents-fixtures.js` parlent à Puppeteer ; ce générateur pilote Playwright (un seul argument à `evaluate`, `pdf` identique). */
    const pageFx = await browser.newPage();
    const Fx = {
      async image(format, variante) {
        const mime = { png: 'image/png', jpeg: 'image/jpeg', webp: 'image/webp' }[format];
        const b64i = await pageFx.evaluate(async (a) => {
          const c = document.createElement('canvas'); c.width = 600; c.height = 400;
          const x = c.getContext('2d');
          x.fillStyle = '#fff'; x.fillRect(0, 0, 600, 400);
          for (let i = 0; i < 400; i++) { x.fillStyle = 'hsl(' + ((i * 37 + a.v * 53) % 360) + ',60%,50%)'; x.fillRect((i * 97 + a.v * 31) % 560, (i * 61 + a.v * 17) % 360, 40, 30); }
          x.fillStyle = '#000'; x.font = '28px sans-serif'; x.fillText('Scan de test ' + a.v, 30, 200);
          return c.toDataURL(a.mime, 0.92).split(',')[1];
        }, { mime, v: variante || 1 });
        return Buffer.from(b64i, 'base64');
      },
      async pdf(html) {
        await pageFx.setContent('<!doctype html><html><head><meta charset="utf-8"></head><body style="font-family:sans-serif;font-size:14px">' + html + '</body></html>');
        return Buffer.from(await pageFx.pdf({ format: 'A4', printBackground: true }));
      },
      pdfTexte(variante, phrase) { return this.pdf('<h1>Compte rendu numérisé ' + (variante || 1) + '</h1><p>' + (phrase || 'Le patient présente une hyperglycémie majeure, amoxicilline prescrite, aucune allergie connue.') + '</p>'); },
      pdfPages(variante, n) { return this.pdf(Array.from({ length: n }, (_, k) => '<div style="page-break-after:always"><h1>Page ' + (k + 1) + '</h1><p>Mot propre à la page : page' + (k + 1) + 'mot' + variante + '</p></div>').join('')); },
      async pdfScan(variante) {
        const png = (await this.image('png', 100 + (variante || 1))).toString('base64');
        return this.pdf('<img src="data:image/png;base64,' + png + '" style="width:600px">');
      },
    };
    fs.mkdirSync(FIXT, { recursive: true });

    /* --- 1. LES FICHIERS DE TEST : fabriqués par Chrome (vraies couches texte, vrais scans) et à la main ------------------------------------------------ */
    const fich = {};
    const poser = (nom, tampon) => { const t = Buffer.isBuffer(tampon) ? tampon : fs.readFileSync(tampon); fs.writeFileSync(path.join(FIXT, nom), t); fich[nom] = t; };
    poser('scan.png', await Fx.image('png', 1));
    poser('scan.jpg', await Fx.image('jpeg', 2));
    poser('scan.webp', await Fx.image('webp', 3));
    poser('courrier-texte.pdf', await Fx.pdfTexte(1, 'Convocation à la réunion de la Direction Médicale : hyperglycémie, amoxicilline, étiquetage des échantillons.'));
    poser('trois-pages.pdf', await Fx.pdfPages(1, 3));
    poser('scan-image.pdf', await Fx.pdfScan(1));
    poser('simple-winansi.pdf', pdfSimple('Ordonnance d\\351livr\\351e : parac\\351tamol 500 mg, cr\\350me apais\\351e'));
    poser('simple-flate.pdf', pdfFlate('Certificat \\351tabli le jour m\\352me : gu\\351rison confirm\\351e'));
    poser('chiffre.pdf', Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\ntrailer\n<< /Root 1 0 R /Encrypt 9 0 R >>\n%%EOF\n', 'latin1'));
    poser('sans-objets.pdf', Buffer.from('%PDF-1.4\nrien de lisible ici\n%%EOF\n', 'latin1'));
    poser('contenu-illisible.pdf', Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n4 0 obj\n<< /Length 5 /Filter /LZWDecode >>\nstream\nabcde\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n', 'latin1'));
    poser('faux.exe', Buffer.from('MZ' + 'x'.repeat(2000), 'latin1'));
    poser('image.gif', Buffer.from('GIF89a' + 'x'.repeat(200), 'latin1'));
    /* Les fichiers DÉRIVÉS (même octets sous un autre nom, ou remplissage) ne sont pas versionnés : le test de la cible les refabrique (`derives` du vecteur). */
    out.derives = {};
    const deriver = (nom, source, remplissage, octets) => {
      const t = octets || Buffer.concat([fich[source], Buffer.alloc(remplissage || 0, 32)]);
      fich[nom] = t; out.derives[nom] = { source: octets ? null : source, remplissage: remplissage || 0, octets: octets ? octets.length : null, octet: octets && octets.length ? octets[0] : null };
    };
    deriver('faux-camoufle.pdf', null, 0, Buffer.alloc(3000, 7));
    deriver('vide.pdf', null, 0, Buffer.alloc(0));
    deriver('png-nomme-pdf.pdf', 'scan.png', 0);
    deriver('jpeg-nomme-png.png', 'scan.jpg', 0);
    deriver('pdf-nomme-jpg.jpg', 'courrier-texte.pdf', 0);
    /* Un fichier un peu lourd (150 Ko) : le PDF à texte suivi d'octets de remplissage APRÈS le marqueur de fin (il reste valide). */
    deriver('gros.pdf', 'courrier-texte.pdf', 150 * 1024);
    const b64 = (n) => fich[n].toString('base64');

    /* --- 2. LE SERVEUR : jetons par rôle, appels directs ---------------------------------------------------------------------------------------------- */
    const jeton = async (role) => {
      const r = await fetch(base() + '/api/session.php', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ role: role, nom: 'SONDE ' + role, identifiant: 'vec.' + role, fonction: role }) });
      return (await r.json()).jeton;
    };
    const api = async (methode, q, jt, corps) => {
      const r = await fetch(base() + '/api/fichiers.php?' + q, { method: methode, headers: Object.assign({ 'X-Sigh-Jeton': jt || '' }, corps ? { 'Content-Type': 'application/octet-stream' } : {}), body: corps });
      const t = Buffer.from(await r.arrayBuffer());
      let j = null; try { j = JSON.parse(t.toString()); } catch (e) { /* octets */ }
      return { statut: r.status, json: j, octets: t };
    };
    const enc = encodeURIComponent;

    /* --- 3. LA PAGE : horloge fixe, module des fichiers ---------------------------------------------------------------------------------------------------- */
    await page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      SIGH.ui.sonner = () => {};
      SIGH.ui.toast = () => {};
      window.__confirmations = [];
    });
    await page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/fichiers.js') });
    await page.evaluate(() => {
      window.H = {
        propre: (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)),
        u8: (b64) => { const bin = atob(b64), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; },
        avecRole: (role, f) => {
          const S = SIGH.store, sess0 = S.session(); S.setSession(Object.assign({}, sess0, { role: role }));
          try { return f(); } finally { S.setSession(sess0); }
        },
      };
    });
    /* La taille maximale : posée dans le magasin du navigateur, lue par `controler` et par `deposerSurFiche`. Le serveur lit la sienne en base. */
    const poserTaille = (v) => page.evaluate((x) => { SIGH.store.setReglage('documentsBornes', x); return true; }, v);

    /* --- 4. FORMATS ET DONNÉES de `D.DOCUMENTS` ---------------------------------------------------------------------------------------------------------- */
    const DOC = await page.evaluate(() => H.propre({ FORMATS: SIGH.data.DOCUMENTS.FORMATS, TAILLE_DEFAUT: SIGH.data.DOCUMENTS.TAILLE_DEFAUT, TAILLE_PLANCHER: SIGH.data.DOCUMENTS.TAILLE_PLANCHER,
      TAILLE_PLAFOND: SIGH.data.DOCUMENTS.TAILLE_PLAFOND, TYPES_PATIENT: SIGH.data.DOCUMENTS.TYPES_PATIENT, ROLES_ZONE_2: SIGH.data.DOCUMENTS.ROLES_ZONE_2, FAMILLES: SIGH.data.DOCUMENTS.FAMILLES }));
    out.donnees = DOC;
    const q = (v) => (typeof v === 'string' ? "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'" : String(v));
    let d = '// ENGENDRÉ par prototype_html/build/vecteurs-fichiers.js : NE PAS ÉDITER. `D.DOCUMENTS` de la maquette (assets/js/data.js) : formats admis, tailles, types de document du patient\n'
      + '// et leur ZONE, profils de la zone 2. La taille maximale est un RÉGLAGE en base (`documentsBornes`) : `fichierTailleDefaut` ne sert que tant que rien n\'est réglé (10 Mo, « à valider »).\n\n'
      + '/// Un format de fichier admis : identifiant, libellé, type MIME, extensions, familles qui l\'admettent (`courrier`, `patient`).\n'
      + 'class FormatFichier {\n  const FormatFichier(this.id, this.libelle, this.mime, this.ext, this.familles);\n  final String id;\n  final String libelle;\n  final String mime;\n  final List<String> ext;\n  final List<String> familles;\n}\n\n'
      + '/// Un type de document du dossier patient et sa zone (1 administratif, 2 médical : RG-13). La zone des dix types est une PROPOSITION À VALIDER.\n'
      + 'class TypeDocumentPatient {\n  const TypeDocumentPatient(this.libelle, this.zone);\n  final String libelle;\n  final int zone;\n}\n\n';
    d += 'const List<FormatFichier> fichierFormats = [\n' + DOC.FORMATS.map((f) => `  FormatFichier(${q(f.id)}, ${q(f.libelle)}, ${q(f.mime)}, [${f.ext.map(q).join(', ')}], [${f.familles.map(q).join(', ')}]),`).join('\n') + '\n];\n\n';
    d += `const int fichierTailleDefaut = ${DOC.TAILLE_DEFAUT};\nconst int fichierTaillePlancher = ${DOC.TAILLE_PLANCHER};\nconst int fichierTaillePlafond = ${DOC.TAILLE_PLAFOND};\n\n`;
    d += 'const List<TypeDocumentPatient> docTypesPatient = [\n' + DOC.TYPES_PATIENT.map((t) => `  TypeDocumentPatient(${q(t.libelle)}, ${t.zone}),`).join('\n') + '\n];\n\n';
    d += '/// Les profils qui lisent les pièces de la zone 2 (`D.DOCUMENTS.ROLES_ZONE_2`).\nconst List<String> docRolesZone2 = [' + DOC.ROLES_ZONE_2.map(q).join(', ') + '];\n';
    const dirDart = path.join(REPO, 'packages/domaine/lib/src/fichiers');
    fs.mkdirSync(dirDart, { recursive: true });
    fs.writeFileSync(path.join(dirDart, 'fichiers_donnees.dart'), d);
    console.log('  écrit : packages/domaine/lib/src/fichiers/fichiers_donnees.dart');

    /* --- 5. OCTETS : format lu sur les premiers octets, empreinte SHA-256 (maquette ET Node) ------------------------------------------------------------- */
    out.octets = [];
    for (const nom of Object.keys(fich)) {
      const r = await page.evaluate((b) => { const u = H.u8(b); return { format: SIGH.fichiers.formatDesOctets(u), sha: SIGH.fichiers.sha256Octets(u) }; }, b64(nom));
      const sn = shaNode(fich[nom]);
      if (r.sha !== sn) throw new Error('SHA-256 de la maquette différent de celui de Node pour ' + nom);
      out.octets.push({ fichier: nom, taille: fich[nom].length, sha256: sn, format: r.format });
    }
    /* Des entrées synthétiques pour le SHA-256 (les frontières de bloc), calculées par Node seul. */
    out.sha256 = [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000, 65536, 262145].map((n) => {
      const b = Buffer.alloc(n); for (let i = 0; i < n; i++) b[i] = (i * 31 + 7) & 255;
      return { taille: n, sha256: shaNode(b) };
    });
    out.sha256.push({ texte: 'abc', sha256: shaNode(Buffer.from('abc')) });

    /* --- 6. CONTRÔLE D'UN FICHIER DÉCLARÉ (`controler`) ---------------------------------------------------------------------------------------------------- */
    const decl = [
      ['courrier.pdf', 'application/pdf', 1234, 'courrier'], ['COURRIER.PDF', '', 1234, 'courrier'], ['scan.JPG', 'image/jpeg', 2048, 'courrier'], ['scan.jpeg', '', 2048, 'patient'],
      ['scan', 'image/png', 4096, 'courrier'], ['scan', 'application/pdf', 4096, 'patient'], ['scan', 'text/plain', 4096, 'courrier'], ['photo.webp', 'image/webp', 5000, 'courrier'], ['photo.webp', 'image/webp', 5000, 'patient'],
      ['photo', 'image/webp', 5000, 'patient'], ['document.exe', 'application/octet-stream', 3000, 'courrier'], ['archive.tar.gz', '', 3000, 'patient'], ['note.txt', 'text/plain', 3000, 'courrier'],
      ['vide.pdf', 'application/pdf', 0, 'courrier'], ['limite.pdf', 'application/pdf', 10 * 1024 * 1024, 'courrier'], ['trop.pdf', 'application/pdf', 10 * 1024 * 1024 + 1, 'courrier'],
      ['un-octet.png', 'image/png', 1, 'patient'], ['sans-ext.', '', 10, 'courrier'], ['Résultat n° 3 (copie).PNG', 'image/png', 99999, 'patient'],
    ];
    const reglages = [null, { tailleMax: 100 * 1024 }, { tailleMax: 1536 * 1024 }];
    out.controles = [];
    for (const rg of reglages) {
      await poserTaille(rg);
      for (const [nom, mime, taille, famille] of decl) {
        const r = await page.evaluate((a) => { const x = SIGH.fichiers.controler({ name: a[0], type: a[1], size: a[2] }, a[3]); return H.propre({ ok: !!x.ok, format: x.format ? x.format.id : null, code: x.code || null, motif: x.motif || null, geste: x.geste || null }); }, [nom, mime, taille, famille]);
        out.controles.push({ nom, mime, taille, famille, reglage: rg, tailleMax: rg ? rg.tailleMax : null, ...r });
      }
    }
    await poserTaille(null);

    /* --- 7. TAILLE MAXIMALE : lecture et réglage (`tailleMax`, `definirTailleMax`) ------------------------------------------------------------------------ */
    out.tailleMax = [];
    for (const rg of [null, {}, { tailleMax: 5 * 1024 * 1024 }, { tailleMax: 999999999999 }, { tailleMax: -5 }, { tailleMax: 0 }, { tailleMax: 'abc' }, { tailleMax: '2097152' }, { tailleMax: 1500.7 }]) {
      await poserTaille(rg);
      const r = await page.evaluate(() => ({ tailleMax: SIGH.fichiers.tailleMax(), reglee: SIGH.fichiers.tailleMaxReglee() }));
      out.tailleMax.push({ reglage: rg, ...r });
    }
    out.reglage = [];
    const cas = [['admin', 5 * 1024 * 1024, 'Scans plus lourds'], ['da', 8 * 1024 * 1024, 'Réunion de la Direction'], ['caissier', 5 * 1024 * 1024, 'Je veux'], ['direction', 5 * 1024 * 1024, 'x'], ['medecin', 1048576, 'x'],
      ['admin', 100 * 1024 - 1, 'trop petit'], ['admin', 100 * 1024, 'plancher'], ['admin', 64 * 1024 * 1024, 'plafond'], ['admin', 64 * 1024 * 1024 + 1, 'au-delà'], ['admin', 1500.5, 'décimal'],
      ['admin', '', 'vide'], ['admin', null, 'nul'], ['admin', 'abc', 'texte'], ['admin', 5 * 1024 * 1024, ''], ['admin', 5 * 1024 * 1024, '   '], ['da', 3 * 1024 * 1024, 'x'.repeat(100)]];
    for (const [role, octets, motif] of cas) {
      await poserTaille({ tailleMax: 7 * 1024 * 1024 });
      const r = await page.evaluate((a) => {
        const S = SIGH.store, n0 = S.raw().audit.length;
        const x = H.avecRole(a[0], () => SIGH.fichiers.definirTailleMax(a[1], a[2]));
        const journal = S.raw().audit.slice(0, S.raw().audit.length - n0).filter((e) => /Taille maximale/.test(e.action || '')).map((e) => ({ action: e.action, avant: e.avant, apres: e.apres }));
        return H.propre({ ok: !!x.ok, code: x.code || null, motif: x.motif || null, geste: x.geste || null, avant: x.avant == null ? null : x.avant, tailleMax: x.tailleMax == null ? null : x.tailleMax, apresReglage: SIGH.fichiers.tailleMax(), journal });
      }, [role, octets, motif]);
      out.reglage.push({ role, octets, motifSaisi: motif, ...r });
    }
    await poserTaille(null);

    /* --- 8. ZONES ET DROIT DE LIRE UN TYPE (`PR.peutVoirDocument`) ----------------------------------------------------------------------------------------- */
    const roles = await page.evaluate(() => Object.keys(SIGH.nav.ROLES));
    out.roles = roles;
    out.zones = await page.evaluate((rl) => {
      const types = SIGH.data.DOCUMENTS.TYPES_PATIENT.map((t) => t.libelle).concat(['Type inconnu', '', null]);
      return H.propre(types.map((t) => ({ type: t, zone: SIGH.data.DOCUMENTS.zoneDe(t), roles: rl.reduce((a, r) => { a[r] = SIGH.parcours.peutVoirDocument(t, { role: r }); return a; }, {}) })));
    }, roles);

    /* --- 9. NOMS NORMALISÉS (`DOC.nomNormalise`, `DOC.slug`, `DOC.abrege`) ---------------------------------------------------------------------------------- */
    const fiches = [
      ['courrier', { date: '2026-08-20', reference: 'ARR-2026-0042', sens: 'arrivee' }, 'pdf'], ['courrier', { date: '2026-08-20', reference: 'DEP-2026-0003', sens: 'depart' }, 'png'],
      ['courrier', { date: '2026-08-20', sens: 'depart' }, 'jpg'], ['courrier', { date: '2026-08-20', sens: 'arrivee' }, 'pdf'], ['courrier', { sens: 'arrivee', reference: 'ARR-2026-0001' }, 'pdf'],
      ['courrier', { date: '2026-08-20T09:30:00', reference: 'ARR-2026-0009' }, '.PDF'], ['courrier', { date: '2026-12-31', reference: 'ARR-2027-12345', sens: 'arrivee' }, 'webp'], ['courrier', { date: '2026-08-20', reference: 'ARR-2026-ABCD' }, 'pdf'],
      ['courrier', { date: '2026-08-20', reference: 'COUR-0042' }, ''], ['courrier', null, 'pdf'],
      ['patient', { date: '2026-08-12', reference: 'GED-00007', code: 'CNT/12/26', type: 'Compte rendu médical' }, 'pdf'], ['patient', { date: '2026-08-12', reference: 'GED-00123', code: 'CNT530/25', type: 'Pièce d’identité' }, 'jpg'],
      ['patient', { date: '2026-08-12', reference: 'GED-1234', code: 'CNT/1/26', type: 'Imagerie / Échographie' }, 'png'], ['patient', { date: '2026-08-12', reference: 'GED-00007', type: 'Facture' }, 'pdf'],
      ['patient', { date: '2026-08-12', reference: 'GED-00007', code: 'CNT/12/26' }, 'pdf'], ['patient', { date: '2026-08-12', reference: 'SANS-NUMERO', code: '  CNT/12/26  ', type: 'Bulletin d’hospitalisation' }, 'pdf'],
      ['patient', { reference: 'GED-00002', code: 'CNT/2/26', type: 'Œuvre d’été (ÀÉÎÕÜ)' }, 'webp'], ['patient', null, 'pdf'],
    ];
    out.noms = await page.evaluate((fl) => fl.map((f) => ({ famille: f[0], fiche: f[1], ext: f[2], nom: SIGH.data.DOCUMENTS.nomNormalise(f[0], f[1], f[2]) })), fiches);
    out.diacritiques = await page.evaluate(() => ['Hyperglycémie', 'ÀÉÎÕÜ àéîõü', 'Œuvre æther ß ø ł', 'Ç ç Ñ ñ', 'Ǻ ǻ ȧ Ẃ ẃ', 'plain ASCII 123', 'Straße Łódź Ørsted', 'Ṩ ṩ ẞ ỳ Ỹ', '', 'Ĳ ĳ Ŀ ŀ'].map((t) => ({ texte: t, sans: SIGH.core.norm(t) })));
    out.slugs = await page.evaluate(() => ['Compte rendu médical', 'Imagerie / Échographie', '  Œuvre d’été (ÀÉÎÕÜ) ', '', null, undefined, '---', 'A  B', 'déjà-vu'].map((t) => ({ texte: t === undefined ? null : t, slug: SIGH.data.DOCUMENTS.slug(t) })));
    out.abrege = await page.evaluate(() => [null, '', 'abc', '0123456789abcdef'].map((t) => ({ sha: t, abrege: SIGH.data.DOCUMENTS.abrege(t) })));

    /* --- 10. LE GESTE DE DÉPÔT contre le serveur réel (`deposerSurFiche`) --------------------------------------------------------------------------------- */
    const ficheC = await page.evaluate(() => { const S = SIGH.store; const c = S.collection('courriers').insert({ reference: 'ARR-2026-0900', sens: 'arrivee', date: '2026-08-20', correspondant: 'Vecteurs', objet: 'Dépôt', nature: 'Lettre', affecteA: 'Direction Administrative', traitement: 'en_attente' }).record; return c.id; });
    const fichePat = await page.evaluate(() => { const S = SIGH.store; const p = S.collection('patients').active()[0];
      return { id: S.collection('documentsPatient').insert({ reference: 'GED-90001', patientId: p.id, code: p.code, patient: p.nom, type: 'Compte rendu médical', date: '2026-08-12', etat: 'valide', depose: 'Vecteurs' }).record.id, patientId: p.id }; });
    const deposer = (nom, famille, type, extra) => page.evaluate(async (a) => {
      const S = SIGH.store, col = S.collection(a.famille === 'courrier' ? 'courriers' : 'documentsPatient');
      const fiche = col.get(a.ficheId);
      const u = H.u8(a.b64);
      const fichier = { name: a.nom, type: a.mime || '', size: u.length, arrayBuffer: () => Promise.resolve(u.buffer) };
      const ctx = { famille: a.famille, col, fiche, type: a.type, portee: a.portee ? ((f) => f.patientId === a.portee) : null, journal: { module: a.famille === 'courrier' ? 'M13' : 'M1', entite: a.famille === 'courrier' ? 'courrier' : 'document' } };
      const r = await SIGH.fichiers.deposerSurFiche(fichier, ctx);
      return H.propre(r.ok ? { ok: true, depot: Object.assign({}, r.depot, { mots: (r.depot.mots || []).map(String).sort() }), nomOrigine: r.nomOrigine, avertissement: !!r.avertissementDoublon }
        : { ok: false, code: r.code, motif: r.motif, geste: r.geste });
    }, Object.assign({ nom: path.basename(nom), mime: '', famille, type: type || null, b64: b64(nom), ficheId: famille === 'courrier' ? ficheC : fichePat.id, portee: null }, extra || {}));
    out.depots = [];
    const nouveauDepot = async (cle, nom, famille, type, extra, note) => { const r = await deposer(nom, famille, type, extra); out.depots.push({ cas: cle, note: note || null, fichier: nom, nom: (extra && extra.nom) || path.basename(nom), mime: (extra && extra.mime) || '', famille, type: type || null, ...r }); return r; };
    await nouveauDepot('courrier-pdf', 'courrier-texte.pdf', 'courrier', null, { mime: 'application/pdf' });
    await nouveauDepot('courrier-png', 'scan.png', 'courrier', null, { mime: 'image/png' });
    await nouveauDepot('courrier-jpeg', 'scan.jpg', 'courrier', null, {});
    await nouveauDepot('courrier-trois-pages', 'trois-pages.pdf', 'courrier', null, {});
    await nouveauDepot('courrier-scan-image', 'scan-image.pdf', 'courrier', null, {});
    await nouveauDepot('courrier-winansi', 'simple-winansi.pdf', 'courrier', null, {});
    await nouveauDepot('courrier-flate', 'simple-flate.pdf', 'courrier', null, {});
    await nouveauDepot('courrier-webp-refuse', 'scan.webp', 'courrier', null, {});
    await nouveauDepot('patient-webp-admis', 'scan.webp', 'patient', 'Compte rendu médical', {});
    await nouveauDepot('patient-pdf', 'courrier-texte.pdf', 'patient', 'Ordonnance', {});
    await nouveauDepot('exe-refuse', 'faux.exe', 'courrier', null, {});
    await nouveauDepot('gif-refuse', 'image.gif', 'patient', 'Facture', {});
    await nouveauDepot('camoufle-pdf', 'faux-camoufle.pdf', 'courrier', null, {});
    await nouveauDepot('png-sous-nom-pdf', 'png-nomme-pdf.pdf', 'courrier', null, {});
    await nouveauDepot('jpeg-sous-nom-png', 'jpeg-nomme-png.png', 'patient', 'Facture', {});
    await nouveauDepot('pdf-sous-nom-jpg', 'pdf-nomme-jpg.jpg', 'courrier', null, {});
    await nouveauDepot('vide', 'vide.pdf', 'courrier', null, {});
    await poserTaille({ tailleMax: 100 * 1024 });
    await nouveauDepot('taille-reglee', 'gros.pdf', 'courrier', null, {}, 'taille maximale réglée à 100 Ko');
    await poserTaille(null);
    await nouveauDepot('taille-defaut', 'gros.pdf', 'courrier', null, {}, 'défaut de 10 Mo : 150 Ko passent');
    /* Le doublon : la fiche porte déjà ce fichier ; une AUTRE fiche du même dossier le porte ; une fiche d'un AUTRE dossier le porte (avertissement, hors geste : testé par `doublon`). */
    await page.evaluate((a) => {
      const S = SIGH.store, F = SIGH.fichiers;
      const c = S.collection('courriers').get(a.ficheC);
      S.collection('courriers').update(c.id, { fichier: { sha256: a.sha, nom: 'deja.pdf', nomNormalise: '2026-08-20_ARR_0900.pdf', mime: 'application/pdf', taille: 10 } });
      const d2 = S.collection('documentsPatient').insert({ reference: 'GED-90002', patientId: a.patientId, code: 'CNT/9/26', patient: 'X', type: 'Facture', date: '2026-08-13',
        fichier: { sha256: a.sha2, nom: 'facture.png', nomNormalise: '2026-08-13_CNT-9-26_facture_002.png', mime: 'image/png', taille: 10 } }).record;
      return d2.id;
    }, { ficheC, sha: shaNode(fich['scan.png']), sha2: shaNode(fich['scan.jpg']), patientId: fichePat.patientId });
    await nouveauDepot('doublon-meme-fiche', 'scan.png', 'courrier', null, {}, 'la fiche porte déjà ce fichier');
    await nouveauDepot('doublon-meme-dossier', 'scan.jpg', 'patient', 'Facture', { portee: fichePat.patientId }, 'une autre fiche du même dossier porte ce fichier');

    /* La fonction `doublon` seule : mêmes fiches, plusieurs empreintes. */
    out.doublons = await page.evaluate((a) => {
      const S = SIGH.store, F = SIGH.fichiers;
      const col = S.collection('courriers');
      const mk = (ref, sha, statut) => col.insert({ reference: ref, sens: 'arrivee', date: '2026-08-21', statut: statut || 'actif', fichier: sha ? { sha256: sha, nom: ref + '.pdf', nomNormalise: ref + '.pdf' } : null }).record;
      const x = mk('ARR-2026-0951', 'a'.repeat(64)), y = mk('ARR-2026-0952', 'b'.repeat(64)), z = mk('ARR-2026-0953', 'a'.repeat(64)), w = mk('ARR-2026-0954', 'c'.repeat(64));
      col.archive(w.id);
      const res = (sha, courante, portee) => { const r = F.doublon(col, sha, courante, portee); return { sha: sha.slice(0, 2), courante: courante ? courante.reference : null, portee: !!portee, memeFiche: r && r.memeFiche ? r.memeFiche.reference : null, autre: r && r.autre ? r.autre.reference : null, aucun: !r }; };
      const rs = [res('a'.repeat(64), x, null), res('a'.repeat(64), y, null), res('a'.repeat(64), null, (f) => f.reference === 'ARR-2026-0953'), res('b'.repeat(64), null, null), res('c'.repeat(64), null, null), res('d'.repeat(64), x, null),
        res('a'.repeat(64), z, null)];
      return H.propre({ ordre: col.all().map((f) => f.reference), fiches: [x, y, z, w].map((f) => ({ id: f.id, reference: f.reference, statut: f.statut === 'archive' ? 'archive' : 'actif', sha256: f.fichier ? f.fichier.sha256 : null, fichier: f.fichier })), cas: rs,
        nomPiece: F.numerise(x) });
    }, {});
    /* `col.archive` ci-dessus : statut relu */
    out.doublons.fiches = out.doublons.fiches.map((f) => f);

    /* --- 11. RATTACHEMENT, RETRAIT, ANNULATION, REGISTRE PAR EMPREINTE ------------------------------------------------------------------------------------- */
    out.rattachement = await page.evaluate(async (a) => {
      const S = SIGH.store, F = SIGH.fichiers, col = S.collection('courriers');
      S.currentUser = () => 'AGENT VECTEUR';
      const fiche = col.insert({ reference: 'ARR-2026-0960', sens: 'arrivee', date: '2026-08-20', correspondant: 'Rattachement', objet: 'Pièce', nature: 'Lettre', affecteA: 'Direction Administrative', traitement: 'en_attente' }).record;
      const depot = { sha256: a.sha, taille: a.taille, mime: 'application/pdf', ext: 'pdf', pages: 2, texteIndexe: true, mots: ['hyperglycémie', 'Amoxicilline', 'x', 'amoxicilline', 'Éther', 'a1'], motsTronques: false };
      const journal = { module: 'M13', entite: 'courrier' };
      const n0 = S.raw().audit.length;
      const rat = F.rattacher(col, fiche, 'courrier', depot, 'Courrier.pdf', journal);
      const apres = H.propre(col.get(fiche.id));
      const reg = H.propre(F.colFichiers().get('FIC-' + a.sha.slice(0, 16)));
      const metier = (n, action) => H.propre(S.raw().audit.slice(0, S.raw().audit.length - n).filter((e) => e.action === action).map((e) => ({ action: e.action, module: e.module, entite: e.entite, reference: e.reference, ancienneValeur: e.ancienneValeur, nouvelleValeur: e.nouvelleValeur }))[0] || null);
      const auditRat = metier(n0, 'Dépôt d’un fichier numérisé');
      const nom0 = F.fichierPour('courrier', fiche, depot, 'Courrier.pdf');
      // retrait
      const n1 = S.raw().audit.length;
      const ret = F.retirer(col, col.get(fiche.id), 'courrier', 'Mauvais scan, à refaire', journal);
      const apresRet = H.propre(col.get(fiche.id));
      const regRet = H.propre(F.colFichiers().get('FIC-' + a.sha.slice(0, 16)));
      const auditRet = metier(n1, 'Pièce numérisée retirée de la fiche');
      ret.undo();
      const apresUndoRet = H.propre(col.get(fiche.id));
      // retrait d'une fiche sans fichier
      const sans = col.insert({ reference: 'ARR-2026-0961', sens: 'arrivee', date: '2026-08-20' }).record;
      const retSans = F.retirer(col, sans, 'courrier', 'x', journal);
      // retraits successifs (l'historique s'allonge)
      const r1 = F.retirer(col, col.get(fiche.id), 'courrier', 'Premier retrait', journal);
      const rat2 = F.rattacher(col, col.get(fiche.id), 'courrier', Object.assign({}, depot, { sha256: 'e'.repeat(64) }), 'Autre.pdf', journal);
      const r2 = F.retirer(col, col.get(fiche.id), 'courrier', 'M'.repeat(300), journal);
      const apresDeux = H.propre(col.get(fiche.id));
      rat.undo;
      return H.propre({ depot, fiche: { reference: fiche.reference, date: fiche.date }, rattache: apres, registre: reg, audit: auditRat, nomConstruit: nom0, retire: apresRet, registreApresRetrait: regRet, auditRetrait: auditRet,
        apresAnnulationRetrait: apresUndoRet, retraitSansFichier: retSans === null, apresDeuxRetraits: apresDeux, numeriseAvant: F.numerise({ fichier: null }), numeriseApres: F.numerise(apres) });
    }, { sha: shaNode(fich['courrier-texte.pdf']), taille: fich['courrier-texte.pdf'].length });
    out.numerise = await page.evaluate(() => [null, {}, { fichier: null }, { fichier: 'ancien.pdf' }, { fichier: {} }, { fichier: { sha256: '' } }, { fichier: { sha256: 'ab'.repeat(32), nom: 'x' } }, { numerise: true }, { numerise: true, fichier: { sha256: 'cd'.repeat(32) } }]
      .map((f) => ({ fiche: f, numerise: SIGH.fichiers.numerise(f) })));
    out.textes = await page.evaluate(async () => {
      const S = SIGH.store, F = SIGH.fichiers;
      const dep = (sha, mots, indexe) => ({ sha256: sha, taille: 10, mime: 'application/pdf', pages: 1, texteIndexe: indexe, mots: mots });
      const a = 'f1'.repeat(32), b = 'f2'.repeat(32), c = 'f3'.repeat(32);
      F.noterFichier(dep(a, ['Hyperglycémie', 'AMOXICILLINE', 'é', 'Éther', 'ok', 'ok'], true), 1);
      F.noterFichier(dep(b, [], false), 1);
      F.noterFichier(dep(c, ['x'.repeat(5)], true), 2);
      F.noterFichier(dep(c, [], true), -1);
      const lire = (s) => H.propre(F.colFichiers().get('FIC-' + s.slice(0, 16)));
      const texteDe = (s) => F.texteDe({ sha256: s });
      return { entrees: [lire(a), lire(b), lire(c)], texteDe: [texteDe(a), texteDe(b), texteDe('0'.repeat(64)), F.texteDe(null), F.texteDe({})] };
    });

    /* --- 12. LE SERVEUR : ce qu'il répond à chaque profil ----------------------------------------------------------------------------------------------------- */
    const regles = JSON.parse(fs.readFileSync(path.join(ROOT, 'api/regles-fichiers.json'), 'utf8'));
    out.regles = regles;
    out.reglesGenerees = JSON.parse(JSON.stringify(require('./gen-regles-fichiers').construire()));
    const jt = {};
    for (const r of roles) jt[r] = await jeton(r);
    out.serveur = { depots: [], lectures: [] };
    const types = ['Compte rendu médical', 'Ordonnance', 'Pièce d’identité', 'Carte d’assurance', 'Facture', 'Type inconnu'];
    let n = 0;
    const png = (k) => { const b = Buffer.from(fich['scan.png']); b[b.length - 1] ^= 0; return Buffer.concat([b, Buffer.from('#' + k)]); };
    for (const role of roles) {
      for (const famille of ['courrier', 'patient']) {
        for (const type of famille === 'patient' ? types : [null]) {
          n++;
          const corps = png(n);
          const r = await api('POST', 'action=deposer&famille=' + famille + '&nom=sonde.png' + (type ? '&type=' + enc(type) : ''), jt[role], corps);
          out.serveur.depots.push({ role, famille, type, statut: r.statut, ok: !!(r.json && r.json.ok), code: r.json && r.json.code || null, motif: r.json && r.json.ok === false ? r.json.motif : null, geste: r.json && r.json.ok === false ? r.json.geste : null, sha256: r.json && r.json.sha256 || null });
        }
      }
    }
    /* Lectures : un compte rendu (zone 2) et une pièce d'identité (zone 1) déposés par l'administrateur, lus par chaque profil ; un courrier lu par chaque profil. */
    const depPatient = async (type, k) => (await api('POST', 'action=deposer&famille=patient&nom=lu.png&type=' + enc(type), jt.admin, png('lu' + k))).json.sha256;
    const shaCR = await depPatient('Compte rendu médical', 1), shaId = await depPatient('Pièce d’identité', 2);
    const shaCour = (await api('POST', 'action=deposer&famille=courrier&nom=lu.png', jt.admin, png('lu3'))).json.sha256;
    for (const role of roles) {
      for (const [famille, sha, type] of [['patient', shaCR, 'zone2'], ['patient', shaId, 'zone1'], ['courrier', shaCour, null], ['courrier', shaCR, 'nonrattachee']]) {
        const r = await api('GET', 'action=lire&famille=' + famille + '&sha256=' + sha, jt[role]);
        out.serveur.lectures.push({ role, famille, type, statut: r.statut, ok: r.statut === 200, code: r.json ? r.json.code : null, motif: r.json ? r.json.motif : null, geste: r.json ? r.json.geste : null });
      }
    }
    /* Les refus de format, de taille, d'empreinte et de session du serveur. */
    const refusServeur = [];
    const unRefus = async (cas, q, jetonUtilise, corps) => { const r = await api('POST', q, jetonUtilise, corps); refusServeur.push({ cas, statut: r.statut, code: r.json && r.json.code, motif: r.json && r.json.motif, geste: r.json && r.json.geste }); };
    await unRefus('sans-session', 'action=deposer&famille=courrier&nom=x.png', '', fich['scan.png']);
    await unRefus('famille-inconnue', 'action=deposer&famille=autre&nom=x.png', jt.admin, fich['scan.png']);
    await unRefus('vide', 'action=deposer&famille=courrier&nom=x.pdf', jt.admin, Buffer.alloc(0));
    await unRefus('exe', 'action=deposer&famille=courrier&nom=x.exe', jt.admin, fich['faux.exe']);
    await unRefus('webp-courrier', 'action=deposer&famille=courrier&nom=x.webp', jt.admin, fich['scan.webp']);
    await unRefus('webp-patient-ok', 'action=deposer&famille=patient&nom=x.webp&type=' + enc('Facture'), jt.admin, fich['scan.webp']);
    await unRefus('empreinte-fausse', 'action=deposer&famille=courrier&nom=x.png&sha256=' + '0'.repeat(64), jt.admin, fich['scan.png']);
    await page.evaluate(() => { SIGH.store.setReglage('documentsBornes', { tailleMax: 100 * 1024 }); return true; });
    await page.evaluate(async () => { await SIGH.store.pousserMaintenant(); for (let i = 0; i < 80 && SIGH.store.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250)); await new Promise((r) => setTimeout(r, 600)); });
    await unRefus('taille-reglee-100ko', 'action=deposer&famille=courrier&nom=x.pdf', jt.admin, fich['gros.pdf']);
    await page.evaluate(() => { SIGH.store.setReglage('documentsBornes', null); return true; });
    await page.evaluate(async () => { await SIGH.store.pousserMaintenant(); for (let i = 0; i < 80 && SIGH.store.fileEnAttente() > 0; i++) await new Promise((r) => setTimeout(r, 250)); await new Promise((r) => setTimeout(r, 600)); });
    out.serveur.refus = refusServeur;

    /* --- 13. L'EXTRACTEUR DE TEXTE PDF DU SERVEUR ------------------------------------------------------------------------------------------------------------- */
    out.extracteur = [];
    for (const nom of ['courrier-texte.pdf', 'trois-pages.pdf', 'scan-image.pdf', 'simple-winansi.pdf', 'simple-flate.pdf', 'chiffre.pdf', 'sans-objets.pdf', 'contenu-illisible.pdf', 'gros.pdf']) {
      const r = await api('POST', 'action=deposer&famille=courrier&nom=' + enc(nom), jt.admin, fich[nom]);
      if (r.statut !== 200) throw new Error('dépôt de ' + nom + ' refusé : ' + JSON.stringify(r.json));
      out.extracteur.push({ fichier: nom, sha256: r.json.sha256, pages: r.json.pages, texteIndexe: r.json.texteIndexe, mots: (r.json.mots || []).map(String).sort(), motsTronques: r.json.motsTronques, raison: r.json.raison });
    }
    /* Une image : pas de couche texte, la raison est dite. */
    const ri = await api('POST', 'action=deposer&famille=courrier&nom=scan.png', jt.admin, fich['scan.png']);
    out.extracteur.push({ fichier: 'scan.png', sha256: ri.json.sha256, pages: ri.json.pages, texteIndexe: ri.json.texteIndexe, mots: [], motsTronques: ri.json.motsTronques, raison: ri.json.raison });

    ecrire('packages/domaine/test/vecteurs/fichiers.json', out);
    console.log('  fixtures : apps/poste/test/fixtures/fichiers (' + (Object.keys(fich).length - Object.keys(out.derives).length) + ' fichiers versionnés, ' + Object.keys(out.derives).length + ' dérivés)');
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error('ÉCHEC :', e); process.exit(1); });
