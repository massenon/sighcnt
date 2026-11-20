/* Références du KIT Dart : monte les VRAIS composants de la maquette (ui.js) avec des données fixes dans un conteneur de
   largeur fixe, mesure la géométrie de chaque partie nommée et capture l'image.
   Sortie : apps/poste/test/references/kit/{kit.json, <composant>.png}. Le test Flutter compare à ces mesures.
     node build/reference-kit.js */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http');
const puppeteer = require('puppeteer');
const ROOT = path.resolve(__dirname, '..');
const SORTIE = path.resolve(ROOT, '..', 'apps', 'poste', 'test', 'references', 'kit');
fs.mkdirSync(SORTIE, { recursive: true });
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml' };
const chrome = process.env.CHROME_PATH || undefined;
const LARGEUR = 960;

const HARNAIS = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><link rel="stylesheet" href="/assets/css/tailwind.css"><style>body{margin:0;background:#f1f5fb;font-family:Inter,'Segoe UI',sans-serif}#racine{width:${LARGEUR}px;padding:16px;box-sizing:border-box}</style></head><body><div id="racine"></div>
<script src="/assets/js/vendor/lucide.min.js"></script><script src="/assets/js/core.js"></script><script src="/assets/js/ui.js"></script></body></html>`;

/* Chaque cas : id, construction (dans la page), parties à mesurer : nom → sélecteur CSS (premier élément). */
const CAS = [
  { id: 'boutons', parties: { primaire: '.btn-primary:not(.btn-sm):not(.btn-lg)', secondaire: '.btn-secondary:not(.btn-sm)', petit: '.btn-sm', grand: '.btn-lg', icone: '.btn-icon' },
    build: `var w=C.el('div',{class:'flex flex-wrap items-center gap-3'});
      w.appendChild(C.el('button.btn.btn-primary',{text:'Enregistrer'}));w.appendChild(C.el('button.btn.btn-secondary',{text:'Annuler'}));
      w.appendChild(C.el('button.btn.btn-primary.btn-sm',{text:'Filtrer'}));w.appendChild(C.el('button.btn.btn-primary.btn-lg',{text:'Valider'}));
      w.appendChild(C.el('button.btn.btn-ghost.btn-icon',null,C.icon('x','h-4 w-4')));return w;` },
  { id: 'badges', parties: { neutre: '.badge-neutral', navy: '.badge-navy', succes: '.badge-success', attention: '.badge-warning', danger: '.badge-danger', info: '.badge-info' },
    build: `var w=C.el('div',{class:'flex gap-3'});['neutral','navy','success','warning','danger','info'].forEach(function(t){w.appendChild(U.badge('Statut '+t.length,t))});return w;` },
  { id: 'carte', parties: { carte: '.card', entete: '.card-head', titre: '.card-title', corps: '.card-body' },
    build: `return U.card('Informations du patient',C.el('p',{class:'text-sm',text:'Corps de la carte'}));` },
  { id: 'kpi', parties: { kpi: '.kpi', libelle: '.kpi-label', valeur: '.kpi-value', pastille: '.kpi span.grid' },
    build: `return U.kpiGrid([{label:'Patients du jour',value:'128',icon:'users',tone:'navy'},{label:'Recettes',value:'1 250 000 FCFA',icon:'wallet',tone:'success'},{label:'En retard',value:'4',icon:'clock',tone:'danger'},{label:'À valider',value:'17',icon:'check',tone:'warning'}]);` },
  { id: 'onglets', parties: { barre: '.border-b', actif: '.tab-active', inactif: '.tab:not(.tab-active)' },
    build: `return U.tabs([{id:'a',label:'Général',count:3,render:function(){return C.el('p',{text:'A'})}},{id:'b',label:'Antécédents',render:function(){return C.el('p',{text:'B'})}},{id:'c',label:'Documents',render:function(){return C.el('p',{text:'C'})}}]);` },
  { id: 'formulaire', parties: { grille: 'form', nom: 'form > div:nth-child(2)', prenom: 'form > div:nth-child(3)', sexe: 'form > div:nth-child(4)', section: 'form > div:nth-child(1)', pleine: 'form > div:nth-child(5)', demi: 'form > div:nth-child(6)', champ: 'form input', libelle: 'form label' },
    build: `return U.form([{type:'section',label:'Identité'},{name:'nom',label:'Nom',required:true,col:'third'},{name:'prenom',label:'Prénom',col:'third'},{name:'sexe',label:'Sexe',type:'select',options:['F','M'],col:'third'},{name:'adresse',label:'Adresse',col:'full'},{name:'tel',label:'Téléphone'},{name:'quartier',label:'Quartier'}],{});` },
  { id: 'note', parties: { note: '.rounded-lg.border' },
    build: `var w=C.el('div',{class:'rounded-lg border px-3 py-2 flex items-start gap-2 border-info-200 bg-info-50'});w.appendChild(C.el('span.shrink-0',{class:'text-info-600'},C.icon('info','h-4 w-4')));w.appendChild(C.el('div.text-xs.text-info-900',{text:'Règle appliquée : la prise en charge vaut à la date.'}));return w;` },
  { id: 'vide', parties: { vide: '.flex-col', icone: '.rounded-full' },
    build: `return U.empty('Aucun enregistrement.',{hint:'Créez le premier.'});` },
  { id: 'modale', hote: 'body', parties: { fond: '.drawer-backdrop', panneau: '.shadow-pop', entete: '.border-b', titre: 'h2', corps: '.px-5.py-4:not(.border-b):not(.border-t)', pied: '.border-t' },
    build: `U.modal({title:'Nouveau patient',subtitle:'Ouverture de dossier',size:'md',body:C.el('p',{class:'text-sm',text:'Contenu'}),footer:[C.el('button.btn.btn-secondary',{text:'Annuler'}),C.el('button.btn.btn-primary',{text:'Enregistrer'})]});return null;` },
  { id: 'tiroir', hote: 'body', parties: { fond: '.drawer-backdrop', panneau: '.shadow-pop', entete: '.border-b', titre: 'h2', pied: '.border-t' },
    build: `U.drawer({title:'Fiche patient',subtitle:'CNT/12/26',body:C.el('p',{class:'text-sm',text:'Détail'}),footer:[C.el('button.btn.btn-secondary',{text:'Fermer'})]});return null;` },
  { id: 'tableau', parties: { carte: '.card', barre: '.border-b', recherche: 'input[type=search], input.input', entete: 'thead', ligneEntete: 'thead tr', ligne: 'tbody tr', cellule: 'tbody td', pied: '.card > div:last-child' },
    build: `var rows=[];for(var i=1;i<=30;i++)rows.push({id:'r'+i,code:'CNT/'+i+'/26',nom:'Patient '+i,montant:i*1500,statut:i%2?'actif':'archive'});
      return U.dataTable({title:'Patients',columns:[{key:'code',label:'Code'},{key:'nom',label:'Nom'},{key:'montant',label:'Montant',align:'right'},{key:'statut',label:'Statut'}],rows:rows,pageSize:12,rowActions:function(r){return C.el('button.btn.btn-ghost.btn-icon',null,C.icon('pencil','h-4 w-4'))}});` },
];

(async () => {
  const srv = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]);
    if (rel === '/harnais.html') { res.writeHead(200, { 'Content-Type': MIME['.html'] }); res.end(HARNAIS); return; }
    const f = path.join(ROOT, rel);
    if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  }).listen(0);
  const port = srv.address().port;
  const nav = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-sandbox'] });
  const sortie = { largeur: LARGEUR, composants: {} };
  const erreurs = [];
  for (const cas of CAS) {
    const page = await nav.newPage();
    await page.setViewport({ width: LARGEUR + 40, height: 900, deviceScaleFactor: 1 });
    page.on('pageerror', (e) => erreurs.push(cas.id + ' : ' + e.message));
    await page.goto(`http://127.0.0.1:${port}/harnais.html`, { waitUntil: 'load' });
    const res = await page.evaluate((build, parties, hote) => {
      var C = window.SIGH.core, U = window.SIGH.ui;
      var n = new Function('C', 'U', build)(C, U);
      if (n) document.getElementById('racine').appendChild(n);
      return new Promise((ok) => setTimeout(() => {
        const racine = hote === 'body' ? document.body : document.getElementById('racine');
        const mesures = {};
        for (const [nom, sel] of Object.entries(parties)) {
          const e = racine.querySelector(sel);
          if (!e) { mesures[nom] = null; continue; }
          const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
          mesures[nom] = { x: +r.left.toFixed(2), y: +r.top.toFixed(2), l: +r.width.toFixed(2), h: +r.height.toFixed(2), taille: parseFloat(cs.fontSize), poids: +cs.fontWeight, rayon: parseFloat(cs.borderTopLeftRadius) || 0, fond: cs.backgroundColor, couleur: cs.color, bordure: cs.borderTopColor, texte: (e.textContent || '').trim().slice(0, 40) };
        }
        ok(mesures);
      }, 400));
    }, cas.build, cas.parties, cas.hote || 'racine');
    sortie.composants[cas.id] = res;
    const cible = cas.hote === 'body' ? null : await page.$('#racine');
    await page.screenshot({ path: path.join(SORTIE, cas.id + '.png'), ...(cible ? { clip: await cible.boundingBox() } : {}) });
    await page.close();
  }
  await nav.close(); srv.close();
  fs.writeFileSync(path.join(SORTIE, 'kit.json'), JSON.stringify(sortie, null, 1));
  const manquants = Object.entries(sortie.composants).flatMap(([c, p]) => Object.entries(p).filter(([, v]) => v === null).map(([k]) => c + '.' + k));
  console.log('références du kit :', Object.keys(sortie.composants).length, 'composants' + (manquants.length ? ' ; parties introuvables : ' + manquants.join(', ') : ''));
  if (erreurs.length) { console.error(erreurs.join('\n')); process.exit(1); }
})();
